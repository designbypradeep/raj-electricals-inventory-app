import 'package:flutter/material.dart';

class StatusColors extends ThemeExtension<StatusColors> {
  final Color success; // In Stock
  final Color warning; // Low Stock
  final Color info; // Info / Neutral

  const StatusColors({
    required this.success,
    required this.warning,
    required this.info,
  });

  static const StatusColors light = StatusColors(
    success: Color(0xFF4CAF50), // Green
    warning: Color.fromARGB(255, 255, 240, 102), // Yellow
    info: Color(0xFF2196F3), // Blue
  );

  static const StatusColors dark = StatusColors(
    success: Color(0xFF6EDC82), // Lighter green for dark
    warning: Color(0xFFFFE07C), // Brighter yellow on dark
    info: Color(0xFF5EC2E8), // Lighter blue variant
  );

  @override
  ThemeExtension<StatusColors> copyWith({
    Color? success,
    Color? warning,
    Color? info,
  }) {
    return StatusColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  ThemeExtension<StatusColors> lerp(
    ThemeExtension<StatusColors>? other,
    double t,
  ) {
    if (other is! StatusColors) return this;
    return StatusColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      info: Color.lerp(info, other.info, t) ?? info,
    );
  }
}
