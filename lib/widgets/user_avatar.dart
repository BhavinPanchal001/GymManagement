import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'customer_avatar.dart';

class UserAvatar extends StatelessWidget {
  final String? imagePath;
  final String? name;
  final double radius;
  final VoidCallback? onTap;
  final bool showEditBadge;

  const UserAvatar({
    super.key,
    this.imagePath,
    this.name,
    this.radius = 24,
    this.onTap,
    this.showEditBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService().profileNotifier,
      builder: (context, _) {
        final auth = AuthService();
        final effectiveImage = imagePath ?? auth.profilePhotoPath;
        final effectiveName = name ?? auth.displayName;

        final avatarWidget = CustomerAvatar(
          imagePath: effectiveImage,
          name: effectiveName.isNotEmpty ? effectiveName : 'Gym Owner',
          radius: radius,
          onTap: onTap,
        );

        if (!showEditBadge) {
          return avatarWidget;
        }

        final badgeSize = (radius * 0.7).clamp(24.0, 36.0);
        final iconSize = (badgeSize * 0.55).clamp(14.0, 20.0);

        return GestureDetector(
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              avatarWidget,
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: badgeSize,
                  height: badgeSize,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.surface,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.camera_alt_rounded,
                      size: iconSize,
                      color: AppColors.primaryOn,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
