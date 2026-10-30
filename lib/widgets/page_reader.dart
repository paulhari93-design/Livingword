import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One block of text to lay out on pages: a heading line or a paragraph.
class PageBlock {
  final String text;
  final TextStyle style;
  final TextAlign align;
  final double spaceAfter;
  final int paragraph; // index in the message; -1 for the heading

  /// The words from [start] to [end] with their marks (bold, colour, ...); null = plain.
  final List<InlineSpan> Function(int start, int end)? spans;
  const PageBlock(this.text, this.style,
      {this.align = TextAlign.start, this.spaceAfter = 16, this.paragraph = -1, this.spans});

  InlineSpan span(int start, int end) {
    final f = spans;
    return f == null
        ? TextSpan(text: text.substring(start, end), style: style)
        : TextSpan(style: style, children: f(start, end));
  }
}

/// Text on a page, drawn exactly as the pages were measured (no app-wide text style or
/// phone language mixed in, which made the drawn text a little taller than measured, so
/// the last line was cut off).
Widget pageText(BuildContext context, InlineSpan span, TextAlign align) => RichText(
      text: span,
      textAlign: align,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    );

/// The part of a block shown on a page (a long paragraph goes on over pages).
class _Piece {
  final int block;
  final int start;
  final int end;
  const _Piece(this.block, this.start, this.end);
}

/// Page mode (like Kindle): the message laid out on pages that exactly fill the screen.
/// Each line is on one page only, so nothing is read twice.
class PageReader extends StatefulWidget {
  const PageReader({
    super.key,
    required this.blocks,
    required this.padding,
    this.initialParagraph,
    required this.sideways,
    required this.animate,
    required this.onPage,
    required this.onTap,
    required this.background,
    this.onDoubleTap,
    this.pieceBuilder,
  });

  final VoidCallback? onDoubleTap; // the list of pages

  /// Draws part of a paragraph on a page (with marks and taps); null = plain text.
  final Widget Function(PageBlock block, int start, int end)? pieceBuilder;

  /// The page colour (a turning page covers the one below it).
  final Color background;

  final List<PageBlock> blocks;
  final EdgeInsets padding;
  final int? initialParagraph;

  /// Swipe left / right turns the page (false: swipe up / down).
  final bool sideways;

  /// The page slides while turning (false: the next page just appears).
  final bool animate;

  /// The page shown changed: [page] of [count], its first paragraph, how far (0..1).
  final void Function(int page, int count, int paragraph, double fraction) onPage;
  final VoidCallback onTap; // show / hide the bars
  @override
  State<PageReader> createState() => PageReaderState();
}

class PageReaderState extends State<PageReader> with SingleTickerProviderStateMixin {
  // Turning like a book: the page rolls over from the right edge (its back shows as it
  // turns) and uncovers the next page; going back, the previous page rolls back in.
  late final AnimationController _anim = AnimationController(vsync: this);
  double _offset = 0; // how far the page is pulled, px (< 0: towards the next page)
  bool _settling = false;
  List<List<_Piece>> _pages = const [];
  Size? _laidOutFor;
  EdgeInsets? _laidOutPadding;
  List<PageBlock>? _laidOutBlocks;
  int _page = 0;
  double _drag = 0;

  // The page rolling over: a picture of it, and which way (+1 forward, -1 back).
  ui.Image? _curlImage;
  int _curlDir = 0;
  final Map<int, GlobalKey> _keys = {};
  GlobalKey _keyFor(int i) => _keys.putIfAbsent(i, () => GlobalKey());

  bool get _curls => widget.animate && widget.sideways;

  /// Takes a picture of the page that will roll ([dir] +1: this page, -1: the previous one).
  bool _beginCurl(int dir) {
    if (!_curls) return false;
    if (_curlDir == dir && _curlImage != null) return true;
    final i = dir > 0 ? _page : _page - 1;
    if (i < 0 || i >= _pages.length) return false;
    try {
      final box = _keyFor(i).currentContext?.findRenderObject();
      if (box is! RenderRepaintBoundary || !box.attached) return false;
      final image = box.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
      _curlImage?.dispose();
      _curlImage = image;
      _curlDir = dir;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _endCurl() {
    _curlImage?.dispose();
    _curlImage = null;
    _curlDir = 0;
    // Only the pages around this one need their keys.
    _keys.removeWhere((i, _) => (i - _page).abs() > 1);
  }

  int get page => _page;
  int get pageCount => _pages.length;
  Size get pageSize => _laidOutFor ?? Size.zero;

  @override
  void dispose() {
    _anim.dispose();
    _curlImage?.dispose();
    super.dispose();
  }

  double get _extent {
    final s = pageSize;
    return widget.sideways ? s.width : s.height;
  }

  /// Next (+1) / previous (-1) page. At the first / last page it stays.
  void turn(int step) {
    final target = _page + step;
    if (target < 0 || target >= _pages.length || _settling) return;
    if (!widget.animate) {
      goTo(target);
    } else {
      _fingerY = null; // (volume keys: a gentle slant)
      _beginCurl(step > 0 ? 1 : -1);
      _settle(step > 0 ? -_extent : _extent);
    }
  }

  /// Straight to [page] (the page list and slider).
  void goTo(int page) {
    if (_pages.isEmpty) return;
    final target = page.clamp(0, _pages.length - 1);
    if (target == _page) return;
    _anim.stop();
    _settling = false;
    setState(() {
      _page = target;
      _offset = 0;
      _endCurl();
    });
    _report();
  }

  /// Lets the page finish its move to [to]: -extent = turned to the next page,
  /// +extent = to the previous page, 0 = back where it was.
  Future<void> _settle(double to) async {
    _settling = true;
    final from = _offset;
    final full = _extent <= 0 ? 1.0 : _extent;
    _anim.duration = Duration(milliseconds: (90 + 230 * (to - from).abs() / full).round());
    final move = Tween<double>(begin: from, end: to).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_anim);
    void step() => setState(() => _offset = move.value);
    move.addListener(step);
    try {
      await _anim.forward(from: 0).orCancel;
    } on TickerCanceled {
      // stopped
    }
    move.removeListener(step);
    if (!mounted) return;
    final turned = to != 0 && _settling;
    setState(() {
      if (turned) _page += to < 0 ? 1 : -1;
      _offset = 0;
      _endCurl();
    });
    _settling = false;
    if (turned) _report();
  }

  int get currentParagraph => _firstParagraph(_page);

  int _firstParagraph(int page) {
    if (page < 0 || page >= _pages.length) return 0;
    for (final p in _pages[page]) {
      final n = widget.blocks[p.block].paragraph;
      if (n >= 0) return n;
    }
    // Only the heading on this page: the first paragraph.
    return 0;
  }

  /// Fills pages of [size] with the blocks, splitting paragraphs between lines.
  List<List<_Piece>> _layout(Size size, TextScaler scaler) {
    final width = size.width - widget.padding.horizontal;
    final height = size.height - widget.padding.vertical;
    if (width <= 0 || height <= 0) return const [];
    final pages = <List<_Piece>>[];
    var page = <_Piece>[];
    var used = 0.0;

    void newPage() {
      if (page.isNotEmpty) pages.add(page);
      page = <_Piece>[];
      used = 0;
    }

    for (var b = 0; b < widget.blocks.length; b++) {
      final block = widget.blocks[b];
      var start = 0;
      while (start < block.text.length) {
        final rest = block.text.substring(start);
        final tp = TextPainter(
          text: block.span(start, block.text.length),
          textAlign: block.align,
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: width);
        // (A little to spare: the screen rounds to whole pixels.)
        final room = height - used - 3;
        if (tp.height <= room) {
          page.add(_Piece(b, start, block.text.length));
          used += tp.height + block.spaceAfter;
          break;
        }
        // Only part of it fits: as many whole lines as there is room for. Each try is
        // measured as it will be drawn, so the last line on the page is never cut.
        final lines = tp.computeLineMetrics();
        int lineEnd(int n) {
          final l = lines[n - 1];
          final pos = tp.getPositionForOffset(Offset(width, l.baseline - l.ascent / 2)).offset;
          final e = tp.getLineBoundary(TextPosition(offset: pos)).end;
          return e <= 0 ? rest.length : e;
        }
        double heightOf(int take) => (TextPainter(
              text: block.span(start, start + take),
              textAlign: block.align,
              textDirection: TextDirection.ltr,
              textScaler: scaler,
            )..layout(maxWidth: width))
            .height;
        var fit = 0;
        var sum = 0.0;
        for (final l in lines) {
          if (sum + l.height > room) break;
          sum += l.height;
          fit++;
        }
        var take = 0;
        while (fit > 0) {
          final t = lineEnd(fit);
          if (t > 0 && heightOf(t) <= room) {
            take = t;
            break;
          }
          fit--;
        }
        if (take == 0) {
          if (page.isEmpty) {
            take = lineEnd(1); // a line taller than a page: put it anyway
          } else {
            newPage();
            continue;
          }
        }
        page.add(_Piece(b, start, start + take));
        start += take;
        // Skip the space where the line broke.
        while (start < block.text.length && block.text[start] == ' ') {
          start++;
        }
        newPage();
      }
    }
    newPage();
    return pages;
  }

  int _pageOfParagraph(int paragraph) {
    for (var i = 0; i < _pages.length; i++) {
      for (final p in _pages[i]) {
        if (widget.blocks[p.block].paragraph == paragraph) return i;
      }
    }
    return 0;
  }

  /// Page [i] as drawn on the screen. [plain]: small, for the page list (no taps).
  Widget buildPage(int i, {bool plain = false}) {
    if (i < 0 || i >= _pages.length) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      // (Clip: rounding may make the last line a hair taller than the page.)
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in _pages[i])
                Padding(
                  padding: EdgeInsets.only(bottom: widget.blocks[p.block].spaceAfter),
                  child: !plain && widget.pieceBuilder != null && widget.blocks[p.block].paragraph >= 0
                      ? widget.pieceBuilder!(widget.blocks[p.block], p.start, p.end)
                      : pageText(
                          context,
                          widget.blocks[p.block].span(p.start, p.end),
                          widget.blocks[p.block].align,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double? _fingerY; // where the finger is (the fold leans with it)

  void _dragStart(double y) {
    _drag = 0;
    _fingerY = y;
  }

  void _dragUpdate(double delta, double y) {
    if (_settling) return;
    _fingerY = y;
    _drag += delta;
    if (!widget.animate) return;
    // The page follows the finger; at the first / last page it only gives a little.
    final hasNext = _page + 1 < _pages.length, hasPrev = _page > 0;
    var o = _drag;
    if ((o < 0 && !hasNext) || (o > 0 && !hasPrev)) {
      o *= 0.15;
    } else if (_curls && o != 0) {
      // The roll keeps the way it started (forward or back) for this swipe.
      final dir = o < 0 ? 1 : -1;
      if (_curlDir == 0) _beginCurl(dir);
      if (_curlDir != 0 && dir != _curlDir) o = 0;
    }
    setState(() => _offset = o.clamp(-_extent, _extent));
  }

  void _dragEnd(double velocity) {
    if (_settling) return;
    final d = _drag;
    _drag = 0;
    // Swipe left (or up) = next page; right (or down) = previous page.
    var next = (d < -40 || velocity < -400) && _page + 1 < _pages.length;
    var prev = (d > 40 || velocity > 400) && _page > 0;
    // A roll that started forward can only finish forward (and back only back).
    if (_curlDir > 0) prev = false;
    if (_curlDir < 0) next = false;
    if (!widget.animate) {
      if (next) goTo(_page + 1);
      if (prev) goTo(_page - 1);
      return;
    }
    // A quick flick turns the page; a slow drag turns it once past a quarter.
    final far = d.abs() > _extent * 0.25 || velocity.abs() > 400;
    if (next && far) {
      _settle(-_extent);
    } else if (prev && far) {
      _settle(_extent);
    } else {
      _settle(0);
    }
  }

  /// A whole page, on its own paper (so a turning page hides the one below it).
  Widget _sheet(int i, {bool lifted = false}) => DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: lifted
              ? const [BoxShadow(color: Color(0x55000000), blurRadius: 18, spreadRadius: 1)]
              : null,
        ),
        // The paper colour is inside the picture taken for the roll, so the turning page
        // is solid (the next page must not show through it).
        child: RepaintBoundary(
          key: _keyFor(i),
          child: ColoredBox(color: widget.background, child: buildPage(i)),
        ),
      );

  Offset _along(double v) => widget.sideways ? Offset(v, 0) : Offset(0, v);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      if (_laidOutFor != size || _laidOutPadding != widget.padding || !identical(_laidOutBlocks, widget.blocks)) {
        // First layout, or the screen / font changed: keep the same paragraph in view.
        final keep = _laidOutFor == null ? widget.initialParagraph : currentParagraph;
        // The first words on the page now (so a re-layout stays on them).
        final anchor = _laidOutFor != null && _page < _pages.length && _pages[_page].isNotEmpty
            ? (widget.blocks.length == (_laidOutBlocks?.length ?? -1) ? _pages[_page].first : null)
            : null;
        _pages = _layout(size, MediaQuery.textScalerOf(context));
        _laidOutFor = size;
        _laidOutPadding = widget.padding;
        _laidOutBlocks = widget.blocks;
        _page = keep == null ? 0 : _pageOfParagraph(keep);
        if (anchor != null) {
          for (var i = 0; i < _pages.length; i++) {
            if (_pages[i].any((q) => q.block == anchor.block && q.start <= anchor.start && anchor.start < q.end)) {
              _page = i;
              break;
            }
          }
        }
        _offset = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) => _report());
      }
      final List<Widget> layers;
      final curl = _curlImage;
      if (_pages.isEmpty) {
        layers = const [];
      } else if (_curls && curl != null && _curlDir != 0) {
        // Rolling: the page below, and the rolling page drawn over it.
        final w = size.width;
        final progress = (_curlDir > 0 ? -_offset / w : 1 - _offset / w).clamp(0.0, 1.0);
        // The fold leans with the finger: finger high = the top turns first.
        final fy = (_fingerY ?? size.height * 0.3).clamp(0.0, size.height);
        layers = [
          _sheet(_curlDir > 0 ? _page + 1 : _page),
          CustomPaint(
            size: size,
            painter: _CurlPainter(
              image: curl,
              progress: progress,
              angle: ((fy / size.height - 0.5) * 0.5).clamp(-0.25, 0.25),
              pivotY: fy,
              radius: math.max(14.0, w * 0.075),
              paper: widget.background,
            ),
          ),
        ];
      } else if (_curls) {
        // Still: the pages before and after lie hidden under this one, ready to roll.
        layers = [
          if (_page > 0) _sheet(_page - 1),
          if (_page + 1 < _pages.length) _sheet(_page + 1),
          Transform.translate(offset: _along(_offset), child: _sheet(_page)),
        ];
      } else if (_offset < 0 && _page + 1 < _pages.length) {
        // Turning forward: the next page lies below; this page lifts away.
        layers = [
          _sheet(_page + 1),
          Transform.translate(offset: _along(_offset), child: _sheet(_page, lifted: true)),
        ];
      } else if (_offset > 0 && _page > 0) {
        // Turning back: the previous page comes in over this one.
        layers = [
          _sheet(_page),
          Transform.translate(offset: _along(_offset - _extent), child: _sheet(_page - 1, lifted: true)),
        ];
      } else {
        layers = [Transform.translate(offset: _along(_offset), child: _sheet(_page))];
      }
      final side = widget.sideways;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragStart: side ? (d) => _dragStart(d.localPosition.dy) : null,
        onHorizontalDragUpdate: side ? (d) => _dragUpdate(d.delta.dx, d.localPosition.dy) : null,
        onHorizontalDragEnd: side ? (d) => _dragEnd(d.primaryVelocity ?? 0) : null,
        onVerticalDragStart: side ? null : (d) => _dragStart(d.localPosition.dx),
        onVerticalDragUpdate: side ? null : (d) => _dragUpdate(d.delta.dy, d.localPosition.dx),
        onVerticalDragEnd: side ? null : (d) => _dragEnd(d.primaryVelocity ?? 0),
        child: ClipRect(child: Stack(fit: StackFit.expand, children: layers)),
      );
    });
  }

  void _report() {
    if (!mounted || _pages.isEmpty) return;
    final f = _pages.length <= 1 ? 1.0 : _page / (_pages.length - 1);
    widget.onPage(_page, _pages.length, _firstParagraph(_page), f);
  }
}


/// Draws a page rolling over like paper (like Kindle). The fold is a slanted line (it
/// leans with the finger, [angle]). On one side of it the page lies flat; then it wraps
/// round a narrow roll, and the rest lies on top, back side up, with the words showing
/// through mirrored. [progress]: 0 = flat, 1 = turned right over.
class _CurlPainter extends CustomPainter {
  _CurlPainter({
    required this.image,
    required this.progress,
    required this.angle,
    required this.pivotY,
    required this.radius,
    required this.paper,
  });

  final ui.Image image;
  final double progress;
  final double angle;
  final double pivotY;
  final double radius;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final r = radius;
    final c = math.cos(angle), sn = math.sin(angle);
    final pivot = Offset(0, pivotY);
    // u: distance across the fold (the fold runs along v).
    double uOf(Offset p) {
      final d = p - pivot;
      return d.dx * c + d.dy * sn;
    }

    final corners = [Offset.zero, Offset(w, 0), Offset(0, h), Offset(w, h)].map(uOf).toList();
    final uMin = corners.reduce(math.min), uMax = corners.reduce(math.max);
    final uf = uMax - progress * (uMax - uMin + (math.pi + 1) * r); // the fold
    if (uf >= uMax) {
      canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Offset.zero & size, Paint());
      return;
    }
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final page = Offset.zero & size;
    final pic = Paint()..filterQuality = FilterQuality.medium;
    const big = 10000.0;

    canvas.save();
    canvas.clipRect(page);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);

    // Shows the page between u0 and u1 at u' = a + (u - u0) * k (k < 0: back side up).
    void strip(double u0, double u1, double a, double k, {Color? over, double shade = 0}) {
      final b = a + (u1 - u0) * k;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(math.min(a, b) - 0.4, -big, math.max(a, b) + 0.4, big));
      canvas.translate(a, 0);
      canvas.scale(k, 1);
      canvas.translate(-u0, 0);
      canvas.rotate(-angle);
      canvas.translate(-pivot.dx, -pivot.dy);
      canvas.clipRect(page);
      canvas.drawImageRect(image, src, page, pic);
      if (over != null) canvas.drawRect(page, Paint()..color = over);
      if (shade > 0) canvas.drawRect(page, Paint()..color = Color.fromRGBO(0, 0, 0, shade));
      canvas.restore();
    }

    // Shadow of the roll on the page below.
    canvas.drawRect(
      Rect.fromLTRB(uf + r, -big, uf + r + 34, big),
      Paint()
        ..shader = ui.Gradient.linear(
            Offset(uf + r, 0), Offset(uf + r + 34, 0), [const Color(0x48000000), const Color(0x00000000)]),
    );

    // The flat part.
    if (uf > uMin) strip(uMin - 2, uf, uMin - 2, 1);

    // Round the roll, in thin strips.
    const step = 2.0;
    final back = <(double, double, double, double, double)>[];
    final end = math.min(uf + math.pi * r, uMax);
    for (var u = math.max(uf, uMin); u < end; u += step) {
      final u1 = math.min(end, u + step);
      final t0 = (u - uf) / r, t1 = (u1 - uf) / r, t = (t0 + t1) / 2;
      final a = uf + r * math.sin(t0), b = uf + r * math.sin(t1);
      final k = (b - a) / (u1 - u);
      if (t < math.pi / 2) {
        // Front of the page, darker as it turns away.
        strip(u, u1, a, k, shade: 0.34 * math.pow(t / (math.pi / 2), 2).toDouble());
      } else {
        back.add((u, u1, a, k, t));
      }
    }
    // Back of the page: one smooth sheet, the words showing through. Evenly lit where it
    // lies flat, darker only towards the outer edge of the roll (no crease line).
    final paperOver = paper.withValues(alpha: 0.58);
    if (uf + math.pi * r < uMax) {
      final u0 = uf + math.pi * r;
      strip(u0, uMax + 2, uf, -1, over: paperOver);
    }
    for (final (u0, u1, a, k, t) in back) {
      strip(u0, u1, a, k, over: paperOver, shade: 0.30 * (1 + math.cos(t)));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CurlPainter old) =>
      old.progress != progress || old.image != image || old.angle != angle || old.pivotY != pivotY ||
      old.radius != radius || old.paper != paper;
}
