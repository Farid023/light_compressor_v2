import 'package:flutter/material.dart';

/// The seed colour for the whole app's [ColorScheme]. Kept navy per the
/// maintainer's chosen brand colour.
const Color _seedColor = Color(0xFF344772);

/// A small, consistent spacing scale used across the example app instead of
/// scattering magic numbers through every widget.
abstract final class AppSpacing {
  /// Extra-tight spacing, e.g. between an icon and its label.
  static const double xs = 4;

  /// Tight spacing, e.g. inside a compact row.
  static const double sm = 8;

  /// Default spacing between related elements.
  static const double md = 12;

  /// Spacing between distinct sections/cards.
  static const double lg = 16;

  /// Generous spacing, e.g. around a full-screen empty state.
  static const double xl = 24;

  /// Large vertical breathing room, e.g. above/below a hero icon.
  static const double xxl = 32;
}

/// Builds the app's [ThemeData] from a single seed colour.
abstract final class AppTheme {
  /// The app theme.
  static ThemeData get light => _themeFor(Brightness.light);

  static ThemeData _themeFor(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(isDense: true),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
