import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'voice_search_sheet.dart';

/// A reusable suffix widget for search TextFields and form TextFields that includes
/// a microphone button for voice typing/search and an optional clear button.
class VoiceSearchSuffix extends StatelessWidget {
  final TextEditingController controller;
  final String? title;
  final String? voiceHint;
  final String? tooltip;
  final String? submitLabel;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final Color? iconColor;
  final double iconSize;
  final bool showClearButton;
  final String Function(String voiceResult)? transformQuery;

  const VoiceSearchSuffix({
    super.key,
    required this.controller,
    this.title,
    this.voiceHint,
    this.tooltip,
    this.submitLabel,
    this.onChanged,
    this.onClear,
    this.iconColor,
    this.iconSize = 20,
    this.showClearButton = true,
    this.transformQuery,
  });

  /// Utility to extract digits from voice input, converting spoken word numbers (e.g. "nine eight") into digits.
  static String extractDigits(String input) {
    final Map<String, String> wordToDigit = {
      'zero': '0', 'oh': '0',
      'one': '1', 'won': '1',
      'two': '2', 'to': '2', 'too': '2',
      'three': '3',
      'four': '4', 'for': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8', 'ate': '8',
      'nine': '9',
    };
    String processed = input.toLowerCase();
    wordToDigit.forEach((word, digit) {
      processed = processed.replaceAll(RegExp(r'\b' + word + r'\b'), digit);
    });
    return processed.replaceAll(RegExp(r'\D'), '');
  }

  void _openVoiceSearch(BuildContext context) {
    VoiceSearchBottomSheet.show(
      context,
      title: title,
      hint: voiceHint ?? 'Speak into microphone...',
      submitLabel: submitLabel,
      currentQuery: controller.text,
      onQueryRecognized: (rawQuery) {
        final query = transformQuery != null ? transformQuery!(rawQuery) : rawQuery;
        controller.text = query;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: query.length),
        );
        onChanged?.call(query);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;
        final effectiveColor = iconColor ?? AppColors.textSecondary;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showClearButton && hasText)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.close_rounded,
                  size: iconSize - 2,
                  color: effectiveColor,
                ),
                tooltip: 'Clear',
                splashRadius: 16,
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                  onClear?.call();
                },
              ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.mic_rounded,
                size: iconSize,
                color: AppColors.primary,
              ),
              tooltip: tooltip ?? 'Voice input',
              splashRadius: 16,
              onPressed: () => _openVoiceSearch(context),
            ),
            const SizedBox(width: 4),
          ],
        );
      },
    );
  }
}
