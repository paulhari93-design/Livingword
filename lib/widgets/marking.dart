import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/highlight.dart';

/// Text runs for one paragraph or verse, showing its marks (colour, bold,
/// underline) and the part chosen by tapping.
List<TextSpan> markedSpans(
  String text,
  Iterable<Highlight> marks, {
  (int, int)? chosen,
  required Color chosenColor,
}) {
  final n = text.length;
  if (n == 0) return const [];
  final colors = List<Color?>.filled(n, null);
  final bold = List<bool>.filled(n, false);
  final under = List<bool>.filled(n, false);
  final pick = List<bool>.filled(n, false);
  for (final h in marks) {
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
  if (chosen != null) {
    for (var k = math.max(0, chosen.$1); k < math.min(n, chosen.$2); k++) {
      pick[k] = true;
    }
  }
  bool same(int a, int b) =>
      colors[a] == colors[b] && bold[a] == bold[b] && under[a] == under[b] && pick[a] == pick[b];

  final spans = <TextSpan>[];
  var runStart = 0;
  for (var k = 1; k <= n; k++) {
    if (k == n || !same(k, runStart)) {
      final c = colors[runStart];
      final plain = c == null && !bold[runStart] && !under[runStart] && !pick[runStart];
      spans.add(TextSpan(
        text: text.substring(runStart, k),
        style: plain
            ? null
            : TextStyle(
                backgroundColor: c ?? (pick[runStart] ? chosenColor : null),
                color: c != null ? Colors.black : null,
                fontWeight: bold[runStart] ? FontWeight.w800 : null,
                decoration: under[runStart] || pick[runStart] ? TextDecoration.underline : null,
                decorationStyle: pick[runStart] && !under[runStart] ? TextDecorationStyle.dotted : null,
                decorationThickness: under[runStart] ? 2 : null,
              ),
      ));
      runStart = k;
    }
  }
  return spans;
}

/// The bar shown after tapping a line: colours, bold, underline, copy, remove, close.
class MarkBar extends StatelessWidget {
  const MarkBar({
    super.key,
    required this.onColor,
    required this.onBold,
    required this.onCopy,
    required this.onClear,
    required this.onClose,
    this.onSendToNotes,
    this.onBookmark,
    this.onShare,
  });

  final ValueChanged<HighlightColor> onColor;
  final VoidCallback onBold;
  final VoidCallback onCopy;
  final VoidCallback onClear;
  final VoidCallback onClose;
  final VoidCallback? onSendToNotes; // 📝 add the chosen lines to MyNotes
  final VoidCallback? onBookmark; // 🔖 bookmark this place
  final VoidCallback? onShare; // share the chosen words as a picture

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget dot(HighlightColor c) => InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onColor(c),
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
      child: SizedBox(
        height: 56,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final c in HighlightColor.offered) dot(c),
              const SizedBox(width: 4),
              IconButton(tooltip: 'Bold', icon: const Icon(Icons.format_bold), onPressed: onBold),
              if (onSendToNotes != null)
                IconButton(
                    tooltip: 'Send to notes', icon: const Icon(Icons.note_add_outlined), onPressed: onSendToNotes),
              if (onBookmark != null)
                IconButton(tooltip: 'Bookmark', icon: const Icon(Icons.bookmark_add_outlined), onPressed: onBookmark),
              if (onShare != null)
                IconButton(tooltip: 'Share as picture', icon: const Icon(Icons.share_outlined), onPressed: onShare),
              IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy), onPressed: onCopy),
              IconButton(tooltip: 'Remove marks', icon: const Icon(Icons.format_clear), onPressed: onClear),
              IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
        ),
      ),
    );
  }
}
