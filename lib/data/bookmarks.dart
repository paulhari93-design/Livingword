import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// A bookmarked place: a paragraph of a message, or a verse of the Bible.
class Bookmark {
  final String kind; // 'message' or 'bible'
  final String lang; // 'ta' / 'en'
  final String code; // message code, or the Bible book number
  final int place; // paragraph index (message) or chapter (Bible)
  final int verse; // Bible: verse index (0-based); message: unused (0)
  final String title; // "65-1204 The Rapture ¶12" / "John 3:16"
  final String snippet; // the start of the text
  final DateTime at;

  const Bookmark({
    required this.kind,
    required this.lang,
    required this.code,
    required this.place,
    this.verse = 0,
    required this.title,
    required this.snippet,
    required this.at,
  });

  String get id => '$kind|$lang|$code|$place|$verse';

  Map<String, dynamic> toJson() => {
        'k': kind, 'l': lang, 'c': code, 'p': place, 'v': verse,
        't': title, 's': snippet, 'a': at.millisecondsSinceEpoch,
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        kind: j['k'] as String? ?? 'message',
        lang: j['l'] as String? ?? 'ta',
        code: j['c'] as String? ?? '',
        place: (j['p'] as num?)?.toInt() ?? 0,
        verse: (j['v'] as num?)?.toInt() ?? 0,
        title: j['t'] as String? ?? '',
        snippet: j['s'] as String? ?? '',
        at: DateTime.fromMillisecondsSinceEpoch((j['a'] as num?)?.toInt() ?? 0),
      );
}

enum BookmarkResult { added, exists, full }

/// All bookmarks, newest first (Prefs 'bookmarks').
class BookmarkStore extends ChangeNotifier {
  BookmarkStore._();
  static final BookmarkStore instance = BookmarkStore._();

  List<Bookmark> _items = [];
  bool _loaded = false;

  Future<List<Bookmark>> all() async {
    if (!_loaded) {
      _loaded = true;
      try {
        final raw = await Prefs.instance.getString('bookmarks');
        if (raw != null) {
          _items = (jsonDecode(raw) as List).map((e) => Bookmark.fromJson(e as Map<String, dynamic>)).toList();
        }
      } catch (_) {}
    }
    return List.unmodifiable(_items);
  }

  Future<bool> contains(String id) async => (await all()).any((b) => b.id == id);

  /// At most this many bookmarks.
  static const max = 10;

  /// Adds the bookmark (not if it is already there, or there are [max] already).
  Future<BookmarkResult> add(Bookmark b) async {
    await all();
    if (_items.any((x) => x.id == b.id)) return BookmarkResult.exists;
    if (_items.length >= max) return BookmarkResult.full;
    _items.insert(0, b);
    await _save();
    return BookmarkResult.added;
  }

  /// The words shown after 🔖, in Tamil or English.
  static String message(BookmarkResult r, bool en) => switch (r) {
        BookmarkResult.added => en ? 'Bookmarked' : 'புக்மார்க் செய்யப்பட்டது',
        BookmarkResult.exists => en ? 'Already bookmarked' : 'ஏற்கனவே புக்மார்க் உள்ளது',
        BookmarkResult.full => en
            ? 'Only $max bookmarks are allowed. Delete one in ⋮ → Bookmarks & highlights.'
            : '$max புக்மார்க் மட்டுமே வைக்கலாம். ⋮ → புக்மார்க் & ஹைலைட் சென்று ஒன்றை நீக்கவும்.',
      };

  Future<void> remove(String id) async {
    await all();
    _items.removeWhere((b) => b.id == id);
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await Prefs.instance.set('bookmarks', jsonEncode(_items.map((b) => b.toJson()).toList()));
  }
}
