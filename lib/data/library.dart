import 'dart:convert';

import '../models/message.dart';
import 'local_files.dart';

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

  List<MessageInfo>? _catalog;
  final Map<String, Message> _messages = {};

  /// Forget cached data (after a download/sync) so the next read uses the new files.
  void reload() {
    _catalog = null;
    _messages.clear();
  }

  /// Messages downloaded to this phone.
  Future<List<MessageInfo>> catalog() async {
    if (_catalog != null) return _catalog!;
    final list = (await LocalFiles.instance.readJson('messages/index.json')) as List?;
    _catalog = (list ?? const [])
        .map((e) => MessageInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return _catalog!;
  }

  Future<Message> message(MessageInfo info) async {
    final cached = _messages[info.code];
    if (cached != null) return cached;
    final raw = await LocalFiles.instance.readString('messages/${info.file}');
    final m = Message.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
    _messages[info.code] = m;
    return m;
  }

  /// Finds every paragraph containing [query] (Tamil or English).
  Future<List<SearchHit>> search(String query, {MessageInfo? only}) async {
    final q = normalizeQuery(query);
    if (q.isEmpty) return [];
    final infos = only != null ? [only] : await catalog();
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
