import 'package:flutter/material.dart';
import '../../models/customer.dart';
import '../../models/gym_settings.dart';
import '../../models/plan_package.dart';
import '../../services/auth_service.dart';
import '../../services/gym_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gym_logo_widget.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  static Future<void> navigate(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
  }

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _gymNameController;
  late TextEditingController _emailController;

  String _selectedPlanTier = CustomerPlan.normal;
  late List<PlanDurationPackage> _packages;
  final Map<String, TextEditingController> _packageControllers = {};

  String? _selectedImagePath;
  bool _isLoading = false;
  bool _isSendingReset = false;

  @override
  void initState() {
    super.initState();
    final auth = AuthService();
    final gym = GymService();

    _nameController = TextEditingController(text: auth.displayName);
    _phoneController = TextEditingController(text: auth.phoneNumber ?? '');
    _emailController = TextEditingController(text: auth.email);
    _gymNameController = TextEditingController(text: gym.settings.gymName);
    _selectedImagePath = gym.settings.gymLogoPath ?? auth.profilePhotoPath;

    final allPackages = gym.settings.durationPackages.isNotEmpty
        ? gym.settings.durationPackages
        : GymSettings.defaultPackages;
    _packages = allPackages.map((p) => p.copyWith()).toList();
    for (var p in _packages) {
      _packageControllers[p.id] = TextEditingController(
        text: p.price.toStringAsFixed(2),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _gymNameController.dispose();
    for (var c in _packageControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    try {
      final auth = AuthService();
      final gym = GymService();

      // Update auth & profile preferences
      await auth.updateProfile(
        displayName: _nameController.text.trim(),
        photoPath: _selectedImagePath ?? '',
        phone: _phoneController.text.trim(),
      );

      // Update gym settings (Name & Plan Pricing)
      final newGymName = _gymNameController.text.trim();

      // Collect updated package prices from controllers
      final updatedPackages = _packages.map((pkg) {
        final ctrl = _packageControllers[pkg.id];
        final price = ctrl != null ? (double.tryParse(ctrl.text.trim()) ?? pkg.price) : pkg.price;
        return pkg.copyWith(price: price);
      }).toList();

      final normal1m = updatedPackages.firstWhere(
        (p) => p.planType == CustomerPlan.normal && p.months == 1,
        orElse: () => const PlanDurationPackage(id: 'pkg_norm_1', planType: CustomerPlan.normal, months: 1, price: 600.0),
      );
      final pt1m = updatedPackages.firstWhere(
        (p) => p.planType == CustomerPlan.personalTraining && p.months == 1,
        orElse: () => const PlanDurationPackage(id: 'pkg_pt_1', planType: CustomerPlan.personalTraining, months: 1, price: 2500.0),
      );
      final ptDiet1m = updatedPackages.firstWhere(
        (p) => p.planType == CustomerPlan.personalTrainingDiet && p.months == 1,
        orElse: () => const PlanDurationPackage(id: 'pkg_pt_diet_1', planType: CustomerPlan.personalTrainingDiet, months: 1, price: 3500.0),
      );

      final updatedSettings = gym.settings.copyWith(
        gymName: newGymName.isNotEmpty ? newGymName : gym.settings.gymName,
        gymLogoPath: _selectedImagePath,
        clearGymLogo: _selectedImagePath == null || _selectedImagePath!.isEmpty,
        normalPlanFee: normal1m.price,
        standardMonthlyFee: normal1m.price,
        ptPlanFee: pt1m.price,
        ptDietPlanFee: ptDiet1m.price,
        durationPackages: updatedPackages,
      );

      await gym.updateSettings(updatedSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Profile & plan pricing updated successfully!',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            backgroundColor: AppColors.surfaceElevated,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: AppColors.absent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _isSendingReset = true);

    try {
      await AuthService().sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email'),
            backgroundColor: AppColors.paid,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthService().getReadableErrorMessage(e)),
            backgroundColor: AppColors.absent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingReset = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gym = GymService();
    final currency = gym.settings.currencySymbol;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Edit Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _isLoading ? null : _handleSave,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: _isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 20),
              label: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Gym Brand Logo Section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                children: [
                  GymLogoSelector(
                    initialLogoPath: _selectedImagePath,
                    initialLogoBase64:
                        _selectedImagePath == gym.settings.gymLogoPath
                            ? gym.settings.gymLogoBase64
                            : null,
                    gymName: _gymNameController.text.isNotEmpty
                        ? _gymNameController.text
                        : (_nameController.text.isNotEmpty ? _nameController.text : 'Gym'),
                    radius: 48,
                    title: 'Gym Brand Logo',
                    storageKey:
                        'gym_logo_${AuthService().currentUser?.uid ?? 'local'}',
                    onLogoSelected: (path) {
                      setState(() {
                        _selectedImagePath = path;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_outlined, size: 15, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Gym Brand Logo',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedImagePath != null
                        ? 'Tap logo to change or remove. Displayed on Member Cards & Receipts.'
                        : 'Tap to upload gym logo. This logo appears on Member Entry Forms & Receipts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Owner Details Section
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Owner Information',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                    // Full Name
                    _buildTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      hint: 'Enter your name',
                      icon: Icons.badge_outlined,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Phone Number
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      hint: '+91 98765 43210',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),

                    // Email Address
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email Address',
                      hint: 'owner@gym.com',
                      icon: Icons.email_outlined,
                      readOnly: true,
                      helperText: 'Account email linked with your authentication credentials.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Gym Info Section
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.fitness_center_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Gym Title',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _gymNameController,
                      label: 'Gym Brand Name',
                      hint: 'e.g. IronPulse Fitness Club',
                      icon: Icons.business_outlined,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Please enter a gym name';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Membership Plans & Duration Packages Section
              _buildMembershipPackagesCard(currency),
              const SizedBox(height: 16),

              // Security & Password Section
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security_rounded, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Security & Password',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Receive a secure link on your email address to reset or change your account password.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isSendingReset ? null : _handleSendPasswordReset,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: _isSendingReset
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.lock_reset_rounded, size: 18),
                        label: const Text(
                          'Send Password Reset Link',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Save Changes Action Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.primaryOn,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryOn),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.save_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembershipPackagesCard(String currency) {
    Color tierColor;
    switch (_selectedPlanTier) {
      case CustomerPlan.personalTraining:
        tierColor = AppColors.secondary;
        break;
      case CustomerPlan.personalTrainingDiet:
        tierColor = const Color(0xFFFF9100);
        break;
      case CustomerPlan.normal:
      default:
        tierColor = AppColors.primary;
        break;
    }

    final activePackages = _packages.where((p) => p.planType == _selectedPlanTier).toList();
    activePackages.sort((a, b) => a.months.compareTo(b.months));

    // Base 1-month price for savings calculation
    final oneMonthPkg = activePackages.firstWhere(
      (p) => p.months == 1,
      orElse: () => activePackages.isNotEmpty
          ? activePackages.first
          : const PlanDurationPackage(id: '', planType: '', months: 1, price: 600),
    );
    final oneMonthPrice = double.tryParse(_packageControllers[oneMonthPkg.id]?.text.trim() ?? '') ?? oneMonthPkg.price;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Plan Tiers & Duration Packages',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'DURATION COMBOS',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Configure package fees according to duration (e.g. 1 Month ₹600, 3 Months ₹1,500) for each membership tier.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),

          // Segmented Plan Tier Tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                _buildTierTab(
                  planType: CustomerPlan.normal,
                  label: 'Normal Plan',
                  icon: Icons.fitness_center_rounded,
                  activeColor: AppColors.primary,
                ),
                const SizedBox(width: 4),
                _buildTierTab(
                  planType: CustomerPlan.personalTraining,
                  label: 'PT Coach',
                  icon: Icons.sports_martial_arts_rounded,
                  activeColor: AppColors.secondary,
                ),
                const SizedBox(width: 4),
                _buildTierTab(
                  planType: CustomerPlan.personalTrainingDiet,
                  label: 'PT + Diet',
                  icon: Icons.restaurant_menu_rounded,
                  activeColor: const Color(0xFFFF9100),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Duration Packages for active tier
          ...activePackages.map((pkg) {
            final ctrl = _packageControllers[pkg.id]!;
            final currentVal = double.tryParse(ctrl.text.trim()) ?? pkg.price;
            final regularFull = oneMonthPrice * pkg.months;
            final savings = (pkg.months > 1 && regularFull > currentVal)
                ? (regularFull - currentVal).toInt()
                : 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: tierColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: tierColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          pkg.title.toUpperCase(),
                          style: TextStyle(
                            color: tierColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (savings > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.paid.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SAVE $currency$savings',
                            style: TextStyle(
                              color: AppColors.paid,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (pkg.months > 1 || activePackages.length > 1)
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, color: AppColors.textMuted, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Remove package',
                          onPressed: () {
                            setState(() {
                              _packages.removeWhere((p) => p.id == pkg.id);
                              _packageControllers.remove(pkg.id)?.dispose();
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    onChanged: (_) => setState(() {}),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter package price';
                      }
                      final num = double.tryParse(val.trim());
                      if (num == null || num < 0) {
                        return 'Please enter a valid price';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        width: 44,
                        alignment: Alignment.center,
                        child: Text(
                          currency,
                          style: TextStyle(
                            color: tierColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      suffixText: pkg.months > 1
                          ? 'total (~$currency${(currentVal / pkg.months).toStringAsFixed(0)}/mo)'
                          : '/ month',
                      suffixStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.surfaceBorder.withValues(alpha: 0.6)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppColors.surfaceBorder.withValues(alpha: 0.6)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: tierColor, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 4),

          // Add Duration Combo Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showAddPackageDialog(context, _selectedPlanTier, currency),
              style: OutlinedButton.styleFrom(
                foregroundColor: tierColor,
                side: BorderSide(color: tierColor.withValues(alpha: 0.4), style: BorderStyle.solid),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Add Duration Combo (e.g. 2, 3, 6, 12 Months)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierTab({
    required String planType,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final isSelected = _selectedPlanTier == planType;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedPlanTier = planType),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: activeColor.withValues(alpha: 0.4)) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isSelected ? activeColor : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? (AppColors.isDark ? Colors.white : activeColor) : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddPackageDialog(BuildContext context, String planType, String currency) async {
    int selectedMonths = 3;
    final monthsController = TextEditingController(text: '3');
    final priceController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppColors.surfaceBorder),
              ),
              title: Row(
                children: [
                  Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Add Duration Combo',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan: ${CustomerPlan.getLabel(planType)}',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Select Duration (Months)',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1, 2, 3, 4, 6, 9, 12].map((m) {
                      final isSel = selectedMonths == m;
                      return ChoiceChip(
                        label: Text('$m ${m == 1 ? "Mo" : "Months"}'),
                        selected: isSel,
                        selectedColor: AppColors.primary.withValues(alpha: 0.25),
                        backgroundColor: AppColors.surfaceElevated,
                        labelStyle: TextStyle(
                          color: isSel ? AppColors.primary : AppColors.textSecondary,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        side: BorderSide(
                          color: isSel ? AppColors.primary : AppColors.surfaceBorder,
                        ),
                        onSelected: (_) {
                          setDialogState(() {
                            selectedMonths = m;
                            monthsController.text = m.toString();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Total Package Price ($currency)',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'e.g. 1500',
                      prefixIcon: Container(
                        width: 36,
                        alignment: Alignment.center,
                        child: Text(currency, style: TextStyle(color: AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final months = int.tryParse(monthsController.text.trim()) ?? selectedMonths;
                    final price = double.tryParse(priceController.text.trim());
                    if (months <= 0 || price == null || price < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid month count and price')),
                      );
                      return;
                    }

                    final newPkg = PlanDurationPackage(
                      id: 'pkg_${planType}_${months}_${DateTime.now().millisecondsSinceEpoch}',
                      planType: planType,
                      months: months,
                      price: price,
                    );

                    setState(() {
                      _packages.removeWhere((p) => p.planType == planType && p.months == months);
                      _packages.add(newPkg);
                      _packageControllers[newPkg.id] = TextEditingController(text: price.toStringAsFixed(2));
                    });

                    Navigator.pop(dialogCtx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.primaryOn,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Add Package', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          style: TextStyle(
            color: readOnly ? AppColors.textMuted : AppColors.textPrimary,
            fontSize: 15,
          ),
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helperText,
            helperMaxLines: 2,
            helperStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
            prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
            filled: true,
            fillColor: readOnly ? AppColors.surfaceElevated.withValues(alpha: 0.5) : AppColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.surfaceBorder.withValues(alpha: 0.6)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.surfaceBorder.withValues(alpha: 0.6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
