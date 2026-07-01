import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the Home-screen revamp visual language.
///
/// These are the raw palette values from the source design
/// (`Arbiter Revamp.dc.html`). Prefer `Theme.of(context).colorScheme.*` in
/// widgets; reach for these named constants only for fixed, semantic status
/// colors (e.g. green = running, red = stop) or brand accents that must look
/// identical across light and dark themes.
class AppColors {
  AppColors._();

  // Brand / accent
  static const Color accent = Color(0xFFF4541F);
  static const Color accentLight = Color(0xFFF7864F);

  // Semantic status colors (fixed across themes)
  static const Color running = Color(0xFF16A34A);
  static const Color runningGlow = Color(0xFF34D27B);
  static const Color error = Color(0xFFDC2626);
  static const Color interception = Color(0xFF7C3AED);
  static const Color info = Color(0xFF2563EB);

  // Light surfaces
  static const Color lightScaffold = Color(0xFFF6F7F9);
  static const Color lightScaffoldAlt = Color(0xFFEAEBEE);
  static const Color lightCard = Color(0xFFFFFCFA);
  static const Color lightCardBorder = Color(0xFFF0E3DC);
  static const Color lightDivider = Color(0xFFF0F1F3);

  // Light text
  static const Color textPrimary = Color(0xFF17191E);
  static const Color textSecondary = Color(0xFF73777F);
  static const Color textMuted = Color(0xFF9AA0A8);

  // Dark surfaces (warm-neutral adaptation of the light palette — NOT reused
  // off-whites, but darks that keep a subtle warm tint so the orange accent
  // sits naturally on top).
  static const Color darkScaffold = Color(0xFF161412);
  static const Color darkCard = Color(0xFF211E1B);
  static const Color darkCardBorder = Color(0xFF322D28);
}

/// Monospace text style (JetBrains Mono) for URLs, ports, numbers, and code.
///
/// Exposed as a helper so widgets can reference the mono font without importing
/// `google_fonts` directly.
TextStyle monoTextStyle({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
}) {
  return GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
  );
}

final ThemeData lightTheme = _buildLightTheme();
final ThemeData darkTheme = _buildDarkTheme();

ThemeData _buildLightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppColors.lightCard,
    error: AppColors.error,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.lightScaffold,
    canvasColor: AppColors.lightScaffold,
    dividerColor: AppColors.lightDivider,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 2,
      backgroundColor: AppColors.lightCard,
      foregroundColor: AppColors.textPrimary,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      color: AppColors.lightCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.lightCardBorder),
      ),
    ),
    // mostly used by the json viewer
    highlightColor: Colors.blue.shade50,
  );

  return base.copyWith(
    textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme),
  );
}

ThemeData _buildDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    primary: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    surface: AppColors.darkCard,
    error: AppColors.error,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.darkScaffold,
    canvasColor: AppColors.darkScaffold,
    dividerColor: AppColors.darkCardBorder,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 2,
      backgroundColor: AppColors.darkCard,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      color: AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.darkCardBorder),
      ),
    ),
    highlightColor: Colors.deepPurple.shade900,
  );

  return base.copyWith(
    textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme),
  );
}
