import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/push.dart';
import 'theme/reading_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If something goes wrong, show the error on screen instead of a blank page.
  ErrorWidget.builder = (details) => Material(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text('Error:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.red, fontSize: 14)),
        ),
      );

  // Connect to Firebase (works offline too; it only needs the internet to download).
  final options = firebaseOptions;
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Firebase init failed: $e');
    }
  }

  // Show the app; load the saved theme and set up notifications in the background.
  runApp(const LivingWordApp());
  unawaited(Push.init());
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
