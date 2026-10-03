import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/gym_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../home_screen.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _authStateChanges;
  StreamSubscription<User?>? _authSubscription;
  String? _lastAttachedUserId;

  @override
  void initState() {
    super.initState();
    // Reusing this stream prevents rebuilds from replacing HomeScreen with the
    // loading screen and losing its selected tab and navigation history.
    _authStateChanges = AuthService().authStateChanges;
    _authSubscription = _authStateChanges.listen((user) async {
      if (user != null) {
        if (_lastAttachedUserId != user.uid) {
          _lastAttachedUserId = user.uid;
          await GymService().attachUser(user.uid);
          await NotificationService().onUserAuthenticated(user.uid);
        }
      } else {
        _lastAttachedUserId = null;
        await GymService().detachUser(clearMemory: true);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If Firebase failed to initialize on startup
    if (Firebase.apps.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.pending.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: AppColors.pending,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Firebase Setup Pending',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Firebase has not been initialized. Please configure your Firebase project credentials in lib/firebase_options.dart or run `flutterfire configure`.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    // Allow navigating to HomeScreen for offline mode exploration
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Continue Offline / Demo Mode'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.primaryOn,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: _authStateChanges,
      builder: (context, snapshot) {
        // While Firebase is checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading Gym Manager...',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // If authenticated, navigate to HomeScreen
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }

        // If not authenticated, show AuthScreen (Sign In / Sign Up)
        return const AuthScreen();
      },
    );
  }
}
