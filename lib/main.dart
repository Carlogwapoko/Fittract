import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store/store.dart';
import 'screens/auth_screen.dart';
import 'screens/meal_picker_screen.dart';
import 'screens/shell_screen.dart';
import 'services/firebase_initializer.dart';
import 'services/theme_controller.dart';
import 'theme/app_palette.dart';
import 'widgets/responsive_app_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await ensureFirebaseInitialized();
  } catch (error, stackTrace) {
    debugPrint('Firebase initialization failed: $error\n$stackTrace');
  }
  runApp(const App());
}

ThemeData buildTheme(Brightness brightness, AppPalette palette) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? palette.darkPrimary : palette.primary;
  final onPrimary = dark ? palette.darkOnPrimary : contrastingOn(primary);
  final background = dark ? palette.darkBackground : palette.softBackground;
  final surface = dark ? palette.darkCard : Colors.white;
  final onSurface = dark ? palette.darkText : palette.text;
  final muted = dark ? palette.darkMutedText : palette.muted;
  final outline = dark
      ? palette.darkDivider
      : palette.borderWidth > 1
      ? palette.primary
      : palette.primary.withValues(alpha: .24);
  final heroBackground = dark ? palette.darkHero : palette.hero;
  final heroForeground = dark ? palette.darkText : contrastingOn(palette.hero);
  final tint = dark ? palette.darkTint : palette.lightTint;
  final inputBorderWidth = palette.borderWidth < 1.5
      ? 1.5
      : palette.borderWidth;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    secondary: dark ? palette.darkAccent : palette.hero,
    onSecondary: dark
        ? contrastingOn(palette.darkAccent)
        : contrastingOn(palette.hero),
    error: dark ? const Color(0xFFFF8A80) : const Color(0xFFC0392B),
    onError: dark ? const Color(0xFF3B0909) : Colors.white,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerLowest: background,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: surface,
    surfaceContainerHighest: surface,
    onSurfaceVariant: muted,
    outline: outline,
    outlineVariant: outline,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: onSurface,
    onInverseSurface: surface,
    inversePrimary: dark ? palette.primary : palette.darkPrimary,
    primaryContainer: tint,
    onPrimaryContainer: onSurface,
    secondaryContainer: tint,
    onSecondaryContainer: onSurface,
    tertiary: dark ? palette.darkAccent : palette.accentTint,
    onTertiary: dark
        ? contrastingOn(palette.darkAccent)
        : contrastingOn(palette.accentTint),
    tertiaryContainer: tint,
    onTertiaryContainer: onSurface,
  );
  final heroActionBackground = dark ? palette.darkTint : palette.accentTint;
  final heroActionForeground = dark
      ? palette.darkText
      : contrastingOn(heroActionBackground);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: 'Roboto',
    dividerColor: outline,
    cardColor: surface,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: TextStyle(
        color: onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    extensions: [
      AppThemeTokens(
        heroBackground: heroBackground,
        heroForeground: heroForeground,
        heroActionBackground: heroActionBackground,
        heroActionForeground: heroActionForeground,
        mintTint: dark ? palette.darkAccent : palette.accentTint,
        softTint: tint,
        softBackground: background,
        cardBackground: surface,
        mutedText: muted,
        divider: outline,
        accent: dark ? palette.darkAccent : palette.accentTint,
        water: dark ? const Color(0xFF4F9BE0) : const Color(0xFF1D6FB8),
        activity: dark ? const Color(0xFFE08A2E) : const Color(0xFFB25E09),
        borderWidth: palette.borderWidth,
      ),
    ],
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: dark ? palette.darkTint : palette.lightTint,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? primary
              : scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    ),
    focusColor: primary.withValues(alpha: dark ? .28 : .16),
    textTheme: ThemeData(brightness: brightness).textTheme
        .apply(bodyColor: onSurface, displayColor: onSurface),
    iconTheme: IconThemeData(color: onSurface),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline, width: inputBorderWidth),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline, width: inputBorderWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: inputBorderWidth),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  bool _localReady = false;
  Object? _localError;
  bool _sessionActive = false;
  bool _showLoginLoading = false;
  bool _loginLoadingMinimumElapsed = false;
  int _loginLoadingGeneration = 0;
  Timer? _loginLoadingTimer;
  final _navigatorKey = GlobalKey<NavigatorState>();
  XFile? _recoveredFoodScanPhoto;
  bool _recoveryRouteScheduled = false;

  @override
  void initState() {
    super.initState();
    _sessionActive = store.hasActiveSession;
    store.addListener(_handleStoreChanged);
    unawaited(_initializeLocalStore());
    unawaited(_restoreLostFoodScan());
  }

  @override
  void dispose() {
    store.removeListener(_handleStoreChanged);
    _loginLoadingTimer?.cancel();
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    final active = store.hasActiveSession;
    if (active != _sessionActive) {
      _sessionActive = active;
      if (active) {
        if (_localReady) _beginLoginLoading();
      } else {
        _loginLoadingGeneration++;
        _loginLoadingTimer?.cancel();
        if (_showLoginLoading && mounted) {
          setState(() {
            _showLoginLoading = false;
            _loginLoadingMinimumElapsed = false;
          });
        }
      }
      _openRecoveredFoodScanIfReady();
      return;
    }
    _finishLoginLoadingIfReady();
    _openRecoveredFoodScanIfReady();
  }

  void _beginLoginLoading() {
    _loginLoadingTimer?.cancel();
    final generation = ++_loginLoadingGeneration;
    setState(() {
      _showLoginLoading = true;
      _loginLoadingMinimumElapsed = false;
    });
    _loginLoadingTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || generation != _loginLoadingGeneration) return;
      _loginLoadingMinimumElapsed = true;
      _finishLoginLoadingIfReady();
    });
    _finishLoginLoadingIfReady();
  }

  void _finishLoginLoadingIfReady() {
    if (!_showLoginLoading ||
        !_loginLoadingMinimumElapsed ||
        !_localReady ||
        store.isAccountRestoring) {
      return;
    }
    _loginLoadingTimer?.cancel();
    setState(() => _showLoginLoading = false);
    _openRecoveredFoodScanIfReady();
  }

  Future<void> _initializeLocalStore() async {
    setState(() {
      _localReady = false;
      _localError = null;
    });
    try {
      if (!store.isInitialized) {
        await store.init(syncCloud: false, rollDay: false);
      }
      themeController.loadFromStore();
      store.roll();
      if (mounted) {
        _sessionActive = store.hasActiveSession;
        setState(() => _localReady = true);
        _finishLoginLoadingIfReady();
        _openRecoveredFoodScanIfReady();
      }
      unawaited(_startCloudSync());
    } catch (error, stackTrace) {
      debugPrint('Local store initialization failed: $error\n$stackTrace');
      if (mounted) setState(() => _localError = error);
    }
  }

  Future<void> _startCloudSync() async {
    if (!store.isCloudLinked) return;
    try {
      await ensureFirebaseInitialized();
    } catch (error, stackTrace) {
      debugPrint('Firebase initialization failed: $error\n$stackTrace');
      store.reportFirebaseInitializationFailure(error);
      return;
    }
    await store.startCloudSync();
  }

  Future<void> _restoreLostFoodScan() async {
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
      if (preferences.getBool(ManualMealScreen.pendingScanPreferenceKey) !=
          true) {
        return;
      }

      final response = await ImagePicker().retrieveLostData();
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        _recoveredFoodScanPhoto = files.first;
      } else if (response.exception != null) {
        debugPrint('Could not recover the captured meal photo: ${response.exception}');
      }
    } on Exception catch (error, stackTrace) {
      debugPrint('Could not recover the captured meal photo: $error\n$stackTrace');
    } finally {
      if (preferences != null) {
        try {
          await preferences.remove(ManualMealScreen.pendingScanPreferenceKey);
        } on Exception catch (error, stackTrace) {
          debugPrint(
            'Could not clear the pending meal photo recovery marker: '
            '$error\n$stackTrace',
          );
        }
      }
    }
    _openRecoveredFoodScanIfReady();
  }

  void _openRecoveredFoodScanIfReady() {
    if (!mounted ||
        _recoveredFoodScanPhoto == null ||
        !_localReady ||
        !_sessionActive ||
        store.isAccountRestoring ||
        _showLoginLoading ||
        _recoveryRouteScheduled) {
      return;
    }

    _recoveryRouteScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoveryRouteScheduled = false;
      final photo = _recoveredFoodScanPhoto;
      final navigator = _navigatorKey.currentState;
      if (!mounted ||
          photo == null ||
          navigator == null ||
          !_localReady ||
          !_sessionActive ||
          store.isAccountRestoring ||
          _showLoginLoading) {
        return;
      }
      _recoveredFoodScanPhoto = null;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ManualMealScreen(recoveredPhoto: photo),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, themeController]),
    builder: (_, _) => MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'FITTRACK',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, themeController.selectedPalette),
      darkTheme: buildTheme(Brightness.dark, themeController.selectedPalette),
      themeMode: themeController.darkMode ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 220),
      builder: (_, child) =>
          ResponsiveAppFrame(child: child ?? const SizedBox.shrink()),
      home: _localReady
          ? store.hasActiveSession
                ? store.isAccountRestoring || _showLoginLoading
                      ? const _LoadingScreen()
                      : const Shell()
                : const AuthScreen()
          : _localError == null
          ? const _LoadingScreen()
          : _StartupErrorScreen(
              error: _localError!,
              onRetry: _initializeLocalStore,
            ),
    ),
  );
}

class _LoadingScreen extends StatefulWidget {
  const _LoadingScreen();

  @override
  State<_LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<_LoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('fittract-login-loading'),
    body: Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: RepaintBoundary(
            child: RotationTransition(
              turns: _rotation,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SvgPicture.asset(
                  'assets/images/fittract_logo.svg',
                  key: const ValueKey('fittract-loading-logo'),
                  width: 112,
                  height: 112,
                  semanticsLabel: 'Fittract fitness and health logo',
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Transform.translate(
            offset: const Offset(0, 88),
            child: Text(
              'Loading your data…',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            const Text('Fittract could not load your data.'),
            const SizedBox(height: 8),
            SelectableText(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}
