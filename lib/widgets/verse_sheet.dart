import 'package:flutter/material.dart';

import '../data/bible.dart';
import '../data/profile.dart';
import '../data/scripture.dart';
import '../screens/bible_reader_screen.dart';
import '../theme/text_settings.dart';

/// Tapping a Bible reference in a message: shows the verse(s) from the Bible on the
/// phone (Tamil and KJV), with a button to open the chapter in the Bible.
Future<void> showScripture(BuildContext context, ScriptureRef ref, {required String lang}) async {
  final books = await Bible.instance.books();
  BibleBookInfo? book;
  for (final b in books) {
    if (b.number == ref.book) book = b;
  }
  if (book == null || !context.mounted) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Download the Bible first (main menu → Bible).'),
      ));
    }
    return;
  }
  final english = appProfile.englishOnly;
  final ta = english ? const <List<String>>[] : await Bible.instance.chapters(book, BibleLang.tamil);
  final en = await Bible.instance.chapters(book, BibleLang.english);
  if (!context.mounted) return;

  List<(int, String)> verses(List<List<String>> chapters) {
    if (ref.chapter < 1 || ref.chapter > chapters.length) return const [];
    final c = chapters[ref.chapter - 1];
    return [
      for (var v = ref.verse; v <= ref.lastVerse && v <= c.length; v++) (v, c[v - 1]),
    ];
  }

  final taV = verses(ta), enV = verses(en);
  final range = ref.lastVerse > ref.verse ? '${ref.verse}-${ref.lastVerse}' : '${ref.verse}';
  final b = book;
  final ts = TextSettingsController.of(context).value;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final color = theme.colorScheme.onSurface;
      Widget block(String title, List<(int, String)> vs, String l) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (vs.isEmpty)
                Text(l == 'en' ? 'Verse not found.' : 'வசனம் கிடைக்கவில்லை.')
              else
                for (final (n, t) in vs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '$n  ',
                          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                      TextSpan(text: t),
                    ]), style: ts.style(ctx, l, color, fontSize: ts.size - 1)),
                  ),
            ],
          );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tamil first in Tamil messages, English first in English ones.
                if (!english && lang != 'en') ...[
                  block('${b.tamil} ${ref.chapter}:$range', taV, 'ta'),
                  const SizedBox(height: 14),
                ],
                block('${b.english} ${ref.chapter}:$range (KJV)', enV, 'en'),
                if (!english && lang == 'en') ...[
                  const SizedBox(height: 14),
                  block('${b.tamil} ${ref.chapter}:$range', taV, 'ta'),
                ],
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(lang == 'en' || english ? 'Open in the Bible' : 'வேதாகமத்தில் திற'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BibleReaderScreen(
                        book: b,
                        initialChapter: ref.chapter,
                        initialVerse: ref.verse,
                      ),
                    ));
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
