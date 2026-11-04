import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/google_auth_service.dart';
import '../store/store.dart';
import '../widgets/shared_widgets.dart';

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

/// User-facing message for a local-account → Firebase migration attempt.
String _migrationMessage(CloudMigrationResult result) => switch (result) {
  CloudMigrationResult.success =>
    'Backed up. This account now syncs across your devices.',
  CloudMigrationResult.alreadyLinked =>
    'This account is already backed up to the cloud.',
  CloudMigrationResult.invalidPassword =>
    'Password incorrect — nothing was uploaded.',
  CloudMigrationResult.declined =>
    'Backup cancelled. Nothing left this device.',
  CloudMigrationResult.unavailable =>
    'Cloud backup is unavailable right now. Nothing was uploaded.',
  CloudMigrationResult.failed =>
    'Cloud backup failed. Your data is untouched on this device.',
};

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  /// Uploads an existing local email account to Firebase. The password is
  /// verified against the on-device PBKDF2 hash *before* the confirmation
  /// dialog is shown, and a wrong password ends the flow without reading
  /// anything for upload or touching the cloud.
  Future<void> _backUpToCloud(BuildContext context) async {
    final fields = await form(context, 'Back up to cloud', [
      F('pw', 'Your account password', '', type: 'pass'),
    ], ok: 'Continue');
    if (fields == null || !context.mounted) return;
    final result = await store.migrateLocalAccountToCloud(
      password: fields['pw'] ?? '',
      requestConfirmation: (message) async =>
          context.mounted ? await confirm(context, message, 'Back up') : false,
    );
    if (!context.mounted) return;
    snack(context, _migrationMessage(result));
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
        store.goal['sw'] = weight;
      }
      weights.removeWhere((entry) => entry[0] == today());
      weights.add([today(), weight]);
    }
    store.save();
  }

  Widget sw(BuildContext context, String k, String title, String sub) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(sub, style: muted),
        trailing: Switch(
          value: store.on(k),
          activeTrackColor: primaryOf(context),
          onChanged: (_) => store.toggle(k),
        ),
      );

  @override
  Widget build(BuildContext context) => live((c) {
    final name = (store.d['name'] as String?) ?? '';
    final displayName = name.isEmpty ? 'Your name' : name;
    final age = store.d['age'];
    final height = store.d['h'];
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
                          child: CircleAvatar(
                            radius: 31,
                            backgroundColor: primaryOf(c),
                            child: Text(
                              name.isEmpty ? '?' : name[0].toUpperCase(),
                              style: TextStyle(
                                color: isDark(c) ? kInk : Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
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
                          child: InkResponse(
                            onTap: () {},
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
            if (store.isEmailAccount && !store.isCloudLinked)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Back up to cloud'),
                subtitle: Text(
                  'Verify your password to sync this account across devices.',
                  style: muted,
                ),
                trailing: const Icon(Icons.cloud_upload_outlined),
                onTap: () => _backUpToCloud(c),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cloud sync'),
              subtitle: Text(store.syncStatusMessage, style: muted),
              trailing: store.syncFailed
                  ? const Icon(Icons.refresh, color: kRed)
                  : const Icon(Icons.cloud_done_outlined),
              onTap: !store.syncFailed
                  ? null
                  : () async {
                      final ok = await store.syncNow();
                      if (!c.mounted) return;
                      snack(
                        c,
                        ok
                            ? 'Backed up to the cloud.'
                            : store.syncStatusMessage,
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
      btn('Log out', () async {
        // Local-first sign-out: the device session always ends, even when the
        // remote Google/Firebase sign-out fails. The failure is surfaced as a
        // warning while this screen is still mounted, then local sign-out
        // proceeds unconditionally so a flaky network can never trap the
        // user in a signed-in state.
        String? remoteWarning;
        if (!store.isEmailAccount && store.hasActiveSession) {
          try {
            await GoogleAuthService().signOut();
          } on FirebaseAuthException catch (error) {
            remoteWarning = googleAuthErrorMessage(error);
          } on FirebaseException catch (error) {
            remoteWarning = googleAuthErrorMessage(error);
          } on GoogleSignInException catch (error) {
            remoteWarning = googleAuthErrorMessage(error);
          }
        }
        if (remoteWarning != null && remoteWarning.isNotEmpty && c.mounted) {
          snack(c, '$remoteWarning You are signed out on this device.');
        }
        await store.signOutAsync();
      }, tonal: true),
    ]);
  });
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
