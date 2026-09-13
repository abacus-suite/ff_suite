import 'package:flutter/material.dart';

/// Aixolo brand colours, taken from the logo (royal blue -> sky -> aqua).
class AixoloColors {
  static const primary = Color(0xFF1A56DB);
  static const primaryDark = Color(0xFF0B3AA8);
  static const sky = Color(0xFF1E90FF);
  static const teal = Color(0xFF14D3C0);
  static const background = Color(0xFFF4F7FE);
  static const border = Color(0xFFE3E9F6);
  static const text = Color(0xFF0F1B3D);
  static const muted = Color(0xFF6B7A99);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);
  static const purple = Color(0xFF7C5CFC);

  static const brandGradient = LinearGradient(
    colors: [primary, sky, teal],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  static const headerGradient = LinearGradient(
    colors: [Color(0xFFDCEBFF), Color(0xFFEEF5FF), background],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );
  static const dangerGradient = LinearGradient(colors: [Color(0xFFE53935), Color(0xFFFF7A45)]);
}

ThemeData aixoloTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AixoloColors.primary,
    primary: AixoloColors.primary,
    secondary: AixoloColors.teal,
    surface: Colors.white,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AixoloColors.border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AixoloColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AixoloColors.background,
      foregroundColor: AixoloColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          color: AixoloColors.text, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.2),
      centerTitle: false,
    ),
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AixoloColors.text),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, color: AixoloColors.text),
      bodyMedium: TextStyle(color: AixoloColors.text, height: 1.35),
      bodySmall: TextStyle(color: AixoloColors.muted, height: 1.3),
      labelLarge: TextStyle(fontWeight: FontWeight.w700),
    ),
    listTileTheme: const ListTileThemeData(
      titleTextStyle: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AixoloColors.text),
      subtitleTextStyle: TextStyle(fontSize: 12.5, color: AixoloColors.muted, height: 1.3),
      iconColor: AixoloColors.muted,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shadowColor: const Color(0x1A0F1B3D),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AixoloColors.border.withValues(alpha: 0.7)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AixoloColors.primary,
        shape: rounded,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: rounded,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        side: const BorderSide(color: AixoloColors.primary),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF7F9FD),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AixoloColors.primary, width: 1.6)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: AixoloColors.border.withValues(alpha: 0.8)),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFFE8EFFF),
      // Spelled out: left to the scheme, labels came out white on white.
      labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AixoloColors.text),
      secondaryLabelStyle:
          const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AixoloColors.primary),
      checkmarkColor: AixoloColors.primary,
      iconTheme: const IconThemeData(color: AixoloColors.primary, size: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    dividerTheme: DividerThemeData(color: AixoloColors.border.withValues(alpha: 0.7), space: 20),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFE3EDFF),
      elevation: 8,
      shadowColor: const Color(0x260F1B3D),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AixoloColors.primary,
      foregroundColor: Colors.white,
    ),
  );
}
