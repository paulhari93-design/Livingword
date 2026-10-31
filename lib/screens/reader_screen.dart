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
import '../widgets/reading_panel.dart';
import 'marks_screen.dart';
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
    BookmarkStore.instance.addListener(_loadPageBookmarks);
    _loadPageBookmarks();
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
    // The handles and toolbar of chosen words move with the text.
    if (_sel != null && !widget.embedded) setState(() {});
    // Keep the place up to date (a few times a second), so it can be saved even when
    // the message is closed straight after scrolling.
    final now = DateTime.now();
    if (now.difference(_lastPlaceAt).inMilliseconds > 250) {
      _lastPlaceAt = now;
      _lastPlace = _currentParagraph();
    }
    _scheduleSave();
  }

  DateTime _lastPlaceAt = DateTime(2000);
  int? _lastPlace; // the paragraph at the top, as last seen while scrolling

  /// Remembers the place and the progress shortly after the reader stops moving.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _saveNow();
    });
  }

  /// Remembers the place and the progress now.
  void _saveNow({bool closing = false}) {
    try {
      if (_scroll.hasClients || _inPageMode) {
        // (When closing, the text may already be off the screen: use the last place seen.)
        final here = closing && !_inPageMode ? (_lastPlace ?? _hereParagraph()) : _hereParagraph();
        _remember(here);
        final m = widget.message;
        // Reaching the end counts once per opening (reading it again counts again).
        final finished = !_counted && _progress.value >= ReadingProgress.done;
        if (finished) _counted = true;
        ReadingProgress.instance.save(m.storageId, m.lang, m.code, _progress.value,
            paragraph: here, finishedNow: finished);
      }
    } catch (_) {
      // (Closing: the screen may already be gone; nothing to save then.)
    }
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
    // Leaving quickly: save the place now (the timed save would be cancelled).
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveNow(closing: true);
    }
    VolumeKeys.detach(_onVolumeKey);
    _progress.dispose();
    final token = _resumeToken;
    if (token != null) ResumeTracker.closed(token);
    _ts?.removeListener(_textChanged);
    final ra = _readAlong, half = _half;
    if (ra != null && half != null) ReadAlong.instance.detach(half, ra);
    if (widget.link != null) widget.link!.unregister(widget.message.lang);
    pageMode.removeListener(_onPageModeChanged);
    BookmarkStore.instance.removeListener(_loadPageBookmarks);
    _thumbScroll?.dispose();
    _flipView?.dispose();
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
    // Opened from the list (no place given): carry on where the reader left off,
    // unless it was read to the end (then it starts again from the beginning).
    var start = widget.initialParagraph;
    final searching = (widget.searchQuery ?? '').trim().isNotEmpty;
    if (start == null && !searching) {
      await ReadingProgress.instance.load();
      final id = widget.message.storageId;
      final p = ReadingProgress.instance.paragraphOf(id);
      if (p != null && p > 0 && ReadingProgress.instance.of(id) < ReadingProgress.done) start = p;
    }
    _remember(start);
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
    } else if (start != null) {
      _jumpToParagraph(start);
      // Page mode: the pages may already be laid out; go to the page of that paragraph.
      _pageStart = start;
      _pageParagraph = start;
      _pages.currentState?.goToParagraph(start);
      if (widget.flashParagraph && widget.initialParagraph != null) {
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
    // Page mode: go to the page where that paragraph starts.
    if (_inPageMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pages.currentState?.goToParagraph(index));
      return;
    }
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
    final here = _inPageMode
        ? (_pageParagraph > 0 ? _pageParagraph : null)
        : (_scroll.hasClients && _scroll.offset > 20 ? _currentParagraph() : null);
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
                for (final c in HighlightColor.offered) dot(c),
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // On the words: choose the line. On empty space (after a short line, etc.):
          // show / hide the title bar.
          // A tap anywhere (words too) shows / hides the bars, as in page mode. Only a
          // Bible reference opens its verse. Long press chooses the line (mark bar).
          onTapUp: (d) {
            if (_sel == null && _onWords(index, d.localPosition)) {
              final o = _offsetAt(index, d.localPosition);
              for (final r in _refs[index] ?? const <ScriptureRef>[]) {
                if (o >= r.start && o < r.end) {
                  showScripture(context, r, lang: widget.message.lang);
                  return;
                }
              }
              // A tap on a highlight chooses it (to delete it or change its colour).
              if (_chooseMarkAt(index, o)) return;
            }
            _onBlankTap();
          },
          // Long press: choose words with the magnifier, as in page mode.
          onLongPressStart: (d) => _selectStart(d.globalPosition),
          onLongPressMoveUpdate: (d) => _selectMove(d.globalPosition),
          onLongPressEnd: (d) => _selectEnd(),
          child: Text.rich(
            key: key,
            TextSpan(
              style: ts.value.style(context, widget.message.lang, textColor, fontSize: _fontSize),
              children: _spansFor(index, text),
            ),
            textAlign: ts.value.align,
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

    // The top bar lies over the text, so it can slide away without moving the text.
    final (bar, barH) = _topBar(m, theme);
    if (!_immersive) _barHeight = barH;

    return Scaffold(
      // (Chosen words get the toolbar above them, as in page mode.)
      bottomNavigationBar: _sel == null && _query.isNotEmpty ? _searchBar(theme) : null,
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
            // Chosen words (long press): handles, magnifier and the toolbar above them.
            ..._selectionLayers(theme),
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
    final key = '${m.storageId}|$_fontSize|${textColor.toARGB32()}|${ts.value.family(m.lang)}|'
        '${ts.value.lineHeight}|${ts.value.justify}|$boldMarks';
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
      blocks.add(PageBlock(text, body,
          paragraph: i, align: ts.value.align, spans: (s, e) => _spansFor(i, text, s, e)));
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
      _closePageView();
      return;
    }
    _openPageView();
  }

  // Kindle's page view: the page shrinks, its neighbours show beside it.
  PageController? _flipView;
  int _flipPage = 0;

  int _flipStart = 0; // the page that was open when the page view opened
  int? _backPage; // "Back to …": the page read before jumping to another one

  void _openPageView() {
    _flipView?.dispose();
    _flipPage = _pageNo;
    _flipStart = _pageNo;
    _flipView = PageController(initialPage: _pageNo, viewportFraction: 0.68);
    setState(() => _pagePanelOpen = true);
    _setImmersive(false);
  }

  /// Back to full-screen reading, on [page] (or the page that was open).
  void _closePageView({int? page}) {
    if (page != null && page != _pageNo) {
      _backPage = _pageNo; // remember where the reading was, for "Back to …"
      _pages.currentState?.goTo(page);
    }
    setState(() => _pagePanelOpen = false);
    _setImmersive(true);
  }

  static const _ribbon = Color(0xFF1E6FD9); // Kindle's blue bookmark ribbon

  /// The small "Back to …" card: a picture of that page; tap to go back to it.
  Widget _backCard(ThemeData theme, PageReaderState st, int page, Size size) {
    final en = widget.message.lang == 'en' || appProfile.englishOnly;
    const w = 74.0;
    final h = size.height > 0 ? w * size.height / size.width : 120.0;
    return GestureDetector(
      onTap: () {
        if (page == _flipStart && _flipPage != _flipStart) {
          // Still choosing: show that page in the row again.
          _flipView?.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        } else {
          _backPage = null;
          _closePageView(page: page);
        }
      },
      child: Container(
        width: w,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border.all(color: theme.colorScheme.onSurface, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 8)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: w,
              height: h * 0.62,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: IgnorePointer(child: st.buildPage(page, plain: true)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(
                en ? 'Back to ${page + 1}' : 'பக்கம் ${page + 1}-க்கு',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- bookmarking a page (the ribbon) ----

  Set<int> _bookmarkedParas = {}; // paragraphs of this message that have a bookmark

  Future<void> _loadPageBookmarks() async {
    final m = widget.message;
    final all = await BookmarkStore.instance.all();
    final set = {
      for (final b in all)
        if (b.kind == 'message' && b.lang == m.lang && b.code == m.code) b.place,
    };
    if (mounted) setState(() => _bookmarkedParas = set);
  }

  bool _pageBookmarked(int page) {
    final st = _pages.currentState;
    if (st == null) return false;
    return _bookmarkedParas.any((p) => st.pageOfParagraph(p) == page);
  }

  /// The ribbon / bookmark button: bookmarks this page, or takes the bookmark off.
  Future<void> _togglePageBookmark(int page) async {
    final st = _pages.currentState;
    if (st == null) return;
    final m = widget.message;
    final on = _bookmarkedParas.where((p) => st.pageOfParagraph(p) == page).toList();
    if (on.isNotEmpty) {
      for (final p in on) {
        await BookmarkStore.instance.remove('message|${m.lang}|${m.code}|$p|0');
      }
      return;
    }
    final p = st.firstParagraphOf(page);
    final text = m.paragraphs[p];
    final r = await BookmarkStore.instance.add(Bookmark(
      kind: 'message',
      lang: m.lang,
      code: m.code,
      place: p,
      title: '${m.code} ${m.title} ¶${_paraNumber(p)}',
      snippet: text.length > 140 ? '${text.substring(0, 140)}…' : text,
      at: DateTime.now(),
    ));
    if (r == BookmarkResult.full && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(BookmarkStore.message(r, m.lang == 'en')),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Widget _pageView(ThemeData theme, double barHeight) {
    final st = _pages.currentState;
    final ctrl = _flipView;
    if (st == null || ctrl == null || _pageCount == 0) return const SizedBox.shrink();
    final size = st.pageSize;
    final en = widget.message.lang == 'en' || appProfile.englishOnly;
    final count = _pageCount;
    final label = en ? 'Page ${_flipPage + 1} of $count' : 'பக்கம் ${_flipPage + 1} / $count';
    // Moved away in this view: back to where it opened; else the page read before a jump.
    final int? back = _flipPage != _flipStart
        ? _flipStart
        : (_backPage != null && _backPage != _pageNo && _backPage! < count ? _backPage : null);
    final dark = theme.brightness == Brightness.dark;
    final around = Color.lerp(theme.scaffoldBackgroundColor, dark ? Colors.white : Colors.black, 0.10)!;
    return GestureDetector(
      // Tap beside the pages: back to the page that was open.
      onTap: _closePageView,
      child: Container(
        color: around,
        child: Column(
          children: [
            SizedBox(height: barHeight),
            Expanded(
              child: Stack(
                children: [
                  // Opening: the page shrinks from full size into the row of pages.
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Transform.scale(scale: 1.45 - 0.45 * t, child: child),
                child: PageView.builder(
                  controller: ctrl,
                  itemCount: count,
                  onPageChanged: (i) => setState(() => _flipPage = i),
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: size.height > 0 ? size.width / size.height : 0.5,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                          onTap: () => _closePageView(page: i), // open this page
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(6),
                              border: i == _pageNo
                                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                                  : null,
                              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10)],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
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
                            ),
                            // The bookmark ribbon (like Kindle): tap to bookmark this page.
                            Positioned(
                              top: 0,
                              right: 8,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _togglePageBookmark(i),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(10, 0, 4, 10),
                                  child: Icon(
                                    _pageBookmarked(i) ? Icons.bookmark : Icons.bookmark_border,
                                    size: 30,
                                    color: _pageBookmarked(i) ? _ribbon : theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
                  ),
                  // "Back to …": the page you came from (like Kindle).
                  if (back != null)
                    Positioned(left: 12, bottom: 10, child: _backCard(theme, st, back, size)),
                ],
              ),
            ),
            Material(
              color: theme.scaffoldBackgroundColor,
              elevation: 6,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                  child: Row(
                    children: [
                      Text(label, style: theme.textTheme.bodySmall),
                      Expanded(
                        child: count < 2
                            ? const SizedBox(height: 48)
                            : Slider(
                                value: _flipPage.toDouble().clamp(0, count - 1),
                                min: 0,
                                max: (count - 1).toDouble(),
                                onChanged: (v) {
                                  setState(() => _flipPage = v.round());
                                  ctrl.jumpToPage(v.round());
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      // One tap anywhere (words too) shows the bars and the page view, like Kindle.
      // Only a tap on a Bible reference opens the verse; words are chosen by long press.
      onTapUp: (d) {
        final o = offsetAt(d.localPosition, onWordsOnly: true);
        if (o != null && _sel == null) {
          for (final r in _refs[i] ?? const <ScriptureRef>[]) {
            if (o >= r.start && o < r.end) {
              showScripture(context, r, lang: widget.message.lang);
              return;
            }
          }
          // A tap on a highlight chooses it (to delete it or change its colour).
          if (_chooseMarkAt(i, o)) return;
        }
        _onPageTap();
      },
      // Long press: choose words with the magnifier (drag to choose more).
      onLongPressStart: (d) => _selectStart(d.globalPosition),
      onLongPressMoveUpdate: (d) => _selectMove(d.globalPosition),
      onLongPressEnd: (d) => _selectEnd(),
      child: Builder(builder: (c) {
        textContext = c;
        _pieceCtx['$i:$start:$end'] = c;
        return pageText(c, b.span(start, end), b.align);
      }),
    );
  }

  // ---------------- page mode: choosing words (like Kindle) ----------------

  /// Where each part of a paragraph is drawn ("paragraph:start:end" → its context).
  final Map<String, BuildContext> _pieceCtx = {};
  Offset? _magnifierAt; // finger position while choosing (shows the magnifier)
  (int, int, int)? _anchor; // the first word chosen: (paragraph, start, end)
  bool _toolbarColours = false; // the toolbar shows the highlight colours

  static RenderParagraph? _paragraphOf(BuildContext c) {
    if (!c.mounted) return null;
    RenderObject? r = c.findRenderObject();
    while (r != null && r is! RenderParagraph) {
      RenderObject? child;
      r.visitChildren((x) => child ??= x);
      r = child;
    }
    final p = r as RenderParagraph?;
    return p != null && p.attached && p.hasSize ? p : null;
  }

  /// The parts of paragraphs on the page shown now, with their drawn text.
  List<(int, int, int, RenderParagraph)> _visibleText() {
    final out = <(int, int, int, RenderParagraph)>[];
    if (!_inPageMode) {
      // Scrolling: the whole paragraphs that are on the screen now.
      final h = MediaQuery.sizeOf(context).height;
      for (final e in _textKeys.entries) {
        final r = e.value.currentContext?.findRenderObject();
        if (r is! RenderParagraph || !r.attached || !r.hasSize) continue;
        final top = r.localToGlobal(Offset.zero).dy;
        if (top > h || top + r.size.height < 0) continue;
        out.add((e.key, 0, widget.message.paragraphs[e.key].length, r));
      }
      return out;
    }
    for (final (p, s, e) in _pages.currentState?.visiblePieces ?? const <(int, int, int)>[]) {
      final c = _pieceCtx['$p:$s:$e'];
      final r = c == null ? null : _paragraphOf(c);
      if (r != null) out.add((p, s, e, r));
    }
    return out;
  }

  /// The word nearest to [global] on the page: (paragraph, start, end).
  (int, int, int)? _wordAt(Offset global) {
    (int, int, int)? best;
    var bestD = double.infinity;
    for (final (p, s, e, r) in _visibleText()) {
      final rect = r.localToGlobal(Offset.zero) & r.size;
      if (rect.width < 3 || rect.height < 3) continue;
      final dx = global.dx < rect.left ? rect.left - global.dx : (global.dx > rect.right ? global.dx - rect.right : 0.0);
      final dy = global.dy < rect.top ? rect.top - global.dy : (global.dy > rect.bottom ? global.dy - rect.bottom : 0.0);
      final d = dx + dy * 3;
      if (d >= bestD) continue;
      final inside = Offset(global.dx.clamp(rect.left + 1, rect.right - 1), global.dy.clamp(rect.top + 1, rect.bottom - 1));
      final pos = r.getPositionForOffset(r.globalToLocal(inside));
      final w = r.getWordBoundary(pos);
      var ws = w.start, we = w.end;
      // Not just a space: take the word next to it.
      final text = widget.message.paragraphs[p];
      while (we > ws && text[s + we - 1].trim().isEmpty) {
        we--;
      }
      if (we <= ws) {
        ws = pos.offset.clamp(0, e - s).toInt();
        we = (ws + 1).clamp(0, e - s).toInt();
      }
      bestD = d;
      best = (p, s + ws, s + we);
    }
    return best;
  }

  void _selectStart(Offset global) {
    final w = _wordAt(global);
    if (w == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _anchor = w;
      _toolbarColours = false;
      _magnifierAt = global;
      _sel = (p1: w.$1, s1: w.$2, p2: w.$1, e2: w.$3);
    });
  }

  void _selectMove(Offset global) {
    final a = _anchor;
    final w = _wordAt(global);
    if (a == null || w == null) return;
    final before = w.$1 < a.$1 || (w.$1 == a.$1 && w.$2 < a.$2);
    setState(() {
      _magnifierAt = global;
      _sel = before ? (p1: w.$1, s1: w.$2, p2: a.$1, e2: a.$3) : (p1: a.$1, s1: a.$2, p2: w.$1, e2: w.$3);
    });
  }

  void _selectEnd() => setState(() => _magnifierAt = null);

  /// Tapped on a highlight (or bold / underline): choose all of it. True if there was one.
  bool _chooseMarkAt(int p, int o) {
    for (final h in _highlights) {
      if (h.paragraph == p && o >= h.start && o < h.end) {
        HapticFeedback.selectionClick();
        setState(() {
          _toolbarColours = false;
          _sel = (p1: p, s1: h.start, p2: p, e2: h.end);
        });
        return true;
      }
    }
    return false;
  }

  /// Whether any of the chosen words already have a mark.
  bool _selectionHasMarks() {
    var found = false;
    _forEachSelected((p, s, e) {
      if (_highlights.any((h) => h.overlaps(p, s, e))) found = true;
    });
    return found;
  }

  /// Where the caret for character [offset] of paragraph [p] is on the screen:
  /// (top of the line, line height), or null when it is not on this page.
  (Offset, double)? _caret(int p, int offset, {bool atEnd = false}) {
    for (final (pp, s, e, r) in _visibleText()) {
      if (pp != p || offset < s || offset > e) continue;
      final pos = TextPosition(offset: offset - s, affinity: atEnd ? TextAffinity.upstream : TextAffinity.downstream);
      final local = r.getOffsetForCaret(pos, Rect.zero);
      final h = r.getFullHeightForCaret(pos) ?? (_fontSize * 1.6);
      return (r.localToGlobal(local), h);
    }
    return null;
  }

  /// Dragging a handle: the start ([isStart]) or end of the chosen words moves.
  void _dragHandle(bool isStart, Offset global, double lineHeight) {
    final sel = _sel;
    if (sel == null) return;
    // Aim at the line the handle belongs to (the finger is on the round knob).
    final aim = global + Offset(0, isStart ? lineHeight * 0.5 + 16 : -(lineHeight * 0.5 + 16));
    final w = _wordAt(aim);
    if (w == null) return;
    var (p1, s1, p2, e2) = (sel.p1, sel.s1, sel.p2, sel.e2);
    if (isStart) {
      (p1, s1) = (w.$1, w.$2);
    } else {
      (p2, e2) = (w.$1, w.$3);
    }
    // Keep start before end.
    if (p1 > p2 || (p1 == p2 && s1 >= e2)) {
      final t = (p1, s1);
      (p1, s1) = (p2, e2 == 0 ? 0 : e2 - 1);
      (p2, e2) = (t.$1, t.$2 + 1);
    }
    setState(() {
      _magnifierAt = global;
      _sel = (p1: p1, s1: s1, p2: p2, e2: e2);
    });
  }

  void _copySelection() {
    final parts = <String>[];
    _forEachSelected((p, s, e) => parts.add(widget.message.paragraphs[p].substring(s, e)));
    Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    setState(() => _sel = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(widget.message.lang == 'en' ? 'Copied' : 'நகலெடுக்கப்பட்டது'),
          duration: const Duration(seconds: 1)),
    );
  }

  /// The handles, the magnifier and the toolbar for the chosen words (page mode).
  List<Widget> _selectionLayers(ThemeData theme) {
    final sel = _sel;
    if (sel == null) {
      _toolbarColours = false; // next time the toolbar starts with its buttons
      return const [];
    }
    final out = <Widget>[];
    final screen = MediaQuery.sizeOf(context);
    final handleColor = theme.colorScheme.primary;
    (Offset, double)? a, b;
    try {
      a = _caret(sel.p1, sel.s1);
      b = _caret(sel.p2, sel.e2, atEnd: true);
    } catch (_) {}

    Widget handle(bool isStart, (Offset, double) at) {
      final (pt, h) = at;
      const knob = 16.0, pad = 14.0;
      return Positioned(
        left: pt.dx - knob / 2 - pad,
        top: (isStart ? pt.dy - knob : pt.dy) - pad,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => _dragHandle(isStart, d.globalPosition, h),
          onPanEnd: (_) => _selectEnd(),
          child: Padding(
            padding: const EdgeInsets.all(pad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isStart) Container(width: knob, height: knob, decoration: BoxDecoration(color: handleColor, shape: BoxShape.circle)),
                Container(width: 2.5, height: h, color: handleColor),
                if (!isStart) Container(width: knob, height: knob, decoration: BoxDecoration(color: handleColor, shape: BoxShape.circle)),
              ],
            ),
          ),
        ),
      );
    }

    if (a != null) out.add(handle(true, a));
    if (b != null) out.add(handle(false, b));

    final mag = _magnifierAt;
    if (mag != null) {
      const d = 104.0;
      out.add(Positioned(
        left: (mag.dx - d / 2).clamp(4.0, screen.width - d - 4),
        top: (mag.dy - d - 46).clamp(4.0, screen.height - d - 4),
        child: const IgnorePointer(
          child: RawMagnifier(
            size: Size(d, d),
            magnificationScale: 1.6,
            focalPointOffset: Offset(0, d / 2 + 40),
            decoration: MagnifierDecoration(
              shape: CircleBorder(side: BorderSide(color: Color(0xFF9E9E9E), width: 1)),
              shadows: [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 3))],
            ),
          ),
        ),
      ));
      return out; // the toolbar comes when the finger is lifted
    }

    // The toolbar: above the chosen words, or below them when there is no room.
    final en = widget.message.lang == 'en' || appProfile.englishOnly;
    String say(String ta, String e) => en ? e : ta;
    const barH = 64.0;
    final width = math.min(screen.width - 24, 420.0);
    double top;
    if (a != null && a.$1.dy - barH - 12 > 40) {
      top = a.$1.dy - barH - 12;
    } else if (b != null) {
      top = math.min(b.$1.dy + b.$2 + 26, screen.height - barH - 24);
    } else {
      top = screen.height - barH - 40;
    }
    Widget tool(IconData icon, String label, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
        );
    Widget colour(HighlightColor c) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _applyToSelection(MarkStyle.color, c),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: c.dot, shape: BoxShape.circle),
                ),
                const SizedBox(height: 3),
                Text(c.label, style: const TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
        );
    final items = _toolbarColours
        ? <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => setState(() => _toolbarColours = false),
            ),
            for (final c in HighlightColor.offered) colour(c),
          ]
        : <Widget>[
            // Already marked: Delete comes first (takes the highlight / bold off).
            if (_selectionHasMarks())
              tool(Icons.delete_outline, say('நீக்கு', 'Delete'), () {
                _forEachSelected(_unmark);
                setState(() => _sel = null);
              }),
            tool(Icons.circle, say('ஹைலைட்', 'Highlight'), () => setState(() => _toolbarColours = true)),
            tool(Icons.format_bold, say('தடித்த', 'Bold'), () => _applyToSelection(MarkStyle.bold)),
            tool(Icons.note_add_outlined, say('குறிப்பு', 'Note'), _sendSelectionToNotes),
            tool(Icons.copy, say('நகல்', 'Copy'), _copySelection),
            tool(Icons.bookmark_add_outlined, say('புக்மார்க்', 'Bookmark'), _bookmarkSelection),
            tool(Icons.share_outlined, say('பகிர்', 'Share'), _shareSelection),
          ];
    out.add(Positioned(
      left: (screen.width - width) / 2,
      top: top,
      width: width,
      child: Material(
        color: const Color(0xFF222222),
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: barH,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              for (final w in items) Center(child: w),
            ],
          ),
        ),
      ),
    ));
    return out;
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

  /// The top bar (the same in pages and in scrolling): Search, Bible, MyNotes, அ / T
  /// (text and layout), ⋮; under them the title, and the Tamil / English switch.
  (AppBar, double) _topBar(Message m, ThemeData theme) {
    const titleRow = 58.0; // room for tall Tamil letters
    final hasLangSwitch = !(_other == null || appProfile.englishOnly);
    final en = m.lang == 'en' || appProfile.englishOnly;
    final height =
        MediaQuery.paddingOf(context).top + kToolbarHeight + titleRow + (hasLangSwitch ? 52 : 0);
    final bar = AppBar(
      actions: [
        IconButton(
          tooltip: en ? 'Search' : 'தேடு',
          icon: const Icon(Icons.search),
          onPressed: _openSearch,
        ),
        const GoToBibleButton(),
        IconButton(
          tooltip: en ? 'MyNotes' : 'எனது குறிப்புகள்',
          icon: const Icon(Icons.sticky_note_2_outlined),
          onPressed: () => openNotes(context),
        ),
        // அ (Tamil) / T (English): font, size, page colour, layout — shows at once.
        IconButton(
          tooltip: en ? 'Text' : 'எழுத்து',
          icon: Text(en ? 'T' : 'அ', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          onPressed: () => showReadingPanel(context, lang: m.lang),
        ),
        MoreMenu(
          lang: m.lang,
          onPdf: _savePdf,
          showNotes: false,
          scrolling: !pageMode.value.on,
          onScrolling: (on) => setPageTurning(!on),
          // Opens this message (at this paragraph) in the top half; main menu below.
          splitTop: (_) {
            final here = _hereParagraph();
            return ReaderScreen(message: m, initialParagraph: here > 0 ? here : null);
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(titleRow + (hasLangSwitch ? 52 : 0)),
        child: Column(
          children: [
            SizedBox(
              height: titleRow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                // (Shrinks rather than overflowing if a font is taller still.)
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width - 32,
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ValueListenableBuilder<double>(
                      valueListenable: _progress,
                      builder: (_, p, __) => Text('${m.code} · ${_progressText(p)}',
                          style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                  ),
                ),
              ),
            ),
            if (hasLangSwitch)
              SizedBox(
                height: 52,
                child: MessageLangSwitch(value: m.lang, onChanged: (_) => _switchLanguage()),
              ),
          ],
        ),
      ),
    );
    return (bar, height);
  }

  Widget _buildPages(Message m, ThemeData theme, Color textColor) {
    final settings = pageMode.value;
    final inset = MediaQuery.viewPaddingOf(context).top;
    if (inset > _pageTopInset) _pageTopInset = inset; // (kept, so the pages never move)
    final (bar, barHeight) = _topBar(m, theme);
    final showBars = !_immersive;
    final en = m.lang == 'en' || appProfile.englishOnly;
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
              swipeEnabled: _sel == null,
              background: theme.scaffoldBackgroundColor,
              onPage: (page, count, paragraph, fraction) {
                _pageParagraph = paragraph;
                _progress.value = fraction;
                _scheduleSave();
                if (mounted && (page != _pageNo || count != _pageCount)) {
                  setState(() {
                    if (page != _pageNo) _sel = null; // turning the page lets go of the chosen words
                    _pageNo = page;
                    _pageCount = count;
                  });
                }
              },
            ),
          ),
          // A bookmarked page shows the ribbon in its corner.
          if (!_pagePanelOpen && _pageCount > 0 && _pageBookmarked(_pageNo))
            const Positioned(
              top: 0,
              right: 18,
              child: IgnorePointer(child: Icon(Icons.bookmark, size: 32, color: _ribbon)),
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
          // Tap: the page shrinks into the row of pages (like Kindle).
          if (showBars && _pagePanelOpen) Positioned.fill(child: _pageView(theme, barHeight)),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            top: showBars ? 0 : -barHeight - 4,
            height: barHeight,
            child: bar,
          ),
          // Chosen words: the toolbar above them, the handles and the magnifier.
          ..._selectionLayers(theme),
          // Searching: matches are orange; up / down go to the next page with a match.
          if (_query.isNotEmpty && _sel == null && !_pagePanelOpen)
            Positioned(left: 0, right: 0, bottom: 0, child: _searchBar(theme)),
        ],
      ),
    );
  }
}
