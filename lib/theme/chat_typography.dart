import 'package:flutter/material.dart';

class ChatTypography {
  /// Sober, readable, mobile-friendly.
  /// Uses platform default font (cleanest + no extra setup).
  static TextTheme textTheme(Brightness brightness) {
    // Slightly different emphasis in dark (same sizes, same weights).
    final base = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;

    final t = base.copyWith(
      // Material 3 names
      displayLarge: const TextStyle(fontSize: 44, height: 1.10, fontWeight: FontWeight.w600),
      displayMedium: const TextStyle(fontSize: 36, height: 1.12, fontWeight: FontWeight.w600),
      displaySmall: const TextStyle(fontSize: 30, height: 1.15, fontWeight: FontWeight.w600),

      headlineLarge: const TextStyle(fontSize: 26, height: 1.20, fontWeight: FontWeight.w600),
      headlineMedium: const TextStyle(fontSize: 22, height: 1.22, fontWeight: FontWeight.w600),
      headlineSmall: const TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w600),

      titleLarge: const TextStyle(fontSize: 18, height: 1.25, fontWeight: FontWeight.w600),
      titleMedium: const TextStyle(fontSize: 16, height: 1.25, fontWeight: FontWeight.w600),
      titleSmall: const TextStyle(fontSize: 14, height: 1.25, fontWeight: FontWeight.w600),

      bodyLarge: const TextStyle(fontSize: 16, height: 1.35, fontWeight: FontWeight.w400),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w400),
      bodySmall: const TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w400),

      labelLarge: const TextStyle(fontSize: 14, height: 1.10, fontWeight: FontWeight.w600),
      labelMedium: const TextStyle(fontSize: 12, height: 1.10, fontWeight: FontWeight.w600),
      labelSmall: const TextStyle(fontSize: 11, height: 1.10, fontWeight: FontWeight.w600),
    );

    return t;
  }
}
