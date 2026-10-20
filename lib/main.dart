import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'theme/reading_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // If something goes wrong, show the error on screen instead of a blank page.
  ErrorWidget.builder = (details) => Material(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text('Error:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.red, fontSize: 14)),
        ),
      );

  // Show the app immediately; load the saved theme in the background.
  runApp(const LivingWordApp());
  unawaited(themeController.load().timeout(const Duration(seconds: 3)).catchError((_) {}));
}

class LivingWordApp extends StatelessWidget {
  const LivingWordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReadingTheme>(
      valueListenable: themeController,
      builder: (context, theme, _) => MaterialApp(
        title: 'LivingWord',
        debugShowCheckedModeBanner: false,
        theme: theme.toThemeData(),
        home: const SplashScreen(),
      ),
    );
  }
}
