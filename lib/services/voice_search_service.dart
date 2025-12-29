/// Voice search service with platform-specific implementation.
/// Uses conditional imports to select the appropriate implementation:
/// - Mobile (Android/iOS): Uses speech_to_text for voice recognition
/// - Desktop (Windows/macOS/Linux): Disabled stub implementation
/// - Web: Disabled stub implementation
export 'voice_search_service_stub.dart'
    if (dart.library.io) 'voice_search_service_io.dart';
