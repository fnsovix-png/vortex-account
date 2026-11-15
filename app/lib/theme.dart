import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF0C0C10);
  static const surface = Color(0xFF16161C);
  static const card = Color(0xFF24242C);
  static Color accent = const Color(0xFF5CF08F);
  static const subtle = Color(0xFFA9A9B2);
  static const hairline = Color(0x22FFFFFF);
}

class ThemePreset {
  final String id;
  final String label;
  final List<Color> colors;

  const ThemePreset(this.id, this.label, this.colors);
}

const themePresets = [
  ThemePreset('aurora', 'Aurora', [Color(0xFF1FA67A), Color(0xFF2B7FD1), Color(0xFF7B3FE4), Color(0xFF14B8A6)]),
  ThemePreset('ember', 'Ember', [Color(0xFFE2542B), Color(0xFFD9326B), Color(0xFFF0A020), Color(0xFF9B2C5E)]),
  ThemePreset('orchid', 'Orchid', [Color(0xFF9D3FD6), Color(0xFFE0479E), Color(0xFF5B3FD6), Color(0xFFC13FA6)]),
  ThemePreset('ocean', 'Ocean', [Color(0xFF1668C7), Color(0xFF0FA3B8), Color(0xFF2840B8), Color(0xFF12B5A0)]),
  ThemePreset('sunset', 'Sunset', [Color(0xFFF0653F), Color(0xFF8E3FD6), Color(0xFFF0A63F), Color(0xFFD63F7E)]),
  ThemePreset('mono', 'Mono', [Color(0xFF5A5A5A), Color(0xFF3A3A3A), Color(0xFF7A7A7A), Color(0xFF2C2C2C)]),
  ThemePreset('rose', 'Rose', [Color(0xFFD9577F), Color(0xFFE8A0B8), Color(0xFFB03F6A), Color(0xFFD97FA0)]),
  ThemePreset('mint', 'Mint', [Color(0xFF2FBF9B), Color(0xFF7FD9B8), Color(0xFF1F8F8A), Color(0xFF3FBF7F)]),
  ThemePreset('candy', 'Candy', [Color(0xFFE85FB0), Color(0xFF5FA8E8), Color(0xFFB07FE8), Color(0xFF5FD9E0)]),
  ThemePreset('lava', 'Lava', [Color(0xFFD92F1F), Color(0xFFF07A1F), Color(0xFF8A140E), Color(0xFFE0501F)]),
  ThemePreset('forest', 'Forest', [Color(0xFF2F7F4A), Color(0xFF7A9A3F), Color(0xFF1F5F4A), Color(0xFF4F8A5A)]),
  ThemePreset('royal', 'Royal', [Color(0xFF3F2FB0), Color(0xFFC29A3F), Color(0xFF6A2F9B), Color(0xFF2F3F9B)]),
];

const double wideBreakpoint = 900;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;

ThemeData buildTheme({String? fontFamily}) {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true, fontFamily: fontFamily);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      onPrimary: Colors.black,
    ),
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.background, elevation: 0, scrolledUnderElevation: 0),
    sliderTheme: SliderThemeData(
      activeTrackColor: Colors.white,
      inactiveTrackColor: const Color(0x33FFFFFF),
      thumbColor: AppColors.accent,
      overlayColor: const Color(0x22FFFFFF),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      trackHeight: 2.5,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Colors.white,
      contentTextStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
    ),
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
  );
}
