import 'package:flutter/material.dart';

class StudioColors {
  StudioColors._();

  /// Canvas Background: Hitam pekat netral di belakang foto utama (#0F0F10)
  static const Color canvasBackground = Color(0xFF0F0F10);

  /// Deep Input / Recessed Field Surface (#131316)
  static const Color inputSurface = Color(0xFF131316);

  /// Panel / Toolbar Surface: Abu gelap untuk Top Bar, Right Inspector, dan Filmstrip (#1A1A1D)
  static const Color panelSurface = Color(0xFF1A1A1D);

  /// Panel Surface Elevated / Card (#222226)
  static const Color panelElevated = Color(0xFF222226);

  /// Panel Border / Divider: Garis tipis 1px pemisah antar panel (#2A2A2E)
  static const Color panelBorder = Color(0xFF2A2A2E);

  /// Subtle Border Highlight (#38383E)
  static const Color borderSubtle = Color(0xFF38383E);

  /// Active Selection Accent: Amber (#F59E0B)
  static const Color accentAmber = Color(0xFFF59E0B);

  /// Active Selection Border White (#FFFFFF)
  static const Color activeWhite = Color(0xFFFFFFFF);

  /// Text Primary (#F3F4F6)
  static const Color textPrimary = Color(0xFFF3F4F6);

  /// Text Secondary (#9CA3AF)
  static const Color textSecondary = Color(0xFF9CA3AF);

  /// Text Muted (#6B7280)
  static const Color textMuted = Color(0xFF6B7280);

  /// Status Colors
  static const Color statusSuccess = Color(0xFF10B981);
  static const Color statusError = Color(0xFFEF4444);
  static const Color statusWarning = Color(0xFFF59E0B);
  static const Color statusFavorite = Color(0xFFEC4899);
}

class StudioTheme {
  StudioTheme._();

  static const String monospaceFont = 'Courier';

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: StudioColors.canvasBackground,
      canvasColor: StudioColors.canvasBackground,
      cardColor: StudioColors.panelSurface,
      dividerColor: StudioColors.panelBorder,
      colorScheme: const ColorScheme.dark(
        primary: StudioColors.accentAmber,
        secondary: StudioColors.accentAmber,
        surface: StudioColors.panelSurface,
        error: StudioColors.statusError,
        onPrimary: Color(0xFF0A0A0B),
        onSecondary: Color(0xFF0A0A0B),
        onSurface: StudioColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: StudioColors.panelSurface,
        foregroundColor: StudioColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: StudioColors.panelSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: StudioColors.panelBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: StudioColors.inputSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        hintStyle: const TextStyle(
          color: StudioColors.textMuted,
          fontSize: 12,
        ),
        labelStyle: const TextStyle(
          color: StudioColors.textSecondary,
          fontSize: 12,
        ),
        floatingLabelStyle: const TextStyle(
          color: StudioColors.accentAmber,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: StudioColors.panelBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: StudioColors.accentAmber, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: StudioColors.statusError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: StudioColors.statusError, width: 1.4),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: StudioColors.accentAmber,
          foregroundColor: const Color(0xFF0B0B0C),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: StudioColors.textPrimary,
          backgroundColor: StudioColors.panelElevated,
          side: const BorderSide(color: StudioColors.borderSubtle),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: StudioColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: StudioColors.panelBorder,
        thickness: 1,
        space: 1,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: StudioColors.accentAmber,
        inactiveTrackColor: StudioColors.panelBorder,
        thumbColor: StudioColors.activeWhite,
        overlayColor: StudioColors.accentAmber.withValues(alpha: 0.2),
        trackHeight: 3,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: StudioColors.textPrimary, fontSize: 14),
        bodyMedium: TextStyle(color: StudioColors.textPrimary, fontSize: 13),
        bodySmall: TextStyle(color: StudioColors.textSecondary, fontSize: 11),
        labelSmall: TextStyle(
          color: StudioColors.textSecondary,
          fontSize: 11,
          fontFamily: monospaceFont,
        ),
      ),
    );
  }
}
