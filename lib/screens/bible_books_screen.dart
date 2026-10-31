import 'package:flutter/material.dart';

import '../data/bible.dart';
import '../data/bible_progress.dart';
import '../theme/reading_theme.dart';
import 'bible_mode_switch.dart';
import 'bible_reader_screen.dart';
import 'section_switch.dart';
import '../data/profile.dart';
import '../widgets/more_menu.dart';
import '../l10n.dart';

/// Tamil Bible: Old / New Testament book lists, with a book-name filter.
class BibleBooksScreen extends StatefulWidget {
  const BibleBooksScreen({super.key});

  @override
  State<BibleBooksScreen> createState() => _BibleBooksScreenState();
}

class _BibleBooksScreenState extends State<BibleBooksScreen> {
  List<BibleBookInfo> _books = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    BibleProgress.instance.load();
    Bible.instance.books().then((b) {
      if (mounted) setState(() => _books = b);
    });
  }

  void _openBook(BibleBookInfo book) {
    if (book.chapterCount == 1) {
      _openChapter(book, 1);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ChapterGridScreen(book: book, onPick: (c) => _openChapter(book, c, replace: true)),
    ));
  }

  void _openChapter(BibleBookInfo book, int chapter, {bool replace = false}) {
    final route = MaterialPageRoute(
      builder: (_) => BibleReaderScreen(book: book, initialChapter: chapter),
    );
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  Widget _list(bool oldTestament, BibleMode mode) {
    final english = mode == BibleMode.english;
    final items = _books.where((b) => b.isOldTestament == oldTestament && b.matches(_query)).toList();
    if (_books.isEmpty) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return Center(child: Text(english ? 'No book found' : 'புத்தகம் கிடைக்கவில்லை'));
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: BibleProgress.instance,
      builder: (context, _) => ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final b = items[i];
        final read = BibleProgress.instance.chaptersRead(b.number);
        final label = Text(switch (mode) {
          BibleMode.tamil => '${b.chapterCount} அதிகாரங்கள்',
          BibleMode.english => '${b.chapterCount} chapters',
          BibleMode.both => '${b.english} · ${b.chapterCount} அதிகாரங்கள் / chapters',
        });
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text('${b.number}', style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
          ),
          title: Text(english ? b.english : b.tamil, style: const TextStyle(fontSize: 18)),
          // Under each book: a line with how many of its chapters are read.
          subtitle: read == 0
              ? label
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: read / b.chapterCount,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(2),
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$read/${b.chapterCount}', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ],
                ),
          trailing: read >= b.chapterCount
              ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 22)
              : null,
          onTap: () => _openBook(b),
        );
      },
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BibleMode>(
      valueListenable: bibleMode,
      builder: (context, mode, _) {
        final english = mode == BibleMode.english;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(english ? 'Holy Bible' : 'பரிசுத்த வேதாகமம்'),
              actions: const [GoToMessagesButton(), MoreMenu(bible: true)],
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(appProfile.englishOnly ? 48 : 104),
                child: Column(
                  children: [
                    if (!appProfile.englishOnly) const BibleModeSwitch(),
                    TabBar(
                      tabs: [
                        Tab(text: english ? 'Old Testament' : 'பழைய ஏற்பாடு'),
                        Tab(text: english ? 'New Testament' : 'புதிய ஏற்பாடு'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr('புத்தகத்தின் பெயர் / Book name'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: TabBarView(children: [_list(true, mode), _list(false, mode)]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Grid of chapter numbers for a book.
class _ChapterGridScreen extends StatelessWidget {
  const _ChapterGridScreen({required this.book, required this.onPick});
  final BibleBookInfo book;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(book.tamil)),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 72,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: book.chapterCount,
        itemBuilder: (_, i) => Material(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onPick(i + 1),
            child: Stack(
              children: [
                Center(
                  child: Text('${i + 1}',
                      style: TextStyle(fontSize: 18, color: theme.colorScheme.onSecondaryContainer)),
                ),
                // How far this chapter is read.
                Positioned(left: 8, right: 8, bottom: 7, child: ChapterProgressLine(book.number, i + 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin line at the bottom of a chapter button: how far that chapter is read.
class ChapterProgressLine extends StatelessWidget {
  const ChapterProgressLine(this.book, this.chapter, {super.key});
  final int book;
  final int chapter;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: BibleProgress.instance,
        builder: (context, _) {
          final f = BibleProgress.instance.chapter(book, chapter);
          if (f < 0.02) return const SizedBox.shrink();
          final theme = Theme.of(context);
          final read = f >= BibleProgress.done;
          return LinearProgressIndicator(
            value: read ? 1 : f,
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
            color: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          );
        },
      );
}
