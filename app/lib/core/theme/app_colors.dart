import 'package:flutter/material.dart';

/// Color tokens for SplitYuk, sampled from the "Receipt Workspace" mockups.
/// See /design.md at the repo root for the full design system rationale.
class AppColors {
  AppColors._();

  static const Color bgApp = Color(0xFFF3F1F6);
  static const Color bgCardOuter = Color(0xFFDAD5C3);
  static const Color bgPaper = Color(0xFFFBF9F4);
  static const Color bgSurface = Color(0xFFFFFFFF);
  static const Color bgInput = Color(0xFFEAE6F2);

  static const Color textPrimary = Color(0xFF1E2130);
  static const Color textSecondary = Color(0xFF6B6B76);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  static const Color accentTerracotta = Color(0xFFC97B6E);
  static const Color accentTerracottaDark = Color(0xFFAD6154);
  static const Color accentMaroon = Color(0xFF7A3B3B);
  static const Color accentViolet = Color(0xFF5B4B8A);
  static const Color accentAmber = Color(0xFFE3B15E);
  static const Color bgAmber = Color(0xFFF6E3BE);
  static const Color textAmber = Color(0xFF8A5A16);
  static const Color accentSuccess = Color(0xFF4E9B6E);
  static const Color accentDanger = Color(0xFFC0483C);

  static const Color dividerDashed = Color(0xFFC9C4D6);
  static const Color borderSubtle = Color(0xFFDDD9E8);

  /// Cycled avatar fill colors — never introduce a 4th hue here, per design.md.
  static const List<Color> avatarPalette = [
    accentTerracotta,
    accentViolet,
    accentAmber,
  ];

  static Color avatarColorFor(int index) =>
      avatarPalette[index % avatarPalette.length];
}
