import 'package:flutter/material.dart';

@immutable
class ChatTokens extends ThemeExtension<ChatTokens> {
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusXl;

  final double space2;
  final double space4;
  final double space8;
  final double space12;
  final double space16;
  final double space20;
  final double space24;
  final double space32;

  final Color borderSubtle;
  final Color borderStrong;

  final double shadowOpacity; // keep shadows minimal, chatgpt-like

  const ChatTokens({
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXl,
    required this.space2,
    required this.space4,
    required this.space8,
    required this.space12,
    required this.space16,
    required this.space20,
    required this.space24,
    required this.space32,
    required this.borderSubtle,
    required this.borderStrong,
    required this.shadowOpacity,
  });

  static ChatTokens from(ColorScheme scheme) {
    final subtle = scheme.outline.withOpacity(scheme.brightness == Brightness.dark ? 0.85 : 1.0);
    final strong = scheme.outline.withOpacity(scheme.brightness == Brightness.dark ? 1.0 : 1.0);

    return ChatTokens(
      radiusSm: 10,
      radiusMd: 14,
      radiusLg: 18,
      radiusXl: 24,

      space2: 2,
      space4: 4,
      space8: 8,
      space12: 12,
      space16: 16,
      space20: 20,
      space24: 24,
      space32: 32,

      borderSubtle: subtle,
      borderStrong: strong,

      shadowOpacity: scheme.brightness == Brightness.dark ? 0.18 : 0.10,
    );
  }

  @override
  ChatTokens copyWith({
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXl,
    double? space2,
    double? space4,
    double? space8,
    double? space12,
    double? space16,
    double? space20,
    double? space24,
    double? space32,
    Color? borderSubtle,
    Color? borderStrong,
    double? shadowOpacity,
  }) {
    return ChatTokens(
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
      space2: space2 ?? this.space2,
      space4: space4 ?? this.space4,
      space8: space8 ?? this.space8,
      space12: space12 ?? this.space12,
      space16: space16 ?? this.space16,
      space20: space20 ?? this.space20,
      space24: space24 ?? this.space24,
      space32: space32 ?? this.space32,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
    );
  }

  @override
  ChatTokens lerp(ThemeExtension<ChatTokens>? other, double t) {
    if (other is! ChatTokens) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t) ?? a;

    double lerpDouble(double a, double b) => a + (b - a) * t;

    return ChatTokens(
      radiusSm: lerpDouble(radiusSm, other.radiusSm),
      radiusMd: lerpDouble(radiusMd, other.radiusMd),
      radiusLg: lerpDouble(radiusLg, other.radiusLg),
      radiusXl: lerpDouble(radiusXl, other.radiusXl),
      space2: lerpDouble(space2, other.space2),
      space4: lerpDouble(space4, other.space4),
      space8: lerpDouble(space8, other.space8),
      space12: lerpDouble(space12, other.space12),
      space16: lerpDouble(space16, other.space16),
      space20: lerpDouble(space20, other.space20),
      space24: lerpDouble(space24, other.space24),
      space32: lerpDouble(space32, other.space32),
      borderSubtle: lerpColor(borderSubtle, other.borderSubtle),
      borderStrong: lerpColor(borderStrong, other.borderStrong),
      shadowOpacity: lerpDouble(shadowOpacity, other.shadowOpacity),
    );
  }
}

extension ChatTokensX on BuildContext {
  ChatTokens get chatTokens => Theme.of(this).extension<ChatTokens>()!;
}
