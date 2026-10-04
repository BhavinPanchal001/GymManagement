import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/customer.dart';
import '../../models/payment.dart';
import '../../models/plan_package.dart';
import '../../services/gym_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../utils/nav_keys.dart';
import '../../widgets/avatar_selector.dart';
import 'customer_detail_screen.dart';

class AddCustomerSheet extends StatefulWidget {
  final Customer? customerToEdit;
  final BuildContext? parentContext;

  const AddCustomerSheet({super.key, this.customerToEdit, this.parentContext});

  static Future<bool?> show(BuildContext context, {Customer? customerToEdit}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddCustomerSheet(
        customerToEdit: customerToEdit,
        parentContext: context,
      ),
    );
  }

  @override
  State<AddCustomerSheet> createState() => _AddCustomerSheetState();
}

class _AddCustomerSheetState extends State<AddCustomerSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _notesController;
  late TextEditingController _cardNumberController;
  late TextEditingController _addressController;
  late TextEditingController _weightController;
  late TextEditingController _chestController;
  late TextEditingController _bicepController;
  late TextEditingController _waistController;
  late TextEditingController _legController;
  bool _showMeasurements = false;

  String? _selectedImagePath;
  late DateTime _joinDate;
  late DateTime _membershipStartDate;
  late DateTime _membershipEndDate;
  String _selectedPlan = CustomerPlan.normal;
  int _selectedDurationMonths = 1;
  bool _collectPaymentNow = false;
  PaymentMethod _selectedPaymentMethod = PaymentMethod.cash;
  bool _isLoading = false;
  late final String _registrationOperationId;

  bool get isEditing => widget.customerToEdit != null;

  @override
  void initState() {
    super.initState();
    _registrationOperationId =
        '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}';
    _nameController = TextEditingController(text: widget.customerToEdit?.name ?? '');
    String initialPhone = widget.customerToEdit?.phone ?? '';
    if (initialPhone.isNotEmpty) {
      final digits = initialPhone.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 12 && digits.startsWith('91')) {
        initialPhone = digits.substring(2);
      } else if (digits.length >= 10) {
        initialPhone = digits.substring(digits.length - 10);
      }
    }
    _phoneController = TextEditingController(text: initialPhone);
    _notesController = TextEditingController(text: widget.customerToEdit?.notes ?? '');
    _cardNumberController = TextEditingController(
      text: widget.customerToEdit?.cardNumber.isNotEmpty == true
          ? widget.customerToEdit!.cardNumber
          : GymService().getNextCardNumber(),
    );
    _addressController = TextEditingController(text: widget.customerToEdit?.address ?? '');
    _weightController = TextEditingController(text: widget.customerToEdit?.weight ?? '');
    _chestController = TextEditingController(text: widget.customerToEdit?.chest ?? '');
    _bicepController = TextEditingController(text: widget.customerToEdit?.bicep ?? '');
    _waistController = TextEditingController(text: widget.customerToEdit?.waist ?? '');
    _legController = TextEditingController(text: widget.customerToEdit?.leg ?? '');
    _showMeasurements =
        (widget.customerToEdit?.weight.isNotEmpty == true ||
        widget.customerToEdit?.chest.isNotEmpty == true ||
        widget.customerToEdit?.bicep.isNotEmpty == true);

    _selectedImagePath = widget.customerToEdit?.imagePath ?? 'avatar:1';
    _joinDate = widget.customerToEdit?.joinDate ?? DateTime.now();
    _selectedPlan = widget.customerToEdit?.planType ?? CustomerPlan.normal;
    _selectedDurationMonths = widget.customerToEdit?.planDurationMonths ?? 1;

    _membershipStartDate = _joinDate;
    _membershipEndDate = GymDateUtils.computeAnniversaryEndDate(_membershipStartDate, _selectedDurationMonths);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _cardNumberController.dispose();
    _addressController.dispose();
    _weightController.dispose();
    _chestController.dispose();
    _bicepController.dispose();
    _waistController.dispose();
    _legController.dispose();
    super.dispose();
  }

  Future<void> _pickJoinDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joinDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: AppColors.primaryOn,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _joinDate = picked;
        _membershipStartDate = picked;
        _membershipEndDate = GymDateUtils.computeAnniversaryEndDate(_membershipStartDate, _selectedDurationMonths);
      });
    }
  }

  Future<void> _pickMembershipStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _membershipStartDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) {
      setState(() {
        _membershipStartDate = picked;
        _membershipEndDate = GymDateUtils.computeAnniversaryEndDate(_membershipStartDate, _selectedDurationMonths);
      });
    }
  }

  Future<void> _pickMembershipEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _membershipEndDate.isAfter(_membershipStartDate)
          ? _membershipEndDate
          : _membershipStartDate.add(const Duration(days: 1)),
      firstDate: _membershipStartDate,
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) => Theme(data: Theme.of(context), child: child!),
    );
    if (picked != null) {
      setState(() {
        _membershipEndDate = picked;
      });
    }
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    Customer? createdCustomer;

    if (isEditing) {
      final updated = widget.customerToEdit!.copyWith(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        imagePath: _selectedImagePath,
        clearImagePath: _selectedImagePath == null,
        joinDate: _joinDate,
        notes: _notesController.text.trim(),
        planType: _selectedPlan,
        planDurationMonths: _selectedDurationMonths,
        cardNumber: _cardNumberController.text.trim(),
        address: _addressController.text.trim(),
        weight: _weightController.text.trim(),
        chest: _chestController.text.trim(),
        bicep: _bicepController.text.trim(),
        waist: _waistController.text.trim(),
        leg: _legController.text.trim(),
      );
      await GymService().updateCustomer(updated);
    } else {
      createdCustomer = await GymService().addCustomer(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        imagePath: _selectedImagePath,
        joinDate: _joinDate,
        notes: _notesController.text.trim(),
        planType: _selectedPlan,
        planDurationMonths: _selectedDurationMonths,
        cardNumber: _cardNumberController.text.trim(),
        address: _addressController.text.trim(),
        weight: _weightController.text.trim(),
        chest: _chestController.text.trim(),
        bicep: _bicepController.text.trim(),
        waist: _waistController.text.trim(),
        leg: _legController.text.trim(),
        markAsPaidNow: _collectPaymentNow,
        initialPaymentMethod: _collectPaymentNow ? _selectedPaymentMethod : null,
        membershipStartDate: _membershipStartDate,
        membershipEndDate: _membershipEndDate,
        membershipFee: GymService().settings.getPriceForDuration(
          _selectedPlan, _selectedDurationMonths,
        ),
        operationId: _registrationOperationId,
      );
    }

    setState(() => _isLoading = false);

    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);

      if (isEditing) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Member "${_nameController.text.trim()}" updated successfully!',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.paid,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (createdCustomer != null) {
        final newCustomerId = createdCustomer.id;
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(
              customerId: newCustomerId,
              initialTabIndex: 1, // Open directly on Attendance tab
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = GymService().settings.currencySymbol;
    return Container(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.surfaceBorder, width: 1.5)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pill handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.surfaceBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                isEditing ? 'Edit Member Profile' : 'Register New Member',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),

              // Avatar / Photo Selector
              AvatarSelector(
                initialImagePath: _selectedImagePath,
                initialImageBase64:
                    _selectedImagePath == widget.customerToEdit?.imagePath
                        ? widget.customerToEdit?.imageBase64
                        : null,
                customerName: _nameController.text,
                storageKey:
                    'avatar_${widget.customerToEdit?.id ?? _registrationOperationId}',
                onImageSelected: (newPath) {
                  setState(() => _selectedImagePath = newPath);
                },
              ),
              const SizedBox(height: 20),

              // Full Name Field
              Text(
                'Full Name',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'e.g. Rahul Sharma',
                  prefixIcon: Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter member name';
                  }
                  return null;
                },
                onChanged: (text) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // Phone Number Field
              Text(
                'Phone Number',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  _PhoneNumberFormatter(),
                ],
                style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'e.g. 9876543210',
                  prefixIcon: Icon(Icons.phone_rounded, color: AppColors.secondary, size: 20),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter phone number';
                  }
                  final trimmed = val.trim();
                  if (trimmed.length != 10 || !RegExp(r'^\d{10}$').hasMatch(trimmed)) {
                    return 'Please enter a valid 10-digit phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Card Number & Joining Date Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Card No.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB71C1C).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ENTRY',
                                style: TextStyle(color: Color(0xFFB71C1C), fontSize: 9, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _cardNumberController,
                          keyboardType: TextInputType.text,
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            hintText: 'e.g. 778',
                            prefixIcon: Icon(Icons.badge_rounded, color: Color(0xFFB71C1C), size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Joining Date',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _pickJoinDate,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    GymDateUtils.formatDate(_joinDate),
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Address Field
              Text(
                'Address (Optional)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressController,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Station Road, Market Area',
                  prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.textMuted, size: 20),
                ),
              ),
              const SizedBox(height: 16),

              // Body Measurements Expandable Card
              _buildMeasurementsCard(),
              const SizedBox(height: 16),

              // Membership Plan Selector
              Row(
                children: [
                  Text(
                    'Membership Plan',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'MONTHLY TIER',
                      style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildPlanOption(
                planKey: CustomerPlan.normal,
                title: 'Normal Plan',
                subtitle: 'Standard gym access & equipment usage',
                icon: Icons.fitness_center_rounded,
                accentColor: AppColors.primary,
                monthlyFee: GymService().settings.normalPlanFee,
                currency: GymService().settings.currencySymbol,
              ),
              const SizedBox(height: 8),
              _buildPlanOption(
                planKey: CustomerPlan.personalTraining,
                title: 'Plan with Personal Training',
                subtitle: 'Dedicated 1-on-1 personal training coach',
                icon: Icons.sports_martial_arts_rounded,
                accentColor: AppColors.secondary,
                monthlyFee: GymService().settings.ptPlanFee,
                currency: GymService().settings.currencySymbol,
              ),
              const SizedBox(height: 8),
              _buildPlanOption(
                planKey: CustomerPlan.personalTrainingDiet,
                title: 'Plan with Personal Training + Diet',
                subtitle: 'Personal trainer plus tailored nutrition chart',
                icon: Icons.restaurant_menu_rounded,
                accentColor: const Color(0xFFFF9100),
                monthlyFee: GymService().settings.ptDietPlanFee,
                currency: GymService().settings.currencySymbol,
              ),
              const SizedBox(height: 18),

              // Duration Package Selector
              _buildDurationPackageSelector(currency),
              const SizedBox(height: 16),

              // Upfront Payment Toggle Card (Only when registering new member)
              if (!isEditing) ...[_buildUpfrontPaymentCard(currency), const SizedBox(height: 16)],

              // Notes Field
              Text(
                'Workout Notes / Goals (Optional)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(hintText: 'e.g. Weight loss plan, morning slot 7am'),
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.primaryOn,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primaryOn),
                        )
                      : Text(
                          isEditing ? 'Save Changes' : 'Register Member',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanOption({
    required String planKey,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required double monthlyFee,
    required String currency,
  }) {
    final isSelected = _selectedPlan == planKey;

    return InkWell(
      onTap: () => setState(() => _selectedPlan = planKey),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.12) : AppColors.surfaceElevated.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? accentColor : AppColors.surfaceBorder, width: isSelected ? 1.8 : 1.0),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? accentColor.withValues(alpha: 0.25) : AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? accentColor : AppColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? accentColor.withValues(alpha: 0.2) : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? accentColor.withValues(alpha: 0.6) : AppColors.surfaceBorder),
              ),
              child: Text(
                '$currency${monthlyFee.toInt()}/mo',
                style: TextStyle(
                  color: isSelected ? accentColor : AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationPackageSelector(String currency) {
    final settings = GymService().settings;
    final packages = settings.getPackagesForPlan(_selectedPlan);

    final hasMatch = packages.any((p) => p.months == _selectedDurationMonths);
    final effectiveSelected = hasMatch ? _selectedDurationMonths : (packages.isNotEmpty ? packages.first.months : 1);

    Color accentColor;
    switch (_selectedPlan) {
      case CustomerPlan.personalTraining:
        accentColor = AppColors.secondary;
        break;
      case CustomerPlan.personalTrainingDiet:
        accentColor = const Color(0xFFFF9100);
        break;
      case CustomerPlan.normal:
      default:
        accentColor = AppColors.primary;
        break;
    }

    final oneMonthPkg = packages.firstWhere(
      (p) => p.months == 1,
      orElse: () =>
          packages.isNotEmpty ? packages.first : const PlanDurationPackage(id: '', planType: '', months: 1, price: 600),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(
              'Package Duration (Combo Pricing)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            )),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$effectiveSelected ${effectiveSelected == 1 ? "MONTH" : "MONTHS"}',
                style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...packages.map((pkg) {
          final isSelected = effectiveSelected == pkg.months;
          final payablePrice = settings.totalForConfiguredPrice(pkg.price);
          final regularPrice = settings.totalForConfiguredPrice(oneMonthPkg.price * pkg.months);
          final savings = (pkg.months > 1 && regularPrice > payablePrice) ? (regularPrice - payablePrice).toInt() : 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => setState(() {
                _selectedDurationMonths = pkg.months;
                _membershipEndDate = GymDateUtils.computeAnniversaryEndDate(_membershipStartDate, _selectedDurationMonths);
              }),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor.withValues(alpha: 0.12)
                      : AppColors.surfaceElevated.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? accentColor : AppColors.surfaceBorder,
                    width: isSelected ? 1.8 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: isSelected ? accentColor : AppColors.textMuted,
                      size: 19,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            runSpacing: 4,
                            children: [
                              Text(
                                pkg.title,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              if (savings > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.paid.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'SAVE $currency$savings',
                                    style: const TextStyle(
                                      color: AppColors.paid,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (pkg.months > 1) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Effective $currency${pkg.monthlyRate.toStringAsFixed(0)} / month',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      GymDateUtils.formatCurrency(payablePrice, symbol: currency),
                      style: TextStyle(
                        color: isSelected ? accentColor : AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildUpfrontPaymentCard(String currency) {
    final settings = GymService().settings;
    final fee = settings.totalForConfiguredPrice(
      settings.getPriceForDuration(_selectedPlan, _selectedDurationMonths),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _collectPaymentNow
            ? AppColors.paid.withValues(alpha: 0.08)
            : AppColors.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _collectPaymentNow ? AppColors.paid.withValues(alpha: 0.5) : AppColors.surfaceBorder,
          width: _collectPaymentNow ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_collectPaymentNow ? AppColors.paid : AppColors.primary).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.payments_rounded,
                  color: _collectPaymentNow ? AppColors.paid : AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Collect Payment Now',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mark membership as settled upfront',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _collectPaymentNow,
                // activeThumbColor: AppColors.paid,
                activeTrackColor: AppColors.paid.withValues(alpha: 0.5),
                onChanged: (val) {
                  setState(() => _collectPaymentNow = val);
                },
              ),
            ],
          ),
          ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickMembershipStartDate,
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'START DATE',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.edit_calendar_rounded, size: 12, color: AppColors.primary),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                GymDateUtils.formatDate(_membershipStartDate),
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textSecondary),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: _pickMembershipEndDate,
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'EXPIRY DATE',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.edit_calendar_rounded, size: 12, color: AppColors.primary),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                GymDateUtils.formatDate(_membershipEndDate),
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range_rounded, size: 13, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Validity: ${GymDateUtils.formatDateRange(_membershipStartDate, _membershipEndDate)}',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Registration Fee',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${CustomerPlan.getShortLabel(_selectedPlan)} • $_selectedDurationMonths ${_selectedDurationMonths == 1 ? "Month" : "Months"}',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                  Text(
                    GymDateUtils.formatCurrency(fee, symbol: currency),
                    style: TextStyle(color: AppColors.paid, fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_collectPaymentNow) ...[
            Text(
              'Payment Method',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                    PaymentMethod.cash,
                    PaymentMethod.gpay,
                    PaymentMethod.phonepe,
                    PaymentMethod.paytm,
                    PaymentMethod.upi,
                    PaymentMethod.card,
                  ].map((method) {
                    final isSelected = _selectedPaymentMethod == method;
                    return InkWell(
                      onTap: () => setState(() => _selectedPaymentMethod = method),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.paid.withValues(alpha: 0.18) : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppColors.paid : AppColors.surfaceBorder,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                              size: 14,
                              color: isSelected ? AppColors.paid : AppColors.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              method.label,
                              style: TextStyle(
                                color: isSelected ? AppColors.paid : AppColors.textPrimary,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
            ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildMeasurementsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showMeasurements = !_showMeasurements),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB71C1C).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.straighten_rounded, color: Color(0xFFB71C1C), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Body Measurements (Entry Card)',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Wt, Chest, Bicep, Waist, Leg',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showMeasurements ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_showMeasurements) ...[
            Divider(height: 1, color: AppColors.surfaceBorder),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildMeasurementInput('Weight (Wt)', '72 kg', _weightController)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildMeasurementInput('Chest', '38"', _chestController)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildMeasurementInput('Bicep', '14.5"', _bicepController)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildMeasurementInput('Waist', '32"', _waistController)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildMeasurementInput('Leg', '22"', _legController)),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMeasurementInput(String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
        ),
      ],
    );
  }
}

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    String digits = text.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }

    int newOffset = digits.length;
    if (newValue.selection.end <= text.length) {
      newOffset = newValue.selection.end.clamp(0, digits.length);
    }

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
