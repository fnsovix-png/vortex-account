import 'package:flutter/material.dart';

class Palette {
  static const background = Color(0xFF09090F);
  static const surface = Color(0xFF101019);
  static const card = Color(0xFF171522);
  static const purple = Color(0xFF8B5CF6);
  static const bright = Color(0xFFA78BFA);
  static const lavender = Color(0xFFC4B5FD);
  static const text = Colors.white;
  static const muted = Color(0xFFA1A1AA);
  static const line = Color(0xFF292536);
  static const free = Color(0xFF34D399);
  static const danger = Color(0xFFF2555A);
}

/// Turns a show's AniList colour into one bright enough to light a dark page. Purple when it has none.
Color showColor(String? hex) {
  final value = int.tryParse((hex ?? '').replaceFirst('#', ''), radix: 16);
  if (value == null) return Palette.purple;
  final hsl = HSLColor.fromColor(Color(0xFF000000 | value));
  return hsl.withSaturation(hsl.saturation.clamp(0.45, 0.9)).withLightness(hsl.lightness.clamp(0.42, 0.62)).toColor();
}

const double wideLayout = 840;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideLayout;

ThemeData buildTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Poppins');
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.background,
    colorScheme: const ColorScheme.dark(primary: Palette.purple, secondary: Palette.bright, surface: Palette.surface, onPrimary: Colors.white, error: Palette.danger),
    dividerColor: Palette.line,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.purple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Palette.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.card,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: Palette.purple)),
      hintStyle: const TextStyle(color: Palette.muted),
      labelStyle: const TextStyle(color: Palette.muted),
      floatingLabelStyle: const TextStyle(color: Palette.bright),
      counterStyle: const TextStyle(color: Palette.muted, fontSize: 11),
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: Palette.card, contentTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w600), behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(backgroundColor: Palette.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Palette.surface),
  );
}
