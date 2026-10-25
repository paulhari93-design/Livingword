import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../data/library.dart';
import '../data/mark_mirror.dart';
import '../data/prefs.dart';
import '../data/reader_store.dart';
import '../models/highlight.dart';
import '../services/pdf_export.dart';
import '../widgets/marking.dart';
import '../models/message.dart';
import '../theme/reading_theme.dart';
import 'message_lang_switch.dart';
import 'notes_screen.dart';
import 'search_screen.dart';
import 'section_switch.dart';
import 'combined_reader_screen.dart';
import 'split_reader_screen.dart';
import 'swipe.dart';
import '../widgets/more_menu.dart';

class ReaderScreen extends StatefulWidget {
  final Message message;
  final int? initialParagraph; // jump here when opened from search
  final String? searchQuery; // mark these words when opened from search
  final bool flashParagraph; // briefly mark initialParagraph (after a language switch)
  final bool embedded; // one half of the Tamil/English split view (no top bar of its own)
  final SplitLink? link; // connects the two halves of the split view

  const ReaderScreen({
    super.key,
    required this.message,
    this.initialParagraph,
    this.searchQuery,
    this.flashParagraph = false,
    this.embedded = false,
    this.link,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const double _minFont = 14;
  static const double _maxFont = 40;
  static const Color _searchColor = Color(0xFFFFB74D); // orange for search matches

  final _store = ReaderStore();
  final _scroll = ScrollController();
  late final List<GlobalKey> _keys =
      List.generate(widget.message.paragraphs.length, (_) => GlobalKey());

  double _fontSize = 20;
  List<Highlight> _highlights = [];
  MessageInfo? _other; // the same message in the other language, if on the phone
  Message? _otherMessage; // its text (to copy marks across)
  List<Highlight>? _otherHighlights; // its marks
  int? _flash; // paragraph briefly marked after switching language
  // The lines chosen by tapping: from paragraph p1, character s1 to paragraph p2, character e2.
  ({int p1, int s1, int p2, int e2})? _sel;

  /// The chosen part of paragraph [i], or null.
  (int, int)? _selIn(int i) {
    final sel = _sel;
    if (sel == null || i < sel.p1 || i > sel.p2) return null;
    final text = widget.message.paragraphs[i];
    final lead = RegExp(r'^\d{1,3}[.\s]\s*').firstMatch(text)?.end ?? 0;
    final s = i == sel.p1 ? sel.s1 : lead;
    final e = i == sel.p2 ? sel.e2 : text.length;
    return e > s ? (s, e) : null;
  }

  /// Runs [action] on the chosen part of every paragraph in the selection.
  void _forEachSelected(void Function(int paragraph, int s, int e) action) {
    final sel = _sel;
    if (sel == null) return;
    for (var i = sel.p1; i <= sel.p2; i++) {
      final r = _selIn(i);
      if (r != null) action(i, r.$1, r.$2);
    }
  }

  // Search-in-reader state
  String _query = ''; // normalized
  List<int> _matchParas = []; // paragraphs that contain the query
  int _matchIndex = 0;

  // Pinch-to-zoom tracking (two fingers change the font size).
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartFont = 20;

  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
    widget.link?.register(
      widget.message.lang,
      follow: _follow,
      reloadMarks: _reloadMarks,
      changeFont: (d) => _setFont(_fontSize + d),
      currentParagraph: () => _scroll.hasClients ? _currentParagraph() : 0,
    );
  }

  // ---------------- split view (Tamil above, English below) ----------------

  bool _userScrolling = false; // this half is being scrolled by a finger
  bool _following = false; // this half is being moved by the other half

  /// The paragraph at the top, and how far into it (0..1).
  (int, double) _topPosition() {
    final i = _currentParagraph();
    final box = _keys[i].currentContext?.findRenderObject();
    final viewport = _scroll.position.context.storageContext.findRenderObject();
    if (box is! RenderBox || viewport is! RenderBox || box.size.height <= 0) return (i, 0);
    final top = viewport.localToGlobal(Offset.zero).dy;
    final boxTop = box.localToGlobal(Offset.zero).dy;
    return (i, ((top - boxTop) / box.size.height).clamp(0.0, 1.0));
  }

  /// Moves this half so that [paragraph] (at [fraction]) is at the top.
  void _follow(int paragraph, double fraction) {
    if (!_scroll.hasClients || _userScrolling || paragraph >= _keys.length) return;
    final box = _keys[paragraph].currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final start = viewport.getOffsetToReveal(box, 0).offset;
    final target = (start + fraction * box.size.height)
        .clamp(_scroll.position.minScrollExtent, _scroll.position.maxScrollExtent);
    _following = true;
    _scroll.jumpTo(target);
    _following = false;
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (widget.link == null || n.depth != 0) return false;
    if (n is UserScrollNotification) {
      _userScrolling = n.direction != ScrollDirection.idle;
    } else if (n is ScrollStartNotification && n.dragDetails != null) {
      _userScrolling = true;
    }
    if (n is ScrollUpdateNotification && _userScrolling && !_following) {
      final (p, f) = _topPosition();
      widget.link!.moved(widget.message.lang, p, f);
    }
    return false;
  }

  /// In the split view, tell the other half to show the new marks.
  void _notifyLink() {
    final link = widget.link;
    if (link == null) return;
    Future.delayed(const Duration(milliseconds: 150), () => link.marksChanged(widget.message.lang));
  }

  /// The other half changed marks (and copied them here): show them.
  Future<void> _reloadMarks() async {
    final own = await _store.loadHighlights(widget.message.storageId);
    final om = _otherMessage;
    final other = om == null ? null : await _store.loadHighlights(om.storageId);
    if (!mounted) return;
    setState(() {
      _highlights = own;
      if (other != null) _otherHighlights = other;
    });
  }

  /// Remembers the message and paragraph, so the Messages button in the Bible comes back here.
  void _remember([int? paragraph]) {
    final m = widget.message;
    Prefs.instance.set('last_message', '${m.lang}|${m.code}|${paragraph ?? 0}');
  }

  void _onScroll() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && _scroll.hasClients) _remember(_currentParagraph());
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (widget.link != null) widget.link!.unregister(widget.message.lang);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final size = await _store.loadFontSize();
    var hls = await _store.loadHighlights(widget.message.storageId);
    // If the message was corrected since the highlights were made, put them back on their words.
    final fixed = Highlight.reanchor(hls, widget.message.paragraphs);
    if (fixed != null) {
      hls = fixed;
      await _store.saveHighlights(widget.message.storageId, hls);
    }
    _remember(widget.initialParagraph);
    final other = await Library.instance
        .find(widget.message.code, widget.message.lang == 'en' ? 'ta' : 'en');
    Message? otherMessage;
    List<Highlight>? otherHls;
    if (other != null) {
      try {
        otherMessage = await Library.instance.message(other);
        otherHls = await _store.loadHighlights(otherMessage.storageId);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _fontSize = size;
      _highlights = hls;
      _other = other;
      _otherMessage = otherMessage;
      _otherHighlights = otherHls;
    });
    final q = widget.searchQuery;
    if (q != null && q.trim().isNotEmpty) {
      _applySearch(q, jumpTo: widget.initialParagraph);
    } else if (widget.initialParagraph != null) {
      _jumpToParagraph(widget.initialParagraph!);
      if (widget.flashParagraph) {
        setState(() => _flash = widget.initialParagraph);
        Future.delayed(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _flash = null);
        });
      }
    }
  }

  // ---------------- search inside this message ----------------

  void _applySearch(String rawQuery, {int? jumpTo}) {
    final q = normalizeQuery(rawQuery);
    final paras = <int>[];
    for (var i = 0; i < widget.message.paragraphs.length; i++) {
      if (findMatches(widget.message.paragraphs[i], q).isNotEmpty) paras.add(i);
    }
    setState(() {
      _query = q;
      _matchParas = paras;
      _matchIndex = jumpTo != null ? math.max(0, paras.indexOf(jumpTo)) : 0;
    });
    if (paras.isNotEmpty) _jumpToParagraph(paras[_matchIndex]);
  }

  void _clearSearch() => setState(() {
        _query = '';
        _matchParas = [];
      });

  void _nextMatch(int step) {
    if (_matchParas.isEmpty) return;
    setState(() => _matchIndex = (_matchIndex + step) % _matchParas.length);
    _jumpToParagraph(_matchParas[_matchIndex]);
  }

  void _jumpToParagraph(int index) {
    // Wait for the layout, then scroll so the paragraph is near the top.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[index].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  /// The paragraph at the top of the screen right now.
  int _currentParagraph() {
    final viewport = _scroll.position.context.storageContext.findRenderObject();
    if (viewport is! RenderBox) return 0;
    final top = viewport.localToGlobal(Offset.zero).dy + 8;
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (bottom > top) return i;
    }
    return 0;
  }

  /// Swipe: the next (step +1) or previous (step -1) message, same language.
  Future<void> _goNeighbour(int step) async {
    final next = await neighbourMessage(widget.message.code, widget.message.lang, step);
    if (!mounted) return;
    if (next == null) {
      showEndOfList(context, step > 0);
      return;
    }
    Navigator.of(context).pushReplacement(slideRoute(ReaderScreen(message: next), forward: step > 0));
  }

  /// Opens Tamil above / English below, at the paragraph being read.
  Future<void> _openBoth() async {
    final other = _otherMessage;
    if (other == null) return;
    final ta = widget.message.lang == 'en' ? other : widget.message;
    final en = widget.message.lang == 'en' ? widget.message : other;
    final here = _scroll.hasClients && _scroll.offset > 20 ? _currentParagraph() : 0;
    final p = widget.message.lang == 'en' ? matchParagraph(en, ta, here) : here;
    await messageLang.set('both');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => messageSplit.value
          ? SplitReaderScreen(tamil: ta, english: en, initialTamilParagraph: p)
          : CombinedReaderScreen(tamil: ta, english: en, initialTamilParagraph: p),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Opens the same message in the other language, at the matching paragraph.
  Future<void> _switchLanguage() async {
    final other = _other;
    if (other == null) return;
    final message = await Library.instance.message(other);
    final here = _scroll.hasClients && _scroll.offset > 20 ? _currentParagraph() : null;
    int? target;
    if (here != null) {
      if (widget.message.lang == 'ta') {
        // Tamil -> English: the Tamil message knows its English paragraph.
        final a = widget.message.align;
        if (a != null && here < a.length) target = a[here];
      } else {
        // English -> Tamil: the first Tamil paragraph matched to this (or a later) English one.
        final a = message.align;
        if (a != null) {
          for (var i = 0; i < a.length; i++) {
            if (a[i] >= here) {
              target = i;
              break;
            }
          }
          target ??= a.length - 1;
        }
      }
      // No match list (e.g. not published yet): use the same position in the message.
      target ??= (here * message.paragraphs.length / widget.message.paragraphs.length).floor();
      target = target.clamp(0, message.paragraphs.length - 1).toInt();
    }
    await messageLang.set(other.lang);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => ReaderScreen(
        message: message,
        initialParagraph: target,
        flashParagraph: target != null,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Saves this message as a PDF, with its highlights, bold and underline.
  Future<void> _savePdf() async {
    final m = widget.message;
    final blocks = <PdfBlock>[];
    final heading = m.heading.isEmpty ? [HeadingLine(true, m.title)] : m.heading;
    for (var i = 0; i < heading.length; i++) {
      final h = heading[i];
      blocks.add(PdfBlock(
        TextSpan(text: h.isTitle ? _spaced(h.text) : h.text, style: h.isTitle ? PdfExport.title : PdfExport.info),
        align: TextAlign.center,
        spaceAfter: h.isTitle ? 6 : 2,
        lineBelow: i == heading.length - 1,
      ));
    }
    for (var i = 0; i < m.paragraphs.length; i++) {
      blocks.add(PdfBlock(TextSpan(
        style: PdfExport.body,
        children: markedSpans(m.paragraphs[i], _highlights.where((h) => h.paragraph == i),
            chosenColor: Colors.transparent),
      )));
    }
    await PdfExport.saveWithMessages(
      context,
      fileName: PdfExport.fileName('${m.code} ${m.title}'),
      blocks: blocks,
    );
  }

  Future<void> _openSearch() async {
    final info = MessageInfo(
      code: widget.message.code,
      title: widget.message.title,
      file: '${widget.message.code}.json',
      lang: widget.message.lang,
    );
    final result = await Navigator.of(context).push<JumpTo>(
      MaterialPageRoute(builder: (_) => SearchScreen(current: info)),
    );
    if (result != null && mounted) _applySearch(result.query, jumpTo: result.paragraph);
  }

  // ---------------- font size & highlights ----------------

  void _setFont(double size, {bool save = true}) {
    setState(() => _fontSize = size.clamp(_minFont, _maxFont).toDouble());
    if (save) _store.saveFontSize(_fontSize);
  }

  /// Colours the text, or turns bold / underline on (or off if the words already have it).
  /// The same is done at the matching place in the other language.
  void _mark(int paragraph, int s, int e, MarkStyle style, [HighlightColor color = HighlightColor.yellow]) {
    if (e <= s) return;
    var on = false;
    setState(() {
      on = applyMark(_highlights, widget.message.paragraphs, paragraph, s, e, style, color);
    });
    _store.saveHighlights(widget.message.storageId, _highlights);
    _notifyLink();
    _mirror(paragraph, s, e, (list, paras, p, s2, e2) {
      applyMark(list, paras, p, s2, e2, style, color, add: on);
    });
  }

  /// Removes every colour, bold and underline from these words (in both languages).
  void _unmark(int paragraph, int s, int e) {
    setState(() => _highlights.removeWhere((h) => h.overlaps(paragraph, s, e)));
    _store.saveHighlights(widget.message.storageId, _highlights);
    _notifyLink();
    _mirror(paragraph, s, e, (list, paras, p, s2, e2) {
      list.removeWhere((h) => h.overlaps(p, s2, e2));
    });
  }

  /// Runs [op] on the matching place in the other language, then saves it.
  void _mirror(int p, int s, int e,
      void Function(List<Highlight> list, List<String> paras, int p, int s, int e) op) {
    final om = _otherMessage;
    final list = _otherHighlights;
    if (om == null || list == null) return;
    final fromTamil = widget.message.lang != 'en';
    final align = fromTamil ? widget.message.align : om.align;
    if (align == null) return;
    final places = mirrorRange(
      fromTamil: fromTamil,
      align: align,
      from: widget.message.paragraphs,
      to: om.paragraphs,
      p: p,
      s: s,
      e: e,
    );
    if (places.isEmpty) return;
    for (final r in places) {
      op(list, om.paragraphs, r.$1, r.$2, r.$3);
    }
    _store.saveHighlights(om.storageId, list).then((_) => widget.link?.marksChanged(widget.message.lang));
  }

  // ---------------- tap to choose a line ----------------

  /// The line around [offset] (see clauseAt in mark_mirror.dart).
  static (int, int)? clauseAt(String text, int offset) => clauseAtOffset(text, offset);

  void _onTapText(int paragraph, int offset) {
    final cur = _sel;
    final inside = _selIn(paragraph);
    if (inside != null && offset >= inside.$1 && offset < inside.$2) {
      setState(() => _sel = null); // tap the chosen lines again to close
      return;
    }
    final c = clauseAt(widget.message.paragraphs[paragraph], offset);
    if (c == null) return;
    if (cur == null) {
      setState(() => _sel = (p1: paragraph, s1: c.$1, p2: paragraph, e2: c.$2));
      return;
    }
    // A second tap stretches the selection to include everything in between.
    final before = paragraph < cur.p1 || (paragraph == cur.p1 && c.$1 < cur.s1);
    final after = paragraph > cur.p2 || (paragraph == cur.p2 && c.$2 > cur.e2);
    setState(() => _sel = (
          p1: before ? paragraph : cur.p1,
          s1: before ? c.$1 : cur.s1,
          p2: after ? paragraph : cur.p2,
          e2: after ? c.$2 : cur.e2,
        ));
  }

  /// Paragraph number for the reference: the number printed at the start of this
  /// paragraph (or the paragraph it belongs to), else its position.
  int _paraNumber(int p) {
    final paras = widget.message.paragraphs;
    for (var k = p; k >= 0; k--) {
      final m = RegExp(r'^(\d{1,3})[.\s]').firstMatch(paras[k]);
      if (m != null) return int.parse(m.group(1)!);
    }
    return p + 1;
  }

  /// 📝 Adds the chosen lines to the prepared note, with title and paragraph number.
  void _sendSelectionToNotes() {
    final sel = _sel;
    if (sel == null) return;
    final parts = <String>[];
    _forEachSelected((p, s, e) => parts.add(widget.message.paragraphs[p].substring(s, e).trim()));
    _sendToNotes(parts.join('\n'), sel.p1, sel.p2);
    setState(() => _sel = null);
  }

  void _sendToNotes(String quote, int p1, int p2) {
    final m = widget.message;
    final a = _paraNumber(p1), b = _paraNumber(p2);
    final para = a == b ? '¶$a' : '¶$a–$b';
    sendToNotes(context, quote, '${m.code} ${m.title}, $para');
  }

  void _applyToSelection(MarkStyle style, [HighlightColor color = HighlightColor.yellow]) {
    if (_sel == null) return;
    _forEachSelected((p, s, e) => _mark(p, s, e, style, color));
    setState(() => _sel = null);
  }

  /// The bar shown at the bottom after tapping a line.
  Widget _markBar(ThemeData theme) {
    Widget dot(HighlightColor c) => InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _applyToSelection(MarkStyle.color, c),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c.color,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outline),
              ),
            ),
          ),
        );
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final c in HighlightColor.values) dot(c),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Bold',
                  icon: const Icon(Icons.format_bold),
                  onPressed: () => _applyToSelection(MarkStyle.bold),
                ),
                IconButton(
                  tooltip: 'Underline',
                  icon: const Icon(Icons.format_underlined),
                  onPressed: () => _applyToSelection(MarkStyle.underline),
                ),
                IconButton(
                  tooltip: 'Send to notes',
                  icon: const Icon(Icons.note_add_outlined),
                  onPressed: _sendSelectionToNotes,
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    final parts = <String>[];
                    _forEachSelected((p, s, e) => parts.add(widget.message.paragraphs[p].substring(s, e)));
                    Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
                    setState(() => _sel = null);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Remove marks',
                  icon: const Icon(Icons.format_clear),
                  onPressed: () {
                    _forEachSelected(_unmark);
                    setState(() => _sel = null);
                  },
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _sel = null),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Splits a paragraph into runs: marks (colour / bold / underline), search matches,
  /// the line chosen by tapping, and plain text.
  List<TextSpan> _spansFor(int paragraph, String text) {
    final n = text.length;
    final colors = List<Color?>.filled(n, null);
    final bold = List<bool>.filled(n, false);
    final under = List<bool>.filled(n, false);
    for (final h in _highlights.where((h) => h.paragraph == paragraph)) {
      for (var k = math.max(0, h.start); k < math.min(n, h.end); k++) {
        switch (h.style) {
          case MarkStyle.color:
            colors[k] = h.color.color;
          case MarkStyle.bold:
            bold[k] = true;
          case MarkStyle.underline:
            under[k] = true;
        }
      }
    }
    if (_query.isNotEmpty) {
      for (final m in findMatches(text, _query)) {
        for (var k = m; k < math.min(n, m + _query.length); k++) {
          colors[k] = _searchColor;
        }
      }
    }
    final chosen = List<bool>.filled(n, false);
    final r = _selIn(paragraph);
    if (r != null) {
      for (var k = math.max(0, r.$1); k < math.min(n, r.$2); k++) {
        chosen[k] = true;
      }
    }
    final chosenColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);
    bool same(int a, int b) =>
        colors[a] == colors[b] && bold[a] == bold[b] && under[a] == under[b] && chosen[a] == chosen[b];

    final spans = <TextSpan>[];
    var runStart = 0;
    for (var k = 1; k <= n; k++) {
      if (k == n || !same(k, runStart)) {
        final c = colors[runStart];
        final plain = c == null && !bold[runStart] && !under[runStart] && !chosen[runStart];
        spans.add(TextSpan(
          text: text.substring(runStart, k),
          style: plain
              ? null
              : TextStyle(
                  backgroundColor: c ?? (chosen[runStart] ? chosenColor : null),
                  color: c != null ? Colors.black : null,
                  fontWeight: bold[runStart] ? FontWeight.w800 : null,
                  decoration: under[runStart] || chosen[runStart] ? TextDecoration.underline : null,
                  decorationStyle: chosen[runStart] && !under[runStart] ? TextDecorationStyle.dotted : null,
                  decorationThickness: under[runStart] ? 2 : null,
                ),
        ));
        runStart = k;
      }
    }
    return spans;
  }

  /// Title (bold) and date / code / place, all centred, above the message text.
  /// The title shrinks if needed so that no word is ever split across two lines.
  Widget _heading(Message m, Color textColor) {
    return LayoutBuilder(builder: (context, box) {
      final titleSize = _titleFontSize(
        m.heading.where((h) => h.isTitle).map((h) => _spaced(h.text)),
        box.maxWidth,
      );
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        child: Column(
          children: [
            for (final h in m.heading)
              Padding(
                padding: EdgeInsets.only(bottom: h.isTitle ? 6 : 2),
                child: SelectableText(
                  h.isTitle ? _spaced(h.text) : h.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: h.isTitle ? titleSize : _fontSize - 2,
                    fontWeight: h.isTitle ? FontWeight.w700 : FontWeight.normal,
                    height: 1.5,
                    color: h.isTitle ? textColor : textColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Divider(color: textColor.withValues(alpha: 0.2), indent: 40, endIndent: 40),
          ],
        ),
      );
    });
  }

  /// "word1,word2" -> "word1, word2" so a title can break after a comma.
  static String _spaced(String t) => t.replaceAllMapped(RegExp(r',(?=\S)'), (_) => ', ');

  /// Largest bold font size (up to text size + 6) at which the longest word of
  /// the title still fits on one line.
  double _titleFontSize(Iterable<String> lines, double maxWidth) {
    final words = lines.expand((l) => l.split(RegExp(r'\s+'))).where((w) => w.isNotEmpty);
    var size = _fontSize + 6;
    while (size > 12) {
      final fits = words.every((w) {
        final tp = TextPainter(
          text: TextSpan(text: w, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        return tp.width <= maxWidth - 4;
      });
      if (fits) break;
      size -= 1;
    }
    return size;
  }

  final Map<int, GlobalKey> _textKeys = {};

  /// Which character of paragraph [index] is under [local] (a point inside its text).
  int _offsetAt(int index, Offset local) {
    final box = _textKeys[index]?.currentContext?.findRenderObject();
    if (box is RenderParagraph) return box.getPositionForOffset(local).offset;
    return 0;
  }

  /// Long press / double tap: offer to send the chosen lines (or this line) to MyNotes.
  Future<void> _offerNotes(int index, Offset local, Offset global) async {
    final offset = _offsetAt(index, local);
    if (_sel == null || _selIn(index) == null) {
      final c = clauseAt(widget.message.paragraphs[index], offset);
      if (c == null) return;
      setState(() => _sel = (p1: index, s1: c.$1, p2: index, e2: c.$2));
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
    if (choice == 'notes') _sendSelectionToNotes();
  }

  Widget _paragraph(int index, String text, Color textColor) {
    final key = _textKeys.putIfAbsent(index, () => GlobalKey());
    return AnimatedContainer(
      key: _keys[index],
      duration: const Duration(milliseconds: 400),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _flash == index ? const Color(0x4087CEEB) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      // Tap = choose the line (tap more lines to stretch the choice).
      // Long press or double tap = send to MyNotes.
      child: Builder(builder: (context) {
        Offset? downLocal, downGlobal;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTapText(index, _offsetAt(index, d.localPosition)),
          onDoubleTapDown: (d) {
            downLocal = d.localPosition;
            downGlobal = d.globalPosition;
          },
          onDoubleTap: () {
            if (downLocal != null) _offerNotes(index, downLocal!, downGlobal!);
          },
          onLongPressStart: (d) => _offerNotes(index, d.localPosition, d.globalPosition),
          child: Text.rich(
            key: key,
            TextSpan(
              style: TextStyle(fontSize: _fontSize, height: 1.6, color: textColor),
              children: _spansFor(index, text),
            ),
          ),
        );
      }),
    );
  }

  // ---------------- pinch to zoom ----------------

  double _pinchDistance() {
    final p = _pointers.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  void _endPointer(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.length < 2 && _pinchStartDistance != null) {
      _pinchStartDistance = null;
      _store.saveFontSize(_fontSize);
    }
  }

  // ---------------- build ----------------

  Widget _searchBar(ThemeData theme) {
    final n = _matchParas.length;
    return Material(
      elevation: 6,
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.search, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n == 0 ? 'No matches' : '${_matchIndex + 1} / $n paragraphs',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(icon: const Icon(Icons.keyboard_arrow_up), onPressed: n == 0 ? null : () => _nextMatch(-1)),
              IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: n == 0 ? null : () => _nextMatch(1)),
              IconButton(icon: const Icon(Icons.close), onPressed: _clearSearch),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Message m, Color textColor) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Listener(
        onPointerDown: (e) {
          _pointers[e.pointer] = e.position;
          if (_pointers.length == 2) {
            _pinchStartDistance = _pinchDistance();
            _pinchStartFont = _fontSize;
          }
        },
        onPointerMove: (e) {
          _pointers[e.pointer] = e.position;
          final start = _pinchStartDistance;
          if (_pointers.length >= 2 && start != null && start > 0) {
            _setFont(_pinchStartFont * _pinchDistance() / start, save: false);
          }
        },
        onPointerUp: (e) => _endPointer(e.pointer),
        onPointerCancel: (e) => _endPointer(e.pointer),
        child: RawScrollbar(
          controller: _scroll,
          thumbVisibility: true,
          interactive: true, // drag the bar to move quickly through the message
          thickness: 8,
          minThumbLength: 56,
          radius: const Radius.circular(8),
          crossAxisMargin: 3,
          mainAxisMargin: 6,
          thumbColor: textColor.withValues(alpha: 0.35),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 24, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (m.heading.isNotEmpty) _heading(m, textColor),
                for (var i = 0; i < m.paragraphs.length; i++)
                  _paragraph(i, m.paragraphs[i], textColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    if (widget.embedded) {
      return Stack(
        children: [
          Positioned.fill(child: _body(m, textColor)),
          if (_sel != null) Positioned(left: 0, right: 0, bottom: 0, child: _markBar(theme)),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        // Tapping the title also goes back.
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.title, overflow: TextOverflow.ellipsis),
              Text(m.code, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
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
        bottom: _other == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: MessageLangSwitch(
                  value: m.lang,
                  showBoth: true,
                  onChanged: (v) => v == 'both' ? _openBoth() : _switchLanguage(),
                ),
              ),
      ),
      bottomNavigationBar: _sel != null
          ? _markBar(theme)
          : (_query.isEmpty ? null : _searchBar(theme)),
      body: MessageSwipe(
        onNext: () => _goNeighbour(1),
        onPrevious: () => _goNeighbour(-1),
        child: _body(m, textColor),
      ),
    );
  }
}
