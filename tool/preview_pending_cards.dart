// Run: flutter run -d chrome -t tool/preview_pending_cards.dart
// Uses memory-only sample data; never attaches to a Firebase account.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym/screens/customers/customers_tab.dart';
import 'package:gym/services/gym_service.dart';
import 'package:gym/services/theme_service.dart';
import 'package:gym/theme/app_theme.dart';

const previewThemeMode = ThemeMode.dark;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Deliberately isolate this sample preview from stored member data.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  await GymService().init();
  await GymService().resetToDemoData(force: true);
  await ThemeService().init();
  await ThemeService().setThemeMode(previewThemeMode);
  runApp(
    MaterialApp(
      title: 'Pending Members · Card Preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: previewThemeMode,
      home: const CustomersTab(),
    ),
  );
}
