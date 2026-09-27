import 'package:flutter/material.dart';
import '../screens/settings/edit_profile_screen.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

class UserProfileMenuButton extends StatelessWidget {
  final VoidCallback? onOpenSettings;

  const UserProfileMenuButton({
    super.key,
    this.onOpenSettings,
  });

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Sign Out?',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to sign out of your account?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.absent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService().signOut();
            },
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AuthService().profileNotifier, ThemeService()]),
      builder: (context, _) {
        final auth = AuthService();
        final theme = ThemeService();
        final user = auth.currentUser;
        final email = user?.email ?? auth.email;
        final name = auth.displayName;

        return PopupMenuButton<String>(
          tooltip: 'Account Menu',
          offset: const Offset(0, 48),
          color: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.surfaceBorder),
          ),
          onSelected: (value) {
            if (value == 'edit_profile') {
              EditProfileScreen.navigate(context);
            } else if (value == 'toggle_theme') {
              theme.toggleTheme();
            } else if (value == 'settings' && onOpenSettings != null) {
              onOpenSettings!();
            } else if (value == 'logout') {
              _confirmSignOut(context);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 220,
                    child: Row(
                      children: [
                        const UserAvatar(radius: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                email,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: AppColors.surfaceBorder, height: 1),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'edit_profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Text('Edit Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'toggle_theme',
              child: Row(
                children: [
                  Icon(
                    theme.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: AppColors.secondary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    theme.isDarkMode ? 'Light Mode' : 'Dark Mode',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  ),
                ],
              ),
            ),
            if (onOpenSettings != null)
              PopupMenuItem<String>(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined, color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: 10),
                    Text('Gym Settings', style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                  ],
                ),
              ),
            PopupMenuItem<String>(
              value: 'logout',
              child: Row(
                children: [
                  const Icon(Icons.logout_rounded, color: AppColors.absent, size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Sign Out',
                    style: TextStyle(
                      color: AppColors.absent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          child: const Padding(
            padding: EdgeInsets.only(right: 12),
            child: UserAvatar(radius: 17),
          ),
        );
      },
    );
  }
}
