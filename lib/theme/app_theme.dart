import 'package:flutter/material.dart';
import '../services/theme_service.dart';

class AppColors {
  static bool get isDark => ThemeService().isDarkMode;

  // Dark Palette
  static const Color _darkBackground = Color(0xFF0C1017);
  static const Color _darkSurface = Color(0xFF161B24);
  static const Color _darkSurfaceElevated = Color(0xFF1F2633);
  static const Color _darkSurfaceBorder = Color(0xFF2B3444);
  static const Color _darkPrimary = Color(0xFFA8CDB6); // Soft sage
  static const Color _darkPrimaryOn = Color(0xFF0C1017);
  static const Color _darkSecondary = Color(0xFFB8D7C4); // Pale sage
  static const Color _darkTextPrimary = Color(0xFFFFFFFF);
  static const Color _darkTextSecondary = Color(0xFFA1ACB8);
  static const Color _darkTextMuted = Color(0xFF657182);
  static const Color _darkWhatsappSurface = Color(0xFF0F2B1D);

  // Light Palette
  static const Color _lightBackground = Color(0xFFF6F5EF);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceElevated = Color(0xFFE8EFE7);
  static const Color _lightSurfaceBorder = Color(0xFFDDE4DD);
  static const Color _lightPrimary = Color(0xFF234D3C); // Forest green
  static const Color _lightPrimaryOn = Color(0xFFFFFFFF);
  static const Color _lightSecondary = Color(0xFF234D3C); // Athletic Blue
  static const Color _lightTextPrimary = Color(0xFF18251F); // Slate 900
  static const Color _lightTextSecondary = Color(0xFF59685F); // Slate 600
  static const Color _lightTextMuted = Color(0xFF59685F); // Slate 400
  static const Color _lightWhatsappSurface = Color(0xFFE8F8EE);

  // Dynamic Theme Colors (Adaptive to Light & Dark Mode)
  static Color get background => isDark ? _darkBackground : _lightBackground;
  static Color get surface => isDark ? _darkSurface : _lightSurface;
  static Color get surfaceElevated =>
      isDark ? _darkSurfaceElevated : _lightSurfaceElevated;
  static Color get surfaceBorder =>
      isDark ? _darkSurfaceBorder : _lightSurfaceBorder;
  static Color get primary => isDark ? _darkPrimary : _lightPrimary;
  static Color get primaryOn => isDark ? _darkPrimaryOn : _lightPrimaryOn;
  static Color get secondary => isDark ? _darkSecondary : _lightSecondary;
  static Color get textPrimary => isDark ? _darkTextPrimary : _lightTextPrimary;
  static Color get textSecondary =>
      isDark ? _darkTextSecondary : _lightTextSecondary;
  static Color get textMuted => isDark ? _darkTextMuted : _lightTextMuted;
  static Color get whatsappSurface =>
      isDark ? _darkWhatsappSurface : _lightWhatsappSurface;

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

  // Shared Status Colors - Mode-specific definitions
  static const Color _darkPaid = Color(0xFF83BC9B); // Emerald Green
  static const Color _darkPending = Color(0xFFD8A85C); // Amber Orange
  static const Color _darkAbsent = Color(0xFFE47C76); // Crimson Coral
  static const Color _darkRest = Color(0xFF497CC2); // Athletic Blue

  static const Color _lightPaid = Color(
    0xFF236442,
  ); // Emerald 600 (High contrast WCAG AA on light mode)
  static const Color _lightPending = Color(
    0xFF8A4B08,
  ); // Amber 600 (High contrast WCAG AA on light mode)
  static const Color _lightAbsent = Color(
    0xFFB42318,
  ); // Crimson 600 (High contrast WCAG AA on light mode)
  static const Color _lightRest = Color(
    0xFF2563EB,
  ); // Athletic Blue 600 (High contrast WCAG AA on light mode)

  // Shared Status Colors (Vibrant and high contrast in both themes, usable in const contexts)
  static const Color paid = Color(0xFF278052); // Emerald Green
  static const Color pending = Color(0xFFA66510); // Amber Orange
  static const Color absent = Color(0xFFC94A46); // Crimson Coral
  static const Color rest = Color(0xFF497CC2); // Athletic Blue

  // Mode-specific definitions
  static const Color darkPaid = _darkPaid;
  static const Color darkPending = _darkPending;
  static const Color darkAbsent = _darkAbsent;
  static const Color darkRest = _darkRest;

  static const Color lightPaid = _lightPaid;
  static const Color lightPending = _lightPending;
  static const Color lightAbsent = _lightAbsent;
  static const Color lightRest = _lightRest;

  // Dynamic Theme Status Colors (for adaptive contexts where needed)
  static Color get dynamicPaid => isDark ? _darkPaid : _lightPaid;
  static Color get dynamicPending => isDark ? _darkPending : _lightPending;
  static Color get dynamicAbsent => isDark ? _darkAbsent : _lightAbsent;
  static Color get dynamicRest => isDark ? _darkRest : _lightRest;

  // WhatsApp Branding
  static const Color whatsapp = Color(0xFF25D366);
  static const Color whatsappDark = Color(0xFF128C7E);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      fontFamily: 'Roboto',
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(44, 44),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.3),
        bodyMedium: TextStyle(fontSize: 14, height: 1.3),
        bodySmall: TextStyle(fontSize: 13, height: 1.3),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkPrimary,
        onPrimary: AppColors.darkPrimaryOn,
        surface: AppColors.darkSurface,
        onSurface: Color(0xFFFFFFFF),
        error: AppColors._darkAbsent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
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
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.darkSurfaceElevated,
        contentTextStyle: TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: AppColors.darkSurfaceBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        isDense: true,
        fillColor: AppColors.darkSurfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
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
          borderSide: const BorderSide(
            color: AppColors.darkPrimary,
            width: 1.5,
          ),
        ),
        hintStyle: const TextStyle(color: Color(0xFF657182), fontSize: 14),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      fontFamily: 'Roboto',
      navigationBarTheme: NavigationBarThemeData(
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textSecondary,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(44, 44),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.3),
        bodyMedium: TextStyle(fontSize: 14, height: 1.3),
        bodySmall: TextStyle(fontSize: 13, height: 1.3),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary,
        onPrimary: AppColors.lightPrimaryOn,
        surface: AppColors.lightSurface,
        onSurface: Color(0xFF18251F),
        error: AppColors._lightAbsent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Color(0xFF18251F)),
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: Color(0xFF18251F),
          fontSize: 20,
          fontWeight: FontWeight.w700,
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
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(
          0xFF1E293B,
        ), // Slate 800: dark high-contrast snackbar in light mode
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        isDense: true,
        fillColor: AppColors.lightSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
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
          borderSide: const BorderSide(
            color: AppColors.lightPrimary,
            width: 1.5,
          ),
        ),
        hintStyle: const TextStyle(color: Color(0xFF59685F), fontSize: 14),
      ),
    );
  }
}
