import 'package:flutter/material.dart';

import 'chat_color_scheme.dart';
import 'chat_tokens.dart';
import 'chat_typography.dart';

class ChatTheme {
  static ThemeData light() => _build(ChatColorSchemes.light());
  static ThemeData dark() => _build(ChatColorSchemes.dark());

  static ThemeData _build(ColorScheme scheme) {
    final tokens = ChatTokens.from(scheme);
    final textTheme = ChatTypography.textTheme(scheme.brightness);

    final shadowColor = scheme.shadow.withOpacity(tokens.shadowOpacity);

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusLg),
      side: BorderSide(color: tokens.borderSubtle, width: 1),
    );

    final inputRadius = BorderRadius.circular(tokens.radiusMd);

    MaterialStateProperty<Color?> overlayFor(Color base) {
      return MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.pressed)) return base.withOpacity(0.10);
        if (states.contains(MaterialState.hovered)) return base.withOpacity(0.06);
        if (states.contains(MaterialState.focused)) return base.withOpacity(0.12);
        return null;
      });
    }

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,

      textTheme: textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),

      scaffoldBackgroundColor: Colors.transparent,

      extensions: <ThemeExtension<dynamic>>[
        tokens,
      ],

      dividerTheme: DividerThemeData(
        color: tokens.borderSubtle,
        thickness: 1,
        space: 1,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onBackground,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onBackground,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: scheme.onBackground),
      ),

      // ✅ Cards: misma forma, pero un toque más “glass”
      cardTheme: CardThemeData(
        color: scheme.surface.withOpacity(0.80),
        elevation: 0,
        shape: cardShape,
        margin: const EdgeInsets.all(0),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusXl),
          side: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.primary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          elevation: const MaterialStatePropertyAll(0),
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return scheme.primary.withOpacity(0.35);
            }
            return scheme.primary;
          }),
          foregroundColor: const MaterialStatePropertyAll(Colors.white),
          overlayColor: overlayFor(Colors.white),
          padding: MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: tokens.space16, vertical: tokens.space12),
          ),
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
            ),
          ),
          textStyle: MaterialStatePropertyAll(textTheme.labelLarge),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return scheme.surfaceVariant.withOpacity(0.60);
            }
            return scheme.surface.withOpacity(0.85);
          }),
          foregroundColor: MaterialStatePropertyAll(scheme.onSurface),
          overlayColor: overlayFor(scheme.onSurface),
          padding: MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: tokens.space16, vertical: tokens.space12),
          ),
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusMd),
            ),
          ),
          side: MaterialStateProperty.resolveWith((states) {
            final color = states.contains(MaterialState.focused)
                ? scheme.primary
                : tokens.borderSubtle;
            return BorderSide(color: color, width: 1);
          }),
          textStyle: MaterialStatePropertyAll(textTheme.labelLarge),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStatePropertyAll(scheme.primary),
          overlayColor: overlayFor(scheme.primary),
          textStyle: MaterialStatePropertyAll(textTheme.labelLarge),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // ✅ Un toque más “panel” (queda mejor sobre el fondo oscuro)
        fillColor: scheme.surface.withOpacity(0.85),
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.space16,
          vertical: tokens.space12,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),

        border: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface.withOpacity(0.92),
        indicatorColor: scheme.primary.withOpacity(0.14),
        elevation: 0,
        labelTextStyle: MaterialStatePropertyAll(
          textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        ),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          final color = states.contains(MaterialState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant;
          return IconThemeData(color: color);
        }),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceVariant.withOpacity(0.65),
        selectedColor: scheme.primary.withOpacity(0.18),
        disabledColor: scheme.surfaceVariant.withOpacity(0.35),
        labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
        padding: EdgeInsets.symmetric(horizontal: tokens.space12, vertical: tokens.space8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          side: BorderSide(color: tokens.borderSubtle, width: 1),
        ),
      ),

      shadowColor: shadowColor,
    );
  }
}
