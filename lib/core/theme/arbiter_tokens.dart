import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the redesigned endpoint editor, derived from the
/// "Arbiter Revamp" Claude Design mock-up. These are scoped to the editor
/// surfaces and intentionally do not replace the app-wide [ThemeData].
///
/// Obtain a light/dark-aware instance with [ArbTokens.of].
class ArbTokens {
  const ArbTokens._(this.brightness);

  final Brightness brightness;

  factory ArbTokens.of(BuildContext context) =>
      ArbTokens._(Theme.of(context).brightness);

  bool get _dark => brightness == Brightness.dark;

  // ---- Brand ----
  /// Primary accent (orange) — shared across light/dark.
  Color get accent => const Color(0xFFF4541F);
  Color get accentSoft => const Color(0x1AF4541F); // 10% accent

  // ---- Surfaces ----
  /// Page/scaffold background behind cards.
  Color get canvas => _dark ? const Color(0xFF15171C) : const Color(0xFFF6F7F9);

  /// Card / input background.
  Color get surface => _dark ? const Color(0xFF1E2127) : Colors.white;

  /// Slightly inset fill (segmented tracks, stepper buttons).
  Color get surfaceMuted =>
      _dark ? const Color(0xFF262A31) : const Color(0xFFEEF0F2);

  /// Hairline borders around cards and inputs.
  Color get border => _dark ? const Color(0xFF2C313A) : const Color(0xFFE6E7EB);

  // ---- Text ----
  Color get textPrimary =>
      _dark ? const Color(0xFFF2F3F5) : const Color(0xFF17191E);
  Color get textSecondary =>
      _dark ? const Color(0xFF9BA1AA) : const Color(0xFF73777F);
  Color get textMuted =>
      _dark ? const Color(0xFF6E7681) : const Color(0xFF9AA0A8);

  // ---- Accents used by badges/dots ----
  Color get green => const Color(0xFF16A34A);
  Color get purple => const Color(0xFF7C3AED);

  /// Dark code-editor surfaces (constant in both themes, like an IDE).
  Color get codeBg => const Color(0xFF0E1117);
  Color get codeBorder => const Color(0xFF20262E);
  Color get codeText => const Color(0xFFC9D1D9);

  // ---- Radii ----
  double get radius => 12;
  double get radiusSm => 9;

  // ---- Typography ----
  /// Section-label style: uppercase mono, muted.
  TextStyle get label => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: textMuted,
      );

  /// Monospace style for paths, code, values.
  TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color ?? textPrimary,
      );

  /// Sans style for UI copy and headings.
  TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color? color,
  }) =>
      GoogleFonts.hankenGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color ?? textPrimary,
      );

  /// Returns a status-code color (2xx green, 4xx amber, 5xx red).
  Color statusColor(int code) {
    if (code >= 200 && code < 300) return green;
    if (code >= 400 && code < 500) return const Color(0xFFF59E0B);
    if (code >= 500) return const Color(0xFFDC2626);
    return textMuted;
  }
}
