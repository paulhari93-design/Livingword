import 'dart:convert';

import 'package:flutter/services.dart';

/// One book of the Bible, as listed in assets/bible/books.json.
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

/// Loads the Tamil Bible from assets (cached after first load).
/// Source: github.com/aruljohn/Bible-tamil (MIT licence).
class Bible {
  Bible._();
  static final Bible instance = Bible._();

  List<BibleBookInfo>? _books;
  final Map<int, List<List<String>>> _chapters = {}; // book -> chapters -> verses

  Future<List<BibleBookInfo>> books() async {
    if (_books != null) return _books!;
    final raw = await rootBundle.loadString('assets/bible/books.json');
    _books = (jsonDecode(raw) as List)
        .map((e) => BibleBookInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return _books!;
  }

  /// All chapters of a book; each chapter is a list of verse texts (verse 1 at index 0).
  Future<List<List<String>>> chapters(BibleBookInfo book) async {
    final cached = _chapters[book.number];
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/bible/${book.file}');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final list = (data['c'] as List).map((c) => (c as List).cast<String>()).toList();
    _chapters[book.number] = list;
    return list;
  }
}
