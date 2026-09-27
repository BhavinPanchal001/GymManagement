import 'package:flutter/material.dart';
import '../services/theme_service.dart';

class AppColors {
  static bool get isDark => ThemeService().isDarkMode;

  // Dark Palette
  static const Color _darkBackground = Color(0xFF0C1017);
  static const Color _darkSurface = Color(0xFF161B24);
  static const Color _darkSurfaceElevated = Color(0xFF1F2633);
  static const Color _darkSurfaceBorder = Color(0xFF2B3444);
  static const Color _darkPrimary = Color(0xFFCCFF00); // Cyber Neon Lime
  static const Color _darkPrimaryOn = Color(0xFF0C1017);
  static const Color _darkSecondary = Color(0xFF00E5FF); // Electric Cyan
  static const Color _darkTextPrimary = Color(0xFFFFFFFF);
  static const Color _darkTextSecondary = Color(0xFFA1ACB8);
  static const Color _darkTextMuted = Color(0xFF657182);
  static const Color _darkWhatsappSurface = Color(0xFF0F2B1D);

  // Light Palette
  static const Color _lightBackground = Color(0xFFF6F8FC);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceElevated = Color(0xFFF1F5F9);
  static const Color _lightSurfaceBorder = Color(0xFFE2E8F0);
  static const Color _lightPrimary = Color(0xFF16A34A); // Vibrant Athletic Emerald
  static const Color _lightPrimaryOn = Color(0xFFFFFFFF);
  static const Color _lightSecondary = Color(0xFF0284C7); // Athletic Blue
  static const Color _lightTextPrimary = Color(0xFF0F172A); // Slate 900
  static const Color _lightTextSecondary = Color(0xFF475569); // Slate 600
  static const Color _lightTextMuted = Color(0xFF94A3B8); // Slate 400
  static const Color _lightWhatsappSurface = Color(0xFFE8F8EE);

  // Dynamic Theme Colors (Adaptive to Light & Dark Mode)
  static Color get background => isDark ? _darkBackground : _lightBackground;
  static Color get surface => isDark ? _darkSurface : _lightSurface;
  static Color get surfaceElevated => isDark ? _darkSurfaceElevated : _lightSurfaceElevated;
  static Color get surfaceBorder => isDark ? _darkSurfaceBorder : _lightSurfaceBorder;
  static Color get primary => isDark ? _darkPrimary : _lightPrimary;
  static Color get primaryOn => isDark ? _darkPrimaryOn : _lightPrimaryOn;
  static Color get secondary => isDark ? _darkSecondary : _lightSecondary;
  static Color get textPrimary => isDark ? _darkTextPrimary : _lightTextPrimary;
  static Color get textSecondary => isDark ? _darkTextSecondary : _lightTextSecondary;
  static Color get textMuted => isDark ? _darkTextMuted : _lightTextMuted;
  static Color get whatsappSurface => isDark ? _darkWhatsappSurface : _lightWhatsappSurface;

  // Dynamic Theme Helpers (for backward compatibility)
  static Color dynamicBackground() => background;
  static Color dynamicSurface() => surface;
  static Color dynamicSurfaceElevated() => surfaceElevated;
  static Color dynamicSurfaceBorder() => surfaceBorder;
  static Color dynamicPrimary() => primary;
  static Color dynamicPrimaryOn() => primaryOn;
  static Color dynamicSecondary() => secondary;
  static Color dynamicTextPrimary() => textPrimary;
  static Color dynamicTextSecondary() => textSecondary;
  static Color dynamicTextMuted() => textMuted;
  static Color dynamicWhatsappSurface() => whatsappSurface;

  // Direct access to explicit mode palettes when needed
  static const Color darkBackground = _darkBackground;
  static const Color darkSurface = _darkSurface;
  static const Color darkSurfaceElevated = _darkSurfaceElevated;
  static const Color darkSurfaceBorder = _darkSurfaceBorder;
  static const Color darkPrimary = _darkPrimary;
  static const Color darkPrimaryOn = _darkPrimaryOn;

  static const Color lightBackground = _lightBackground;
  static const Color lightSurface = _lightSurface;
  static const Color lightSurfaceElevated = _lightSurfaceElevated;
  static const Color lightSurfaceBorder = _lightSurfaceBorder;
  static const Color lightPrimary = _lightPrimary;
  static const Color lightPrimaryOn = _lightPrimaryOn;

  // Shared Status Colors (Vibrant and high contrast in both themes)
  static const Color paid = Color(0xFF00E676); // Emerald Green
  static const Color pending = Color(0xFFFF9100); // Amber Orange
  static const Color absent = Color(0xFFFF5252); // Crimson Coral
  static const Color rest = Color(0xFF448AFF); // Athletic Blue

  // WhatsApp Branding
  static const Color whatsapp = Color(0xFF25D366);
  static const Color whatsappDark = Color(0xFF128C7E);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkPrimary,
        onPrimary: AppColors.darkPrimaryOn,
        surface: AppColors.darkSurface,
        onSurface: Color(0xFFFFFFFF),
        error: AppColors.absent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.darkSurfaceBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.darkSurfaceBorder, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkSurfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkSurfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkPrimary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: Color(0xFF657182), fontSize: 14),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary,
        onPrimary: AppColors.lightPrimaryOn,
        surface: AppColors.lightSurface,
        onSurface: Color(0xFF0F172A),
        error: AppColors.absent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Color(0xFF0F172A)),
        titleTextStyle: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightSurfaceBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.lightSurfaceBorder, width: 1),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightSurfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightSurfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.lightPrimary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      ),
    );
  }
}
