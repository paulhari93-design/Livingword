import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// How far each Bible chapter has been read (0..1), for the progress lines in the
/// book list and the chapter grids. Kept on the phone (Prefs 'bible_progress'),
/// the same for Tamil and English.
class BibleProgress extends ChangeNotifier {
  BibleProgress._();
  static final BibleProgress instance = BibleProgress._();

  /// Read to here (or further) counts as read.
  static const done = 0.9;

  Map<String, Map<String, double>> _books = {}; // "43" -> {"3": 0.7}
  bool _loaded = false;
  Timer? _saveTimer;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await Prefs.instance.getString('bible_progress');
      if (raw != null) {
        _books = (jsonDecode(raw) as Map<String, dynamic>).map((b, chs) => MapEntry(
            b, (chs as Map<String, dynamic>).map((c, f) => MapEntry(c, (f as num).toDouble()))));
      }
    } catch (_) {}
    notifyListeners();
  }

  /// How far chapter [chapter] of book [book] is read (0..1).
  double chapter(int book, int chapter) => _books['$book']?['$chapter'] ?? 0;

  /// How many chapters of [book] are read.
  int chaptersRead(int book) => (_books['$book']?.values ?? const <double>[]).where((f) => f >= done).length;

  /// The reader has seen this much of the chapter. Only ever goes up.
  void update(int book, int chapter, double fraction) {
    if (!_loaded) {
      load().then((_) => update(book, chapter, fraction));
      return;
    }
    final f = fraction.clamp(0.0, 1.0);
    final chs = _books.putIfAbsent('$book', () => {});
    if (f <= (chs['$chapter'] ?? 0) + 0.01) return;
    chs['$chapter'] = f;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      Prefs.instance.set('bible_progress', jsonEncode(_books));
    });
  }
}
