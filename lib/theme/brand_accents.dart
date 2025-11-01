import 'package:flutter/material.dart';

class BrandAccents extends ThemeExtension<BrandAccents> {
  final Color accent1; // e.g., #FFD166
  final Color accent2; // e.g., #06D6A0 (light) / #20E2AA (dark)

  const BrandAccents({required this.accent1, required this.accent2});

  static const BrandAccents light = BrandAccents(
    accent1: Color(0xFFFFD166),
    accent2: Color(0xFF06D6A0),
  );

  static const BrandAccents dark = BrandAccents(
    accent1: Color(0xFFFFD166),
    accent2: Color(0xFF20E2AA),
  );

  @override
  BrandAccents copyWith({Color? accent1, Color? accent2}) {
    return BrandAccents(
      accent1: accent1 ?? this.accent1,
      accent2: accent2 ?? this.accent2,
    );
  }

  @override
  BrandAccents lerp(ThemeExtension<BrandAccents>? other, double t) {
    if (other is! BrandAccents) return this;
    return BrandAccents(
      accent1: Color.lerp(accent1, other.accent1, t) ?? accent1,
      accent2: Color.lerp(accent2, other.accent2, t) ?? accent2,
    );
  }
}
