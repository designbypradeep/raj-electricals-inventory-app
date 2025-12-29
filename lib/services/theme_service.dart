import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const String _themeKey = 'theme_mode';
  static const String _customPrimaryKey = 'custom_primary_color_argb';
  static const String _customSecondaryKey = 'custom_secondary_color_argb';

  /// Get the current theme mode from shared preferences
  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? 0; // Default to system

    switch (themeIndex) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Set the theme mode and save to shared preferences
  Future<void> setThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();

    int themeIndex;
    switch (themeMode) {
      case ThemeMode.light:
        themeIndex = 1;
        break;
      case ThemeMode.dark:
        themeIndex = 2;
        break;
      default:
        themeIndex = 0; // system
    }

    await prefs.setInt(_themeKey, themeIndex);
  }

  /// Get theme mode as string for display
  String getThemeModeString(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      default:
        return 'System';
    }
  }

  /// Get all available theme modes
  List<ThemeMode> getAllThemeModes() {
    return [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
  }

  // ===== Custom Brand Colors (Primary/Secondary) =====
  Future<Color?> getCustomPrimaryColor() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_customPrimaryKey);
    if (value == null) return null;
    return Color(value);
  }

  Future<Color?> getCustomSecondaryColor() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_customSecondaryKey);
    if (value == null) return null;
    return Color(value);
  }

  Future<void> setCustomColors({Color? primary, Color? secondary}) async {
    final prefs = await SharedPreferences.getInstance();
    if (primary == null) {
      await prefs.remove(_customPrimaryKey);
    } else {
      await prefs.setInt(_customPrimaryKey, primary.value);
    }
    if (secondary == null) {
      await prefs.remove(_customSecondaryKey);
    } else {
      await prefs.setInt(_customSecondaryKey, secondary.value);
    }
  }

  Future<void> clearCustomColors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customPrimaryKey);
    await prefs.remove(_customSecondaryKey);
  }
}
