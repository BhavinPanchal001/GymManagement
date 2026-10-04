import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/animation_utils.dart';

/// Provides a refined, non-jarring staggered entrance animation (fade + subtle slide).
/// Perfect for dashboard cards, list items, statistics, and modal contents.
class AnimatedFadeSlide extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset offset;
  final Curve curve;

  const AnimatedFadeSlide({
    super.key,
    required this.child,
    this.duration = AppAnimations.contentDuration,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.08),
    this.curve = AppAnimations.curveEaseOut,
  });

  /// Factory helper for staggered list items
  factory AnimatedFadeSlide.staggered({
    Key? key,
    required Widget child,
    required int index,
    int maxStaggerIndex = 8,
    Duration step = AppAnimations.staggerStep,
    Duration baseDelay = Duration.zero,
    Offset offset = const Offset(0, 0.08),
  }) {
    final effectiveIndex = index.clamp(0, maxStaggerIndex);
    return AnimatedFadeSlide(
      key: key,
      delay: baseDelay + (step * effectiveIndex),
      offset: offset,
      child: child,
    );
  }

  @override
  State<AnimatedFadeSlide> createState() => _AnimatedFadeSlideState();
}

class _AnimatedFadeSlideState extends State<AnimatedFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnimation = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(curved);

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppAnimations.isReducedMotion(context)) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
