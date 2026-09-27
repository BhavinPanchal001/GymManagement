import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/services/theme_service.dart';
import 'package:gym/theme/app_theme.dart';
import 'package:gym/screens/settings/settings_tab.dart';
import 'package:gym/services/gym_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final themeService = ThemeService();
    await themeService.init();
    await themeService.setThemeMode(ThemeMode.dark);
    await GymService().init();
  });

  test('ThemeService mode switching and persistence test', () async {
    final theme = ThemeService();

    // Set to Dark
    await theme.setThemeMode(ThemeMode.dark);
    expect(theme.themeMode, ThemeMode.dark);
    expect(theme.isDarkMode, true);
    expect(theme.themeModeName, 'Dark Mode');
    expect(AppColors.isDark, true);

    // Dynamic color values in dark mode
    expect(AppColors.background, AppColors.darkBackground);
    expect(AppColors.surface, AppColors.darkSurface);
    expect(AppColors.primary, AppColors.darkPrimary);

    // Set to Light
    await theme.setThemeMode(ThemeMode.light);
    expect(theme.themeMode, ThemeMode.light);
    expect(theme.isDarkMode, false);
    expect(theme.themeModeName, 'Light Mode');
    expect(AppColors.isDark, false);

    // Dynamic color values in light mode
    expect(AppColors.background, AppColors.lightBackground);
    expect(AppColors.surface, AppColors.lightSurface);
    expect(AppColors.primary, AppColors.lightPrimary);

    // Toggle theme
    await theme.toggleTheme();
    expect(theme.themeMode, ThemeMode.dark);
    expect(theme.isDarkMode, true);

    await theme.toggleTheme();
    expect(theme.themeMode, ThemeMode.light);
    expect(theme.isDarkMode, false);

    // Set to System Default
    await theme.setThemeMode(ThemeMode.system);
    expect(theme.themeMode, ThemeMode.system);
    expect(theme.themeModeName, 'System Default');
  });

  testWidgets('SettingsTab renders Theme card and interacts with mode selector', (tester) async {
    final theme = ThemeService();
    await theme.setThemeMode(ThemeMode.dark);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: theme.themeMode,
        home: const SettingsTab(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Appearance & Theme Card header
    expect(find.text('Appearance & Theme'), findsOneWidget);
    expect(find.text('Dark Mode'), findsWidgets);
    expect(find.text('Light Mode'), findsWidgets);
    expect(find.text('System'), findsWidgets);

    // Tap Light Mode selector
    await tester.tap(find.text('Light Mode').first);
    await tester.pumpAndSettle();

    expect(theme.themeMode, ThemeMode.light);
    expect(AppColors.isDark, false);

    // Tap System Default selector
    await tester.tap(find.text('System').first);
    await tester.pumpAndSettle();

    expect(theme.themeMode, ThemeMode.system);
  });
}
