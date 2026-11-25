import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../services/food_image_service.dart';
import '../services/google_auth_service.dart';
import '../services/theme_controller.dart';
import '../store/store.dart';
import '../theme/app_palette.dart';
import '../widgets/shared_widgets.dart';

Uint8List? _compressProfilePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  var longestSide = math
      .min(math.max(oriented.width, oriented.height), 768)
      .toInt();
  while (true) {
    final resized = math.max(oriented.width, oriented.height) > longestSide
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height
                ? longestSide
                : (oriented.width * longestSide / oriented.height).round(),
            height: oriented.height > oriented.width
                ? longestSide
                : (oriented.height * longestSide / oriented.width).round(),
            interpolation: img.Interpolation.average,
          )
        : oriented;
    for (final quality in [80, 70, 60, 50, 40]) {
      final jpeg = img.encodeJpg(resized, quality: quality);
      if (jpeg.length <= 680 * 1024) return Uint8List.fromList(jpeg);
    }
    if (longestSide <= 128) break;
    longestSide = (longestSide * 0.8).round();
  }
  return null;
}

/// User-facing message for a password-change outcome. Verification failures
/// are reported without touching stored data (the store guarantees this).
String _passwordChangeMessage(PasswordChangeResult result) => switch (result) {
  PasswordChangeResult.success => 'Password updated.',
  PasswordChangeResult.invalidInput =>
    'New password needs at least 8 characters.',
  PasswordChangeResult.wrongCurrentPassword =>
    'Current password is incorrect. Your password was not changed.',
  PasswordChangeResult.notEmailAccount =>
    'Password changes are managed by your Google account.',
  PasswordChangeResult.storageError =>
    'Could not access saved account data. Please try again.',
  PasswordChangeResult.serviceError =>
    'Could not reach the account service. Your password was not changed.',
};

String _migrationMessage(CloudMigrationResult result) => switch (result) {
  CloudMigrationResult.success =>
    'Connected. This account now syncs across your devices.',
  CloudMigrationResult.alreadyLinked => 'This account is already connected.',
  CloudMigrationResult.invalidPassword =>
    'Password incorrect — nothing was uploaded.',
  CloudMigrationResult.declined => 'Cancelled. Your data stays on this device.',
  CloudMigrationResult.unavailable =>
    'Cloud sync is unavailable right now. Nothing was uploaded.',
  CloudMigrationResult.failed => 'Cloud sync did not finish. Your data is still saved on this device; retry from Cloud sync.',
};

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, this.photoPicker});

  final Future<XFile?> Function()? photoPicker;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool _logoutInProgress = false;

  Future<void> _chooseProfilePhoto(BuildContext context) async {
    try {
      final picked =
          await (widget.photoPicker ??
              () => ImagePicker().pickImage(
                source: ImageSource.gallery,
                imageQuality: 78,
                maxWidth: 768,
                maxHeight: 768,
              ))();
      if (picked == null || !context.mounted) return;

      final bytes = _compressProfilePhoto(await picked.readAsBytes());
      if (!context.mounted) return;
      if (bytes == null) {
        snack(context, 'Could not read this photo. Choose another image.');
        return;
      }

      store.d['profilePhoto'] = {'localPhoto': base64Encode(bytes)};
      store.save();
      if (context.mounted) {
        snack(
          context,
          store.syncEnabled
              ? 'Profile photo saved. Syncing to your account.'
              : 'Profile photo saved on this device.',
        );
      }
    } on Exception {
      if (context.mounted) {
        snack(context, 'Could not select or save the profile photo.');
      }
    }
  }

  Future<void> editPersonalDetails(BuildContext context) async {
    final details = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PersonalDetailsSheet(
        name: store.d['name'] as String? ?? '',
        age: store.d['age'] as int?,
        height: store.d['h'] as int?,
        sex: store.d['sex'] as String? ?? 'other',
        activityLevel: store.d['activityLevel'] as String? ?? 'light',
        weight: store.d['weights'].isEmpty
            ? null
            : store.lastW() * (store.on('lb') ? 2.2046 : 1),
        isImperial: store.on('lb'),
      ),
    );
    if (details == null || !context.mounted) return;
    store.d['name'] = details['name'];
    store.d['age'] = details['age'];
    store.d['h'] = details['height'];
    store.d['sex'] = details['sex'];
    store.d['activityLevel'] = details['activityLevel'];
    final weight = details['weight'] as double?;
    if (weight != null) {
      final weights = store.d['weights'] as List;
      if (weights.isEmpty && store.goalField('sw') == 0) {
        store.ensureGoal()['sw'] = weight;
      }
      weights.removeWhere((entry) => entry[0] == today());
      weights.add([today(), weight]);
    }
    store.save();
  }

  Future<void> _chooseColorPalette(BuildContext context) async {
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ColorPaletteSheet(),
    );
    if (applied != true) themeController.cancelPalettePreview();
  }

  Future<void> _connectAccountToCloud(BuildContext context) async {
    final fields = await form(context, 'Connect account to cloud', [
      F('pw', 'Your account password', '', type: 'pass'),
    ], ok: 'Continue');
    if (fields == null || !context.mounted) return;
    final result = await store.migrateLocalAccountToCloud(
      password: fields['pw'] ?? '',
      requestConfirmation: (message) async =>
          context.mounted ? await confirm(context, message, 'Connect') : false,
    );
    if (context.mounted) snack(context, _migrationMessage(result));
  }

  Future<void> _logOut(BuildContext c) async {
    if (_logoutInProgress) return;
    setState(() => _logoutInProgress = true);
    try {
      if (!await confirm(c, 'Are you sure you want to log out?', 'Log Out') ||
          !mounted) {
        return;
      }

      final signOutGoogle = !store.isEmailAccount && store.hasActiveSession;
      var syncCompleted = false;
      var firebaseSignedOut = false;
      final warnings = <String>[];
      final result = await store.signOutAsync();
      syncCompleted = result.syncCompleted;
      firebaseSignedOut = result.firebaseSignOutError == null;
      final authError = result.firebaseSignOutError;
      if (authError is FirebaseException) {
        warnings.add(googleAuthErrorMessage(authError));
      } else if (authError is TimeoutException) {
        warnings.add('Firebase sign-out took too long to complete.');
      }
      if (!syncCompleted) {
        warnings.add(
          'The latest changes are saved on this device but could not be synced.',
        );
      }
      if (!mounted) return;
      if (signOutGoogle) {
        try {
          await GoogleAuthService()
              .signOut(firebaseAlreadySignedOut: firebaseSignedOut)
              .timeout(const Duration(seconds: 3));
        } on FirebaseAuthException catch (error) {
          warnings.add(googleAuthErrorMessage(error));
        } on FirebaseException catch (error) {
          warnings.add(googleAuthErrorMessage(error));
        } on GoogleSignInException catch (error) {
          warnings.add(googleAuthErrorMessage(error));
        } on TimeoutException {
          warnings.add('Google sign-out took too long to complete.');
        }
      }

      if (warnings.isNotEmpty && c.mounted) {
        snack(c, '${warnings.join(' ')} You are signed out on this device.');
      }
    } finally {
      if (mounted) {
        setState(() => _logoutInProgress = false);
      }
    }
  }

  Widget sw(BuildContext context, String k, String title, String sub) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(sub, style: muted),
        trailing: Switch(
          value: store.on(k),
          activeTrackColor: primaryOf(context),
          onChanged: (value) => k == 'dark'
              ? themeController.setDarkMode(value)
              : store.toggle(k),
        ),
      );

  @override
  Widget build(BuildContext context) => live((c) {
    final name = (store.d['name'] as String?) ?? '';
    final displayName = name.isEmpty ? 'Your name' : name;
    final age = store.d['age'];
    final height = store.d['h'];
    final rawProfilePhoto = store.d['profilePhoto'];
    final profilePhoto = rawProfilePhoto is Map ? rawProfilePhoto : const {};
    final localPhoto = profilePhoto['localPhoto'];
    final profileImageId = profilePhoto['imageId'];
    final providerPhotoUrl = store.d['photoUrl'];
    return tabBody([
      hdr(c, 'Profile & preferences', 'Your corner.'),
      card(
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: tintOf(c),
                          child: ClipOval(
                            child: SizedBox(
                              width: 62,
                              height: 62,
                              child: _ProfileAvatarImage(
                                initials: name.isEmpty
                                    ? '?'
                                    : name[0].toUpperCase(),
                                localPhoto: localPhoto is String
                                    ? localPhoto
                                    : null,
                                imageId: profileImageId is String
                                    ? profileImageId
                                    : null,
                                photoUrl: providerPhotoUrl is String
                                    ? providerPhotoUrl
                                    : null,
                                uid: store.sessionUid,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 4,
                        child: Material(
                          color: Theme.of(c).colorScheme.surface,
                          shape: CircleBorder(
                            side: BorderSide(
                              color: Theme.of(c).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Tooltip(
                            message: 'Change profile photo',
                            child: InkResponse(
                              onTap: () => _chooseProfilePhoto(c),
                              radius: 22,
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: Icon(
                                  Icons.camera_alt_outlined,
                                  size: 15,
                                  color: primaryOf(c),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: kGapLg),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text('${store.d['user']}', style: muted),
                  ],
                ),
              ],
            ),
            const SizedBox(height: kGapLg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    Text(
                      age == null ? '—' : '$age',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Text('Age', style: muted),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      height == null ? '—' : '$height cm',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Text('Height', style: muted),
                  ],
                ),
                Column(
                  children: [
                    Text(
                      store.d['weights'].isEmpty
                          ? 'Not logged'
                          : store.wt(store.lastW()),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Text('Weight', style: muted),
                  ],
                ),
              ],
            ),
            const SizedBox(height: kGapLg),
            btn(
              '✎  Edit personal details',
              () => editPersonalDetails(c),
              tonal: true,
            ),
          ],
        ),
      ),
      h3('A nudge when you need it'),
      card(
        child: Column(
          children: [
            sw(
              c,
              'wr',
              'Workout reminders (in-app)',
              'Show a card on the Today screen. System notifications are not available yet.',
            ),
            sw(
              c,
              'wtr',
              'Water reminders (in-app)',
              'Show a hydration card while your daily goal is unmet.',
            ),
            sw(
              c,
              'mr',
              'Meal reminders (in-app)',
              'Show a meal logging card until 3 meals are logged.',
            ),
          ],
        ),
      ),
      h3('Make it yours'),
      card(
        child: Column(
          children: [
            sw(
              c,
              'dark',
              'Dark mode',
              'A darker look that is easier on the eyes',
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Color palette'),
              subtitle: Text(
                '${themeController.selectedPalette.name}'
                '${themeController.selectedPalette.id == AppPalette.teal.id ? ' (default)' : ''}',
                style: muted,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final color in [
                    themeController.selectedPalette.primary,
                    themeController.selectedPalette.lightTint,
                    themeController.selectedPalette.hero,
                    themeController.selectedPalette.softBackground,
                  ])
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(c).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => _chooseColorPalette(c),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Units'),
              subtitle: Text(
                store.on('lb') ? 'Imperial · lb' : 'Metric · kg, km, ml',
                style: muted,
              ),
              onTap: () => store.toggle('lb'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Privacy & account'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!store.isEmailAccount) {
                  snack(
                    c,
                    'Password changes are managed by your Google account.',
                  );
                  return;
                }
                final f = await form(c, 'Change password', [
                  F('cur', 'Current password', '', type: 'pass'),
                  F('p', 'New password', '', type: 'pass'),
                ], ok: 'Update');
                if (f == null || !c.mounted) return;
                final result = await store.changePassword(
                  currentPassword: f['cur'] ?? '',
                  newPassword: f['p'] ?? '',
                );
                if (!c.mounted) return;
                snack(c, _passwordChangeMessage(result));
              },
            ),
            if (store.hasActiveSession &&
                store.isEmailAccount &&
                !store.isCloudLinked)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Connect account to cloud'),
                subtitle: Text(
                  'Verify your password to sync across devices.',
                  style: muted,
                ),
                trailing: const Icon(Icons.cloud_upload_outlined),
                onTap: () => _connectAccountToCloud(c),
              ),
            if (store.hasActiveSession)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cloud sync'),
                subtitle: Text(store.syncStatusMessage, style: muted),
                trailing: store.syncFailed
                    ? Icon(Icons.refresh, color: Theme.of(c).colorScheme.error)
                    : const Icon(Icons.cloud_done_outlined),
                onTap: !store.syncFailed
                    ? null
                    : () async {
                        final ok = await store.syncNow();
                        if (!c.mounted) return;
                        snack(
                          c,
                          ok ? 'Sync complete.' : store.syncStatusMessage,
                        );
                      },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reset all data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (await confirm(
                  c,
                  'Erase your fitness records? Your profile and goals stay.',
                  'Erase',
                )) {
                  store.resetCurrentAccountData();
                }
              },
            ),
          ],
        ),
      ),
      IgnorePointer(
        ignoring: _logoutInProgress,
        child: btn(
          _logoutInProgress ? 'Logging out...' : 'Log out',
          () => _logOut(c),
          tonal: true,
        ),
      ),
    ]);
  });
}

class _ProfileAvatarImage extends StatefulWidget {
  const _ProfileAvatarImage({
    required this.initials,
    required this.localPhoto,
    required this.imageId,
    required this.photoUrl,
    required this.uid,
  });

  final String initials;
  final String? localPhoto;
  final String? imageId;
  final String? photoUrl;
  final String? uid;

  @override
  State<_ProfileAvatarImage> createState() => _ProfileAvatarImageState();
}

class _ProfileAvatarImageState extends State<_ProfileAvatarImage> {
  Future<Uint8List?>? _remoteImage;

  void _loadRemoteImage() {
    final uid = widget.uid;
    final imageId = widget.imageId;
    _remoteImage =
        widget.localPhoto != null ||
            uid == null ||
            imageId == null ||
            imageId.isEmpty
        ? null
        : FoodImageService().download(uid: uid, imageId: imageId);
  }

  @override
  void initState() {
    super.initState();
    _loadRemoteImage();
  }

  @override
  void didUpdateWidget(covariant _ProfileAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.imageId != widget.imageId ||
        oldWidget.localPhoto != widget.localPhoto) {
      _loadRemoteImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      backgroundColor: primaryOf(context),
      child: Text(
        widget.initials,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final localPhoto = widget.localPhoto;
    if (localPhoto != null && localPhoto.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(localPhoto),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
      } on FormatException {
        return fallback;
      }
    }

    final imageId = widget.imageId;
    final uid = widget.uid;
    if (imageId != null && imageId.isNotEmpty && uid != null) {
      return FutureBuilder<Uint8List?>(
        future: _remoteImage,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          return bytes == null
              ? fallback
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                );
        },
      );
    }

    final photoUrl = widget.photoUrl;
    if (photoUrl != null && photoUrl.startsWith('https://')) {
      return Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }
}

class _ColorPaletteSheet extends StatefulWidget {
  const _ColorPaletteSheet();

  @override
  State<_ColorPaletteSheet> createState() => _ColorPaletteSheetState();
}

class _ColorPaletteSheetState extends State<_ColorPaletteSheet> {
  late String _selectedId = themeController.selectedPaletteId;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose your palette',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: kGapLg),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = (constraints.maxWidth - kGapMd) / 2;
                return Wrap(
                  spacing: kGapMd,
                  runSpacing: kGapMd,
                  children: [
                    for (final palette in AppPalette.all)
                      SizedBox(
                        width: cardWidth,
                        child: _paletteCard(context, palette),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: kGapMd),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    themeController.resetToDefault();
                    setState(() => _selectedId = AppPalette.teal.id);
                  },
                  child: const Text('Reset to default'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: kGapSm),
                FilledButton(
                  onPressed: () {
                    themeController.applyPalette(_selectedId);
                    Navigator.pop(context, true);
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _paletteCard(BuildContext context, AppPalette palette) {
    final selected = _selectedId == palette.id;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name} palette${selected ? ', selected' : ''}',
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: .08)
            : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected && palette.borderWidth <= 1
                ? colors.primary
                : colors.outlineVariant,
            width: selected ? 2 : palette.borderWidth,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() => _selectedId = palette.id);
            themeController.previewPalette(palette.id);
          },
          child: Padding(
            padding: const EdgeInsets.all(kGapMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        palette.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, color: colors.primary, size: 20),
                  ],
                ),
                const SizedBox(height: kGapXs),
                Text(
                  palette.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: kGapMd),
                Row(
                  children: [
                    for (final color in [
                      if (isDark(context)) ...[
                        palette.darkPrimary,
                        palette.darkTint,
                        palette.darkHero,
                      ] else ...[
                        palette.primary,
                        palette.lightTint,
                        palette.hero,
                      ],
                    ])
                      Expanded(
                        child: Container(
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            border: Border.all(color: colors.outlineVariant),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonalDetailsSheet extends StatefulWidget {
  final String name;
  final int? age;
  final int? height;
  final String sex;
  final String activityLevel;
  final double? weight;
  final bool isImperial;

  const _PersonalDetailsSheet({
    required this.name,
    required this.age,
    required this.height,
    required this.sex,
    required this.activityLevel,
    required this.weight,
    required this.isImperial,
  });

  @override
  State<_PersonalDetailsSheet> createState() => _PersonalDetailsSheetState();
}

class _PersonalDetailsSheetState extends State<_PersonalDetailsSheet> {
  late final _name = TextEditingController(text: widget.name);
  late final _age = TextEditingController(text: widget.age?.toString() ?? '');
  late final _height = TextEditingController(
    text: widget.height?.toString() ?? '',
  );
  late final _weight = TextEditingController(
    text: widget.weight?.toStringAsFixed(1) ?? '',
  );
  late String _sex = const {'female', 'male', 'other'}.contains(widget.sex)
      ? widget.sex
      : 'other';
  late String _activityLevel = widget.activityLevel;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Personal details',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text('Make your profile feel like yours.', style: muted),
            const SizedBox(height: kGapLg),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: kGapMd),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      prefixIcon: Icon(Icons.cake_outlined),
                      suffixText: 'years',
                    ),
                  ),
                ),
                const SizedBox(width: kGapMd),
                Expanded(
                  child: TextField(
                    controller: _height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      prefixIcon: Icon(Icons.height),
                      suffixText: 'cm',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: kGapMd),
            DropdownButtonFormField<String>(
              initialValue: _sex,
              decoration: const InputDecoration(
                labelText: 'Sex used for calorie estimates',
              ),
              items: const [
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(
                  value: 'other',
                  child: Text('Other / prefer not to say'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _sex = value);
              },
            ),
            const SizedBox(height: kGapMd),
            DropdownButtonFormField<String>(
              initialValue:
                  const {
                    'sedentary',
                    'light',
                    'moderate',
                    'active',
                    'very_active',
                  }.contains(_activityLevel)
                  ? _activityLevel
                  : 'light',
              decoration: const InputDecoration(labelText: 'Activity level'),
              items: const [
                DropdownMenuItem(
                  value: 'sedentary',
                  child: Text('Mostly sitting'),
                ),
                DropdownMenuItem(value: 'light', child: Text('Lightly active')),
                DropdownMenuItem(
                  value: 'moderate',
                  child: Text('Moderately active'),
                ),
                DropdownMenuItem(value: 'active', child: Text('Very active')),
                DropdownMenuItem(
                  value: 'very_active',
                  child: Text('Extremely active'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _activityLevel = value);
              },
            ),
            const SizedBox(height: kGapMd),
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Weight',
                prefixIcon: const Icon(Icons.monitor_weight_outlined),
                suffixText: widget.isImperial ? 'lb' : 'kg',
              ),
            ),
            const SizedBox(height: kGapLg),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(kGapLg),
              decoration: BoxDecoration(
                color: tintOf(context),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: primaryOf(context)),
                  const SizedBox(width: kGapMd),
                  const Expanded(
                    child: Text(
                      'Your personal details stay on your profile.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kGapLg),
            btn('Save changes', _save),
          ],
        ),
      ),
    ),
  );

  void _save() {
    final name = _name.text.trim();
    final ageText = _age.text.trim();
    final heightText = _height.text.trim();
    final weightText = _weight.text.trim();
    final age = ageText.isEmpty ? null : int.tryParse(ageText);
    final height = heightText.isEmpty ? null : int.tryParse(heightText);
    final enteredWeight = weightText.isEmpty
        ? null
        : double.tryParse(weightText);

    if (ageText.isNotEmpty && (age == null || age < 1 || age > 120)) {
      snack(context, 'Enter a valid age between 1 and 120.');
      return;
    }
    if (heightText.isNotEmpty &&
        (height == null || height < 50 || height > 300)) {
      snack(context, 'Enter a valid height between 50 and 300 cm.');
      return;
    }
    if (weightText.isNotEmpty &&
        (enteredWeight == null || enteredWeight <= 0 || enteredWeight > 1000)) {
      snack(
        context,
        'Enter a valid weight greater than 0 and no more than 1000.',
      );
      return;
    }

    final weight = enteredWeight == null
        ? null
        : enteredWeight / (widget.isImperial ? 2.2046 : 1);
    Navigator.pop(context, {
      'name': name,
      'age': age,
      'height': height,
      'sex': _sex,
      'activityLevel': _activityLevel,
      'weight': weight,
    });
  }
}
