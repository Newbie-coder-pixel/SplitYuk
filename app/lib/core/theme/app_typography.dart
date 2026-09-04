import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography per design.md §3: a "printed receipt" mono family for
/// titles/IDs/labels, and the platform default sans family for body copy.
///
/// A generic `monospace` font family is used deliberately instead of a
/// bundled/network font — it keeps the app dependency-free for something
/// purely cosmetic, and still reads as "printed" via weight + letter-spacing.
class AppTypography {
  AppTypography._();

  static const String monoFamily = 'monospace';

  static const TextStyle heroTitle = TextStyle(
    fontFamily: monoFamily,
    fontSize: 34,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle screenTitle = TextStyle(
    fontFamily: monoFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionHeading = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle eyebrow = TextStyle(
    fontFamily: monoFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
    color: AppColors.textSecondary,
  );

  static const TextStyle amountLarge = TextStyle(
    fontFamily: monoFamily,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    color: AppColors.accentTerracottaDark,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle amount = TextStyle(
    fontFamily: monoFamily,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle buttonLabel = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.textOnAccent,
  );

  static const TextStyle stamp = TextStyle(
    fontFamily: monoFamily,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
    color: AppColors.accentViolet,
  );
}
