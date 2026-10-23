import 'package:flutter/material.dart';

import '../data/cloud.dart';
import '../data/library.dart';
import '../data/local_files.dart';
import '../services/push.dart';
import '../theme/reading_theme.dart';
import 'bible_books_screen.dart';
import 'download_screen.dart';
import 'home_screen.dart';
import 'reader_screen.dart';

/// The two main choices: the Bible and the Messages.
/// Also checks for new / corrected messages each time the app opens.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  @override
  void initState() {
    super.initState();
    Push.pings.addListener(_checkForNew);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForNew());
  }

  @override
  void dispose() {
    Push.pings.removeListener(_checkForNew);
    super.dispose();
  }

  /// Downloads new messages and silently replaces corrected ones.
  /// Shows "New Message Available" when something new arrived.
  Future<void> _checkForNew() async {
    if (!await LocalFiles.instance.messagesDownloaded) return;
    try {
      final result = await Cloud.instance.syncMessages();
      Library.instance.reload();
      if (!mounted || !result.hasNew) return;
      _showNewBanner(result);
    } catch (_) {
      // No internet: try again next time.
    }
  }

  void _showNewBanner(SyncResult r) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    final titles = r.newTitles.join('\n');
    messenger.showMaterialBanner(MaterialBanner(
      leading: const Icon(Icons.fiber_new, size: 32),
      content: Text(
        'புதிய செய்தி கிடைக்கிறது / New Message Available\n$titles',
        style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: messenger.hideCurrentMaterialBanner,
          child: const Text('மூடு / Close'),
        ),
        FilledButton(
          onPressed: () async {
            messenger.hideCurrentMaterialBanner();
            if (r.newCodes.length == 1) {
              final infos = await Library.instance.catalog();
              final info = infos.where((m) => m.code == r.newCodes.first).firstOrNull;
              if (info == null || !mounted) return;
              final message = await Library.instance.message(info);
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ReaderScreen(message: message)),
              );
            } else {
              _openMessages();
            }
          },
          child: const Text('திற / Open'),
        ),
      ],
    ));
  }

  Future<bool> _ensureDownloaded({required bool bible}) async {
    final have = bible
        ? await LocalFiles.instance.bibleDownloaded
        : await LocalFiles.instance.messagesDownloaded;
    if (have) return true;
    if (!mounted) return false;
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DownloadScreen(offerMessages: !bible, offerBible: bible),
    ));
    return ok == true;
  }

  Future<void> _openBible() async {
    if (!await _ensureDownloaded(bible: true) || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BibleBooksScreen()));
  }

  Future<void> _openMessages() async {
    if (!await _ensureDownloaded(bible: false) || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

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
              title: 'தமிழ்/English பரிசுத்த வேதாகமம்',
              subtitle: 'Tamil / English (KJV) Holy Bible',
              color: const Color(0xFF8D5524),
              onTap: _openBible,
            ),
            const SizedBox(height: 16),
            _MenuCard(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/messages_logo.jpg', width: 64, height: 76, fit: BoxFit.cover),
              ),
              title: 'தீர்க்கதரிசி. வில்லியம் மரியன் பிரன்ஹாமின் செய்திகள்',
              subtitle: 'Messages',
              color: const Color(0xFF2E5E8C),
              onTap: _openMessages,
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
