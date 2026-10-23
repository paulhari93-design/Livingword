import 'dart:async';

import 'package:flutter/material.dart';

import '../data/local_files.dart';
import 'download_screen.dart';
import 'main_menu_screen.dart';

/// Shown for 2 seconds when the app opens, then goes to the main menu.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), _goNext);
  }

  Future<void> _goNext() async {
    final setupDone = await LocalFiles.instance.setupDone;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (_, __, ___) =>
          setupDone ? const MainMenuScreen() : const DownloadScreen(firstRun: true),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          child: Column(
            children: [
              // The full photo, never cropped; it shrinks to leave room for the text.
              Expanded(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/splash.jpg', fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // The text always has its own space at the bottom.
              const Text(
                'ஏழாம் தூதனுடைய சத்தத்தின் நாட்களிலே...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
