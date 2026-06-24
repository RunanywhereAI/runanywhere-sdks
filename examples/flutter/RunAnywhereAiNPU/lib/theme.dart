import 'package:flutter/material.dart';

// Palette mirrored from the RunAnywhereAI app: orange primary, warm neutrals,
// warm-gold tertiary, emerald success. Shared across the Kotlin/Flutter/RN demos.

const _primary70 = Color(0xFFFF6D1F);
const _primary60 = Color(0xFFE65500);
const _primary30 = Color(0xFF732B00);
const _primary20 = Color(0xFF4E1C00);
const _primary90 = Color(0xFFFFDBCA);
const _secondary80 = Color(0xFFD0C5BF);
const _secondary30 = Color(0xFF4C4541);
const _tertiary80 = Color(0xFFE5C52A);
const _tertiary30 = Color(0xFF554600);
const _error80 = Color(0xFFFFB4AB);
const _error20 = Color(0xFF690005);
const _neutral6 = Color(0xFF141414);
const _neutral12 = Color(0xFF201F1F);
const _neutral17 = Color(0xFF2B2A2A);
const _neutral90 = Color(0xFFE6E1E0);
const _neutralVar30 = Color(0xFF4E4542);
const _neutralVar60 = Color(0xFF9B908B);
const _neutralVar80 = Color(0xFFD1C5C0);

/// Emerald success — used for the "NPU ready" state.
const raSuccess = Color(0xFF3DD68C);

final _darkScheme = const ColorScheme.dark().copyWith(
  primary: _primary70,
  onPrimary: _primary20,
  primaryContainer: _primary30,
  onPrimaryContainer: _primary90,
  secondary: _secondary80,
  onSecondary: _secondary30,
  tertiary: _tertiary80,
  onTertiary: _tertiary30,
  error: _error80,
  onError: _error20,
  surface: _neutral6,
  onSurface: _neutral90,
  surfaceContainerHighest: _neutral17,
  surfaceContainerHigh: _neutral17,
  surfaceContainer: _neutral12,
  onSurfaceVariant: _neutralVar80,
  outline: _neutralVar60,
  outlineVariant: _neutralVar30,
);

final _lightScheme = const ColorScheme.light().copyWith(
  primary: _primary60,
  onPrimary: Colors.white,
  tertiary: _tertiary30,
  error: const Color(0xFFBA1A1A),
);

ThemeData buildTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark ? _darkScheme : _lightScheme;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Figtree');
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
    ),
  );
}

/// Monospace style for live metric readouts (tokens/s, ms, arch).
const metricTextStyle = TextStyle(
  fontFamily: 'MapleMono',
  fontSize: 13,
  fontWeight: FontWeight.w500,
);
