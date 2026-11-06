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
  final primary = dark ? palette.lightTint : palette.primary;
  final heroBackground = dark
      ? Color.alphaBlend(
          palette.hero.withValues(alpha: .45),
          const Color(0xFF101A18),
        )
      : palette.hero;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
      ).copyWith(
        primary: primary,
        onPrimary: contrastingOn(primary),
        secondary: dark ? palette.lightTint : palette.hero,
        onSecondary: contrastingOn(dark ? palette.lightTint : palette.hero),
        surface: dark ? const Color(0xFF162321) : Colors.white,
        onSurface: dark ? const Color(0xFFE8F0EE) : palette.text,
        outlineVariant: dark
            ? const Color(0xFF354844)
            : palette.primary.withValues(alpha: .18),
      );
  final outline = scheme.outlineVariant;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF101A18)
        : palette.softBackground,
    fontFamily: 'Roboto',
    extensions: [
      AppThemeTokens(
        heroBackground: heroBackground,
        heroForeground: contrastingOn(heroBackground),
        heroActionBackground: dark ? palette.primary : palette.accentTint,
        heroActionForeground: contrastingOn(
          dark ? palette.primary : palette.accentTint,
        ),
        mintTint: palette.accentTint,
        softTint: palette.lightTint,
        softBackground: dark ? const Color(0xFF101A18) : palette.softBackground,
      ),
    ],
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: dark
          ? Color.alphaBlend(
              palette.primary.withValues(alpha: .22),
              scheme.surface,
            )
          : palette.lightTint,
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
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 1.5),
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
