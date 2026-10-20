/// One entry in assets/messages/index.json (the catalog used for search).
class MessageInfo {
  final String code; // e.g. 47-0508 = year 47, month 05, day 08
  final String title;
  final String file;

  const MessageInfo({required this.code, required this.title, required this.file});

  factory MessageInfo.fromJson(Map<String, dynamic> j) => MessageInfo(
        code: j['code'] as String,
        title: j['title'] as String,
        file: j['file'] as String,
      );

  /// Matches "47-0508", "470508", "47 05 08", part of a code, or part of the title.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final codeDigits = code.replaceAll(RegExp(r'\D'), '');
    if (qDigits.isNotEmpty && codeDigits.contains(qDigits)) return true;
    return title.toLowerCase().contains(q);
  }
}

/// A full message: its paragraphs of text.
class Message {
  final String code;
  final String title;
  final List<String> paragraphs;

  const Message({required this.code, required this.title, required this.paragraphs});

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        code: j['code'] as String,
        title: j['title'] as String,
        paragraphs: (j['paragraphs'] as List).cast<String>(),
      );
}
