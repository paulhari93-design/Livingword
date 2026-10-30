import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/bookmarks.dart';
import '../data/news.dart';
import '../data/progress.dart';
import '../data/scripture.dart';
import '../services/share_quote.dart';
import '../services/volume_keys.dart';
import '../widgets/verse_sheet.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../data/library.dart';
import '../data/mark_mirror.dart';
import '../data/prefs.dart';
import '../data/reader_store.dart';
import '../data/reading_mode.dart';
import '../widgets/page_reader.dart';
import '../models/highlight.dart';
import '../services/pdf_export.dart';
import '../widgets/marking.dart';
import '../models/message.dart';
import '../theme/reading_theme.dart';
import '../theme/text_settings.dart';
import 'message_lang_switch.dart';
import 'notes_screen.dart';
import 'search_screen.dart';
import 'section_switch.dart';
import 'read_along.dart';
import 'split_app_screen.dart';
import 'split_reader_screen.dart';
import 'swipe.dart';
import '../data/profile.dart';
import '../widgets/more_menu.dart';
import '../l10n.dart';

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

class _ReaderScreenState extends State<ReaderScreen> with SingleTickerProviderStateMixin {
  static const double _minFont = 14;
  static const double _maxFont = 40;
  static const Color _searchColor = Color(0xFFFFB74D); // orange for search matches

  final _store = ReaderStore();
  final _scroll = ScrollController();
  // Page mode (⋮ → Advanced settings → Page mode): pages like Kindle.
  final _pages = GlobalKey<PageReaderState>();
  int _pageParagraph = 0; // first paragraph on the page shown
  int? _pageStart; // open page mode at this paragraph
  bool _pageBars = false; // page mode: title bar + pages shown (tap to show / hide)
  double _pageTopInset = 0; // the phone's status bar, kept so pages do not move
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

  // Full screen (like Kindle): the top bar slides away while reading.
  bool _immersive = false;
  double _barHeight = 0; // height of the top bar (incl. the phone's status bar), when shown

  void _setImmersive(bool on) {
    if (on == _immersive || widget.embedded) return;
    setState(() => _immersive = on);
    // Also hide the phone's status bar (not in the split view: the other half needs it).
    if (!appSplitOpen.value) {
      SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  /// Scrolling down hides the bars (full screen); scrolling up shows them.
  bool _onScrollForBars(ScrollNotification n) {
    if (n.depth == 0 && n is ScrollUpdateNotification && n.dragDetails != null) {
      final d = n.scrollDelta ?? 0;
      // Scrolling down goes full screen; scrolling up brings the title bar and Back again.
      if (d > 6 && n.metrics.pixels > 40) _setImmersive(true);
      if (d < -6) _setImmersive(false);
    }
    return _onScrollNotification(n);
  }

  /// A tap on blank space (margins, gaps between paragraphs): close the chosen lines,
  /// or hide / show the bars.
  void _onBlankTap() {
    if (_sel != null) {
      setState(() => _sel = null);
      return;
    }
    _setImmersive(!_immersive);
  }

  // Bible references in each paragraph (tap = show the verse).
  Map<int, List<ScriptureRef>> _refs = {};

  // How far the message is read (0..1), for the progress line and "min left".
  final _progress = ValueNotifier<double>(0);
  bool _counted = false; // already counted as read to the end in this opening
  late final int _words = widget.message.paragraphs
      .fold<int>(0, (n, p) => n + p.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length);

  // Search-in-reader state
  String _query = ''; // normalized
  List<int> _matchParas = []; // paragraphs that contain the query
  int _matchIndex = 0;

  // Pinch-to-zoom tracking (two fingers change the font size).
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartFont = 20;

  Timer? _saveTimer;
  int? _resumeToken;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
    HighlightEvents.instance.addListener(_onHighlightsDeleted);
    pageMode.addListener(_onPageModeChanged);
    _pageStart = widget.initialParagraph;
    // Page mode opens full screen, like Kindle (tap to show the title bar).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inPageMode) _setImmersive(true);
    });
    if (!widget.embedded) VolumeKeys.attach(_onVolumeKey);
    // ⋮ → History: this message was opened.
    ReadingProgress.instance.opened(widget.message.storageId, widget.message.lang, widget.message.code);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateProgress());
    // Opened = seen: take it out of ⋮ → Notifications.
    NewsStore.instance.markRead(widget.message.code, widget.message.lang);
    // Reopen here next time the app starts (not for the split view or its halves).
    if (!widget.embedded && !appSplitOpen.value) _resumeToken = ResumeTracker.opened('message');
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
    if ((widget.link == null && _half == null) || n.depth != 0) return false;
    if (n is UserScrollNotification) {
      _userScrolling = n.direction != ScrollDirection.idle;
    } else if (n is ScrollStartNotification && n.dragDetails != null) {
      _userScrolling = true;
    }
    if (n is ScrollUpdateNotification && _userScrolling && !_following) {
      final (p, f) = _topPosition();
      widget.link?.moved(widget.message.lang, p, f);
      final half = _half;
      if (half != null) ReadAlong.instance.moved(half, p, f);
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

  // Text settings for this part of the screen (a split-view half has its own).
  TextSettingsController? _ts;
  TextSettingsController get ts => _ts ?? textSettings;

  // Read along (split view): this reader's half, and how it is reached.
  int? _half;
  ReadAlongTarget? _readAlong;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final half = SplitHalf.of(context);
    if (half != null && _readAlong == null && !widget.embedded) {
      _half = half;
      _readAlong = ReadAlongTarget(
        kind: 'message',
        key: widget.message.code,
        message: widget.message,
        follow: (p, f) => _follow(p, f),
      );
      ReadAlong.instance.attach(half, _readAlong!);
    }
    final c = TextSettingsController.of(context);
    if (!identical(c, _ts)) {
      _ts?.removeListener(_textChanged);
      _ts = c;
      c.addListener(_textChanged);
      _fontSize = c.value.size;
    }
  }

  void _textChanged() {
    if (mounted) setState(() => _fontSize = ts.value.size);
  }

  /// Remembers the message and paragraph, so the Messages button in the Bible comes back here.
  void _remember([int? paragraph]) {
    final m = widget.message;
    final para = m.paragraphs.isEmpty ? null : m.paragraphs[(paragraph ?? 0).clamp(0, m.paragraphs.length - 1)];
    if (m.lang == 'en') {
      setReadingPreview(en: para);
    } else {
      setReadingPreview(ta: para);
    }
    Prefs.instance.set('last_message', '${m.lang}|${m.code}|${paragraph ?? 0}');
  }

  void _onScroll() {
    _updateProgress();
    _scheduleSave();
  }

  /// Remembers the place and the progress shortly after the reader stops moving.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && (_scroll.hasClients || _inPageMode)) {
        _remember(_hereParagraph());
        final m = widget.message;
        // Reaching the end counts once per opening (reading it again counts again).
        final finished = !_counted && _progress.value >= ReadingProgress.done;
        if (finished) _counted = true;
        ReadingProgress.instance.save(m.storageId, m.lang, m.code, _progress.value,
            paragraph: _hereParagraph(), finishedNow: finished);
      }
    });
  }

  /// A highlight of this message was deleted in ⋮ → Bookmarks & highlights.
  void _onHighlightsDeleted() {
    final id = HighlightEvents.instance.last;
    if (id == widget.message.storageId || id == _otherMessage?.storageId) _reloadMarks();
  }

  @override
  void dispose() {
    HighlightEvents.instance.removeListener(_onHighlightsDeleted);
    if (_immersive && !appSplitOpen.value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _saveTimer?.cancel();
    VolumeKeys.detach(_onVolumeKey);
    _progress.dispose();
    final token = _resumeToken;
    if (token != null) ResumeTracker.closed(token);
    _ts?.removeListener(_textChanged);
    final ra = _readAlong, half = _half;
    if (ra != null && half != null) ReadAlong.instance.detach(half, ra);
    if (widget.link != null) widget.link!.unregister(widget.message.lang);
    pageMode.removeListener(_onPageModeChanged);
    _thumbScroll?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final size = ts.value.size;
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
    _findScripture();
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

  Future<void> _findScripture() async {
    final finder = await ScriptureFinder.get();
    if (finder == null || !mounted) return;
    final found = <int, List<ScriptureRef>>{};
    final paras = widget.message.paragraphs;
    for (var i = 0; i < paras.length; i++) {
      final r = finder.find(paras[i]);
      if (r.isNotEmpty) found[i] = r;
    }
    if (mounted && found.isNotEmpty) setState(() => _refs = found);
  }

  // ---------------- reading progress / page mode ----------------

  void _updateProgress() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final max = pos.maxScrollExtent;
    _progress.value = max <= 0 ? 1 : (pos.pixels / max).clamp(0.0, 1.0);
  }

  String _progressText(double p) {
    final en = widget.message.lang == 'en';
    final perMinute = en ? 180 : 120; // average reading speed (words a minute)
    final left = ((_words * (1 - p)) / perMinute).ceil();
    final pct = (p * 100).round();
    if (p >= ReadingProgress.done) return en ? '$pct% · read' : '$pct% · வாசித்தாயிற்று';
    return en ? '$pct% · $left min left' : '$pct% · $left நிமிடம் மீதம்';
  }

  /// Turn the page: one screen forward / back (swipe left / right, or the volume keys).
  void _turnPage(int step) {
    if (_inPageMode) {
      _pages.currentState?.turn(step);
      return;
    }
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (step > 0 && pos.pixels >= pos.maxScrollExtent - 2) return;
    if (step < 0 && pos.pixels <= pos.minScrollExtent + 2) return;
    _setImmersive(true);
    final target = (pos.pixels + step * pos.viewportDimension * 0.92)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  /// Volume down = next page, volume up = previous page (only while this message is on top).
  bool _onVolumeKey(bool down) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    _turnPage(down ? 1 : -1);
    return true;
  }


  // ---------------- bookmark / share ----------------

  Future<void> _bookmarkSelection() async {
    final sel = _sel;
    if (sel == null) return;
    final m = widget.message;
    final text = m.paragraphs[sel.p1];
    final added = await BookmarkStore.instance.add(Bookmark(
      kind: 'message',
      lang: m.lang,
      code: m.code,
      place: sel.p1,
      title: '${m.code} ${m.title} ¶${_paraNumber(sel.p1)}',
      snippet: text.length > 140 ? '${text.substring(0, 140)}…' : text,
      at: DateTime.now(),
    ));
    if (!mounted) return;
    setState(() => _sel = null);
    final en = m.lang == 'en';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(BookmarkStore.message(added, en)),
      duration: Duration(seconds: added == BookmarkResult.full ? 4 : 1),
    ));
  }

  void _shareSelection() {
    final sel = _sel;
    if (sel == null) return;
    final m = widget.message;
    final parts = <String>[];
    _forEachSelected((p, s, e) => parts.add(m.paragraphs[p].substring(s, e).trim()));
    final a = _paraNumber(sel.p1), b = _paraNumber(sel.p2);
    ShareQuote.share(
      context,
      quote: parts.join(' '),
      source: '${m.code} ${m.title}, ¶${a == b ? a : '$a–$b'}',
      style: ts.value.style(context, m.lang, Colors.black),
    );
    setState(() => _sel = null);
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
      // Just below the top bar (which lies over the text while it is shown).
      final view = _scroll.hasClients ? _scroll.position.viewportDimension : 0.0;
      final under = !_immersive && view > 0 ? _barHeight / view : 0.0;
      Scrollable.ensureVisible(
        ctx,
        alignment: (0.06 + under).clamp(0.0, 0.6),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  /// The paragraph at the top of the screen right now.
  int _currentParagraph() {
    if (!_scroll.hasClients) return 0;
    final viewport = _scroll.position.context.storageContext.findRenderObject();
    if (viewport is! RenderBox) return 0;
    // (The top bar lies over the text while it is shown.)
    final top = viewport.localToGlobal(Offset.zero).dy + 8 + (_immersive || widget.embedded ? 0 : _barHeight);
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
      pageBuilder: (_, __, ___) => SplitReaderScreen(tamil: ta, english: en, initialTamilParagraph: p),
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
    ts.setSize(_fontSize, save: save);
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
    // A Bible reference: show the verse (unless lines are being chosen).
    if (_sel == null) {
      for (final r in _refs[paragraph] ?? const <ScriptureRef>[]) {
        if (offset >= r.start && offset < r.end) {
          showScripture(context, r, lang: widget.message.lang);
          return;
        }
      }
    }
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
                  tooltip: 'Send to notes',
                  icon: const Icon(Icons.note_add_outlined),
                  onPressed: _sendSelectionToNotes,
                ),
                IconButton(
                  tooltip: 'Bookmark',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: _bookmarkSelection,
                ),
                IconButton(
                  tooltip: 'Share as picture',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: _shareSelection,
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
  /// The words of a paragraph with their marks; [from] / [to]: only that part (page mode).
  List<TextSpan> _spansFor(int paragraph, String text, [int from = 0, int? to]) {
    final n = text.length;
    final stop = math.min(n, to ?? n);
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
    final link = List<bool>.filled(n, false);
    for (final r in _refs[paragraph] ?? const <ScriptureRef>[]) {
      for (var k = math.max(0, r.start); k < math.min(n, r.end); k++) {
        link[k] = true;
      }
    }
    final linkColor = Theme.of(context).colorScheme.primary;
    final chosenColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.25);
    bool same(int a, int b) =>
        colors[a] == colors[b] &&
        bold[a] == bold[b] &&
        under[a] == under[b] &&
        chosen[a] == chosen[b] &&
        link[a] == link[b];

    final spans = <TextSpan>[];
    var runStart = from;
    for (var k = from + 1; k <= stop; k++) {
      if (k == stop || !same(k, runStart)) {
        final c = colors[runStart];
        final isLink = link[runStart];
        final plain = c == null && !bold[runStart] && !under[runStart] && !chosen[runStart] && !isLink;
        spans.add(TextSpan(
          text: text.substring(runStart, k),
          style: plain
              ? null
              : TextStyle(
                  backgroundColor: c ?? (chosen[runStart] ? chosenColor : null),
                  color: c != null ? Colors.black : (isLink ? linkColor : null),
                  fontWeight: bold[runStart] ? FontWeight.w800 : null,
                  decoration: under[runStart] || chosen[runStart] || isLink ? TextDecoration.underline : null,
                  decorationColor: isLink && !under[runStart] && !chosen[runStart] ? linkColor : null,
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
                    fontFamily: ts.value.family(m.lang),
                    fontFamilyFallback: ts.value.fallback(m.lang),
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

  /// Is [local] on the words of paragraph [index] (not on the empty space beside them)?
  bool _onWords(int index, Offset local) {
    final box = _textKeys[index]?.currentContext?.findRenderObject();
    if (box is! RenderParagraph) return true;
    final len = widget.message.paragraphs[index].length;
    final boxes = box.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
    return boxes.any((b) => b.toRect().inflate(6).contains(local));
  }

  /// Which character of paragraph [index] is under [local] (a point inside its text).
  int _offsetAt(int index, Offset local) {
    final box = _textKeys[index]?.currentContext?.findRenderObject();
    if (box is RenderParagraph) return box.getPositionForOffset(local).offset;
    return 0;
  }

  /// Long press / double tap: offer to send the chosen lines (or this line) to MyNotes.
  Future<void> _offerNotes(int index, Offset local, Offset global) =>
      _offerNotesAt(index, _offsetAt(index, local), global);

  Future<void> _offerNotesAt(int index, int offset, Offset global) async {
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
            title: Tr('குறிப்பில் சேர் / Send to notes'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (choice == 'notes') _sendSelectionToNotes();
  }

  Widget _paragraph(int index, String text, Color textColor) {
    final key = _textKeys.putIfAbsent(index, () => GlobalKey());
    // Each paragraph is drawn once and then only moved while scrolling. Without this,
    // every paragraph of the whole message was drawn again for every frame of a
    // scroll, which made long Tamil messages (heavier letters to draw) blur and stutter.
    return RepaintBoundary(child: AnimatedContainer(
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
          // On the words: choose the line. On empty space (after a short line, etc.):
          // show / hide the title bar.
          onTapUp: (d) => _onWords(index, d.localPosition)
              ? _onTapText(index, _offsetAt(index, d.localPosition))
              : _onBlankTap(),
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
              style: ts.value.style(context, widget.message.lang, textColor, fontSize: _fontSize),
              children: _spansFor(index, text),
            ),
          ),
        );
      }),
    ));
  }

  // ---------------- pinch to zoom ----------------

  double _pinchDistance() {
    final p = _pointers.values.take(2).toList();
    return (p[0] - p[1]).distance;
  }

  bool _swipeMulti = false; // two fingers down (zooming)

  void _endPointer(int pointer) {
    _pointers.remove(pointer);
    if (_pointers.length < 2 && _pinchStartDistance != null) {
      _pinchStartDistance = null;
      ts.setSize(_fontSize);
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
      onNotification: _onScrollForBars,
      child: Listener(
        onPointerDown: (e) {
          _pointers[e.pointer] = e.position;
          if (_pointers.length == 1) _swipeMulti = false;
          if (_pointers.length == 2) {
            _swipeMulti = true;
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
        onPointerUp: (e) {
          _endPointer(e.pointer);
        },
        onPointerCancel: (e) {
          _endPointer(e.pointer);
        },
        // Tap on blank space: hide / show the bars (taps on text still choose lines).
        child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _onBlankTap,
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
            // Room at the top for the bar that lies over the text.
            padding: EdgeInsets.fromLTRB(20, 16 + (widget.embedded ? 0 : _barHeight), 24, 48),
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

    if (_inPageMode) return _buildPages(m, theme, textColor);

    final hasLangSwitch = !(_other == null || appProfile.englishOnly);
    // The top bar lies over the text, so it can slide away without moving the text.
    if (!_immersive) {
      _barHeight = MediaQuery.paddingOf(context).top + kToolbarHeight + (hasLangSwitch ? 52 : 0);
    }
    final bar = AppBar(
        // Tapping the title also goes back.
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.title, overflow: TextOverflow.ellipsis),
              // "65-1204 · 42% · 25 min left"
              ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (_, p, __) => Text('${m.code} · ${_progressText(p)}',
                    style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          const GoToBibleButton(),
          MoreMenu(
            lang: widget.message.lang,
            onPdf: _savePdf,
            // Opens this message (at this paragraph) in the top half; main menu below.
            splitTop: (_) {
              final here = _hereParagraph();
              return ReaderScreen(message: widget.message, initialParagraph: here > 0 ? here : null);
            },
          ),
        ],
        bottom: !hasLangSwitch
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: MessageLangSwitch(
                  value: m.lang,
                  onChanged: (_) => _switchLanguage(),
                ),
              ),
      );

    return Scaffold(
      bottomNavigationBar: _sel != null
          ? _markBar(theme)
          : (_query.isEmpty ? null : _searchBar(theme)),
      body: Stack(
          children: [
            Positioned.fill(child: _body(m, textColor)),
            // The top bar: slides up out of view in full screen.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              top: _immersive ? -_barHeight - 4 : 0,
              height: _barHeight,
              child: bar,
            ),
            // A thin line at the bottom: how far the message is read.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (_, p, __) => LinearProgressIndicator(
                  value: p,
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
    );
  }

  // ---------------- page mode (like Kindle) ----------------

  /// Page mode is on (not in the split view).
  bool get _inPageMode => pageMode.value.on && !widget.embedded && _half == null && !appSplitOpen.value;

  /// The paragraph the reader is at (top of the screen / first on the page).
  int _hereParagraph() {
    if (_inPageMode) return _pageParagraph;
    return _scroll.hasClients ? _currentParagraph() : (widget.initialParagraph ?? 0);
  }

  int _pageNo = 0, _pageCount = 0;
  ScrollController? _thumbScroll;
  List<PageBlock>? _blocks;
  String? _blocksKey;

  /// Page mode switched on / off (or its settings changed) in ⋮ → Advanced settings.
  void _onPageModeChanged() {
    if (!mounted) return;
    if (pageMode.value.on) {
      _pageStart = _scroll.hasClients ? _currentParagraph() : _pageParagraph;
      setState(() {});
      if (_inPageMode) _setImmersive(true);
    } else {
      final wasPages = _pageCount > 0;
      final p = _pageParagraph;
      setState(() => _pageCount = 0);
      if (wasPages) _jumpToParagraph(p); // scrolling again, at the same place
    }
  }

  /// The message as plain blocks of text (no highlights) for the pages.
  List<PageBlock> _pageBlocks(Message m, Color textColor) {
    // Bold words are wider, so the pages are laid out again when bold marks change.
    final boldMarks = Object.hashAll(_highlights
        .where((h) => h.style == MarkStyle.bold)
        .map((h) => Object.hash(h.paragraph, h.start, h.end)));
    final key = '${m.storageId}|$_fontSize|${textColor.toARGB32()}|${ts.value.family(m.lang)}|$boldMarks';
    if (key == _blocksKey && _blocks != null) return _blocks!;
    final body = ts.value.style(context, m.lang, textColor, fontSize: _fontSize);
    final blocks = <PageBlock>[];
    for (var i = 0; i < m.heading.length; i++) {
      final h = m.heading[i];
      final last = i == m.heading.length - 1;
      blocks.add(PageBlock(
        h.isTitle ? _spaced(h.text) : h.text,
        body.copyWith(
          fontSize: h.isTitle ? _fontSize + 4 : _fontSize - 2,
          fontWeight: h.isTitle ? FontWeight.w700 : FontWeight.normal,
          height: 1.5,
          color: h.isTitle ? body.color : body.color?.withValues(alpha: 0.8),
        ),
        align: TextAlign.center,
        spaceAfter: last ? 28 : (h.isTitle ? 6 : 2),
      ));
    }
    for (var i = 0; i < m.paragraphs.length; i++) {
      final text = m.paragraphs[i];
      blocks.add(PageBlock(text, body, paragraph: i, spans: (s, e) => _spansFor(i, text, s, e)));
    }
    _blocksKey = key;
    return _blocks = blocks;
  }

  bool _pagePanelOpen = false; // the title bar and the list of pages are shown

  /// Tap on the page (not on the words): show the title bar and the list of pages;
  /// tap again: full screen. (With lines chosen, a tap closes the choice first.)
  void _onPageTap() {
    if (_sel != null) {
      setState(() => _sel = null);
      return;
    }
    if (_pagePanelOpen || !_immersive) {
      setState(() => _pagePanelOpen = false);
      _setImmersive(true);
      return;
    }
    final st = _pages.currentState;
    final size = st?.pageSize ?? Size.zero;
    final w = size.height > 0 ? _thumbHeight * size.width / size.height + 12 : 80.0;
    _thumbScroll?.dispose();
    _thumbScroll = ScrollController(
      initialScrollOffset: (w * _pageNo - MediaQuery.sizeOf(context).width / 2 + w / 2).clamp(0, double.infinity),
    );
    setState(() => _pagePanelOpen = true);
    _setImmersive(false);
  }

  /// Part of a paragraph on a page: tap the words to choose lines (then highlight, bold,
  /// note, ...), tap a Bible reference to read it, long press to send to MyNotes.
  Widget _pagePiece(PageBlock b, int start, int end) {
    final i = b.paragraph;
    BuildContext? textContext;
    RenderParagraph? paragraph() {
      RenderObject? r = textContext?.findRenderObject();
      while (r != null && r is! RenderParagraph) {
        RenderObject? child;
        r.visitChildren((c) => child ??= c);
        r = child;
      }
      return r as RenderParagraph?;
    }

    int? offsetAt(Offset local, {bool onWordsOnly = false}) {
      final r = paragraph();
      if (r == null) return null;
      if (onWordsOnly) {
        final boxes = r.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: end - start));
        if (!boxes.any((x) => x.toRect().inflate(6).contains(local))) return null;
      }
      return start + r.getPositionForOffset(local).offset;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final o = offsetAt(d.localPosition, onWordsOnly: true);
        if (o == null) {
          _onPageTap();
        } else {
          if (_pagePanelOpen) setState(() => _pagePanelOpen = false);
          _onTapText(i, o);
        }
      },
      onLongPressStart: (d) {
        final o = offsetAt(d.localPosition);
        if (o != null) _offerNotesAt(i, o, d.globalPosition);
      },
      child: Builder(builder: (c) {
        textContext = c;
        return pageText(c, b.span(start, end), b.align);
      }),
    );
  }

  static const double _thumbHeight = 128;

  /// Kindle-like panel at the bottom: every page small (tap one to go there) and a slider.
  Widget _pagePanel(ThemeData theme) {
    final st = _pages.currentState;
    final count = _pageCount;
    if (st == null || count == 0) return const SizedBox.shrink();
    final size = st.pageSize;
    final thumbW = size.height > 0 ? _thumbHeight * size.width / size.height : 70.0;
    final en = widget.message.lang == 'en' || appProfile.englishOnly;
    final label = en ? 'Page ${_pageNo + 1} of $count' : 'பக்கம் ${_pageNo + 1} / $count';
    return Material(
      color: theme.colorScheme.surfaceContainer,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _thumbHeight + 20,
              child: ListView.builder(
                controller: _thumbScroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                itemCount: count,
                itemExtent: thumbW + 12,
                itemBuilder: (_, i) {
                  final here = i == _pageNo;
                  return GestureDetector(
                    onTap: () => st.goTo(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: here ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                            width: here ? 2.5 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: size.width,
                              height: size.height,
                              child: IgnorePointer(child: st.buildPage(i, plain: true)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Expanded(
                    child: count < 2
                        ? const SizedBox(height: 48)
                        : Slider(
                            value: _pageNo.toDouble().clamp(0, count - 1),
                            min: 0,
                            max: (count - 1).toDouble(),
                            onChanged: (v) => st.goTo(v.round()),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPages(Message m, ThemeData theme, Color textColor) {
    final settings = pageMode.value;
    final inset = MediaQuery.viewPaddingOf(context).top;
    if (inset > _pageTopInset) _pageTopInset = inset; // (kept, so the pages never move)
    final barHeight = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final showBars = !_immersive;
    final en = m.lang == 'en' || appProfile.englishOnly;
    final bar = AppBar(
      title: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.title, overflow: TextOverflow.ellipsis),
            ValueListenableBuilder<double>(
              valueListenable: _progress,
              builder: (_, p, __) => Text('${m.code} · ${_progressText(p)}',
                  style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      actions: [
        MoreMenu(
          lang: m.lang,
          onPdf: _savePdf,
          splitTop: (_) {
            final here = _hereParagraph();
            return ReaderScreen(message: m, initialParagraph: here > 0 ? here : null);
          },
        ),
      ],
    );
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: PageReader(
              key: _pages,
              blocks: _pageBlocks(m, textColor),
              padding: EdgeInsets.fromLTRB(24, _pageTopInset + 20, 24, 40),
              initialParagraph: _pageStart,
              sideways: settings.sideways,
              animate: settings.animate,
              onTap: _onPageTap,
              pieceBuilder: _pagePiece,
              background: theme.scaffoldBackgroundColor,
              onPage: (page, count, paragraph, fraction) {
                _pageParagraph = paragraph;
                _progress.value = fraction;
                _scheduleSave();
                if (mounted && (page != _pageNo || count != _pageCount)) {
                  setState(() {
                    _pageNo = page;
                    _pageCount = count;
                  });
                }
              },
            ),
          ),
          // Page number at the bottom (like Kindle).
          if (!showBars && _pageCount > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: IgnorePointer(
                child: Text(
                  en ? 'Page ${_pageNo + 1} of $_pageCount' : 'பக்கம் ${_pageNo + 1} / $_pageCount',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: textColor.withValues(alpha: 0.55)),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            top: showBars ? 0 : -barHeight - 4,
            height: barHeight,
            child: bar,
          ),
          // Chosen lines: highlight, bold, underline, notes, bookmark, share (as in scrolling).
          if (_sel != null)
            Positioned(left: 0, right: 0, bottom: 0, child: _markBar(theme))
          else if (showBars && _pagePanelOpen)
            Positioned(left: 0, right: 0, bottom: 0, child: _pagePanel(theme)),
        ],
      ),
    );
  }
}
