import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/gym_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gym_logo_widget.dart';
import '../home_screen.dart';
import 'forgot_password_sheet.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Sign In controllers
  final _signInFormKey = GlobalKey<FormState>();
  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();
  bool _signInObscurePassword = true;
  bool _isSignInLoading = false;
  String? _signInError;

  // Sign Up controllers
  final _signUpFormKey = GlobalKey<FormState>();
  final _signUpNameController = TextEditingController();
  final _signUpGymNameController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPasswordController = TextEditingController();
  final _signUpConfirmPasswordController = TextEditingController();
  String? _signUpSelectedImagePath;
  bool _signUpObscurePassword = true;
  bool _signUpObscureConfirmPassword = true;
  bool _isSignUpLoading = false;
  String? _signUpError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        if (!_tabController.indexIsChanging) {
          _signInError = null;
          _signUpError = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpGymNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    _signUpConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!_signInFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isSignInLoading = true;
      _signInError = null;
    });

    try {
      await AuthService().signInWithEmailAndPassword(
        email: _signInEmailController.text,
        password: _signInPasswordController.text,
      );
      // Navigation is automatically handled by AuthGate
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSignInLoading = false;
          _signInError = AuthService().getReadableErrorMessage(e);
        });
      }
    }
  }

  Future<void> _handleSignUp() async {
    if (!_signUpFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isSignUpLoading = true;
      _signUpError = null;
    });

    try {
      await AuthService().signUpWithEmailAndPassword(
        email: _signUpEmailController.text,
        password: _signUpPasswordController.text,
        displayName: _signUpNameController.text,
        photoPath: _signUpSelectedImagePath,
      );
      final gymName = _signUpGymNameController.text.trim();
      await GymService().updateSettings(
        GymService().settings.copyWith(
          gymName: gymName.isNotEmpty ? gymName : GymService().settings.gymName,
          gymLogoPath: _signUpSelectedImagePath,
        ),
      );
      // Navigation is automatically handled by AuthGate
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSignUpLoading = false;
          _signUpError = AuthService().getReadableErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Branding Header
                  _buildHeader(),
                  const SizedBox(height: 32),

                  // Tab switcher (Sign In / Sign Up)
                  _buildTabBar(),
                  const SizedBox(height: 24),

                  // Forms Container
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _tabController.index == 0
                        ? _buildSignInCard()
                        : _buildSignUpCard(),
                  ),
                  const SizedBox(height: 18),

                  // Offline / Guest Mode Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.flash_on_rounded, color: AppColors.primary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Explore Without Firebase',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Offline mode with full member management',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const HomeScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.primaryOn,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text(
                            'Open App',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.fitness_center_rounded,
            color: AppColors.primaryOn,
            size: 38,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'GYM MANAGER',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Manage members, attendance & subscriptions',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabController,
        onTap: (index) => setState(() {}),
        indicator: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.5),
            width: 1.2,
          ),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        tabs: const [
          Tab(text: 'Sign In'),
          Tab(text: 'Create Account'),
        ],
      ),
    );
  }

  Widget _buildSignInCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: AutofillGroup(
        child: Form(
          key: _signInFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_signInError != null) ...[
              _buildErrorBanner(_signInError!),
              const SizedBox(height: 18),
            ],

            // Email input
            _buildTextField(
              controller: _signInEmailController,
              label: 'Email Address',
              hint: 'owner@example.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(val.trim())) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password input
            _buildTextField(
              controller: _signInPasswordController,
              label: 'Password',
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscureText: _signInObscurePassword,
              autofillHints: const [AutofillHints.password],
              suffixIcon: IconButton(
                icon: Icon(
                  _signInObscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _signInObscurePassword = !_signInObscurePassword;
                  });
                },
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Please enter your password';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),

            // Forgot Password button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  ForgotPasswordSheet.show(
                    context,
                    initialEmail: _signInEmailController.text.trim(),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sign In Action Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSignInLoading ? null : _handleSignIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.primaryOn,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isSignInLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primaryOn,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.login_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Sign In',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildSignUpCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: AutofillGroup(
        child: Form(
          key: _signUpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_signUpError != null) ...[
              _buildErrorBanner(_signUpError!),
              const SizedBox(height: 18),
            ],

            // Gym Brand Logo Selector
            Center(
              child: Column(
                children: [
                  GymLogoSelector(
                    initialLogoPath: _signUpSelectedImagePath,
                    gymName: _signUpGymNameController.text.trim().isNotEmpty
                        ? _signUpGymNameController.text.trim()
                        : (_signUpNameController.text.trim().isNotEmpty
                            ? _signUpNameController.text.trim()
                            : 'Gym'),
                    title: 'Upload Gym Logo',
                    radius: 44,
                    allowRemove: true,
                    onLogoSelected: (path) {
                      setState(() {
                        _signUpSelectedImagePath = path;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _signUpSelectedImagePath != null
                        ? 'Gym logo selected (Tap to change)'
                        : 'Upload Gym Logo (Optional)',
                    style: TextStyle(
                      color: _signUpSelectedImagePath != null
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Will appear on Member Entry Cards & Receipts',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Display Name
            _buildTextField(
              controller: _signUpNameController,
              label: 'Full Name / Gym Owner',
              hint: 'John Doe',
              icon: Icons.person_outline_rounded,
              autofillHints: const [AutofillHints.name],
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Gym Name
            _buildTextField(
              controller: _signUpGymNameController,
              label: 'Gym / Fitness Center Name',
              hint: 'e.g. IronPulse Fitness Club',
              icon: Icons.fitness_center_rounded,
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter your gym or club name';
                }
                if (val.trim().length < 2) {
                  return 'Gym name must be at least 2 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Email input
            _buildTextField(
              controller: _signUpEmailController,
              label: 'Email Address',
              hint: 'owner@example.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(val.trim())) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password input
            _buildTextField(
              controller: _signUpPasswordController,
              label: 'Password',
              hint: 'At least 6 characters',
              icon: Icons.lock_outline_rounded,
              obscureText: _signUpObscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              suffixIcon: IconButton(
                icon: Icon(
                  _signUpObscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _signUpObscurePassword = !_signUpObscurePassword;
                  });
                },
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Please enter a password';
                }
                if (val.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Confirm Password input
            _buildTextField(
              controller: _signUpConfirmPasswordController,
              label: 'Confirm Password',
              hint: 'Repeat your password',
              icon: Icons.check_circle_outline_rounded,
              obscureText: _signUpObscureConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _signUpObscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _signUpObscureConfirmPassword = !_signUpObscureConfirmPassword;
                  });
                },
              ),
              validator: (val) {
                if (val == null || val.isEmpty) {
                  return 'Please confirm your password';
                }
                if (val != _signUpPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Create Account Action Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSignUpLoading ? null : _handleSignUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.primaryOn,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isSignUpLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primaryOn,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_add_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Create Account',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.absent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.absent, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.absent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.absent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.absent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.absent,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
