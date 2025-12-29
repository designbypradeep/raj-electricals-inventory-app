/// Platform-specific implementation for dart:io platforms.
/// Uses speech_to_text on mobile (Android/iOS), disabled on desktop.

import 'dart:io' show Platform;
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Callback type for when speech results are received.
typedef VoiceSearchResultCallback = void Function(String text);

/// Callback type for listening state changes.
typedef VoiceSearchStatusCallback = void Function(bool isListening);

/// Voice search service with platform-aware implementation.
/// Enabled on mobile (Android/iOS), disabled on desktop (Windows/macOS/Linux).
class VoiceSearchService {
  stt.SpeechToText? _speech;
  bool _isInitialized = false;
  bool _isListening = false;

  /// Check if running on a mobile platform (Android or iOS).
  static bool get _isMobilePlatform {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Whether voice search is available on this platform.
  bool get isAvailable => _isInitialized && _isMobilePlatform;

  /// Whether currently listening for speech.
  bool get isListening => _isListening;

  /// Initialize the speech recognition service.
  /// Returns true if initialization was successful.
  /// Only initializes on mobile platforms.
  Future<bool> initialize() async {
    if (!_isMobilePlatform) {
      // Skip initialization on desktop platforms
      return false;
    }

    try {
      _speech = stt.SpeechToText();
      _isInitialized = await _speech!.initialize(
        onError: (error) {
          _isListening = false;
        },
        onStatus: (status) {
          _isListening = status == stt.SpeechToText.listeningStatus;
        },
      );
      return _isInitialized;
    } catch (e) {
      _isInitialized = false;
      return false;
    }
  }

  /// Start listening for speech input.
  /// [onResult] is called when speech is recognized.
  /// [onStatusChange] is called when listening state changes.
  /// [localeId] optional locale for speech recognition (e.g., 'en_US', 'hi_IN').
  Future<void> startListening({
    required VoiceSearchResultCallback onResult,
    VoiceSearchStatusCallback? onStatusChange,
    String? localeId,
  }) async {
    if (!isAvailable || _speech == null) {
      return;
    }

    try {
      _isListening = true;
      onStatusChange?.call(true);

      await _speech!.listen(
        onResult: (result) {
          final text = result.recognizedWords;
          if (text.isNotEmpty) {
            onResult(text);
          }
          if (result.finalResult) {
            _isListening = false;
            onStatusChange?.call(false);
          }
        },
        localeId: localeId,
        listenMode: stt.ListenMode.search,
        cancelOnError: true,
        partialResults: true,
      );
    } catch (e) {
      _isListening = false;
      onStatusChange?.call(false);
    }
  }

  /// Stop listening for speech input.
  Future<void> stopListening() async {
    if (_speech != null && _isListening) {
      await _speech!.stop();
      _isListening = false;
    }
  }

  /// Cancel the current listening session.
  Future<void> cancel() async {
    if (_speech != null) {
      await _speech!.cancel();
      _isListening = false;
    }
  }

  /// Dispose of resources.
  void dispose() {
    if (_speech != null) {
      _speech!.cancel();
      _speech = null;
    }
    _isInitialized = false;
    _isListening = false;
  }
}
