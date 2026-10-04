import 'dart:async';
import 'package:flutter/material.dart';
import '../services/voice_search_service.dart';
import '../theme/app_theme.dart';

class VoiceSearchBottomSheet extends StatefulWidget {
  final String hint;
  final String? currentQuery;
  final String? title;
  final String? submitLabel;
  final void Function(String query) onQueryRecognized;

  const VoiceSearchBottomSheet({
    super.key,
    required this.hint,
    required this.onQueryRecognized,
    this.currentQuery,
    this.title,
    this.submitLabel,
  });

  static Future<void> show(
    BuildContext context, {
    required String hint,
    required void Function(String query) onQueryRecognized,
    String? currentQuery,
    String? title,
    String? submitLabel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => VoiceSearchBottomSheet(
        hint: hint,
        onQueryRecognized: onQueryRecognized,
        currentQuery: currentQuery,
        title: title,
        submitLabel: submitLabel,
      ),
    );
  }

  @override
  State<VoiceSearchBottomSheet> createState() => _VoiceSearchBottomSheetState();
}

class _VoiceSearchBottomSheetState extends State<VoiceSearchBottomSheet>
    with SingleTickerProviderStateMixin {
  final VoiceSearchService _voiceService = VoiceSearchService();

  late AnimationController _animController;
  late Animation<double> _pulseAnimation;

  String _words = '';
  bool _isListening = false;
  String _statusText = 'Listening...';
  String? _errorMessage;
  double _soundLevel = 0.0;
  Timer? _autoSubmitTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _words = widget.currentQuery ?? '';

    // Automatically start listening after sheet transition completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
    });
  }

  @override
  void dispose() {
    _autoSubmitTimer?.cancel();
    _animController.dispose();
    _voiceService.stopListening();
    super.dispose();
  }

  Future<void> _startListening() async {
    _autoSubmitTimer?.cancel();
    setState(() {
      _isListening = true;
      _errorMessage = null;
      _statusText = 'Listening...';
    });

    final success = await _voiceService.startListening(
      onResult: (words, isFinal) {
        if (!mounted) return;
        setState(() {
          _words = words;
          if (words.isNotEmpty) {
            _statusText = isFinal ? 'Finished listening' : 'Listening...';
          }
        });

        if (isFinal && words.trim().isNotEmpty) {
          // Schedule auto-submit after a brief delay so user sees confirmed words
          _autoSubmitTimer?.cancel();
          _autoSubmitTimer = Timer(const Duration(milliseconds: 650), () {
            _submitQuery(words.trim());
          });
        }
      },
      onSoundLevelChange: (level) {
        if (mounted) {
          setState(() {
            _soundLevel = level;
          });
        }
      },
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'notListening' || status == 'done') {
          setState(() {
            _isListening = false;
            if (_words.trim().isEmpty && _errorMessage == null) {
              _statusText = 'Didn\'t catch that. Tap mic to retry.';
            }
          });
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isListening = false;
          if (error.errorMsg.toLowerCase().contains('denied') ||
              error.errorMsg.toLowerCase().contains('permission')) {
            _errorMessage = 'Microphone permission denied. Please allow microphone access in settings.';
          } else {
            _errorMessage = 'Speech recognition error: ${error.errorMsg}';
          }
          _statusText = 'Error occurred';
        });
      },
    );

    if (!success && mounted) {
      setState(() {
        _isListening = false;
        _errorMessage = 'Voice search is unavailable on this device.';
        _statusText = 'Unavailable';
      });
    }
  }

  Future<void> _stopListening() async {
    _autoSubmitTimer?.cancel();
    await _voiceService.stopListening();
    if (mounted) {
      setState(() {
        _isListening = false;
        _statusText = _words.isNotEmpty ? 'Tap Search or speak again' : 'Tap mic to speak';
      });
    }
  }

  void _submitQuery(String query) {
    _autoSubmitTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
      widget.onQueryRecognized(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppColors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceBorder,
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mic_rounded, color: primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title ?? 'Voice Search',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      widget.hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Live Transcription Display Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isListening
                    ? primary.withValues(alpha: 0.5)
                    : AppColors.surfaceBorder,
              ),
            ),
            child: Column(
              children: [
                if (_errorMessage != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.orange, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ] else if (_words.isNotEmpty) ...[
                  Text(
                    _words,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ] else ...[
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _isListening ? 'Speak now...' : (_words.isNotEmpty ? 'Tap search to apply' : 'Tap mic below to try again'),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Animated Central Microphone
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isListening)
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Container(
                        width: 90 * _pulseAnimation.value,
                        height: 90 * _pulseAnimation.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primary.withValues(
                            alpha: (0.28 * (1.3 - _pulseAnimation.value)).clamp(0.05, 0.3),
                          ),
                        ),
                      );
                    },
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_isListening) {
                        _stopListening();
                      } else {
                        _startListening();
                      }
                    },
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isListening ? primary : AppColors.surfaceElevated,
                        border: Border.all(
                          color: _isListening ? primary : AppColors.surfaceBorder,
                          width: 2,
                        ),
                        boxShadow: [
                          if (_isListening)
                            BoxShadow(
                              color: primary.withValues(alpha: 0.4),
                              blurRadius: 18,
                              spreadRadius: 3,
                            ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _isListening ? AppColors.primaryOn : AppColors.textPrimary,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Simulated Audio Waveform Bar (When listening)
          if (_isListening)
            SizedBox(
              height: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(7, (index) {
                  final factors = [0.4, 0.7, 1.0, 0.85, 0.5, 0.9, 0.35];
                  final levelMultiplier = (_soundLevel > 0 ? (_soundLevel / 10).clamp(0.5, 1.5) : 0.8);
                  final barHeight = (18 * factors[index] * levelMultiplier).clamp(4.0, 22.0);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: 3.5,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            )
          else
            const SizedBox(height: 24),

          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              if (_words.isNotEmpty) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _words = '';
                        _statusText = 'Tap mic to speak';
                      });
                    },
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.surfaceBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => _submitQuery(_words.trim()),
                    icon: Icon(
                      widget.submitLabel != null && widget.submitLabel != 'Search'
                          ? Icons.check_rounded
                          : Icons.search_rounded,
                      size: 20,
                    ),
                    label: Text(widget.submitLabel ?? 'Search'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: AppColors.primaryOn,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.surfaceBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
