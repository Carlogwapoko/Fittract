import 'package:flutter/material.dart';

class AppPalette {
  final String id;
  final String name;
  final String subtitle;
  final Color primary;
  final Color hero;
  final Color lightTint;
  final Color accentTint;
  final Color softBackground;
  final Color text;
  final Color muted;
  final Color darkBackground;
  final Color darkCard;
  final Color darkPrimary;
  final Color darkText;
  final Color darkOnPrimary;
  final Color darkAccent;
  final Color darkMutedText;
  final Color darkTint;
  final Color darkHero;
  final Color darkDivider;
  final double borderWidth;

  const AppPalette({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.primary,
    required this.hero,
    required this.lightTint,
    required this.accentTint,
    required this.softBackground,
    required this.text,
    required this.muted,
    required this.darkBackground,
    required this.darkCard,
    required this.darkPrimary,
    required this.darkText,
    required this.darkOnPrimary,
    required this.darkAccent,
    required this.darkMutedText,
    required this.darkTint,
    required this.darkHero,
    required this.darkDivider,
    this.borderWidth = 1,
  });

  static const teal = AppPalette(
    id: 'teal',
    name: 'Teal',
    subtitle: 'Default look',
    primary: Color(0xFF0B6B60),
    hero: Color(0xFF1B4943),
    lightTint: Color(0xFFD7F1E9),
    accentTint: Color(0xFFA6E9D7),
    softBackground: Color(0xFFF2F6F5),
    text: Color(0xFF0F2D29),
    muted: Color(0xFF4F6964),
    darkBackground: Color(0xFF0E1B19),
    darkCard: Color(0xFF162624),
    darkPrimary: Color(0xFF5CCFBF),
    darkText: Color(0xFFE3F0ED),
    darkOnPrimary: Color(0xFF0A1F1C),
    darkAccent: Color(0xFFA6E9D7),
    darkMutedText: Color(0xFFA0AAA7),
    darkTint: Color(0xFF22463F),
    darkHero: Color(0xFF1E302C),
    darkDivider: Color(0xFF34433F),
  );

  static const all = [
    teal,
    AppPalette(
      id: 'soft_sand',
      name: 'Soft sand',
      subtitle: 'Low glare',
      primary: Color(0xFF7A5C2E),
      hero: Color(0xFF4A3B24),
      lightTint: Color(0xFFEFE3CC),
      accentTint: Color(0xFFDCC9A8),
      softBackground: Color(0xFFF5F0E6),
      text: Color(0xFF2B2418),
      muted: Color(0xFF65543A),
      darkBackground: Color(0xFF1C1812),
      darkCard: Color(0xFF272118),
      darkPrimary: Color(0xFFD9B77A),
      darkText: Color(0xFFEDE4D3),
      darkOnPrimary: Color(0xFF2B2418),
      darkAccent: Color(0xFFE69F00),
      darkMutedText: Color(0xFFA5A094),
      darkTint: Color(0xFF473C29),
      darkHero: Color(0xFF332B1E),
      darkDivider: Color(0xFF403A30),
    ),
    AppPalette(
      id: 'sage_mist',
      name: 'Sage mist',
      subtitle: 'Calm and low stimulation',
      primary: Color(0xFF4F6F5E),
      hero: Color(0xFF2F4439),
      lightTint: Color(0xFFDCE8E0),
      accentTint: Color(0xFFBBD0C2),
      softBackground: Color(0xFFF1F4F0),
      text: Color(0xFF1F2B25),
      muted: Color(0xFF4D6256),
      darkBackground: Color(0xFF131A16),
      darkCard: Color(0xFF1C2620),
      darkPrimary: Color(0xFF9CC4AB),
      darkText: Color(0xFFE1EAE4),
      darkOnPrimary: Color(0xFF16231C),
      darkAccent: Color(0xFFBBD0C2),
      darkMutedText: Color(0xFF9DA39F),
      darkTint: Color(0xFF31493A),
      darkHero: Color(0xFF25332B),
      darkDivider: Color(0xFF303A33),
    ),
    AppPalette(
      id: 'color_blind_safe',
      name: 'Color-blind safe',
      subtitle: 'No red/green reliance',
      primary: Color(0xFF0072B2),
      hero: Color(0xFF00324F),
      lightTint: Color(0xFFD6E9F5),
      accentTint: Color(0xFFE69F00),
      softBackground: Color(0xFFF4F8FB),
      text: Color(0xFF153044),
      muted: Color(0xFF456273),
      darkBackground: Color(0xFF0D1620),
      darkCard: Color(0xFF162230),
      darkPrimary: Color(0xFF56B4E9),
      darkText: Color(0xFFE6EDF3),
      darkOnPrimary: Color(0xFF07202F),
      darkAccent: Color(0xFFE69F00),
      darkMutedText: Color(0xFFA1A5AA),
      darkTint: Color(0xFF20394C),
      darkHero: Color(0xFF1D2D3C),
      darkDivider: Color(0xFF303B47),
    ),
    AppPalette(
      id: 'high_contrast',
      name: 'High contrast',
      subtitle: 'Low vision (extra contrast)',
      primary: Color(0xFF003A8C),
      hero: Color(0xFF000000),
      lightTint: Color(0xFFE7EEFA),
      accentTint: Color(0xFFFFD400),
      softBackground: Color(0xFFFFFFFF),
      text: Color(0xFF000000),
      muted: Color(0xFF444444),
      darkBackground: Color(0xFF000000),
      darkCard: Color(0xFF000000),
      darkPrimary: Color(0xFFFFD400),
      darkText: Color(0xFFFFFFFF),
      darkOnPrimary: Color(0xFF000000),
      darkAccent: Color(0xFFFFD400),
      darkMutedText: Color(0xFFB3B3B3),
      darkTint: Color(0xFF332B00),
      darkHero: Color(0xFF111111),
      darkDivider: Color(0xFFFFFFFF),
      borderWidth: 2,
    ),
    AppPalette(
      id: 'graphite',
      name: 'Graphite (gray)',
      subtitle: 'Neutral and minimal',
      primary: Color(0xFF3A3A3A),
      hero: Color(0xFF2B2B2B),
      lightTint: Color(0xFFE4E4E4),
      accentTint: Color(0xFFBDBDBD),
      softBackground: Color(0xFFF1F1F1),
      text: Color(0xFF1C1C1C),
      muted: Color(0xFF5F5F5F),
      darkBackground: Color(0xFF121212),
      darkCard: Color(0xFF1E1E1E),
      darkPrimary: Color(0xFFD0D0D0),
      darkText: Color(0xFFEDEDED),
      darkOnPrimary: Color(0xFF121212),
      darkAccent: Color(0xFFBDBDBD),
      darkMutedText: Color(0xFFA5A5A5),
      darkTint: Color(0xFF3C3C3C),
      darkHero: Color(0xFF282828),
      darkDivider: Color(0xFF393939),
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
  final Color cardBackground;
  final Color mutedText;
  final Color divider;
  final Color accent;
  final Color water;
  final Color activity;
  final double borderWidth;

  const AppThemeTokens({
    required this.heroBackground,
    required this.heroForeground,
    required this.heroActionBackground,
    required this.heroActionForeground,
    required this.mintTint,
    required this.softTint,
    required this.softBackground,
    required this.cardBackground,
    required this.mutedText,
    required this.divider,
    required this.accent,
    required this.water,
    required this.activity,
    required this.borderWidth,
  });

  double get inputBorderWidth => borderWidth < 1.5 ? 1.5 : borderWidth;
  double get focusedInputBorderWidth => borderWidth > 1.5 ? borderWidth : 3;

  @override
  AppThemeTokens copyWith({
    Color? heroBackground,
    Color? heroForeground,
    Color? heroActionBackground,
    Color? heroActionForeground,
    Color? mintTint,
    Color? softTint,
    Color? softBackground,
    Color? cardBackground,
    Color? mutedText,
    Color? divider,
    Color? accent,
    Color? water,
    Color? activity,
    double? borderWidth,
  }) => AppThemeTokens(
    heroBackground: heroBackground ?? this.heroBackground,
    heroForeground: heroForeground ?? this.heroForeground,
    heroActionBackground: heroActionBackground ?? this.heroActionBackground,
    heroActionForeground: heroActionForeground ?? this.heroActionForeground,
    mintTint: mintTint ?? this.mintTint,
    softTint: softTint ?? this.softTint,
    softBackground: softBackground ?? this.softBackground,
    cardBackground: cardBackground ?? this.cardBackground,
    mutedText: mutedText ?? this.mutedText,
    divider: divider ?? this.divider,
    accent: accent ?? this.accent,
    water: water ?? this.water,
    activity: activity ?? this.activity,
    borderWidth: borderWidth ?? this.borderWidth,
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
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      water: Color.lerp(water, other.water, t)!,
      activity: Color.lerp(activity, other.activity, t)!,
      borderWidth: _lerpDouble(borderWidth, other.borderWidth, t),
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

AppThemeTokens appTokensOf(BuildContext context) {
  final theme = Theme.of(context);
  final configured = theme.extension<AppThemeTokens>();
  if (configured != null) return configured;

  final palette = AppPalette.teal;
  final dark = theme.brightness == Brightness.dark;
  final heroBackground = dark ? palette.darkHero : palette.hero;
  final heroActionBackground = dark ? palette.darkTint : palette.accentTint;
  return AppThemeTokens(
    heroBackground: heroBackground,
    heroForeground: dark ? palette.darkText : contrastingOn(heroBackground),
    heroActionBackground: heroActionBackground,
    heroActionForeground: dark
        ? palette.darkText
        : contrastingOn(heroActionBackground),
    mintTint: dark ? palette.darkAccent : palette.accentTint,
    softTint: dark ? palette.darkTint : palette.lightTint,
    softBackground: dark ? palette.darkBackground : palette.softBackground,
    cardBackground: dark ? palette.darkCard : Colors.white,
    mutedText: dark ? palette.darkMutedText : palette.muted,
    divider: dark
        ? palette.darkDivider
        : palette.primary.withValues(alpha: .24),
    accent: dark ? palette.darkAccent : palette.accentTint,
    water: dark ? const Color(0xFF4F9BE0) : const Color(0xFF1D6FB8),
    activity: dark ? const Color(0xFFE08A2E) : const Color(0xFFB25E09),
    borderWidth: 1,
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
