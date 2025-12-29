/// Stub implementation of speech_to_text_windows for Windows builds.
/// This provides a no-op implementation to avoid native build errors.
library speech_to_text_windows;

import 'package:speech_to_text_platform_interface/speech_to_text_platform_interface.dart';

/// Stub implementation of speech_to_text for Windows.
/// Always returns unavailable/not initialized to disable voice search on Windows.
class SpeechToTextWindowsStub extends SpeechToTextPlatform {
  /// Registers this class as the default instance of [SpeechToTextPlatform].
  static void registerWith() {
    SpeechToTextPlatform.instance = SpeechToTextWindowsStub();
  }

  @override
  Future<bool> hasPermission() {
    return Future.value(false);
  }

  @override
  Future<bool> initialize({
    debugLogging = false,
    List<SpeechConfigOption>? options,
  }) {
    // Always return false - speech-to-text is not available on Windows in this app
    return Future.value(false);
  }

  @override
  Future<void> stop() {
    // No-op on Windows
    return Future.value();
  }

  @override
  Future<void> cancel() {
    // No-op on Windows
    return Future.value();
  }

  @override
  Future<bool> listen({
    String? localeId,
    @Deprecated('Use SpeechListenOptions.partialResults instead')
    partialResults = true,
    @Deprecated('Use SpeechListenOptions.onDevice instead') onDevice = false,
    @Deprecated('Use SpeechListenOptions.listenMode instead')
    int listenMode = 0,
    @Deprecated('Use SpeechListenOptions.sampleRate instead') sampleRate = 0,
    SpeechListenOptions? options,
  }) {
    // No-op on Windows - always return false (not available)
    return Future.value(false);
  }

  @override
  Future<List<dynamic>> locales() {
    return Future.value([]);
  }
}
