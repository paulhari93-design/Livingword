import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/highlight.dart';

/// Saves highlights and font size on the phone, so they survive
/// closing and reopening the app. (Phase 2 will also sync them to
/// the user's account in Firestore.)
class ReaderStore {
  static const _fontKey = 'font_size';
  static String _hlKey(String code) => 'highlights_$code';

  Future<double> loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_fontKey) ?? 20;
  }

  Future<void> saveFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontKey, size);
  }

  Future<List<Highlight>> loadHighlights(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hlKey(code));
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveHighlights(String code, List<Highlight> highlights) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _hlKey(code),
      jsonEncode(highlights.map((h) => h.toJson()).toList()),
    );
  }
}
