import 'package:flutter/material.dart';

import 'models.dart';

/// Palette d'Authentik : papier chaud, encre bleu nuit, vert-de-gris pour
/// l'accent, et trois couleurs de verdict (vert, ambre, vermillon de sceau).
class Palette {
  const Palette._({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.authentic,
    required this.review,
    required this.suspect,
    required this.dark,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color accentSoft;
  final Color authentic;
  final Color review;
  final Color suspect;
  final bool dark;

  static const light = Palette._(
    bg: Color(0xFFF4F1E8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFAF8F2),
    ink: Color(0xFF172033),
    muted: Color(0xFF6A7080),
    line: Color(0xFFE4DFD2),
    accent: Color(0xFF1F6F6B),
    accentSoft: Color(0xFFDCEBE9),
    authentic: Color(0xFF2E7D5A),
    review: Color(0xFFC08410),
    suspect: Color(0xFFB3361F),
    dark: false,
  );

  static const darkTheme = Palette._(
    bg: Color(0xFF11141B),
    surface: Color(0xFF1A1F29),
    surfaceAlt: Color(0xFF151A23),
    ink: Color(0xFFE9E6DD),
    muted: Color(0xFF9AA1B0),
    line: Color(0xFF2A303C),
    accent: Color(0xFF4DB3AA),
    accentSoft: Color(0xFF1D3A3A),
    authentic: Color(0xFF4CB98A),
    review: Color(0xFFE0A93B),
    suspect: Color(0xFFE5705A),
    dark: true,
  );

  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTheme : light;

  Color verdictColor(Verdict v) => switch (v) {
        Verdict.authentic => authentic,
        Verdict.review => review,
        Verdict.suspect => suspect,
      };

  Color checkColor(CheckId id) => switch (id) {
        CheckId.sealOverlay => suspect,
        CheckId.signatureOverlay => const Color(0xFF7A4FD1),
        CheckId.textConsistency => review,
        CheckId.copyMove => const Color(0xFFD1478F),
        CheckId.noiseConsistency => accent,
        CheckId.ela => const Color(0xFF3C7DD9),
        CheckId.metadata => muted,
      };
}

const kSerif = <String>['Georgia', 'Cambria', 'Times New Roman', 'serif'];
const kSans = <String>['Segoe UI', 'Inter', 'Roboto', 'Helvetica Neue', 'Arial'];

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.darkTheme : Palette.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.accent,
    brightness: b,
  ).copyWith(
    primary: p.accent,
    surface: p.surface,
    onSurface: p.ink,
    outline: p.line,
    error: p.suspect,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    fontFamilyFallback: kSans,
    dividerColor: p.line,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
      fontFamilyFallback: kSans,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.dark ? const Color(0xFF0B1514) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.accent, width: 1.6),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      thumbColor: p.accent,
      inactiveTrackColor: p.line,
      overlayColor: p.accent.withValues(alpha: 0.12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : p.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.line,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: p.bg, fontSize: 12),
    ),
  );
}
