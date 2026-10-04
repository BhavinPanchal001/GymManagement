import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

class VoiceSearchService {
  static final VoiceSearchService _instance = VoiceSearchService._internal();
  factory VoiceSearchService() => _instance;
  VoiceSearchService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  bool get isListening => _speech.isListening;
  bool get isAvailable => _speech.isAvailable;
  Future<bool> get hasPermission => _speech.hasPermission;

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
  }) async {
    if (_isInitialized && _speech.isAvailable) return true;
    try {
      _isInitialized = await _speech.initialize(
        onStatus: (status) {
          debugPrint('VoiceSearch status: $status');
          onStatus?.call(status);
        },
        onError: (errorNotification) {
          debugPrint('VoiceSearch error: ${errorNotification.errorMsg} - permanent: ${errorNotification.permanent}');
          onError?.call(errorNotification);
        },
      );
      return _isInitialized;
    } catch (e) {
      debugPrint('VoiceSearch initialization failed: $e');
      return false;
    }
  }

  Future<bool> startListening({
    required void Function(String recognizedWords, bool isFinal) onResult,
    void Function(double soundLevel)? onSoundLevelChange,
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
    Duration? listenFor,
    Duration? pauseFor,
  }) async {
    final available = await initialize(onStatus: onStatus, onError: onError);
    if (!available) return false;

    try {
      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.search,
          cancelOnError: true,
          partialResults: true,
          onDevice: false,
          listenFor: listenFor ?? const Duration(seconds: 20),
          pauseFor: pauseFor ?? const Duration(seconds: 3),
        ),
        onSoundLevelChange: onSoundLevelChange,
      );
      return true;
    } catch (e) {
      debugPrint('VoiceSearch startListening failed: $e');
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint('VoiceSearch stop error: $e');
    }
  }

  Future<void> cancelListening() async {
    try {
      if (_speech.isListening) {
        await _speech.cancel();
      }
    } catch (e) {
      debugPrint('VoiceSearch cancel error: $e');
    }
  }
}
