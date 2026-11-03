import 'package:flutter/material.dart';

/// The lamp's glow in the logo: the accent on dark themes.
const lampColor = Color(0xFFF4CD8C);

/// The app's colour themes. Dark (black with the lamp's warm light) is the default.
enum AppTheme {
  dark('Dark'),
  midnight('Midnight'),
  sepia('Sepia'),
  white('White');

  final String label;
  const AppTheme(this.label);

  /// Background, the surface steps above it, text, accent and muted text.
  ({Brightness brightness, Color bg, List<Color> steps, Color text, Color accent, Color onAccent, Color muted}) get palette =>
      switch (this) {
        AppTheme.dark => (
            brightness: Brightness.dark,
            bg: const Color(0xFF000000),
            steps: const [Color(0xFF0B0A08), Color(0xFF13110E), Color(0xFF1A1713), Color(0xFF221E18), Color(0xFF2B261F)],
            text: const Color(0xFFEDE5D8),
            accent: lampColor,
            onAccent: const Color(0xFF1E1407),
            muted: const Color(0xFF9A8F7E),
          ),
        AppTheme.midnight => (
            brightness: Brightness.dark,
            bg: const Color(0xFF0A1328),
            steps: const [Color(0xFF0D1730), Color(0xFF111D3A), Color(0xFF162443), Color(0xFF1C2B4E), Color(0xFF23345B)],
            text: const Color(0xFFE4E9F5),
            accent: lampColor,
            onAccent: const Color(0xFF1E1407),
            muted: const Color(0xFF8D99B5),
          ),
        AppTheme.sepia => (
            brightness: Brightness.light,
            bg: const Color(0xFFF4EAD5),
            steps: const [Color(0xFFF0E5CD), Color(0xFFEBDEC3), Color(0xFFE5D7B9), Color(0xFFDFCFAE), Color(0xFFD8C6A2)],
            text: const Color(0xFF3B2C1D),
            accent: const Color(0xFF8A5A22),
            onAccent: const Color(0xFFFFF8EC),
            muted: const Color(0xFF7D6A52),
          ),
        AppTheme.white => (
            brightness: Brightness.light,
            bg: const Color(0xFFFFFFFF),
            steps: const [Color(0xFFF8F6F3), Color(0xFFF2EFEA), Color(0xFFECE8E2), Color(0xFFE5E0D9), Color(0xFFDDD7CF)],
            text: const Color(0xFF1B1A18),
            accent: const Color(0xFF94601C),
            onAccent: const Color(0xFFFFFFFF),
            muted: const Color(0xFF6F6A63),
          ),
      };

  ThemeData get data {
    final p = palette;
    final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: p.brightness).copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.accent,
      onSecondary: p.onAccent,
      tertiary: p.accent,
      surface: p.bg,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
      outline: p.muted,
      surfaceContainerLowest: p.bg,
      surfaceContainerLow: p.steps[0],
      surfaceContainer: p.steps[1],
      surfaceContainerHigh: p.steps[2],
      surfaceContainerHighest: p.steps[3],
      outlineVariant: p.steps[4],
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      appBarTheme: AppBarTheme(backgroundColor: p.bg, surfaceTintColor: Colors.transparent),
      cardTheme: CardThemeData(
        color: p.steps[1],
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          // Light themes get a hairline instead of a shadow.
          side: p.brightness == Brightness.light ? BorderSide(color: p.steps[3]) : BorderSide.none,
        ),
      ),
    );
  }

  static AppTheme fromName(String? name) => switch (name) {
        // Older saved values (ThemeMode names).
        'light' => AppTheme.white,
        'system' || null => AppTheme.dark,
        final n => AppTheme.values.asNameMap()[n] ?? AppTheme.dark,
      };
}
