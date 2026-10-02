import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../utils/image_storage_utils.dart';
import 'customer_avatar.dart';

class AvatarSelector extends StatefulWidget {
  final String? initialImagePath;
  final String? initialImageBase64;
  final String customerName;
  final ValueChanged<String?> onImageSelected;
  final String title;
  final bool allowRemove;
  final double radius;
  final String storageKey;

  const AvatarSelector({
    super.key,
    this.initialImagePath,
    this.initialImageBase64,
    required this.customerName,
    required this.onImageSelected,
    this.title = 'Choose Photo',
    this.allowRemove = true,
    this.radius = 46,
    this.storageKey = 'avatar',
  });

  @override
  State<AvatarSelector> createState() => _AvatarSelectorState();
}

class _AvatarSelectorState extends State<AvatarSelector> {
  String? _currentSelection;
  String? _currentImageBase64;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentSelection = widget.initialImagePath;
    _currentImageBase64 = widget.initialImageBase64;
  }

  @override
  void didUpdateWidget(covariant AvatarSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialImagePath != widget.initialImagePath ||
        oldWidget.initialImageBase64 != widget.initialImageBase64) {
      _currentSelection = widget.initialImagePath;
      _currentImageBase64 = widget.initialImageBase64;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (pickedFile != null) {
        final persistentPath = await ImageStorageUtils.persistImage(
          pickedFile.path,
          '${widget.storageKey}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        setState(() {
          _currentSelection = persistentPath;
          _currentImageBase64 = null;
        });
        widget.onImageSelected(_currentSelection);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open camera/gallery: $e'),
            backgroundColor: Colors.redAccent,
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
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildPickerOption(
                      icon: Icons.photo_camera_rounded,
                      label: 'Camera',
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
                      label: 'Gallery',
                      color: const Color(0xFF2979FF),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(ImageSource.gallery);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Or choose a fitness avatar:',
                style: TextStyle(
                  color: Color(0xFF8B949E),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 8,
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final avatarKey = 'avatar:${i + 1}';
                    final isSelected = _currentSelection == avatarKey;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _currentSelection = avatarKey;
                          _currentImageBase64 = null;
                        });
                        widget.onImageSelected(avatarKey);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: const Color(0xFFCCFF00), width: 3)
                              : null,
                        ),
                        child: CustomerAvatar(
                          imagePath: avatarKey,
                          name: 'A',
                          radius: 24,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.allowRemove && _currentSelection != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5252),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    label: const Text(
                      'Remove Photo',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    onPressed: () {
                      setState(() {
                        _currentSelection = null;
                        _currentImageBase64 = null;
                      });
                      widget.onImageSelected(null);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
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
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: _showPickerBottomSheet,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFCCFF00),
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFCCFF00).withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CustomerAvatar(
                imagePath: _currentSelection,
                imageBase64: _currentImageBase64,
                name: widget.customerName.isNotEmpty ? widget.customerName : 'New User',
                radius: widget.radius,
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
                  color: const Color(0xFFCCFF00),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Color(0xFF0F141C),
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
