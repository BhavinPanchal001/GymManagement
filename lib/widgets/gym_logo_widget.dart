import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import 'customer_avatar.dart';

/// Reusable display widget for Gym Logo with support for local file paths,
/// network URLs, avatar presets, and stylized fallbacks.
class GymLogoWidget extends StatelessWidget {
  final String? logoPath;
  final String gymName;
  final double size;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final double borderWidth;
  final Color? backgroundColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  const GymLogoWidget({
    super.key,
    required this.logoPath,
    this.gymName = 'Gym',
    this.size = 40.0,
    this.shape = BoxShape.circle,
    this.borderRadius,
    this.borderColor,
    this.borderWidth = 1.5,
    this.backgroundColor,
    this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    final effectiveBorderColor = borderColor ?? AppColors.primary;
    final effectiveIconColor = iconColor ?? effectiveBorderColor;
    final effectiveBg = backgroundColor ?? (AppColors.isDark ? AppColors.surface : Colors.white);

    if (logoPath != null && logoPath!.startsWith('avatar:')) {
      content = CustomerAvatar(
        imagePath: logoPath,
        name: gymName.isNotEmpty ? gymName : 'Gym',
        radius: size / 2,
      );
    } else if (logoPath != null && logoPath!.trim().isNotEmpty) {
      final cleanPath = _sanitizePath(logoPath!.trim());
      if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
        content = Image.network(
          cleanPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _buildFallback(effectiveIconColor, effectiveBg),
        );
      } else {
        final file = File(cleanPath);
        if (file.existsSync()) {
          content = Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, stack) => _buildFallback(effectiveIconColor, effectiveBg),
          );
        } else {
          content = _buildFallback(effectiveIconColor, effectiveBg);
        }
      }
    } else {
      content = _buildFallback(effectiveIconColor, effectiveBg);
    }

    Widget framedWidget;
    if (shape == BoxShape.circle) {
      framedWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectiveBg,
          border: Border.all(color: effectiveBorderColor, width: borderWidth),
        ),
        child: ClipOval(child: content),
      );
    } else {
      final radius = borderRadius ?? BorderRadius.circular(8);
      framedWidget = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: effectiveBg,
          border: Border.all(color: effectiveBorderColor, width: borderWidth),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: content,
        ),
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: framedWidget,
      );
    }

    return framedWidget;
  }

  Widget _buildFallback(Color iconColor, Color bg) {
    return Container(
      width: size,
      height: size,
      color: bg,
      child: Center(
        child: Icon(
          Icons.fitness_center_rounded,
          color: iconColor,
          size: size * 0.55,
        ),
      ),
    );
  }

  static String _sanitizePath(String rawPath) {
    if (rawPath.startsWith('file://')) {
      try {
        return Uri.parse(rawPath).toFilePath();
      } catch (_) {
        return rawPath.replaceFirst('file://', '');
      }
    }
    return rawPath;
  }
}

/// Interactive selector widget for uploading and updating the Gym Logo
class GymLogoSelector extends StatefulWidget {
  final String? initialLogoPath;
  final String gymName;
  final ValueChanged<String?> onLogoSelected;
  final String title;
  final bool allowRemove;
  final double radius;

  const GymLogoSelector({
    super.key,
    this.initialLogoPath,
    required this.gymName,
    required this.onLogoSelected,
    this.title = 'Gym Brand Logo',
    this.allowRemove = true,
    this.radius = 46,
  });

  @override
  State<GymLogoSelector> createState() => _GymLogoSelectorState();
}

class _GymLogoSelectorState extends State<GymLogoSelector> {
  String? _currentLogoPath;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentLogoPath = widget.initialLogoPath;
  }

  @override
  void didUpdateWidget(covariant GymLogoSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLogoPath != widget.initialLogoPath) {
      _currentLogoPath = widget.initialLogoPath;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (pickedFile != null) {
        setState(() {
          _currentLogoPath = pickedFile.path;
        });
        widget.onLogoSelected(_currentLogoPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open camera or gallery: $e'),
            backgroundColor: AppColors.absent,
          ),
        );
      }
    }
  }

  void _showPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.fitness_center_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Logo appears on member entry cards & payment receipts',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _buildPickerOption(
                        icon: Icons.photo_camera_rounded,
                        label: 'Take Photo',
                        color: const Color(0xFF00E676),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImage(ImageSource.camera);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildPickerOption(
                        icon: Icons.photo_library_rounded,
                        label: 'Choose File',
                        color: const Color(0xFF2979FF),
                        onTap: () {
                          Navigator.pop(ctx);
                          _pickImage(ImageSource.gallery);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Or pick a gym brand emblem preset:',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 8,
                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final avatarKey = 'avatar:${i + 1}';
                      final isSelected = _currentLogoPath == avatarKey;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentLogoPath = avatarKey;
                          });
                          widget.onLogoSelected(avatarKey);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: AppColors.primary, width: 3)
                                : null,
                          ),
                          child: CustomerAvatar(
                            imagePath: avatarKey,
                            name: widget.gymName,
                            radius: 24,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.allowRemove && _currentLogoPath != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.absent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: const Text(
                        'Remove Logo',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      onPressed: () {
                        setState(() {
                          _currentLogoPath = null;
                        });
                        widget.onLogoSelected(null);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _showPickerBottomSheet,
            child: Container(
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: GymLogoWidget(
                logoPath: _currentLogoPath,
                gymName: widget.gymName.isNotEmpty ? widget.gymName : 'Gym Logo',
                size: size,
                borderColor: Colors.transparent,
                borderWidth: 0,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _showPickerBottomSheet,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.primaryOn,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
