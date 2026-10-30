import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'prefs.dart';
import 'profile.dart';

/// One newly published message.
class NewsItem {
  final String code;
  final String title;
  final String lang; // 'ta' or 'en'
  final DateTime at;
  const NewsItem({required this.code, required this.title, required this.lang, required this.at});

  Map<String, dynamic> toJson() => {'c': code, 't': title, 'l': lang, 'a': at.millisecondsSinceEpoch};
  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        code: j['c'] as String,
        title: j['t'] as String,
        lang: j['l'] as String? ?? 'ta',
        at: DateTime.fromMillisecondsSinceEpoch((j['a'] as num?)?.toInt() ?? 0),
      );
}

/// "Notifications" in the ⋮ menu: the messages published lately, and whether the
/// reader has looked at them yet (orange dot on ⋮ until they do).
class NewsStore extends ChangeNotifier {
  NewsStore._();
  static final NewsStore instance = NewsStore._();

  static const _max = 60;
  List<NewsItem> _items = [];
  bool _unseen = false;
  bool _loaded = false;

  /// Newest first; only the languages this profile reads.
  List<NewsItem> get items =>
      appProfile.englishOnly ? _items.where((i) => i.lang == 'en').toList() : List.unmodifiable(_items);

  /// True when something new was published that the reader has not opened yet.
  bool get unseen => _unseen && items.isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await Prefs.instance.getString('news');
      if (raw != null) {
        _items = (jsonDecode(raw) as List).map((e) => NewsItem.fromJson(e as Map<String, dynamic>)).toList();
      }
      _unseen = await Prefs.instance.getBool('news_unseen') ?? false;
    } catch (_) {}
    notifyListeners();
  }

  /// Called after a check for new messages found some.
  Future<void> add(List<NewsItem> fresh) async {
    if (fresh.isEmpty) return;
    await load();
    final keys = {for (final f in fresh) '${f.lang}/${f.code}'};
    _items = [
      ...fresh,
      ..._items.where((i) => !keys.contains('${i.lang}/${i.code}')),
    ].take(_max).toList();
    _unseen = true;
    notifyListeners();
    await _save();
  }

  /// A message was opened: it is no longer news, so it leaves Notifications.
  Future<void> markRead(String code, String lang) async {
    await load();
    final before = _items.length;
    _items.removeWhere((i) => i.lang == lang && i.code.toUpperCase() == code.toUpperCase());
    if (_items.length == before) return;
    if (items.isEmpty) _unseen = false;
    notifyListeners();
    await _save();
  }

  /// The reader opened Notifications and saw the names: they are cleared (for the
  /// languages this profile reads), and the orange dot goes away.
  Future<List<NewsItem>> takeAll() async {
    await load();
    final shown = items;
    final english = appProfile.englishOnly;
    _items = english ? _items.where((i) => i.lang != 'en').toList() : [];
    _unseen = false;
    notifyListeners();
    await _save();
    return shown;
  }

  Future<void> _save() async {
    await Prefs.instance.set('news', jsonEncode(_items.map((i) => i.toJson()).toList()));
    await Prefs.instance.set('news_unseen', _unseen);
  }
}
