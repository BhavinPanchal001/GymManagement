import 'package:flutter/material.dart';
import '../../utils/animation_utils.dart';

/// Smooth counting animation for numerical stats, KPI values, and currency amounts.
/// Uses Flutter's built-in [TweenAnimationBuilder] for zero-boilerplate, leak-free performance.
class AnimatedCounter extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final int decimalPlaces;
  final Duration duration;
  final Curve curve;
  final bool formatWithCommas;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.decimalPlaces = 0,
    this.duration = const Duration(milliseconds: 650),
    this.curve = AppAnimations.curveEaseOut,
    this.formatWithCommas = true,
  });

  String _formatNumber(double val) {
    if (decimalPlaces == 0) {
      final intVal = val.round();
      if (!formatWithCommas) return '$intVal';
      // Format with Indian / International comma grouping
      final s = intVal.toString();
      final regex = RegExp(r'(\d+?)(?=(\d{3})+(?!\d))');
      return s.replaceAllMapped(regex, (m) => '${m[1]},');
    } else {
      final formatted = val.toStringAsFixed(decimalPlaces);
      if (!formatWithCommas) return formatted;
      final parts = formatted.split('.');
      final whole = parts[0].replaceAllMapped(
        RegExp(r'(\d+?)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
      return '$whole.${parts[1]}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppAnimations.isReducedMotion(context)) {
      return Text(
        '$prefix${_formatNumber(value.toDouble())}$suffix',
        style: style,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (context, currentVal, child) {
        return Text(
          '$prefix${_formatNumber(currentVal)}$suffix',
          style: style,
        );
      },
    );
  }
}
