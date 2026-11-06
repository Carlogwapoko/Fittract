import 'package:flutter/material.dart';

class AppPalette {
  final String id;
  final String name;
  final Color primary;
  final Color hero;
  final Color lightTint;
  final Color accentTint;
  final Color softBackground;
  final Color text;

  const AppPalette({
    required this.id,
    required this.name,
    required this.primary,
    required this.hero,
    required this.lightTint,
    required this.accentTint,
    required this.softBackground,
    required this.text,
  });

  static const teal = AppPalette(
    id: 'teal',
    name: 'Teal',
    primary: Color(0xFF0B6B60),
    hero: Color(0xFF1B4943),
    lightTint: Color(0xFFD7F1E9),
    accentTint: Color(0xFFA6E9D7),
    softBackground: Color(0xFFF2F6F5),
    text: Color(0xFF0F2D29),
  );

  static const all = [
    teal,
    AppPalette(
      id: 'ocean',
      name: 'Ocean blue',
      primary: Color(0xFF176B87),
      hero: Color(0xFF123E55),
      lightTint: Color(0xFFD7EFF7),
      accentTint: Color(0xFFA6DCEC),
      softBackground: Color(0xFFF1F7FA),
      text: Color(0xFF17303A),
    ),
    AppPalette(
      id: 'forest',
      name: 'Forest green',
      primary: Color(0xFF36734A),
      hero: Color(0xFF234A32),
      lightTint: Color(0xFFDDF1E2),
      accentTint: Color(0xFFA6D8B4),
      softBackground: Color(0xFFF2F7F1),
      text: Color(0xFF1F3325),
    ),
    AppPalette(
      id: 'sunset',
      name: 'Sunset orange',
      primary: Color(0xFFB85A26),
      hero: Color(0xFF713A20),
      lightTint: Color(0xFFFBE4D0),
      accentTint: Color(0xFFF5C29A),
      softBackground: Color(0xFFFBF5F0),
      text: Color(0xFF38271D),
    ),
    AppPalette(
      id: 'berry',
      name: 'Berry purple',
      primary: Color(0xFF774C9A),
      hero: Color(0xFF442B5C),
      lightTint: Color(0xFFEDE0F6),
      accentTint: Color(0xFFD8B9EA),
      softBackground: Color(0xFFF7F3FA),
      text: Color(0xFF30263A),
    ),
    AppPalette(
      id: 'rose',
      name: 'Rose pink',
      primary: Color(0xFFA84F6F),
      hero: Color(0xFF673248),
      lightTint: Color(0xFFF7DFE8),
      accentTint: Color(0xFFF0B6CA),
      softBackground: Color(0xFFFBF3F6),
      text: Color(0xFF38232C),
    ),
    AppPalette(
      id: 'slate',
      name: 'Slate',
      primary: Color(0xFF536777),
      hero: Color(0xFF334452),
      lightTint: Color(0xFFE0E9EF),
      accentTint: Color(0xFFB8CBD8),
      softBackground: Color(0xFFF3F6F8),
      text: Color(0xFF25323A),
    ),
  ];

  static AppPalette byId(String? id) =>
      all.firstWhere((palette) => palette.id == id, orElse: () => teal);
}

class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  final Color heroBackground;
  final Color heroForeground;
  final Color heroActionBackground;
  final Color heroActionForeground;
  final Color mintTint;
  final Color softTint;
  final Color softBackground;

  const AppThemeTokens({
    required this.heroBackground,
    required this.heroForeground,
    required this.heroActionBackground,
    required this.heroActionForeground,
    required this.mintTint,
    required this.softTint,
    required this.softBackground,
  });

  @override
  AppThemeTokens copyWith({
    Color? heroBackground,
    Color? heroForeground,
    Color? heroActionBackground,
    Color? heroActionForeground,
    Color? mintTint,
    Color? softTint,
    Color? softBackground,
  }) => AppThemeTokens(
    heroBackground: heroBackground ?? this.heroBackground,
    heroForeground: heroForeground ?? this.heroForeground,
    heroActionBackground: heroActionBackground ?? this.heroActionBackground,
    heroActionForeground: heroActionForeground ?? this.heroActionForeground,
    mintTint: mintTint ?? this.mintTint,
    softTint: softTint ?? this.softTint,
    softBackground: softBackground ?? this.softBackground,
  );

  @override
  AppThemeTokens lerp(ThemeExtension<AppThemeTokens>? other, double t) {
    if (other is! AppThemeTokens) return this;
    return AppThemeTokens(
      heroBackground: Color.lerp(heroBackground, other.heroBackground, t)!,
      heroForeground: Color.lerp(heroForeground, other.heroForeground, t)!,
      heroActionBackground: Color.lerp(
        heroActionBackground,
        other.heroActionBackground,
        t,
      )!,
      heroActionForeground: Color.lerp(
        heroActionForeground,
        other.heroActionForeground,
        t,
      )!,
      mintTint: Color.lerp(mintTint, other.mintTint, t)!,
      softTint: Color.lerp(softTint, other.softTint, t)!,
      softBackground: Color.lerp(softBackground, other.softBackground, t)!,
    );
  }
}

AppThemeTokens appTokensOf(BuildContext context) {
  final theme = Theme.of(context);
  final configured = theme.extension<AppThemeTokens>();
  if (configured != null) return configured;

  final palette = AppPalette.teal;
  final dark = theme.brightness == Brightness.dark;
  final heroBackground = dark
      ? Color.alphaBlend(
          palette.hero.withValues(alpha: .45),
          const Color(0xFF101A18),
        )
      : palette.hero;
  final heroActionBackground = dark ? palette.primary : palette.accentTint;
  return AppThemeTokens(
    heroBackground: heroBackground,
    heroForeground: contrastingOn(heroBackground),
    heroActionBackground: heroActionBackground,
    heroActionForeground: contrastingOn(heroActionBackground),
    mintTint: palette.accentTint,
    softTint: palette.lightTint,
    softBackground: dark ? const Color(0xFF101A18) : palette.softBackground,
  );
}

Color contrastingOn(Color background) {
  final whiteContrast = _contrastRatio(Colors.white, background);
  final darkContrast = _contrastRatio(const Color(0xFF101A18), background);
  return whiteContrast >= darkContrast ? Colors.white : const Color(0xFF101A18);
}

double _contrastRatio(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + .05) / (darker + .05);
}

bool hasAccessibleContrast(Color foreground, Color background) =>
    _contrastRatio(foreground, background) >= 4.5;
