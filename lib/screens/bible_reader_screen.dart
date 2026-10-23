import 'package:flutter/material.dart';

import '../data/bible.dart';
import '../data/reader_store.dart';
import '../theme/reading_theme.dart';
import 'bible_mode_switch.dart';

/// Reads one book of the Bible in Tamil, English (KJV), or both.
/// Swipe left/right (or use the arrows) to change chapter.
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
  double _fontSize = 20;

  BibleMode get _mode => bibleMode.value;
  List<List<String>>? _tamil;
  List<List<String>>? _english;

  bool get _needTamil => _mode != BibleMode.english;
  bool get _needEnglish => _mode != BibleMode.tamil;
  bool get _ready => (!_needTamil || _tamil != null) && (!_needEnglish || _english != null);

  @override
  void initState() {
    super.initState();
    _store.loadFontSize().then((s) {
      if (mounted) setState(() => _fontSize = s);
    });
    bibleMode.addListener(_onModeChanged);
    _loadTexts();
  }

  void _onModeChanged() {
    if (!mounted) return;
    setState(() {});
    _loadTexts();
  }

  Future<void> _loadTexts() async {
    if (_needTamil && _tamil == null) {
      final t = await Bible.instance.chapters(widget.book, BibleLang.tamil);
      if (mounted) setState(() => _tamil = t);
    }
    if (_needEnglish && _english == null) {
      final e = await Bible.instance.chapters(widget.book, BibleLang.english);
      if (mounted) setState(() => _english = e);
    }
  }

  @override
  void dispose() {
    bibleMode.removeListener(_onModeChanged);
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

  String get _bookName => switch (_mode) {
        BibleMode.tamil => widget.book.tamil,
        BibleMode.english => widget.book.english,
        BibleMode.both => '${widget.book.tamil} · ${widget.book.english}',
      };

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
              Flexible(child: Text('$_bookName $_chapter', overflow: TextOverflow.ellipsis)),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: const BibleModeSwitch(),
        ),
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pages,
              itemCount: total,
              onPageChanged: (i) => setState(() => _chapter = i + 1),
              itemBuilder: (_, i) => _ChapterPage(
                title: '$_bookName ${i + 1}',
                tamil: _needTamil ? _tamil![i] : null,
                english: _needEnglish ? _english![i] : null,
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
                      label: Text(_mode == BibleMode.english ? 'Previous' : 'முந்தைய'),
                    ),
                    const Spacer(),
                    Text('$_chapter / $total', style: theme.textTheme.bodyMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: _chapter < total ? () => _goTo(_chapter + 1) : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_mode == BibleMode.english ? 'Next' : 'அடுத்து'),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// One chapter: title + numbered verses (Tamil, English, or both), with its own scroll bar.
class _ChapterPage extends StatefulWidget {
  const _ChapterPage({
    required this.title,
    required this.tamil,
    required this.english,
    required this.fontSize,
    required this.textColor,
    required this.numberColor,
  });

  final String title;
  final List<String>? tamil;
  final List<String>? english;
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
    final ta = widget.tamil;
    final en = widget.english;
    final both = ta != null && en != null;
    final count = (ta ?? en)!.length;
    final englishColor = both ? widget.textColor.withValues(alpha: 0.75) : widget.textColor;

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
        itemCount: count + 1,
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
          final number = TextSpan(
            text: '$i  ',
            style: TextStyle(
                fontSize: widget.fontSize * 0.75, fontWeight: FontWeight.bold, color: widget.numberColor),
          );
          final children = <InlineSpan>[number];
          if (ta != null) children.add(TextSpan(text: ta[i - 1]));
          if (both) children.add(const TextSpan(text: '\n'));
          if (en != null && i - 1 < en.length) {
            children.add(TextSpan(
              text: en[i - 1],
              style: both
                  ? TextStyle(fontSize: widget.fontSize * 0.9, fontStyle: FontStyle.italic, color: englishColor)
                  : null,
            ));
          }
          return Padding(
            padding: EdgeInsets.only(bottom: both ? 18 : 12),
            child: SelectableText.rich(
              TextSpan(
                style: TextStyle(fontSize: widget.fontSize, height: 1.6, color: widget.textColor),
                children: children,
              ),
            ),
          );
        },
      ),
    );
  }
}
