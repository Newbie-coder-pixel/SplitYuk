import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A random, non-identifying per-installation token (PRD §12), used only
/// so the backend relay can rate-limit abuse. This is the one narrow,
/// explicit exception to "nothing persists" (PRD §3 — alongside OS
/// permission grants): it identifies this app install, never a person,
/// bill, or contact, and carries no link to any of that data.
class InstallationId {
  InstallationId._();

  static const _prefsKey = 'splityuk_installation_token';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString(_prefsKey);
    if (token == null) {
      token = _generate();
      await prefs.setString(_prefsKey, token);
    }
    _cached = token;
    return token;
  }

  static String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
