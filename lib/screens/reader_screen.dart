import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/library.dart';
import '../data/reader_store.dart';
import '../models/highlight.dart';
import '../models/message.dart';
import '../theme/reading_theme.dart';
import 'search_screen.dart';

class ReaderScreen extends StatefulWidget {
  final Message message;
  final int? initialParagraph; // jump here when opened from search
  final String? searchQuery; // mark these words when opened from search

  const ReaderScreen({
    super.key,
    required this.message,
    this.initialParagraph,
    this.searchQuery,
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

  // Search-in-reader state
  String _query = ''; // normalized
  List<int> _matchParas = []; // paragraphs that contain the query
  int _matchIndex = 0;

  // Pinch-to-zoom tracking (two fingers change the font size).
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartFont = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final size = await _store.loadFontSize();
    var hls = await _store.loadHighlights(widget.message.code);
    // If the message was corrected since the highlights were made, put them back on their words.
    final fixed = Highlight.reanchor(hls, widget.message.paragraphs);
    if (fixed != null) {
      hls = fixed;
      await _store.saveHighlights(widget.message.code, hls);
    }
    if (!mounted) return;
    setState(() {
      _fontSize = size;
      _highlights = hls;
    });
    final q = widget.searchQuery;
    if (q != null && q.trim().isNotEmpty) {
      _applySearch(q, jumpTo: widget.initialParagraph);
    } else if (widget.initialParagraph != null) {
      _jumpToParagraph(widget.initialParagraph!);
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

  Future<void> _openSearch() async {
    final info = MessageInfo(code: widget.message.code, title: widget.message.title, file: '${widget.message.code}.json');
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

  void _addHighlight(int paragraph, TextSelection sel, HighlightColor color) {
    if (!sel.isValid || sel.isCollapsed) return;
    final s = math.min(sel.start, sel.end);
    final e = math.max(sel.start, sel.end);
    setState(() {
      _highlights.removeWhere((h) => h.overlaps(paragraph, s, e));
      _highlights.add(Highlight(
        paragraph: paragraph,
        start: s,
        end: e,
        color: color,
        text: widget.message.paragraphs[paragraph].substring(s, e),
      ));
    });
    _store.saveHighlights(widget.message.code, _highlights);
  }

  void _removeHighlight(int paragraph, TextSelection sel) {
    if (!sel.isValid) return;
    final s = math.min(sel.start, sel.end);
    final e = sel.isCollapsed ? s + 1 : math.max(sel.start, sel.end);
    setState(() => _highlights.removeWhere((h) => h.overlaps(paragraph, s, e)));
    _store.saveHighlights(widget.message.code, _highlights);
  }

  /// Splits a paragraph into runs: user highlights, search matches, plain text.
  List<TextSpan> _spansFor(int paragraph, String text) {
    final colors = List<Color?>.filled(text.length, null);
    for (final h in _highlights.where((h) => h.paragraph == paragraph)) {
      for (var k = math.max(0, h.start); k < math.min(text.length, h.end); k++) {
        colors[k] = h.color.color;
      }
    }
    if (_query.isNotEmpty) {
      for (final m in findMatches(text, _query)) {
        for (var k = m; k < math.min(text.length, m + _query.length); k++) {
          colors[k] = _searchColor;
        }
      }
    }
    final spans = <TextSpan>[];
    var runStart = 0;
    for (var k = 1; k <= text.length; k++) {
      if (k == text.length || colors[k] != colors[runStart]) {
        final c = colors[runStart];
        spans.add(TextSpan(
          text: text.substring(runStart, k),
          style: c == null ? null : TextStyle(backgroundColor: c, color: Colors.black),
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

  Widget _paragraph(int index, String text, Color textColor) {
    return Padding(
      key: _keys[index],
      padding: const EdgeInsets.only(bottom: 16),
      child: SelectableText.rich(
        TextSpan(
          style: TextStyle(fontSize: _fontSize, height: 1.6, color: textColor),
          children: _spansFor(index, text),
        ),
        contextMenuBuilder: (context, state) {
          final sel = state.textEditingValue.selection;
          void done() {
            state.hideToolbar();
            state.userUpdateTextEditingValue(
              state.textEditingValue.copyWith(selection: TextSelection.collapsed(offset: sel.end)),
              SelectionChangedCause.toolbar,
            );
          }

          final items = <ContextMenuButtonItem>[
            for (final c in HighlightColor.values)
              ContextMenuButtonItem(
                label: c.label,
                onPressed: () {
                  _addHighlight(index, sel, c);
                  done();
                },
              ),
            ContextMenuButtonItem(
              label: 'Remove',
              onPressed: () {
                _removeHighlight(index, sel);
                done();
              },
            ),
            ...state.contextMenuButtonItems, // Copy, Select all
          ];
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: items,
          );
        },
      ),
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

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.title, overflow: TextOverflow.ellipsis),
            Text(m.code, style: theme.textTheme.bodySmall),
          ],
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
          const ThemeButton(),
        ],
      ),
      bottomNavigationBar: _query.isEmpty ? null : _searchBar(theme),
      body: Listener(
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
}
