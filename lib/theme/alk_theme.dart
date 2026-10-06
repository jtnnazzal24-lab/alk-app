import 'package:flutter/material.dart';

/// Ported 1:1 from the RN app's `theme.config.js` + `sandy-primitives.tsx`.
class AlkColors {
  final Color primary;
  final Color background;
  final Color surface;
  final Color foreground;
  final Color muted;
  final Color border;
  final Color teal;
  final Color mint;
  final Color gold;
  final Color success;
  final Color warning;
  final Color error;
  final Color tealSoft;
  final Color mintSoft;
  final Color goldSoft;
  final Color soft;

  const AlkColors({
    required this.primary,
    required this.background,
    required this.surface,
    required this.foreground,
    required this.muted,
    required this.border,
    required this.teal,
    required this.mint,
    required this.gold,
    required this.success,
    required this.warning,
    required this.error,
    required this.tealSoft,
    required this.mintSoft,
    required this.goldSoft,
    required this.soft,
  });

  /// Warm "friendly companion" palette — creamy background, sage primary,
  /// warm charcoal text, calm teal for healthy readings, warm orange for
  /// elevated readings (gentle alert, no panic).
  static const Map<String, Color> sandyColorsLight = {
    'navy': Color(0xFF3B3A36),
    'surface': Color(0xFFFFFDF8),
    'blue': Color(0xFF4E7D61),
    'green': Color(0xFF5F8D6E),
    'orange': Color(0xFFE07A3F),
    'teal': Color(0xFF1F8A8A),
    'tealSoft': Color(0xFFE4F2F0),
    'mint': Color(0xFFEAF2E8),
    'mintSoft': Color(0xFFEAF2E8),
    'gold': Color(0xFFC98A2D),
    'goldSoft': Color(0xFFFBF3E0),
    'soft': Color(0xFFF3EDE0),
    'text': Color(0xFF3B3A36),
    'muted': Color(0xFF7A756C),
    'border': Color(0xFFE4DCCB),
    'danger': Color(0xFFC94F4F),
  };

  static const Map<String, Color> sandyColorsDark = {
    'navy': Color(0xFFF8FAFC),
    'surface': Color(0xFF162033),
    'blue': Color(0xFF60A5FA),
    'green': Color(0xFF34D399),
    'orange': Color(0xFFFDBA74),
    'teal': Color(0xFF22D3EE),
    'tealSoft': Color(0xFF163A43),
    'mint': Color(0xFF064E3B),
    'mintSoft': Color(0xFF064E3B),
    'gold': Color(0xFFFBBF24),
    'goldSoft': Color(0xFF3A2A10),
    'soft': Color(0xFF1E2B42),
    'text': Color(0xFFF8FAFC),
    'muted': Color(0xFFA7B4C8),
    'border': Color(0xFF2C3A52),
    'danger': Color(0xFFFDA4AF),
  };

  /// ALK brand color used for notification LEDs/accents (warm teal).
  static const Color notificationAccent = Color(0xFF1F8A8A);

  static const AlkColors light = AlkColors(
    primary: Color(0xFF4E7D61),
    background: Color(0xFFF7F2E7),
    surface: Color(0xFFFFFDF8),
    foreground: Color(0xFF3B3A36),
    muted: Color(0xFF7A756C),
    border: Color(0xFFE4DCCB),
    teal: Color(0xFF1F8A8A),
    mint: Color(0xFFEAF2E8),
    gold: Color(0xFFC98A2D),
    success: Color(0xFF5F8D6E),
    warning: Color(0xFFE07A3F),
    error: Color(0xFFC94F4F),
    tealSoft: Color(0xFFE4F2F0),
    mintSoft: Color(0xFFEAF2E8),
    goldSoft: Color(0xFFFBF3E0),
    soft: Color(0xFFF3EDE0),
  );

  static const AlkColors dark = AlkColors(
    primary: Color(0xFF60A5FA),
    background: Color(0xFF0B1220),
    surface: Color(0xFF162033),
    foreground: Color(0xFFF8FAFC),
    muted: Color(0xFFA7B4C8),
    border: Color(0xFF2C3A52),
    teal: Color(0xFF22D3EE),
    mint: Color(0xFF064E3B),
    gold: Color(0xFFFBBF24),
    success: Color(0xFF34D399),
    warning: Color(0xFFFDBA74),
    error: Color(0xFFFDA4AF),
    tealSoft: Color(0xFF163A43),
    mintSoft: Color(0xFF064E3B),
    goldSoft: Color(0xFF3A2A10),
    soft: Color(0xFF1E2B42),
  );
}

/// Returns the palette that matches the current theme brightness.
///
/// Screens must never hardcode a light-only colour (e.g. `Colors.amber.shade50`):
/// in dark mode such a card keeps a near-white background while the theme's text
/// colour is near-white too, so the text disappears and the card shows up as an
/// empty white box.
class AlkPalette {
  const AlkPalette._();

  static AlkColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? AlkColors.dark
          : AlkColors.light;
}

/// Builds the Material themes used across the app, mirroring the RN look
/// (rounded cards on a soft-blue background, Arabic-first typography).
class AlkTheme {
  static ThemeData light() => _build(AlkColors.light, Brightness.light);

  static ThemeData dark() => _build(AlkColors.dark, Brightness.dark);

  static ThemeData _build(AlkColors c, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.primary,
        onPrimary: c.surface,
        secondary: c.teal,
        onSecondary: c.surface,
        surface: c.surface,
        onSurface: c.foreground,
        error: c.error,
        onError: c.surface,
      ),
      scaffoldBackgroundColor: c.background,
      fontFamilyFallback: const ['Noto Naskh Arabic', 'Roboto', 'Segoe UI'],
    );

    return base.copyWith(
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primary,
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.surface
              : c.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary
              : c.border,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
