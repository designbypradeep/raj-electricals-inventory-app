import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFFC1441E);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
      fontFamily: 'Poppins',
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontWeight: FontWeight.bold),
        bodyMedium: TextStyle(fontSize: 14),
      ),
    );
  }
}
