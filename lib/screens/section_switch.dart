import 'package:flutter/material.dart';

import '../data/bible.dart';
import '../data/library.dart';
import '../data/local_files.dart';
import '../data/prefs.dart';
import 'bible_books_screen.dart';
import 'bible_reader_screen.dart';
import 'download_screen.dart';
import 'home_screen.dart';
import 'reader_screen.dart';

/// Small buttons in the top bar to jump between the Bible and the Messages,
/// using the same pictures as the main menu.

/// Opens [screen] from the main menu, so going back always returns to the main menu.
Future<void> _goTo(BuildContext context, Widget screen, {required bool bible}) async {
  final nav = Navigator.of(context);
  final have = bible
      ? await LocalFiles.instance.bibleDownloaded
      : await LocalFiles.instance.messagesDownloaded;
  if (!have) {
    final ok = await nav.push<bool>(MaterialPageRoute(
      builder: (_) => DownloadScreen(offerMessages: !bible, offerBible: bible),
    ));
    if (ok != true) return;
  }
  // Find the last place read, if any.
  Widget? last;
  try {
    last = bible ? await _lastBible() : await _lastMessage();
  } catch (_) {}
  nav.popUntil((route) => route.isFirst);
  nav.push(MaterialPageRoute(builder: (_) => screen));
  if (last != null) nav.push(MaterialPageRoute(builder: (_) => last!));
}

/// The Bible chapter read last ('book:chapter').
Future<Widget?> _lastBible() async {
  final saved = await Prefs.instance.getString('last_bible');
  final parts = saved?.split(':');
  if (parts == null || parts.length != 2) return null;
  final number = int.tryParse(parts[0]);
  final chapter = int.tryParse(parts[1]) ?? 1;
  final books = await Bible.instance.books();
  for (final b in books) {
    if (b.number == number) {
      return BibleReaderScreen(book: b, initialChapter: chapter.clamp(1, b.chapterCount).toInt());
    }
  }
  return null;
}

/// The message read last ('lang|code|paragraph').
Future<Widget?> _lastMessage() async {
  final saved = await Prefs.instance.getString('last_message');
  final parts = saved?.split('|');
  if (parts == null || parts.length != 3) return null;
  final info = await Library.instance.find(parts[1], parts[0]);
  if (info == null) return null;
  final message = await Library.instance.message(info);
  await messageLang.set(info.lang);
  final para = int.tryParse(parts[2]) ?? 0;
  return ReaderScreen(
    message: message,
    initialParagraph: para > 0 && para < message.paragraphs.length ? para : null,
  );
}

/// Brown book button (shown in the Messages) → Bible.
class GoToBibleButton extends StatelessWidget {
  const GoToBibleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: 'பரிசுத்த வேதாகமம் / Holy Bible',
        child: Material(
          color: const Color(0xFF8D5524),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _goTo(context, const BibleBooksScreen(), bible: true),
            child: const SizedBox(
              width: 34,
              height: 34,
              child: Icon(Icons.menu_book_rounded, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prophet picture button (shown in the Bible) → Messages.
class GoToMessagesButton extends StatelessWidget {
  const GoToMessagesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: 'உரைக்கப்பட்ட வார்த்தை / Spoken Word',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _goTo(context, const HomeScreen(), bible: false),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/messages_logo.jpg', width: 30, height: 36, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}
