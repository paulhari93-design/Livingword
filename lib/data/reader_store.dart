import 'dart:convert';

import '../models/highlight.dart';
import 'prefs.dart';

/// Saves highlights and font size on the phone, so they survive
/// closing and reopening the app. (Phase 2 will also sync them to
/// the user's account in Firestore.)
class ReaderStore {
  static const _fontKey = 'font_size';
  static String _hlKey(String code) => 'highlights_$code';

  Future<double> loadFontSize() async {
    return (await Prefs.instance.getDouble(_fontKey)) ?? 20;
  }

  Future<void> saveFontSize(double size) async {
    await Prefs.instance.set(_fontKey, size);
  }

  Future<List<Highlight>> loadHighlights(String code) async {
    final raw = await Prefs.instance.getString(_hlKey(code));
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveHighlights(String code, List<Highlight> highlights) async {
    await Prefs.instance.set(
      _hlKey(code),
      jsonEncode(highlights.map((h) => h.toJson()).toList()),
    );
  }
}
