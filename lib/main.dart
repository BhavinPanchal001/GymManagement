import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'screens/splash/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/gym_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'utils/nav_keys.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase initialization error/warning: $e');
  }

  await AuthService().init();
  await GymService().init();
  await ThemeService().init();
  try {
    await NotificationService().init();
  } catch (e) {
    debugPrint('NotificationService init error/warning: $e');
  }
  runApp(const GymManagerApp());
}

class GymManagerApp extends StatelessWidget {
  const GymManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final theme = ThemeService();
        final isDark = theme.isDarkMode;
        final navBarBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;

        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: navBarBg,
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarDividerColor: Colors.transparent,
          ),
        );

        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          title: 'Gym Manager',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: theme.themeMode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
