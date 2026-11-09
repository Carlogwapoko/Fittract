import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'store/store.dart';
import 'screens/auth_screen.dart';
import 'screens/shell_screen.dart';
import 'services/theme_controller.dart';
import 'theme/app_palette.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort: a missing/unsupported Firebase configuration must never
  // block startup — the app falls back to fully local accounts.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Keep going without cloud auth/sync.
  }
  await store.init();
  themeController.loadFromStore();
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

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, themeController]),
    builder: (_, _) => MaterialApp(
      title: 'FITTRACK',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, themeController.selectedPalette),
      darkTheme: buildTheme(Brightness.dark, themeController.selectedPalette),
      themeMode: themeController.darkMode ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 220),
      home: store.hasActiveSession ? const Shell() : const AuthScreen(),
    ),
  );
}
