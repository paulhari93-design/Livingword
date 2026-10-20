import 'package:flutter/material.dart';

enum HighlightColor {
  neon('Neon', Color(0xB339FF14)),
  skyBlue('Sky blue', Color(0xB387CEEB)),
  yellow('Yellow', Color(0xB3FFFF00));

  const HighlightColor(this.label, this.color);
  final String label;
  final Color color;
}

/// A highlight is saved as: paragraph number + character range + colour.
class Highlight {
  final int paragraph;
  final int start;
  final int end;
  final HighlightColor color;

  const Highlight({
    required this.paragraph,
    required this.start,
    required this.end,
    required this.color,
  });

  bool overlaps(int p, int s, int e) => paragraph == p && start < e && s < end;

  Map<String, dynamic> toJson() =>
      {'p': paragraph, 's': start, 'e': end, 'c': color.name};

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        paragraph: j['p'] as int,
        start: j['s'] as int,
        end: j['e'] as int,
        color: HighlightColor.values.firstWhere(
          (c) => c.name == j['c'],
          orElse: () => HighlightColor.yellow,
        ),
      );
}
