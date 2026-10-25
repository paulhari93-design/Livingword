import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../data/library.dart';
import '../data/mark_mirror.dart';
import '../data/reader_store.dart';
import '../models/highlight.dart';
import '../models/message.dart';
import '../services/pdf_export.dart';
import '../widgets/marking.dart';
import '../widgets/more_menu.dart';
import 'message_lang_switch.dart';
import 'notes_screen.dart';
import 'reader_screen.dart';
import 'section_switch.dart';
import 'split_reader_screen.dart';
import 'swipe.dart';

/// "Both" in normal view: one reader, each Tamil paragraph followed by its English.
/// Tap a line to choose it (tap more lines to stretch), then colour / bold / underline,
/// send to notes or copy. Marks are copied to the other language.
class CombinedReaderScreen extends StatefulWidget {
  const CombinedReaderScreen({super.key, required this.tamil, required this.english, this.initialTamilParagraph});

  final Message tamil;
  final Message english;
  final int? initialTamilParagraph;

  @override
  State<CombinedReaderScreen> createState() => _CombinedReaderScreenState();
}

class _CombinedReaderScreenState extends State<CombinedReaderScreen> {
  static const double _minFont = 14, _maxFont = 40;

  final _store = ReaderStore();
  final _scroll = ScrollController();
  double _fontSize = 20;
  List<Highlight> _taMarks = [];
  List<Highlight> _enMarks = [];

  // Chosen lines: language, from paragraph v1 char s1 to paragraph v2 char e2.
  ({bool en, int v1, int s1, int v2, int e2})? _sel;

  late final List<int> _align = _makeAlign();
  late final List<List<int>> _englishUnder = _group(); // English paragraphs shown under each Tamil one
  final Map<int, GlobalKey> _blockKeys = {}; // Tamil paragraph blocks (for "where am I")
  final Map<String, GlobalKey> _textKeys = {};

  Message get _ta => widget.tamil;
  Message get _en => widget.english;

  @override
  void initState() {
    super.initState();
    messageSplit.addListener(_viewChanged);
    _load();
  }

  @override
  void dispose() {
    messageSplit.removeListener(_viewChanged);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final size = await _store.loadFontSize();
    final ta = await _store.loadHighlights(_ta.storageId);
    final en = await _store.loadHighlights(_en.storageId);
    if (!mounted) return;
    setState(() {
      _fontSize = size;
      _taMarks = ta;
      _enMarks = en;
    });
    final p = widget.initialTamilParagraph;
    if (p != null && p > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _blockKeys[p]?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.05);
      });
    }
  }

  /// For each Tamil paragraph, its English paragraph (from publishing), else the same position.
  List<int> _makeAlign() {
    final a = _ta.align;
    if (a != null && a.length == _ta.paragraphs.length) return a;
    final n = _ta.paragraphs.length, m = _en.paragraphs.length;
    return List.generate(n, (i) => m == 0 ? 0 : math.min(m - 1, (i * m / math.max(1, n)).floor()));
  }

  /// Each English paragraph goes under the last Tamil paragraph matched to it (or before it).
  List<List<int>> _group() {
    final groups = List.generate(_ta.paragraphs.length, (_) => <int>[]);
    if (groups.isEmpty) return groups;
    var owner = 0;
    for (var j = 0; j < _en.paragraphs.length; j++) {
      while (owner + 1 < _align.length && _align[owner + 1] <= j) {
        owner++;
      }
      groups[owner].add(j);
    }
    return groups;
  }

  // ---------------- views ----------------

  int _currentTamilParagraph() {
    final viewport = _scroll.hasClients ? _scroll.position.context.storageContext.findRenderObject() : null;
    if (viewport is! RenderBox) return 0;
    final top = viewport.localToGlobal(Offset.zero).dy + 8;
    for (var i = 0; i < _ta.paragraphs.length; i++) {
      final box = _blockKeys[i]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      if (box.localToGlobal(Offset(0, box.size.height)).dy > top) return i;
    }
    return 0;
  }

  /// Normal ⇄ split was chosen in "Both ⋮".
  void _viewChanged() {
    if (!mounted || !messageSplit.value) return;
    final p = _currentTamilParagraph();
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => SplitReaderScreen(tamil: _ta, english: _en, initialTamilParagraph: p),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Tamil or English only, at the paragraph being read.
  Future<void> _single(String lang) async {
    final p = _currentTamilParagraph();
    final message = lang == 'en' ? _en : _ta;
    final target = lang == 'en' ? matchParagraph(_ta, _en, p) : p;
    await messageLang.set(lang);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => ReaderScreen(
        message: message,
        initialParagraph: target > 0 ? target : null,
        flashParagraph: target > 0,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  Future<void> _goNeighbour(int step) async {
    final ta = await neighbourMessage(_ta.code, 'ta', step);
    if (!mounted) return;
    if (ta == null) {
      showEndOfList(context, step > 0);
      return;
    }
    final enInfo = await Library.instance.find(ta.code, 'en');
    final en = enInfo == null ? null : await Library.instance.message(enInfo);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(slideRoute(
      en == null ? ReaderScreen(message: ta) : CombinedReaderScreen(tamil: ta, english: en),
      forward: step > 0,
    ));
  }

  void _setFont(double size) {
    setState(() => _fontSize = size.clamp(_minFont, _maxFont).toDouble());
    _store.saveFontSize(_fontSize);
  }

  // ---------------- choosing lines and marking ----------------

  List<String> _texts(bool en) => en ? _en.paragraphs : _ta.paragraphs;
  List<Highlight> _marks(bool en) => en ? _enMarks : _taMarks;

  (int, int)? _selIn(bool en, int v) {
    final sel = _sel;
    if (sel == null || sel.en != en || v < sel.v1 || v > sel.v2) return null;
    final text = _texts(en)[v];
    final s = v == sel.v1 ? sel.s1 : textStart(text);
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

  List<(int, int, int)> _mirror(bool en, int v, int s, int e) => mirrorRange(
        fromTamil: !en,
        align: _align,
        from: _texts(en),
        to: _texts(!en),
        p: v,
        s: s,
        e: e,
      );

  void _save() {
    _store.saveHighlights(_ta.storageId, _taMarks);
    _store.saveHighlights(_en.storageId, _enMarks);
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

  String _selectedText() {
    final parts = <String>[];
    _forEachSelected((en, v, s, e) => parts.add(_texts(en)[v].substring(s, e).trim()));
    return parts.join('\n');
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _selectedText()));
    setState(() => _sel = null);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
  }

  int _paraNumber(bool en, int p) {
    final paras = _texts(en);
    for (var k = p; k >= 0; k--) {
      final m = RegExp(r'^(\d{1,3})[.\s]').firstMatch(paras[k]);
      if (m != null) return int.parse(m.group(1)!);
    }
    return p + 1;
  }

  void _sendToNotes() {
    final sel = _sel;
    if (sel == null) return;
    final m = sel.en ? _en : _ta;
    final a = _paraNumber(sel.en, sel.v1), b = _paraNumber(sel.en, sel.v2);
    sendToNotes(context, _selectedText(), '${m.code} ${m.title}, ${a == b ? '¶$a' : '¶$a–$b'}');
    setState(() => _sel = null);
  }

  Future<void> _offerNotes(bool en, int v, int offset, Offset global) async {
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

  Future<void> _savePdf() async {
    final blocks = <PdfBlock>[
      PdfBlock(TextSpan(text: _ta.title, style: PdfExport.title), align: TextAlign.center, spaceAfter: 2),
      PdfBlock(TextSpan(text: _en.title, style: PdfExport.info), align: TextAlign.center, spaceAfter: 2),
      PdfBlock(TextSpan(text: _ta.code, style: PdfExport.info), align: TextAlign.center, lineBelow: true),
    ];
    for (var i = 0; i < _ta.paragraphs.length; i++) {
      blocks.add(PdfBlock(
        TextSpan(
          style: PdfExport.body,
          children: markedSpans(_ta.paragraphs[i], _taMarks.where((h) => h.paragraph == i),
              chosenColor: Colors.transparent),
        ),
        spaceAfter: 4,
      ));
      for (final j in _englishUnder[i]) {
        blocks.add(PdfBlock(
          TextSpan(
            style: PdfExport.body.copyWith(fontStyle: FontStyle.italic, color: const Color(0xFF333333)),
            children: markedSpans(_en.paragraphs[j], _enMarks.where((h) => h.paragraph == j),
                chosenColor: Colors.transparent),
          ),
          spaceAfter: 4,
        ));
      }
      blocks.add(const PdfBlock(TextSpan(text: ' '), spaceAfter: 4));
    }
    await PdfExport.saveWithMessages(context,
        fileName: PdfExport.fileName('${_ta.code} ${_en.title} (Tamil-English)'), blocks: blocks);
  }

  // ---------------- layout ----------------

  Widget _text(bool en, int v, Color textColor) {
    final key = _textKeys.putIfAbsent('$en-$v', () => GlobalKey());
    final chosenColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);
    int at(Offset local) {
      final box = key.currentContext?.findRenderObject();
      return box is RenderParagraph ? box.getPositionForOffset(local).offset : 0;
    }

    Offset? downLocal, downGlobal;
    return Padding(
      padding: EdgeInsets.only(bottom: en ? 10 : 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _onTap(en, v, at(d.localPosition)),
        onDoubleTapDown: (d) {
          downLocal = d.localPosition;
          downGlobal = d.globalPosition;
        },
        onDoubleTap: () {
          if (downLocal != null) _offerNotes(en, v, at(downLocal!), downGlobal!);
        },
        onLongPressStart: (d) => _offerNotes(en, v, at(d.localPosition), d.globalPosition),
        child: Text.rich(
          key: key,
          TextSpan(
            style: en
                ? TextStyle(
                    fontSize: _fontSize * 0.92,
                    height: 1.55,
                    fontStyle: FontStyle.italic,
                    color: textColor.withValues(alpha: 0.78))
                : TextStyle(fontSize: _fontSize, height: 1.6, color: textColor),
            children: markedSpans(_texts(en)[v], _marks(en).where((h) => h.paragraph == v),
                chosen: _selIn(en, v), chosenColor: chosenColor),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final rule = theme.colorScheme.primary.withValues(alpha: 0.35);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_ta.title, overflow: TextOverflow.ellipsis),
              Text(_ta.code, style: theme.textTheme.bodySmall),
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
          const GoToBibleButton(),
          MoreMenu(onPdf: _savePdf),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: MessageLangSwitch(
            value: 'both',
            showBoth: true,
            onChanged: (v) {
              if (v != 'both') _single(v);
            },
          ),
        ),
      ),
      bottomNavigationBar: _sel == null
          ? null
          : SafeArea(
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
      body: MessageSwipe(
        onNext: () => _goNeighbour(1),
        onPrevious: () => _goNeighbour(-1),
        child: RawScrollbar(
          controller: _scroll,
          thumbVisibility: true,
          interactive: true,
          thickness: 8,
          minThumbLength: 56,
          radius: const Radius.circular(8),
          crossAxisMargin: 3,
          thumbColor: textColor.withValues(alpha: 0.35),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 24, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_ta.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: _fontSize + 4, fontWeight: FontWeight.w700, color: textColor)),
                const SizedBox(height: 4),
                Text(_en.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: _fontSize, fontStyle: FontStyle.italic, color: textColor.withValues(alpha: 0.8))),
                const SizedBox(height: 4),
                Text(_ta.code,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: _fontSize - 4, color: textColor.withValues(alpha: 0.7))),
                Divider(color: textColor.withValues(alpha: 0.2), indent: 40, endIndent: 40, height: 32),
                for (var i = 0; i < _ta.paragraphs.length; i++)
                  Container(
                    key: _blockKeys.putIfAbsent(i, () => GlobalKey()),
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rule, width: 0.5))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _text(false, i, textColor),
                        for (final j in _englishUnder[i]) _text(true, j, textColor),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
