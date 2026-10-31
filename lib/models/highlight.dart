import 'package:flutter/material.dart';

enum HighlightColor {
  // Kindle's colours (measured from Kindle on a phone).
  aqua('Aqua', Color(0xB343C1C4)),
  pink('Pink', Color(0xB3E39396)),
  orange('Orange', Color(0xB3E3A356)),
  yellow('Yellow', Color(0xB3E5CD5F)),
  green('Green', Color(0xB33AC89A)),
  // Older colours: still shown for highlights made with them, no longer offered.
  neon('Neon', Color(0xB339FF14)),
  skyBlue('Sky blue', Color(0xB387CEEB));

  const HighlightColor(this.label, this.color);
  final String label;
  final Color color;

  /// The colours offered when highlighting, in Kindle's order.
  static const offered = [aqua, pink, orange, yellow, green];

  /// The colour of the dot in the colour row (without transparency).
  Color get dot => color.withValues(alpha: 1);
}

/// What a mark does: colour the background, make the text bold, or underline it.
enum MarkStyle { color, bold, underline }

/// A highlight is saved as: paragraph number + character range + colour,
/// plus the highlighted words themselves so it can be found again after a correction.
class Highlight {
  final int paragraph;
  final int start;
  final int end;
  final HighlightColor color; // used when style == MarkStyle.color
  final MarkStyle style;
  final String? text; // the highlighted words (null for highlights saved by older versions)

  const Highlight({
    required this.paragraph,
    required this.start,
    required this.end,
    this.color = HighlightColor.yellow,
    this.style = MarkStyle.color,
    this.text,
  });

  bool overlaps(int p, int s, int e) => paragraph == p && start < e && s < end;

  Highlight moved(int newParagraph, int newStart) => Highlight(
        paragraph: newParagraph,
        start: newStart,
        end: newStart + (end - start),
        color: color,
        style: style,
        text: text,
      );

  Map<String, dynamic> toJson() => {
        'p': paragraph,
        's': start,
        'e': end,
        'c': color.name,
        if (style != MarkStyle.color) 'k': style.name,
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
        style: MarkStyle.values.firstWhere(
          (k) => k.name == j['k'],
          orElse: () => MarkStyle.color,
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
            style: h.style,
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
