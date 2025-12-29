/// Stub implementation for platforms without speech-to-text support (Web).
/// This provides disabled voice search functionality.
library;

/// Callback type for when speech results are received.
typedef VoiceSearchResultCallback = void Function(String text);

/// Callback type for listening state changes.
typedef VoiceSearchStatusCallback = void Function(bool isListening);

/// Voice search service stub - always returns disabled state.
class VoiceSearchService {
  /// Whether voice search is available on this platform.
  bool get isAvailable => false;

  /// Whether currently listening for speech.
  bool get isListening => false;

  /// Initialize the speech recognition service.
  /// Returns true if initialization was successful.
  Future<bool> initialize() async {
    return false;
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
    // No-op on unsupported platforms
  }

  /// Stop listening for speech input.
  Future<void> stopListening() async {
    // No-op on unsupported platforms
  }

  /// Cancel the current listening session.
  Future<void> cancel() async {
    // No-op on unsupported platforms
  }

  /// Dispose of resources.
  void dispose() {
    // No-op on unsupported platforms
  }
}
