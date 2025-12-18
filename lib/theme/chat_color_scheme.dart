import 'package:flutter/material.dart';

class ChatColorSchemes {
  // ✅ Accent (tema tipo preview): emerald
  // Nota: NO renombro la constante para no romper imports/usos.
  static const Color accentBlue = Color(0xFF10B981); // emerald-500

  // Light neutrals (ligero toque emerald en outline)
  static const Color _lightBg = Color(0xFFF7F7F8);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurface2 = Color(0xFFF2F2F3);
  static const Color _lightBorder = Color(0x1A10B981); // emerald suave (10%)
  static const Color _lightText = Color(0xFF0F172A);
  static const Color _lightText2 = Color(0xFF475569);

  // Dark neutrals (más “slate/blue-black” como tu preview)
  static const Color _darkBg = Color(0xFF020617); // slate-950
  static const Color _darkSurface = Color(0xFF0F172A); // slate-900-ish
  static const Color _darkSurface2 = Color(0xFF111827); // slate-800-ish
  static const Color _darkBorder = Color(0x3310B981); // emerald 20% (borde)
  static const Color _darkText = Color(0xFFE5E7EB);
  static const Color _darkText2 = Color(0xFF9CA3AF);

  static ColorScheme light() {
    return const ColorScheme(
      brightness: Brightness.light,

      primary: accentBlue,
      onPrimary: Colors.white,

      secondary: accentBlue,
      onSecondary: Colors.white,

      tertiary: accentBlue,
      onTertiary: Colors.white,

      background: _lightBg,
      onBackground: _lightText,

      surface: _lightSurface,
      onSurface: _lightText,

      surfaceVariant: _lightSurface2,
      onSurfaceVariant: _lightText2,

      outline: _lightBorder,
      outlineVariant: _lightBorder,

      error: Color(0xFFEF4444),
      onError: Colors.white,

      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: _darkSurface,
      onInverseSurface: _darkText,
      inversePrimary: accentBlue,
    );
  }

  static ColorScheme dark() {
    return const ColorScheme(
      brightness: Brightness.dark,

      primary: accentBlue,
      onPrimary: Colors.white,

      secondary: accentBlue,
      onSecondary: Colors.white,

      tertiary: accentBlue,
      onTertiary: Colors.white,

      background: _darkBg,
      onBackground: _darkText,

      surface: _darkSurface,
      onSurface: _darkText,

      surfaceVariant: _darkSurface2,
      onSurfaceVariant: _darkText2,

      outline: _darkBorder,
      outlineVariant: _darkBorder,

      error: Color(0xFFF87171),
      onError: Color(0xFF111827),

      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: _lightSurface,
      onInverseSurface: _lightText,
      inversePrimary: accentBlue,
    );
  }
}
