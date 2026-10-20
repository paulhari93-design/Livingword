import 'package:flutter/material.dart';

import '../data/bible.dart';
import '../theme/reading_theme.dart';
import 'bible_reader_screen.dart';

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

  Widget _list(bool oldTestament) {
    final items = _books.where((b) => b.isOldTestament == oldTestament && b.matches(_query)).toList();
    if (_books.isEmpty) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return const Center(child: Text('புத்தகம் கிடைக்கவில்லை'));
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final b = items[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text('${b.number}', style: TextStyle(color: theme.colorScheme.onPrimaryContainer)),
          ),
          title: Text(b.tamil, style: const TextStyle(fontSize: 18)),
          subtitle: Text('${b.english} · ${b.chapterCount} அதிகாரங்கள்'),
          onTap: () => _openBook(b),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('தமிழ் வேதாகமம்'),
          actions: const [ThemeButton()],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'பழைய ஏற்பாடு'),
              Tab(text: 'புதிய ஏற்பாடு'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'புத்தகத்தின் பெயர் / Book name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: TabBarView(children: [_list(true), _list(false)]),
            ),
          ],
        ),
      ),
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
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onPick(i + 1),
            child: Center(
              child: Text('${i + 1}',
                  style: TextStyle(fontSize: 18, color: theme.colorScheme.onSecondaryContainer)),
            ),
          ),
        ),
      ),
    );
  }
}
