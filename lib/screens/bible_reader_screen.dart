import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../data/bible.dart';
import '../data/mark_mirror.dart';
import '../data/prefs.dart';
import '../data/reader_store.dart';
import '../models/highlight.dart';
import '../services/pdf_export.dart';
import '../theme/reading_theme.dart';
import '../widgets/marking.dart';
import 'bible_mode_switch.dart';
import 'notes_screen.dart';
import 'section_switch.dart';
import '../widgets/more_menu.dart';

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

  // Both languages are always loaded: marks made in one are copied to the other.
  bool get _needTamil => true;
  bool get _needEnglish => true;
  bool get _ready => _tamil != null && _english != null;

  @override
  void initState() {
    super.initState();
    _store.loadFontSize().then((s) {
      if (mounted) setState(() => _fontSize = s);
    });
    bibleMode.addListener(_onModeChanged);
    bibleSplit.addListener(_onModeChanged);
    _loadTexts();
    _remember();
  }

  /// Remembers this place, so the Bible button in the Messages comes back here.
  void _remember() => Prefs.instance.set('last_bible', '${widget.book.number}:$_chapter');

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
    bibleSplit.removeListener(_onModeChanged);
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

  /// Saves the chapter on screen as a PDF (in the chosen language), with its marks.
  Future<void> _savePdf() async {
    final ta = _tamil, en = _english;
    if (ta == null || en == null) return;
    final c = _chapter;
    final taVerses = c - 1 < ta.length ? ta[c - 1] : const <String>[];
    final enVerses = c - 1 < en.length ? en[c - 1] : const <String>[];
    final taMarks = await _store.loadHighlights('bible_ta_${widget.book.number}_$c');
    final enMarks = await _store.loadHighlights('bible_en_${widget.book.number}_$c');
    final showTa = _mode != BibleMode.english, showEn = _mode != BibleMode.tamil;
    final title = '$_bookName $c';
    final blocks = <PdfBlock>[
      PdfBlock(TextSpan(text: title, style: PdfExport.title), align: TextAlign.center, lineBelow: true),
    ];
    final count = math.max(showTa ? taVerses.length : 0, showEn ? enVerses.length : 0);
    for (var v = 0; v < count; v++) {
      final parts = <InlineSpan>[
        TextSpan(
          text: '${v + 1}  ',
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF406F8A)),
        ),
      ];
      if (showTa && v < taVerses.length) {
        parts.add(TextSpan(
            children: markedSpans(taVerses[v], taMarks.where((h) => h.paragraph == v),
                chosenColor: Colors.transparent)));
      }
      if (showTa && showEn) parts.add(const TextSpan(text: '\n'));
      if (showEn && v < enVerses.length) {
        parts.add(TextSpan(
          style: showTa ? const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF333333)) : null,
          children: markedSpans(enVerses[v], enMarks.where((h) => h.paragraph == v),
              chosenColor: Colors.transparent),
        ));
      }
      blocks.add(PdfBlock(TextSpan(style: PdfExport.body, children: parts), spaceAfter: showTa && showEn ? 12 : 8));
    }
    if (!mounted) return;
    await PdfExport.saveWithMessages(
      context,
      fileName: PdfExport.fileName('${widget.book.english} $c'),
      blocks: blocks,
    );
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
          const GoToMessagesButton(),
          MoreMenu(onPdf: _savePdf),
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
              onPageChanged: (i) {
                setState(() => _chapter = i + 1);
                _remember();
              },
              itemBuilder: (_, i) => _ChapterPage(
                key: ValueKey('${widget.book.number}-${i + 1}'),
                book: widget.book.number,
                bookTamil: widget.book.tamil,
                bookEnglish: widget.book.english,
                chapter: i + 1,
                title: '$_bookName ${i + 1}',
                tamil: i < _tamil!.length ? _tamil![i] : const [],
                english: i < _english!.length ? _english![i] : const [],
                showTamil: _mode != BibleMode.english,
                showEnglish: _mode != BibleMode.tamil,
                split: bibleSplit.value,
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
/// Tap a line to choose it (tap more lines to stretch the choice), then colour, bold or
/// underline it. Marks are copied to the same verse in the other language.
class _ChapterPage extends StatefulWidget {
  const _ChapterPage({
    super.key,
    required this.book,
    required this.bookTamil,
    required this.bookEnglish,
    required this.chapter,
    required this.title,
    required this.tamil,
    required this.english,
    required this.showTamil,
    required this.showEnglish,
    required this.split,
    required this.fontSize,
    required this.textColor,
    required this.numberColor,
  });

  final int book;
  final String bookTamil;
  final String bookEnglish;
  final int chapter;
  final String title;
  final List<String> tamil;
  final List<String> english;
  final bool showTamil;
  final bool showEnglish;
  final bool split; // in "Both": split view instead of verse-under-verse
  final double fontSize;
  final Color textColor;
  final Color numberColor;

  @override
  State<_ChapterPage> createState() => _ChapterPageState();
}

class _ChapterPageState extends State<_ChapterPage> {
  final _scroll = ScrollController();
  final _store = ReaderStore();
  List<Highlight> _taMarks = [];
  List<Highlight> _enMarks = [];

  // Chosen lines: language, from verse v1 char s1 to verse v2 char e2 (verses 0-based).
  ({bool en, int v1, int s1, int v2, int e2})? _sel;

  String get _taKey => 'bible_ta_${widget.book}_${widget.chapter}';
  String get _enKey => 'bible_en_${widget.book}_${widget.chapter}';

  @override
  void initState() {
    super.initState();
    _loadMarks();
  }

  Future<void> _loadMarks() async {
    final ta = await _store.loadHighlights(_taKey);
    final en = await _store.loadHighlights(_enKey);
    if (mounted) {
      setState(() {
        _taMarks = ta;
        _enMarks = en;
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _scrollTa.dispose();
    _scrollEn.dispose();
    super.dispose();
  }

  List<String> _texts(bool en) => en ? widget.english : widget.tamil;
  List<Highlight> _marks(bool en) => en ? _enMarks : _taMarks;

  void _save() {
    _store.saveHighlights(_taKey, _taMarks);
    _store.saveHighlights(_enKey, _enMarks);
  }

  // ---------------- choosing lines ----------------

  (int, int)? _selIn(bool en, int v) {
    final sel = _sel;
    if (sel == null || sel.en != en || v < sel.v1 || v > sel.v2) return null;
    final text = _texts(en)[v];
    final s = v == sel.v1 ? sel.s1 : 0;
    final e = v == sel.v2 ? sel.e2 : text.length;
    return e > s ? (s, e) : null;
  }

  void _forEachSelected(void Function(bool en, int v, int s, int e) action) {
    final sel = _sel;
    if (sel == null) return;
    for (var v = sel.v1; v <= sel.v2; v++) {
      final r = _selIn(sel.en, v);
      if (r != null) action(sel.en, v, r.$1, r.$2);
    }
  }

  void _onTap(bool en, int v, int offset) {
    final cur = _sel;
    final inside = _selIn(en, v);
    if (inside != null && offset >= inside.$1 && offset < inside.$2) {
      setState(() => _sel = null);
      return;
    }
    final c = clauseAtOffset(_texts(en)[v], offset);
    if (c == null) return;
    if (cur == null || cur.en != en) {
      setState(() => _sel = (en: en, v1: v, s1: c.$1, v2: v, e2: c.$2));
      return;
    }
    final before = v < cur.v1 || (v == cur.v1 && c.$1 < cur.s1);
    final after = v > cur.v2 || (v == cur.v2 && c.$2 > cur.e2);
    setState(() => _sel = (
          en: en,
          v1: before ? v : cur.v1,
          s1: before ? c.$1 : cur.s1,
          v2: after ? v : cur.v2,
          e2: after ? c.$2 : cur.e2,
        ));
  }

  /// The same verse in the other language, same share of its lines.
  List<(int, int, int)> _mirror(bool en, int v, int s, int e) {
    final ta = widget.tamil, eng = widget.english;
    if (ta.isEmpty || eng.isEmpty) return const [];
    final align = List<int>.generate(ta.length, (i) => math.min(i, eng.length - 1));
    return mirrorRange(
      fromTamil: !en,
      align: align,
      from: _texts(en),
      to: _texts(!en),
      p: v,
      s: s,
      e: e,
    );
  }

  void _apply(MarkStyle style, [HighlightColor color = HighlightColor.yellow]) {
    setState(() {
      _forEachSelected((en, v, s, e) {
        final on = applyMark(_marks(en), _texts(en), v, s, e, style, color);
        for (final r in _mirror(en, v, s, e)) {
          applyMark(_marks(!en), _texts(!en), r.$1, r.$2, r.$3, style, color, add: on);
        }
      });
      _sel = null;
    });
    _save();
  }

  void _clear() {
    setState(() {
      _forEachSelected((en, v, s, e) {
        _marks(en).removeWhere((h) => h.overlaps(v, s, e));
        for (final r in _mirror(en, v, s, e)) {
          _marks(!en).removeWhere((h) => h.overlaps(r.$1, r.$2, r.$3));
        }
      });
      _sel = null;
    });
    _save();
  }

  /// 📝 Adds the chosen verses to the prepared note, e.g. "Genesis 1:1-3".
  void _sendToNotes() {
    final sel = _sel;
    if (sel == null) return;
    final parts = <String>[];
    _forEachSelected((en, v, s, e) {
      final t = _texts(en)[v].substring(s, e).trim();
      parts.add(sel.v1 == sel.v2 ? t : '${v + 1} $t');
    });
    final name = sel.en ? widget.bookEnglish : widget.bookTamil;
    final verses = sel.v1 == sel.v2 ? '${sel.v1 + 1}' : '${sel.v1 + 1}-${sel.v2 + 1}';
    sendToNotes(context, parts.join(' '), '$name ${widget.chapter}:$verses');
    setState(() => _sel = null);
  }

  void _copy() {
    final parts = <String>[];
    _forEachSelected((en, v, s, e) => parts.add('${v + 1}  ${_texts(en)[v].substring(s, e)}'));
    Clipboard.setData(ClipboardData(text: '${widget.title}\n${parts.join('\n')}'));
    setState(() => _sel = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  // ---------------- layout ----------------

  /// One verse. [onlyEnglish]: in the split view, show just one language (true = English).
  Widget _verse(int i, {bool? onlyEnglish}) {
    final v = i - 1;
    final showTa = onlyEnglish != true && widget.showTamil && v < widget.tamil.length;
    final showEn = onlyEnglish != false && widget.showEnglish && v < widget.english.length;
    final both = showTa && showEn;
    final chosenColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);
    final englishColor = both ? widget.textColor.withValues(alpha: 0.75) : widget.textColor;

    final numberText = '$i  ';
    final children = <InlineSpan>[
      TextSpan(
        text: numberText,
        style: TextStyle(
            fontSize: widget.fontSize * 0.75, fontWeight: FontWeight.bold, color: widget.numberColor),
      ),
    ];
    final taStart = numberText.length;
    final taEnd = showTa ? taStart + widget.tamil[v].length : taStart;
    if (showTa) {
      children.add(TextSpan(
        children: markedSpans(widget.tamil[v], _taMarks.where((h) => h.paragraph == v),
            chosen: _selIn(false, v), chosenColor: chosenColor),
      ));
    }
    if (both) children.add(const TextSpan(text: '\n'));
    final enStart = both ? taEnd + 1 : taStart;
    if (showEn) {
      children.add(TextSpan(
        style: both
            ? TextStyle(fontSize: widget.fontSize * 0.9, fontStyle: FontStyle.italic, color: englishColor)
            : null,
        children: markedSpans(widget.english[v], _enMarks.where((h) => h.paragraph == v),
            chosen: _selIn(true, v), chosenColor: chosenColor),
      ));
    }

    final key = _textKeys.putIfAbsent('$onlyEnglish-$v', () => GlobalKey());

    // Which language and character is at a touch point.
    (bool, int) at(Offset local) {
      final box = key.currentContext?.findRenderObject();
      final off = box is RenderParagraph ? box.getPositionForOffset(local).offset : 0;
      if (showTa && off >= taStart && off <= taEnd) {
        return (false, math.max(0, math.min(off - taStart, widget.tamil[v].length - 1)));
      }
      if (showEn && off >= enStart) {
        return (true, math.max(0, math.min(off - enStart, widget.english[v].length - 1)));
      }
      return (!showTa, 0); // the verse number
    }

    Offset? downLocal, downGlobal;
    return Padding(
      key: onlyEnglish == null ? null : _paneKeys[onlyEnglish]!.putIfAbsent(v, () => GlobalKey()),
      padding: EdgeInsets.only(bottom: both ? 18 : 12),
      // Tap = choose the line (tap more lines to stretch). Long press / double tap = send to MyNotes.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final (en, off) = at(d.localPosition);
          _onTap(en, v, off);
        },
        onDoubleTapDown: (d) {
          downLocal = d.localPosition;
          downGlobal = d.globalPosition;
        },
        onDoubleTap: () {
          if (downLocal != null) _offerNotes(v, at(downLocal!), downGlobal!);
        },
        onLongPressStart: (d) => _offerNotes(v, at(d.localPosition), d.globalPosition),
        child: Text.rich(
          key: key,
          TextSpan(
            style: TextStyle(fontSize: widget.fontSize, height: 1.6, color: widget.textColor),
            children: children,
          ),
        ),
      ),
    );
  }

  final Map<String, GlobalKey> _textKeys = {};

  // ---------------- split view: Tamil above, English below ----------------

  final _scrollTa = ScrollController();
  final _scrollEn = ScrollController();
  final Map<bool, Map<int, GlobalKey>> _paneKeys = {false: {}, true: {}};
  final Map<bool, bool> _dragging = {false: false, true: false};
  bool _jumping = false;

  ScrollController _paneScroll(bool en) => en ? _scrollEn : _scrollTa;

  bool _onPaneScroll(bool en, ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is UserScrollNotification) {
      _dragging[en] = n.direction != ScrollDirection.idle;
    } else if (n is ScrollStartNotification && n.dragDetails != null) {
      _dragging[en] = true;
    }
    if (n is ScrollUpdateNotification && _dragging[en]! && !_jumping) {
      final (v, f) = _paneTop(en);
      _paneFollow(!en, v, f);
    }
    return false;
  }

  /// The verse at the top of a half, and how far into it (0..1).
  (int, double) _paneTop(bool en) {
    final c = _paneScroll(en);
    if (!c.hasClients) return (0, 0);
    final viewport = c.position.context.storageContext.findRenderObject();
    if (viewport is! RenderBox) return (0, 0);
    final top = viewport.localToGlobal(Offset.zero).dy;
    final keys = _paneKeys[en]!;
    final verses = keys.keys.toList()..sort();
    for (final v in verses) {
      final box = keys[v]!.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final boxTop = box.localToGlobal(Offset.zero).dy;
      if (boxTop + box.size.height > top) {
        return (v, box.size.height <= 0 ? 0 : ((top - boxTop) / box.size.height).clamp(0.0, 1.0));
      }
    }
    return (0, 0);
  }

  /// Moves a half so that verse [v] (at [fraction]) is at the top.
  void _paneFollow(bool en, int v, double fraction) {
    if (_dragging[en]!) return;
    final c = _paneScroll(en);
    if (!c.hasClients) return;
    final keys = _paneKeys[en]!;
    if (keys.isEmpty) return;
    final last = keys.keys.reduce(math.max);
    final box = keys[math.min(v, last)]?.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final start = viewport.getOffsetToReveal(box, 0).offset;
    final target = (start + fraction * box.size.height)
        .clamp(c.position.minScrollExtent, c.position.maxScrollExtent);
    _jumping = true;
    c.jumpTo(target);
    _jumping = false;
  }

  Widget _chapterTitle() => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(widget.title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: widget.fontSize + 4, fontWeight: FontWeight.w700, color: widget.textColor)),
      );

  Widget _pane(bool en) {
    final c = _paneScroll(en);
    final count = en ? widget.english.length : widget.tamil.length;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) => _onPaneScroll(en, n),
      child: RawScrollbar(
        controller: c,
        thumbVisibility: true,
        interactive: true,
        thickness: 8,
        minThumbLength: 40,
        radius: const Radius.circular(8),
        crossAxisMargin: 3,
        thumbColor: widget.textColor.withValues(alpha: 0.35),
        child: SingleChildScrollView(
          controller: c,
          padding: EdgeInsets.fromLTRB(20, 10, 24, _sel == null ? 40 : 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _chapterTitle(),
              for (var i = 1; i <= count; i++) _verse(i, onlyEnglish: en),
            ],
          ),
        ),
      ),
    );
  }

  /// Long press / double tap: offer to send the chosen verses (or this line) to MyNotes.
  Future<void> _offerNotes(int v, (bool, int) place, Offset global) async {
    final (en, offset) = place;
    if (_selIn(en, v) == null) {
      final c = clauseAtOffset(_texts(en)[v], offset);
      if (c == null) return;
      setState(() => _sel = (en: en, v1: v, s1: c.$1, v2: v, e2: c.$2));
    }
    final size = MediaQuery.of(context).size;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, size.width - global.dx, size.height - global.dy),
      items: const [
        PopupMenuItem(
          value: 'notes',
          child: ListTile(
            leading: Icon(Icons.note_add_outlined),
            title: Text('குறிப்பில் சேர் / Send to notes'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (choice == 'notes') _sendToNotes();
  }

  @override
  Widget build(BuildContext context) {
    final count = math.max(
      widget.showTamil ? widget.tamil.length : 0,
      widget.showEnglish ? widget.english.length : 0,
    );

    final split = widget.showTamil && widget.showEnglish && widget.split;
    return Stack(
      children: [
        if (split)
          Column(
            children: [
              Expanded(child: _pane(false)),
              Container(height: 7, color: widget.numberColor.withValues(alpha: 0.55)),
              Expanded(child: _pane(true)),
            ],
          )
        else
        RawScrollbar(
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
            padding: EdgeInsets.fromLTRB(20, 12, 24, _sel == null ? 48 : 110),
            itemCount: count + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: widget.fontSize + 4,
                          fontWeight: FontWeight.w700,
                          color: widget.textColor)),
                );
              }
              return _verse(i);
            },
          ),
        ),
        if (_sel != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MarkBar(
              onColor: (c) => _apply(MarkStyle.color, c),
              onBold: () => _apply(MarkStyle.bold),
              onUnderline: () => _apply(MarkStyle.underline),
              onCopy: _copy,
              onSendToNotes: _sendToNotes,
              onClear: _clear,
              onClose: () => setState(() => _sel = null),
            ),
          ),
      ],
    );
  }
}
