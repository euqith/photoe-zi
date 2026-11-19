import 'package:flutter/material.dart';

class StudioColors {
  StudioColors._();

  /// Canvas Background: Hitam pekat netral di belakang foto utama (#0F0F10)
  static const Color canvasBackground = Color(0xFF0F0F10);

  /// Panel / Toolbar Surface: Abu gelap untuk Top Bar, Right Inspector, dan Filmstrip (#1A1A1D)
  static const Color panelSurface = Color(0xFF1A1A1D);

  /// Panel Surface Elevated / Card (#222226)
  static const Color panelElevated = Color(0xFF222226);

  /// Panel Border / Divider: Garis tipis 1px pemisah antar panel (#2A2A2E)
  static const Color panelBorder = Color(0xFF2A2A2E);

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
        onPrimary: Color(0xFF000000),
        onSecondary: Color(0xFF000000),
        onSurface: StudioColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: StudioColors.panelSurface,
        foregroundColor: StudioColors.textPrimary,
        elevation: 0,
        centerTitle: false,
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

