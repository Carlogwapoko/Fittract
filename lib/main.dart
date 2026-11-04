import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'store/store.dart';
import 'screens/auth_screen.dart';
import 'screens/shell_screen.dart';

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
  runApp(const App());
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? kMint : kPri;
  final scheme = ColorScheme.fromSeed(seedColor: kPri, brightness: brightness)
      .copyWith(
        primary: primary,
        onPrimary: dark ? kInk : Colors.white,
        secondary: dark ? kMint : kDk,
        surface: dark ? kSurfaceDark : Colors.white,
        onSurface: dark ? const Color(0xFFE4EFEC) : kInk,
        outlineVariant: dark ? kLineDark : kLn,
      );
  final outline = dark ? kLineDark : kLn;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? kBgDark : kBg,
    fontFamily: 'Roboto',
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: dark ? const Color(0xFF294A43) : kLt,
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
    focusColor: dark
        ? kMint.withValues(alpha: .28)
        : kPri.withValues(alpha: .16),
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

/// Built once: [buildTheme] (ColorScheme.fromSeed in particular) is too
/// expensive to run on every [Store] notify, and the App-level listenable
/// fires on every save.
class _AppThemes {
  static final ThemeData light = buildTheme(Brightness.light);
  static final ThemeData dark = buildTheme(Brightness.dark);
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (_, _) => MaterialApp(
      title: 'FITTRACK',
      debugShowCheckedModeBanner: false,
      theme: _AppThemes.light,
      darkTheme: _AppThemes.dark,
      themeMode: store.on('dark') ? ThemeMode.dark : ThemeMode.system,
      home: store.hasActiveSession ? const Shell() : const AuthScreen(),
    ),
  );
}
