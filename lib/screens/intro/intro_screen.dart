import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../auth/auth_gate.dart';

class IntroScreen extends StatefulWidget {
  final bool isReview;

  const IntroScreen({
    super.key,
    this.isReview = false,
  });

  static const String keyHasSeenIntro = 'has_seen_intro_v1';

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<_IntroSlideData> _slides = const [
    _IntroSlideData(
      badge: 'MEMBER DIRECTORY & CHECK-IN',
      title: 'Smart Member &\nAttendance Tracking',
      subtitle:
          'Register members with photos, track 1-tap daily attendance, manage workout plans, and monitor expiring subscriptions in real-time.',
      icon: Icons.groups_rounded,
      accentColor: Color(0xFFCCFF00),
      features: [
        '1-Tap Daily Attendance Check-In',
        'Normal, Personal Training & Diet Plans',
        'Automatic Expiration Status Flags',
      ],
    ),
    _IntroSlideData(
      badge: 'DIGITAL BILLING & ALERTS',
      title: 'One-Tap Invoicing &\nWhatsApp Reminders',
      subtitle:
          'Create professional gym receipts, track pending dues effortlessly, and send formatted WhatsApp alerts with fee breakdowns in seconds.',
      icon: Icons.receipt_long_rounded,
      accentColor: Color(0xFF00E5FF),
      features: [
        'Professional Digital Bills & Receipts',
        'Instant WhatsApp Payment Reminders',
        'Cash, UPI & Card Payment Tracking',
      ],
    ),
    _IntroSlideData(
      badge: 'GROWTH & FINANCIAL ANALYTICS',
      title: 'Real-Time Expenses &\nBusiness Insights',
      subtitle:
          'Record gym expenses, track daily net revenue, view membership growth charts, and export PDF/Excel reports with zero hassle.',
      icon: Icons.insights_rounded,
      accentColor: Color(0xFF00E676),
      features: [
        'Monthly Cashflow & Revenue Breakdowns',
        'Maintenance, Rent & Salary Expense Logs',
        'Comprehensive Profit & Loss Analytics',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(IntroScreen.keyHasSeenIntro, true);

    if (!mounted) return;

    if (widget.isReview) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, anim, secondaryAnim) => const AuthGate(),
          transitionsBuilder: (context, animation, secondaryAnim, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  void _onNext() {
    if (_currentIndex < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _completeIntro();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentIndex];
    final isLast = _currentIndex == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar with Branding & Skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  // App Brand Logo Chip
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      color: AppColors.primary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'IRONPULSE',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),

                  // Skip or Close Button
                  if (widget.isReview)
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondary,
                      tooltip: 'Close Tour',
                      visualDensity: VisualDensity.compact,
                    )
                  else if (!isLast)
                    TextButton(
                      onPressed: _completeIntro,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 32),
                ],
              ),
            ),

            // Page View Carousel
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final item = _slides[index];

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final availableHeight = constraints.maxHeight;
                      final isCompact = availableHeight < 620;
                      final isVeryShort = availableHeight < 500;

                      final heroHeight = isVeryShort
                          ? 120.0
                          : (isCompact ? 160.0 : 200.0);
                      final iconSize = isVeryShort
                          ? 38.0
                          : (isCompact ? 48.0 : 58.0);

                      return SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: isCompact ? 6 : 12,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(height: isCompact ? 4 : 10),

                                // Visual Hero Card
                                Container(
                                  height: heroHeight,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        item.accentColor.withValues(alpha: 0.15),
                                        AppColors.surfaceElevated,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: item.accentColor.withValues(alpha: 0.25),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: item.accentColor.withValues(alpha: 0.08),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Background glowing pulse rings
                                      Container(
                                        width: heroHeight * 0.65,
                                        height: heroHeight * 0.65,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: item.accentColor.withValues(alpha: 0.1),
                                        ),
                                      ),
                                      Container(
                                        width: heroHeight * 0.45,
                                        height: heroHeight * 0.45,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: item.accentColor.withValues(alpha: 0.18),
                                        ),
                                      ),
                                      // Main Icon
                                      Icon(
                                        item.icon,
                                        size: iconSize,
                                        color: item.accentColor,
                                      ),
                                    ],
                                  ),
                                ),

                                SizedBox(height: isCompact ? 14 : 20),

                                // Category Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: item.accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: item.accentColor.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    item.badge,
                                    style: TextStyle(
                                      color: item.accentColor,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),

                                SizedBox(height: isCompact ? 10 : 14),

                                // Title
                                Text(
                                  item.title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: isVeryShort ? 19 : (isCompact ? 22 : 25),
                                    fontWeight: FontWeight.w900,
                                    height: 1.2,
                                    letterSpacing: -0.4,
                                  ),
                                ),

                                SizedBox(height: isCompact ? 8 : 10),

                                // Subtitle
                                Text(
                                  item.subtitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: isVeryShort ? 12 : 13.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),

                                SizedBox(height: isCompact ? 12 : 16),

                                // Feature Chips list
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: isCompact ? 10 : 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.surfaceBorder),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: item.features.map((feat) {
                                      return Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: isCompact ? 3.5 : 5,
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.check_circle_rounded,
                                              size: isCompact ? 15 : 17,
                                              color: item.accentColor,
                                            ),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: Text(
                                                feat,
                                                style: TextStyle(
                                                  color: AppColors.textPrimary,
                                                  fontSize: isCompact ? 12 : 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                SizedBox(height: isCompact ? 10 : 16),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Bottom Navigation & Indicator Controls
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.surfaceBorder),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Row(
                    children: [
                      // Dot Page Indicators
                      Row(
                        children: List.generate(_slides.length, (index) {
                          final isSelected = _currentIndex == index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.only(right: 4),
                            height: 7,
                            width: isSelected ? 20 : 6,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? slide.accentColor
                                  : AppColors.surfaceBorder,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),

                      const Spacer(),

                      // Back button (if index > 0)
                      if (_currentIndex > 0) ...[
                        IconButton(
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          padding: const EdgeInsets.all(4),
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          color: AppColors.textSecondary,
                          tooltip: 'Previous',
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 2),
                      ],

                      // Next / Get Started Action Button
                      ElevatedButton(
                        onPressed: _onNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.primaryOn,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isLast ? 'Get Started' : 'Next',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              isLast
                                  ? Icons.rocket_launch_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroSlideData {
  final String badge;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final List<String> features;

  const _IntroSlideData({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.features,
  });
}
