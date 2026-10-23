import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_files.dart';

/// One book of the Bible, as listed in bible/books.json.
class BibleBookInfo {
  final int number; // 1..66
  final String english;
  final String tamil;
  final int chapterCount;
  final String file;

  const BibleBookInfo({
    required this.number,
    required this.english,
    required this.tamil,
    required this.chapterCount,
    required this.file,
  });

  bool get isOldTestament => number <= 39;

  factory BibleBookInfo.fromJson(Map<String, dynamic> j) => BibleBookInfo(
        number: j['n'] as int,
        english: j['en'] as String,
        tamil: j['ta'] as String,
        chapterCount: j['ch'] as int,
        file: j['f'] as String,
      );

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return tamil.contains(q) || english.toLowerCase().contains(q);
  }
}

/// Which Bible text to show.
enum BibleLang { tamil, english }

/// How the reader shows the text: Tamil, English (KJV), or both under each other.
enum BibleMode { tamil, english, both }

/// The chosen Bible language, shared by the book list and the reader, and remembered.
class BibleModeController extends ValueNotifier<BibleMode> {
  BibleModeController() : super(BibleMode.tamil) {
    _load();
  }
  static const _key = 'bible_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      value = BibleMode.values.firstWhere((m) => m.name == saved, orElse: () => BibleMode.tamil);
    } catch (_) {}
  }

  Future<void> set(BibleMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }
}

final bibleMode = BibleModeController();

/// Loads the downloaded Tamil Bible and English KJV from the phone (cached after first load).
/// Sources: github.com/aruljohn/Bible-tamil and github.com/aruljohn/Bible-kjv (MIT licence).
class Bible {
  Bible._();
  static final Bible instance = Bible._();

  List<BibleBookInfo>? _books;
  final Map<String, List<List<String>>> _chapters = {}; // 'lang-book' -> chapters -> verses

  Future<List<BibleBookInfo>> books() async {
    if (_books != null) return _books!;
    final raw = await LocalFiles.instance.readString('bible/books.json');
    if (raw == null) return const [];
    _books = (jsonDecode(raw) as List)
        .map((e) => BibleBookInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return _books!;
  }

  /// All chapters of a book; each chapter is a list of verse texts (verse 1 at index 0).
  Future<List<List<String>>> chapters(BibleBookInfo book, [BibleLang lang = BibleLang.tamil]) async {
    final key = '${lang.name}-${book.number}';
    final cached = _chapters[key];
    if (cached != null) return cached;
    final folder = lang == BibleLang.tamil ? 'bible/ta' : 'bible/en';
    final raw = await LocalFiles.instance.readString('$folder/${book.file}');
    if (raw == null) return const [];
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final list = (data['c'] as List).map((c) => (c as List).cast<String>()).toList();
    _chapters[key] = list;
    return list;
  }
}
