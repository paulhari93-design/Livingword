import 'package:flutter/material.dart';

import '../models/message.dart';
import 'split_reader_screen.dart' show matchParagraph;

/// Which half of the split view a screen is in (0 = top, 1 = bottom).
class SplitHalf extends InheritedWidget {
  const SplitHalf({super.key, required this.index, required super.child});
  final int index;

  static int? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SplitHalf>()?.index;

  @override
  bool updateShouldNotify(SplitHalf oldWidget) => oldWidget.index != index;
}

/// A reader in one half of the split view.
class ReadAlongTarget {
  ReadAlongTarget({required this.kind, required this.key, this.message, required this.follow});

  final String kind; // 'message' or 'bible'
  String key; // message code, or Bible book number (the chapter is part of the position)
  final Message? message; // for matching Tamil ↔ English paragraphs
  /// Move to [position] (paragraph, or chapter * 1000 + verse for the Bible) at [fraction].
  final void Function(int position, double fraction) follow;
}

/// Read along: in the split view, when both halves show the same message (Tamil and
/// English) or the same Bible book, scrolling one half scrolls the other with it.
class ReadAlong extends ChangeNotifier {
  ReadAlong._();
  static final ReadAlong instance = ReadAlong._();

  final Map<int, ReadAlongTarget> _targets = {};
  bool _on = false;

  /// Both halves show the same message (by code) or the same Bible book.
  bool get canLink {
    final a = _targets[0], b = _targets[1];
    return a != null && b != null && a.kind == b.kind && a.key.toUpperCase() == b.key.toUpperCase();
  }

  bool get on => _on && canLink;

  void setOn(bool value) {
    _on = value;
    notifyListeners();
  }

  void attach(int half, ReadAlongTarget t) {
    _targets[half] = t;
    notifyListeners();
  }

  void detach(int half, ReadAlongTarget t) {
    if (identical(_targets[half], t)) {
      _targets.remove(half);
      if (!canLink) _on = false;
      notifyListeners();
    }
  }

  void changed() {
    if (!canLink) _on = false;
    notifyListeners();
  }

  /// Split view closed.
  void reset() {
    _targets.clear();
    _on = false;
  }

  /// The user scrolled [half] to [position]; move the other half to the matching place.
  void moved(int half, int position, double fraction) {
    if (!on) return;
    final me = _targets[half], other = _targets[1 - half];
    if (me == null || other == null) return;
    var target = position;
    final a = me.message, b = other.message;
    if (me.kind == 'message' && a != null && b != null && a.lang != b.lang) {
      target = matchParagraph(a, b, position);
    }
    other.follow(target, fraction);
  }
}
