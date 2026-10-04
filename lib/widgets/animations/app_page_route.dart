import 'package:flutter/material.dart';
import '../../utils/animation_utils.dart';

/// A sleek, modern page route with subtle slide and fade transition.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;

  AppPageRoute({
    required this.builder,
    super.settings,
    Duration duration = AppAnimations.pageDuration,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (AppAnimations.isReducedMotion(context)) {
              return child;
            }

            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: AppAnimations.curveEaseOut,
              reverseCurve: AppAnimations.curveEaseInOut,
            );

            // Subtle slide from right-bottom with fade
            const beginOffset = Offset(0.06, 0.0);
            const endOffset = Offset.zero;

            final slideAnimation = Tween<Offset>(
              begin: beginOffset,
              end: endOffset,
            ).animate(curvedAnimation);

            final fadeAnimation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(curvedAnimation);

            return SlideTransition(
              position: slideAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: child,
              ),
            );
          },
        );
}
