import 'package:flutter/material.dart';

import '../data/bible.dart';
import '../data/reader_store.dart';
import '../theme/reading_theme.dart';

/// Reads one book of the Bible. Swipe left/right (or use the arrows) to change chapter.
class BibleReaderScreen extends StatefulWidget {
  final BibleBookInfo book;
  final int initialChapter; // 1-based

  const BibleReaderScreen({super.key, required this.book, this.initialChapter = 1});

  @override
  State<BibleReaderScreen> createState() => _BibleReaderScreenState();
}

class _BibleReaderScreenState extends State<BibleReaderScreen> {
  static const double _minFont = 14;
  static const double _maxFont = 40;

  final _store = ReaderStore();
  late final PageController _pages = PageController(initialPage: widget.initialChapter - 1);
  late int _chapter = widget.initialChapter;
  List<List<String>>? _chapters;
  double _fontSize = 20;

  @override
  void initState() {
    super.initState();
    _store.loadFontSize().then((s) {
      if (mounted) setState(() => _fontSize = s);
    });
    Bible.instance.chapters(widget.book).then((c) {
      if (mounted) setState(() => _chapters = c);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _setFont(double size) {
    setState(() => _fontSize = size.clamp(_minFont, _maxFont).toDouble());
    _store.saveFontSize(_fontSize);
  }

  void _goTo(int chapter) {
    if (chapter < 1 || chapter > widget.book.chapterCount) return;
    _pages.animateToPage(chapter - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _pickChapter() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 64, mainAxisSpacing: 8, crossAxisSpacing: 8),
        itemCount: widget.book.chapterCount,
        itemBuilder: (_, i) => OutlinedButton(
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: () => Navigator.of(ctx).pop(i + 1),
          child: Text('${i + 1}'),
        ),
      ),
    );
    if (picked != null) _pages.jumpToPage(picked - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final numberColor = theme.colorScheme.primary;
    final total = widget.book.chapterCount;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: total > 1 ? _pickChapter : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text('${widget.book.tamil} $_chapter', overflow: TextOverflow.ellipsis)),
              if (total > 1) const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Smaller text',
            icon: const Text('A−', style: TextStyle(fontSize: 16)),
            onPressed: () => _setFont(_fontSize - 2),
          ),
          IconButton(
            tooltip: 'Bigger text',
            icon: const Text('A+', style: TextStyle(fontSize: 22)),
            onPressed: () => _setFont(_fontSize + 2),
          ),
          const ThemeButton(),
        ],
      ),
      body: _chapters == null
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pages,
              itemCount: total,
              onPageChanged: (i) => setState(() => _chapter = i + 1),
              itemBuilder: (_, i) => _ChapterPage(
                title: '${widget.book.tamil} ${i + 1}',
                verses: _chapters![i],
                fontSize: _fontSize,
                textColor: textColor,
                numberColor: numberColor,
              ),
            ),
      bottomNavigationBar: total <= 1
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _chapter > 1 ? () => _goTo(_chapter - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('முந்தைய'),
                    ),
                    const Spacer(),
                    Text('$_chapter / $total', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: _chapter < total ? () => _goTo(_chapter + 1) : null,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [Text('அடுத்து'), Icon(Icons.chevron_right)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// One chapter: title + numbered verses, with its own scroll bar.
class _ChapterPage extends StatefulWidget {
  const _ChapterPage({
    required this.title,
    required this.verses,
    required this.fontSize,
    required this.textColor,
    required this.numberColor,
  });

  final String title;
  final List<String> verses;
  final double fontSize;
  final Color textColor;
  final Color numberColor;

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verses = widget.verses;
    return RawScrollbar(
      controller: _scroll,
      thumbVisibility: true,
      interactive: true,
      thickness: 8,
      minThumbLength: 56,
      radius: const Radius.circular(8),
      crossAxisMargin: 3,
      thumbColor: widget.textColor.withValues(alpha: 0.35),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 24, 48),
        itemCount: verses.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(widget.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: widget.fontSize + 4, fontWeight: FontWeight.w700, color: widget.textColor)),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText.rich(TextSpan(
              style: TextStyle(fontSize: widget.fontSize, height: 1.6, color: widget.textColor),
              children: [
                TextSpan(
                  text: '$i  ',
                  style: TextStyle(
                      fontSize: widget.fontSize * 0.75, fontWeight: FontWeight.bold, color: widget.numberColor),
                ),
                TextSpan(text: verses[i - 1]),
              ],
            )),
          );
        },
      ),
    );
  }
}
