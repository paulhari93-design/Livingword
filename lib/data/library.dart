import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/message.dart';
import 'local_files.dart';
import 'prefs.dart';

/// Folder on the phone for each language: Tamil in messages/, English in messages_en/.
String messageFolder(String lang) => lang == 'en' ? 'messages_en' : 'messages';

/// The chosen message language ('ta' or 'en'), shared by the list and the reader, and remembered.
class MessageLangController extends ValueNotifier<String> {
  MessageLangController() : super('ta') {
    _load();
  }
  static const _key = 'message_lang';

  Future<void> _load() async {
    final saved = await Prefs.instance.getString(_key);
    if (saved == 'ta' || saved == 'en') value = saved!;
  }

  Future<void> set(String lang) async {
    value = lang;
    await Prefs.instance.set(_key, lang);
  }
}

final messageLang = MessageLangController();

/// In "Both": true = split view (Tamil above, English below, each scrolling),
/// false = normal view (each Tamil paragraph with its English under it). Remembered.
class MessageSplitController extends ValueNotifier<bool> {
  MessageSplitController() : super(true) {
    _load();
  }
  static const _key = 'message_split';

  Future<void> _load() async {
    final saved = await Prefs.instance.getBool(_key);
    if (saved != null) value = saved;
  }

  Future<void> set(bool split) async {
    value = split;
    await Prefs.instance.set(_key, split);
  }
}

final messageSplit = MessageSplitController();

/// One place where a search word was found.
class SearchHit {
  final MessageInfo info;
  final int paragraph;
  final String text; // the paragraph text
  final int matchStart; // where the first match starts in [text]
  final int count; // how many times it appears in this paragraph

  const SearchHit({
    required this.info,
    required this.paragraph,
    required this.text,
    required this.matchStart,
    required this.count,
  });
}

/// Loads the message catalog and message texts (cached after first load).
class Library {
  Library._();
  static final Library instance = Library._();

  final Map<String, List<MessageInfo>> _catalogs = {}; // lang -> list
  final Map<String, Message> _messages = {}; // 'lang/code' -> message

  /// Forget cached data (after a download/sync) so the next read uses the new files.
  void reload() {
    _catalogs.clear();
    _messages.clear();
  }

  /// Messages downloaded to this phone, in [lang] (default: the chosen language).
  Future<List<MessageInfo>> catalog({String? lang}) async {
    final l = (lang ?? messageLang.value) == 'en' ? 'en' : 'ta'; // 'both' lists the Tamil titles
    final cached = _catalogs[l];
    if (cached != null) return cached;
    List? list;
    try {
      list = (await LocalFiles.instance.readJson('${messageFolder(l)}/index.json')) as List?;
    } catch (_) {}
    final result = (list ?? const [])
        .map((e) => MessageInfo.fromJson(e as Map<String, dynamic>, lang: l))
        .toList();
    _catalogs[l] = result;
    return result;
  }

  /// The same message in another language, if it is on the phone.
  Future<MessageInfo?> find(String code, String lang) async {
    final list = await catalog(lang: lang);
    for (final m in list) {
      if (m.code.toUpperCase() == code.toUpperCase()) return m;
    }
    return null;
  }

  Future<Message> message(MessageInfo info) async {
    final key = '${info.lang}/${info.code}';
    final cached = _messages[key];
    if (cached != null) return cached;
    final raw = await LocalFiles.instance.readString('${messageFolder(info.lang)}/${info.file}');
    final m = Message.fromJson(jsonDecode(raw!) as Map<String, dynamic>, lang: info.lang);
    _messages[key] = m;
    return m;
  }

  /// Finds every paragraph containing [query] (Tamil or English).
  Future<List<SearchHit>> search(String query, {MessageInfo? only, String? lang}) async {
    final q = normalizeQuery(query);
    if (q.isEmpty) return [];
    final infos = only != null ? [only] : await catalog(lang: lang);
    final hits = <SearchHit>[];
    for (final info in infos) {
      final m = await message(info);
      for (var i = 0; i < m.paragraphs.length; i++) {
        final matches = findMatches(m.paragraphs[i], q);
        if (matches.isNotEmpty) {
          hits.add(SearchHit(
            info: info,
            paragraph: i,
            text: m.paragraphs[i],
            matchStart: matches.first,
            count: matches.length,
          ));
        }
      }
    }
    return hits;
  }
}

/// Trims the query and squeezes repeated spaces.
String normalizeQuery(String q) => q.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Start positions of every match of [q] (already normalized) in [text].
List<int> findMatches(String text, String q) {
  if (q.isEmpty) return const [];
  final hay = text.toLowerCase();
  final result = <int>[];
  var from = 0;
  while (true) {
    final i = hay.indexOf(q, from);
    if (i < 0) break;
    result.add(i);
    from = i + q.length;
  }
  return result;
}
