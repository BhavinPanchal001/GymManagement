import 'package:flutter/material.dart';

/// Centralized animation constants and utilities ensuring consistent,
/// silky smooth, and professional micro-interactions throughout Gym Manager.
class AppAnimations {
  // Micro-interactions (taps, toggles, badges, chips)
  static const Duration microDuration = Duration(milliseconds: 180);

  // Normal transitions (dialogs, cards expanding, tab indicators, status changes)
  static const Duration normalDuration = Duration(milliseconds: 280);

  // Larger page / content entrance animations
  static const Duration contentDuration = Duration(milliseconds: 380);

  // Modal sheets and screen transitions
  static const Duration pageDuration = Duration(milliseconds: 320);

  // Stagger step interval for lists / grids
  static const Duration staggerStep = Duration(milliseconds: 45);

  // Curvature standards
  static const Curve curveFastOut = Curves.fastOutSlowIn;
  static const Curve curveEaseOut = Curves.easeOutCubic;
  static const Curve curveEaseInOut = Curves.easeInOutCubic;
  static const Curve curveSpring = Curves.easeOutBack;

  /// Check whether the user has requested reduced motion in system settings.
  static bool isReducedMotion(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  /// Get effective duration considering reduced motion preferences.
  static Duration getEffectiveDuration(BuildContext context, Duration duration) {
    if (isReducedMotion(context)) {
      return Duration.zero;
    }
    return duration;
  }
}
