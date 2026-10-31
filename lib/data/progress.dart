import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// One message in the reading history.
class HistoryEntry {
  final String lang; // 'ta' / 'en'
  final String code;
  double progress; // where the reader is now, 0..1
  int timesRead; // how many times read to the end
  int paragraph; // where the reader left off
  DateTime lastOpened;

  HistoryEntry({
    required this.lang,
    required this.code,
    this.progress = 0,
    this.timesRead = 0,
    this.paragraph = 0,
    required this.lastOpened,
  });

  Map<String, dynamic> toJson() => {
        'l': lang, 'c': code, 'p': progress, 'n': timesRead, 'q': paragraph,
        't': lastOpened.millisecondsSinceEpoch,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        lang: j['l'] as String? ?? 'ta',
        code: j['c'] as String? ?? '',
        progress: (j['p'] as num?)?.toDouble() ?? 0,
        timesRead: (j['n'] as num?)?.toInt() ?? 0,
        paragraph: (j['q'] as num?)?.toInt() ?? 0,
        lastOpened: DateTime.fromMillisecondsSinceEpoch((j['t'] as num?)?.toInt() ?? 0),
      );
}

/// ⋮ → History: every message opened, how far it is read, and how many times it was
/// read to the end. Saved on the phone (Prefs 'history', keyed by storageId).
class ReadingProgress extends ChangeNotifier {
  ReadingProgress._();
  static final ReadingProgress instance = ReadingProgress._();

  /// Read to here (or further) counts as read to the end.
  static const done = 0.95;

  Map<String, HistoryEntry> _history = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await Prefs.instance.getString('history');
      if (raw != null) {
        _history = (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, HistoryEntry.fromJson(v as Map<String, dynamic>)));
      }
    } catch (_) {}
    notifyListeners();
  }

  double of(String storageId) => _history[storageId]?.progress ?? 0;
  int timesRead(String storageId) => _history[storageId]?.timesRead ?? 0;

  /// Where the reader left off in this message (paragraph), or null.
  int? paragraphOf(String storageId) => _history[storageId]?.paragraph;

  /// Newest first.
  List<HistoryEntry> entries() =>
      _history.values.toList()..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));

  /// A message was opened.
  Future<void> opened(String storageId, String lang, String code) async {
    await load();
    final e = _history.putIfAbsent(
        storageId, () => HistoryEntry(lang: lang, code: code, lastOpened: DateTime.now()));
    e.lastOpened = DateTime.now();
    await _save();
  }

  /// Where the reader is now. [finishedNow]: reached the end in this reading (counted once
  /// per opening, so reading it again later counts again).
  Future<void> save(String storageId, String lang, String code, double fraction,
      {int paragraph = 0, bool finishedNow = false}) async {
    await load();
    final e = _history.putIfAbsent(
        storageId, () => HistoryEntry(lang: lang, code: code, lastOpened: DateTime.now()));
    e.progress = fraction.clamp(0.0, 1.0);
    e.paragraph = paragraph;
    e.lastOpened = DateTime.now();
    if (finishedNow) e.timesRead++;
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await Prefs.instance.set('history', jsonEncode(_history.map((k, v) => MapEntry(k, v.toJson()))));
  }
}
