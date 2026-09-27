import 'dart:io';
import 'package:flutter/material.dart';

class CustomerAvatar extends StatelessWidget {
  final String? imagePath;
  final String name;
  final double radius;
  final VoidCallback? onTap;

  const CustomerAvatar({
    super.key,
    required this.imagePath,
    required this.name,
    this.radius = 24,
    this.onTap,
  });

  static final List<List<Color>> avatarGradients = [
    [const Color(0xFFFF5722), const Color(0xFFFF9800)],
    [const Color(0xFF7C4DFF), const Color(0xFF00B0FF)],
    [const Color(0xFF00E676), const Color(0xFF1DE9B6)],
    [const Color(0xFFFF4081), const Color(0xFFFF80AB)],
    [const Color(0xFFFFD600), const Color(0xFFFF6D00)],
    [const Color(0xFF00B0FF), const Color(0xFF00E5FF)],
    [const Color(0xFF651FFF), const Color(0xFFB388FF)],
    [const Color(0xFF00C853), const Color(0xFF64DD17)],
  ];

  static final List<IconData> avatarIcons = [
    Icons.fitness_center_rounded,
    Icons.sports_gymnastics_rounded,
    Icons.local_fire_department_rounded,
    Icons.directions_run_rounded,
    Icons.sports_mma_rounded,
    Icons.bolt_rounded,
    Icons.military_tech_rounded,
    Icons.favorite_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    Widget avatarContent;

    if (imagePath != null && imagePath!.startsWith('avatar:')) {
      final indexStr = imagePath!.replaceAll('avatar:', '');
      final index = (int.tryParse(indexStr) ?? 1) - 1;
      final safeIndex = (index >= 0 && index < avatarGradients.length) ? index : 0;
      final gradient = avatarGradients[safeIndex];
      final icon = avatarIcons[safeIndex % avatarIcons.length];

      avatarContent = Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: radius * 1.05,
          color: Colors.white,
        ),
      );
    } else if (imagePath != null && imagePath!.isNotEmpty) {
      if (imagePath!.startsWith('http://') || imagePath!.startsWith('https://')) {
        avatarContent = Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: NetworkImage(imagePath!),
              fit: BoxFit.cover,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        );
      } else {
        String cleanPath = imagePath!;
        if (cleanPath.startsWith('file://')) {
          try {
            cleanPath = Uri.parse(cleanPath).toFilePath();
          } catch (_) {
            cleanPath = cleanPath.replaceFirst('file://', '');
          }
        }
        final file = File(cleanPath);
        if (file.existsSync()) {
          avatarContent = Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
                image: FileImage(file),
                fit: BoxFit.cover,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          );
        } else {
          avatarContent = _buildInitialsFallback();
        }
      }
    } else {
      avatarContent = _buildInitialsFallback();
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatarContent,
      );
    }

    return avatarContent;
  }

  Widget _buildInitialsFallback() {
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
        : 'U';

    final safeIndex = (name.hashCode.abs()) % avatarGradients.length;
    final gradient = avatarGradients[safeIndex];

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.85,
          ),
        ),
      ),
    );
  }
}
