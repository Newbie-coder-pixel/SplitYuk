import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A colored circle with a member's initials, cycling through the fixed
/// avatar palette (design.md §4) so any group stays within the app's
/// color system rather than introducing arbitrary per-user colors.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    required this.colorIndex,
    this.radius = 20,
    this.selected = false,
  });

  final String name;
  final int colorIndex;
  final double radius;
  final bool selected;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.avatarColorFor(colorIndex);
    return CircleAvatar(
      radius: radius,
      backgroundColor: selected ? color : color.withValues(alpha: 0.85),
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}
