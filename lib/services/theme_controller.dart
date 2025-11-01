import 'package:flutter/material.dart';
import 'theme_service.dart';

/// ThemeController manages custom brand colors with live preview and persistence.
class ThemeController extends ChangeNotifier {
  ThemeController._internal();
  static final ThemeController instance = ThemeController._internal();

  final ThemeService _service = ThemeService();

  // Persisted colors (nullable means use defaults)
  Color? _savedPrimary;
  Color? _savedSecondary;

  // Preview overrides (not persisted)
  Color? _previewPrimary;
  Color? _previewSecondary;

  Color? get savedPrimary => _savedPrimary;
  Color? get savedSecondary => _savedSecondary;
  Color? get previewPrimary => _previewPrimary;
  Color? get previewSecondary => _previewSecondary;

  /// Load saved custom colors from storage
  Future<void> loadSavedColors() async {
    _savedPrimary = await _service.getCustomPrimaryColor();
    _savedSecondary = await _service.getCustomSecondaryColor();
    notifyListeners();
  }

  /// Apply preview colors (not persisted). Pass null to clear preview for that channel.
  void previewColors({Color? primary, Color? secondary}) {
    _previewPrimary = primary;
    _previewSecondary = secondary;
    notifyListeners();
  }

  /// Clear any active preview and revert to saved colors
  void clearPreview() {
    _previewPrimary = null;
    _previewSecondary = null;
    notifyListeners();
  }

  /// Save custom colors. Pass null to remove customization and use defaults.
  Future<void> saveColors({Color? primary, Color? secondary}) async {
    await _service.setCustomColors(primary: primary, secondary: secondary);
    _savedPrimary = primary;
    _savedSecondary = secondary;
    // Clear preview after save
    _previewPrimary = null;
    _previewSecondary = null;
    notifyListeners();
  }

  /// Reset to defaults (remove any saved custom colors)
  Future<void> resetToDefaults() async {
    await _service.clearCustomColors();
    _savedPrimary = null;
    _savedSecondary = null;
    _previewPrimary = null;
    _previewSecondary = null;
    notifyListeners();
  }
}
