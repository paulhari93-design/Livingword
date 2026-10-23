import 'package:flutter/material.dart';

enum HighlightColor {
  neon('Neon', Color(0xB339FF14)),
  skyBlue('Sky blue', Color(0xB387CEEB)),
  yellow('Yellow', Color(0xB3FFFF00));

  const HighlightColor(this.label, this.color);
  final String label;
  final Color color;
}

/// A highlight is saved as: paragraph number + character range + colour,
/// plus the highlighted words themselves so it can be found again after a correction.
class Highlight {
  final int paragraph;
  final int start;
  final int end;
  final HighlightColor color;
  final String? text; // the highlighted words (null for highlights saved by older versions)

  const Highlight({
    required this.paragraph,
    required this.start,
    required this.end,
    required this.color,
    this.text,
  });

  bool overlaps(int p, int s, int e) => paragraph == p && start < e && s < end;

  Highlight moved(int newParagraph, int newStart) => Highlight(
        paragraph: newParagraph,
        start: newStart,
        end: newStart + (end - start),
        color: color,
        text: text,
      );

  Map<String, dynamic> toJson() => {
        'p': paragraph,
        's': start,
        'e': end,
        'c': color.name,
        if (text != null) 't': text,
      };

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        paragraph: j['p'] as int,
        start: j['s'] as int,
        end: j['e'] as int,
        color: HighlightColor.values.firstWhere(
          (c) => c.name == j['c'],
          orElse: () => HighlightColor.yellow,
        ),
        text: j['t'] as String?,
      );

  /// After a message is corrected, puts each highlight back on its words.
  /// Returns null if nothing changed; otherwise the fixed list (highlights whose
  /// words were removed from the message are dropped).
  static List<Highlight>? reanchor(List<Highlight> list, List<String> paragraphs) {
    var changed = false;
    final out = <Highlight>[];
    for (final h in list) {
      final t = h.text;
      final inRange = h.paragraph < paragraphs.length && h.end <= paragraphs[h.paragraph].length;
      if (t == null) {
        // Older highlight without saved words: keep it if it still fits, and remember its words now.
        changed = true;
        if (inRange) {
          out.add(Highlight(
            paragraph: h.paragraph,
            start: h.start,
            end: h.end,
            color: h.color,
            text: paragraphs[h.paragraph].substring(h.start, h.end),
          ));
        }
        continue;
      }
      if (inRange && paragraphs[h.paragraph].substring(h.start, h.end) == t) {
        out.add(h);
        continue;
      }
      changed = true;
      // Look in the same paragraph first, then nearby ones.
      Highlight? found;
      for (final d in const [0, -1, 1, -2, 2, -3, 3]) {
        final p = h.paragraph + d;
        if (p < 0 || p >= paragraphs.length) continue;
        final text = paragraphs[p];
        // choose the occurrence closest to the old position
        var best = -1;
        var from = 0;
        while (true) {
          final i = text.indexOf(t, from);
          if (i < 0) break;
          if (best < 0 || (i - h.start).abs() < (best - h.start).abs()) best = i;
          from = i + 1;
        }
        if (best >= 0) {
          found = h.moved(p, best);
          break;
        }
      }
      if (found != null) out.add(found);
    }
    return changed ? out : null;
  }
}
