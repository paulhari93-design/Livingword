import 'dart:math' as math;

import '../models/highlight.dart';

/// Lines ("clauses") in a paragraph, and copying marks between Tamil and English.

const _stops = ',;.?!';
const _closers = '"”’\')]';

int _words(String t) => t
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.replaceAll(RegExp('[,;.?!:"“”‘’\'()\\[\\]—–-]'), '').isNotEmpty)
    .length;

/// Where the text starts after a paragraph number like "12  " or "27. ".
int textStart(String text) => RegExp(r'^\d{1,3}[.\s]\s*').firstMatch(text)?.end ?? 0;

/// The lines of a paragraph: each runs from one , ; . ? ! to the next.
/// A single word before a comma ("Now,") is joined to the words after it.
List<(int, int)> clausesOf(String text) {
  if (text.trim().isEmpty) return const [];
  final lead = textStart(text);
  final segs = <List<int>>[]; // [start, end, start of its last piece]
  var start = lead;
  var i = lead;
  while (i < text.length) {
    if (_stops.contains(text[i])) {
      var j = i + 1;
      while (j < text.length && (_stops.contains(text[j]) || _closers.contains(text[j]))) {
        j++;
      }
      segs.add([start, j, start]);
      start = j;
      i = j;
    } else {
      i++;
    }
  }
  if (start < text.length) segs.add([start, text.length, start]);

  String piece(List<int> g) => text.substring(g[2], g[1]);
  bool endsWithComma(List<int> g) {
    var t = piece(g).trimRight();
    while (t.isNotEmpty && _closers.contains(t[t.length - 1])) {
      t = t.substring(0, t.length - 1);
    }
    return t.endsWith(',');
  }

  var k = 0;
  while (k < segs.length) {
    final one = _words(piece(segs[k])) <= 1;
    if (one && endsWithComma(segs[k]) && k + 1 < segs.length) {
      segs[k + 1][0] = segs[k][0]; // keep going to the next , ; .
      segs.removeAt(k);
      continue;
    }
    if (one && k > 0 && endsWithComma(segs[k - 1])) {
      segs[k - 1][1] = segs[k][1];
      segs[k - 1][2] = segs[k][2];
      segs.removeAt(k);
      continue;
    }
    k++;
  }

  final out = <(int, int)>[];
  for (final g in segs) {
    var s = g[0], e = g[1];
    while (s < e && text[s].trim().isEmpty) {
      s++;
    }
    while (e > s && text[e - 1].trim().isEmpty) {
      e--;
    }
    if (e > s) out.add((s, e));
  }
  return out;
}

/// The line around [offset].
(int, int)? clauseAtOffset(String text, int offset) {
  final list = clausesOf(text);
  if (list.isEmpty) return null;
  var g = list.first;
  for (final x in list) {
    if (offset >= x.$1 && offset < x.$2) return x;
    if (offset >= x.$2) g = x;
  }
  return g;
}

/// Adds a mark to [list] (or, for bold / underline already there, takes it off).
/// [add]: true = always add, false = always remove, null = toggle (bold / underline).
/// Returns true if the mark is now on.
bool applyMark(List<Highlight> list, List<String> paragraphs, int p, int s, int e,
    MarkStyle style, HighlightColor color, {bool? add}) {
  if (e <= s || p < 0 || p >= paragraphs.length) return false;
  e = math.min(e, paragraphs[p].length);
  final same = list.where((h) => h.style == style && h.overlaps(p, s, e)).toList();
  final on = add ?? (style == MarkStyle.color || !same.any((h) => h.start <= s && h.end >= e));
  list.removeWhere((h) => h.style == style && h.overlaps(p, s, e));
  if (on) {
    list.add(Highlight(
      paragraph: p,
      start: s,
      end: e,
      color: color,
      style: style,
      text: paragraphs[p].substring(s, e),
    ));
  }
  return on;
}

/// Finds the place in the other language that matches characters [s]..[e] of
/// paragraph [p]. Uses the paragraph matching made when publishing ([align]:
/// for each Tamil paragraph, its English paragraph), then the same share of lines.
/// Returns a list of (paragraph, start, end) in the other language.
List<(int, int, int)> mirrorRange({
  required bool fromTamil,
  required List<int> align,
  required List<String> from,
  required List<String> to,
  required int p,
  required int s,
  required int e,
}) {
  if (from.isEmpty || to.isEmpty || p >= from.length) return const [];
  final tamilCount = fromTamil ? from.length : to.length;
  final englishCount = fromTamil ? to.length : from.length;
  if (align.length != tamilCount) return const [];

  // English paragraphs belonging to Tamil paragraph i.
  (int, int) enRange(int i) {
    final a = align[i].clamp(0, englishCount - 1).toInt();
    final next = i + 1 < tamilCount ? align[i + 1] : englishCount;
    final b = math.max(a, math.min(englishCount, next) - 1);
    return (a, b);
  }

  // Target paragraphs, in order.
  final targets = <int>[];
  if (fromTamil) {
    final r = enRange(p);
    for (var j = r.$1; j <= r.$2; j++) {
      targets.add(j);
    }
  } else {
    for (var i = 0; i < tamilCount; i++) {
      final r = enRange(i);
      if (p >= r.$1 && p <= r.$2) targets.add(i);
    }
    if (targets.isEmpty) {
      var best = 0;
      for (var i = 0; i < tamilCount; i++) {
        if ((align[i] - p).abs() < (align[best] - p).abs()) best = i;
      }
      targets.add(best);
    }
  }

  // Which share of the source paragraph's lines is marked.
  final src = clausesOf(from[p]);
  if (src.isEmpty) return const [];
  var a = 0, b = src.length - 1;
  for (var k = 0; k < src.length; k++) {
    if (src[k].$2 > s) {
      a = k;
      break;
    }
  }
  for (var k = src.length - 1; k >= 0; k--) {
    if (src[k].$1 < e) {
      b = k;
      break;
    }
  }
  if (b < a) b = a;
  final f1 = a / src.length;
  final f2 = (b + 1) / src.length;

  // The same share of the target lines.
  final lines = <(int, int, int)>[];
  for (final t in targets) {
    for (final c in clausesOf(to[t])) {
      lines.add((t, c.$1, c.$2));
    }
  }
  if (lines.isEmpty) return const [];
  final m = lines.length;
  final i1 = (f1 * m).floor().clamp(0, m - 1).toInt();
  final i2 = math.max(i1, ((f2 * m).ceil() - 1).clamp(0, m - 1).toInt());

  // Join the chosen lines into one range per paragraph.
  final out = <(int, int, int)>[];
  for (var k = i1; k <= i2; k++) {
    final l = lines[k];
    if (out.isNotEmpty && out.last.$1 == l.$1) {
      out[out.length - 1] = (l.$1, out.last.$2, l.$3);
    } else {
      out.add(l);
    }
  }
  return out;
}
