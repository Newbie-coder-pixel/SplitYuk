import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'screens/intro/intro_screen.dart';
import 'state/session_controller.dart';

void main() {
  runApp(const SplitYukApp());
}

class SplitYukApp extends StatelessWidget {
  const SplitYukApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionController(),
      child: MaterialApp(
        title: 'SplitYuk',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const IntroScreen(),
      ),
    );
  }
}
