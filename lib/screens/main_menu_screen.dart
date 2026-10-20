import 'package:flutter/material.dart';

import '../theme/reading_theme.dart';
import 'bible_books_screen.dart';
import 'home_screen.dart';

/// The two main choices: Tamil Bible and the Messages.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.png', width: 34, height: 34),
            ),
            const SizedBox(width: 10),
            const Text('LivingWord'),
          ],
        ),
        actions: const [ThemeButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            _MenuCard(
              leading: const Icon(Icons.menu_book_rounded, size: 48, color: Colors.white),
              title: 'தமிழ் வேதாகமம்',
              subtitle: 'Tamil Bible',
              color: const Color(0xFF8D5524),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BibleBooksScreen()),
              ),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/messages_logo.jpg', width: 64, height: 76, fit: BoxFit.cover),
              ),
              title: 'வில்லியம் மரியன் பிரன்ஹாமின் செய்திகள்',
              subtitle: 'Messages',
              color: const Color(0xFF2E5E8C),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700, height: 1.4)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}
