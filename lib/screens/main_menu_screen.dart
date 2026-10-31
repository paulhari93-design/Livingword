import 'package:flutter/material.dart';

import '../data/cloud.dart';
import '../data/library.dart';
import '../data/local_files.dart';
import '../services/push.dart';
import 'bible_books_screen.dart';
import 'download_screen.dart';
import 'home_screen.dart';
import '../data/profile.dart';
import '../widgets/more_menu.dart';
import '../l10n.dart';
import '../theme/reading_theme.dart';

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
    appProfile.addListener(_profileChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForNew());
  }

  @override
  void dispose() {
    Push.pings.removeListener(_checkForNew);
    appProfile.removeListener(_profileChanged);
    super.dispose();
  }

  void _profileChanged() {
    if (mounted) setState(() {});
  }

  DateTime? _lastCheck;

  /// Downloads new messages and silently replaces corrected ones. New ones show up
  /// under ⋮ → Notifications (orange dot), not as a pop-up.
  Future<void> _checkForNew() async {
    // A notification and opening the app can come together: check at most every 20 s.
    final now = DateTime.now();
    if (_lastCheck != null && now.difference(_lastCheck!) < const Duration(seconds: 20)) return;
    _lastCheck = now;
    if (!await LocalFiles.instance.messagesDownloaded) return;
    try {
      final result = await Cloud.instance.syncMessages();
      if (result.hasNew || result.corrected > 0) Library.instance.reload();
    } catch (_) {
      // No internet: try again next time.
    }
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
    Theme.of(context); // rebuild when the theme changes
    final readingTheme = ThemeController.of(context).value;
    final colors = _cardColors(readingTheme);
    // Warm cream background with the plain Light theme only; other themes keep theirs.
    final light = readingTheme == ReadingTheme.light;
    const cream = Color(0xFFFAF6EF);
    return Scaffold(
      backgroundColor: light ? cream : null,
      appBar: AppBar(
        backgroundColor: light ? cream : null,
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
        actions: const [MoreMenu()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // The picture at the top, then the Bible and the Messages below it.
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/home_jesus.jpg',
                height: MediaQuery.sizeOf(context).height * 0.38,
                width: double.infinity,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.45), // keep the face in view
              ),
            ),
            const SizedBox(height: 16),
            _MenuCard(
              leading: Icon(Icons.menu_book_rounded, size: 48, color: colors.text),
              title: appProfile.englishOnly ? 'THE HOLY BIBLE' : 'பரிசுத்த வேதாகமம்',
              subtitle: appProfile.englishOnly ? 'King James Version' : 'THE HOLY BIBLE (KJV)',
              color: colors.card,
              textColor: colors.text,
              onTap: _openBible,
            ),
            const SizedBox(height: 16),
            _MenuCard(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/messages_logo.jpg', width: 64, height: 76, fit: BoxFit.cover),
              ),
              title: appProfile.englishOnly
                  ? 'Messages of the Prophet William Marrion Branham'
                  : 'தீர்க்கதரிசி. வில்லியம் மரியன் பிரன்ஹாமின் செய்திகள்',
              subtitle: appProfile.englishOnly ? 'Spoken Word' : 'Messages',
              color: colors.card,
              textColor: colors.text,
              onTap: _openMessages,
            ),
          ],
        ),
      ),
    );
  }
}

/// Colours of the Bible / Messages cards for each theme, chosen to stand out from
/// the background: a deep red card on light themes, a warm cream card on dark ones.
({Color card, Color text}) _cardColors(ReadingTheme t) => switch (t) {
      ReadingTheme.light => (card: const Color(0xFF7A2E2A), text: Colors.white), // robe red on cream
      ReadingTheme.sepia => (card: const Color(0xFF5E2620), text: Colors.white), // darker red on sepia
      ReadingTheme.green => (card: const Color(0xFF7A2E2A), text: Colors.white), // red against green
      ReadingTheme.dark => (card: const Color(0xFFEAD9B8), text: const Color(0xFF3A1E18)), // cream on black
      ReadingTheme.navy => (card: const Color(0xFFF0CF8E), text: const Color(0xFF2A1A10)), // amber on night blue
    };

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Color color;
  final Color textColor;
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
        // Same height for both cards, however long the title is.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 140),
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: textColor, fontSize: 19, fontWeight: FontWeight.w700, height: 1.35)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: textColor.withValues(alpha: 0.75), fontSize: 14)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: textColor.withValues(alpha: 0.75), size: 30),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
