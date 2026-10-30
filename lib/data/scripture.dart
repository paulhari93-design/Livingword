import 'bible.dart';

/// A Bible reference found in a message, e.g. "Hebrews 13:8" or "எபி. 13:8".
class ScriptureRef {
  final int start; // characters in the paragraph
  final int end;
  final int book; // 1..66
  final int chapter;
  final int verse;
  final int lastVerse; // = verse for a single verse
  const ScriptureRef(this.start, this.end, this.book, this.chapter, this.verse, this.lastVerse);
}

/// Finds Bible references in message paragraphs (English and Tamil, full names and the
/// usual short forms such as "St. John", "I Corinthians", "வெளி.", "மத்.").
class ScriptureFinder {
  ScriptureFinder._(this._english, this._tamil);

  static ScriptureFinder? _instance;

  /// Built once, from the Bible's book list on the phone.
  static Future<ScriptureFinder?> get() async {
    if (_instance != null) return _instance;
    final books = await Bible.instance.books();
    if (books.isEmpty) return null;
    final en = <String, int>{};
    final ta = <String, int>{};
    for (final b in books) {
      en[_key(b.english)] = b.number;
      ta[_taKey(b.tamil)] = b.number;
    }
    // English names as Brother Branham said them.
    const extraEn = {
      'psalm': 19, 'revelations': 66, 'song of solomon': 22, 'songs': 22, 'canticles': 22,
      'saint john': 43, 'st john': 43, 'saint matthew': 40, 'st matthew': 40, 'saint mark': 41,
      'st mark': 41, 'saint luke': 42, 'st luke': 42, 'the acts': 44, 'acts of the apostles': 44,
      'revelation of jesus christ': 66,
    };
    en.addAll(extraEn);
    // Tamil short forms used in the translations.
    const extraTa = {
      'லூக்கா': 42, 'லூக்': 42, 'மத்': 40, 'மாற்': 41, 'யோ': 43, 'யோவா': 43, 'அப்': 44,
      'அப்போஸ்தலர்': 44, 'அப்போ': 44, 'வெளி': 66, 'வெளிப்படுத்தல்': 66, 'எபி': 58, 'எபே': 49,
      'எசே': 26, 'ஏசா': 23, 'ஆதி': 1, 'யாத்': 2, 'லேவி': 3, 'எண்': 4, 'உபா': 5, 'சங்': 19,
      'சங்கீதங்கள்': 19, 'நீதி': 20, 'பிர': 21, 'எரே': 24, 'தானி': 27, 'சக': 38, 'மல்': 39,
      'கலா': 48, 'பிலி': 50, 'கொலோ': 51, 'யாக்': 59, 'ரோ': 45, 'தீத்': 56,
    };
    ta.addAll(extraTa);
    return _instance = ScriptureFinder._(en, ta);
  }

  final Map<String, int> _english; // "1 corinthians" -> 46
  final Map<String, int> _tamil; // "1 கொரிந்தியர்" -> 46

  static String _key(String s) => s.toLowerCase().replaceAll('.', '').replaceAll(RegExp(r'\s+'), ' ').trim();
  static String _taKey(String s) =>
      s.replaceAll('லுூ', 'லூ').replaceAll('.', '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static final _enRe = RegExp(
    r"\b((?:[123]|I{1,3}|First|Second|Third|1st|2nd|3rd)\s+)?((?:St\.?|Saint)\s+)?"
    r"([A-Z][a-z]+(?:\s+of\s+[A-Z][a-z]+)?)\s+(\d{1,3}):(\d{1,3})(?:\s*[-–]\s*(\d{1,3}))?",
  );
  static final _taRe = RegExp(
    r"((?:[123]\s?))?((?:பரிசுத்த|பரி\.)\s?)?([஀-௿]+(?:\s[஀-௿]+)?)\.?"
    r"\s?(\d{1,3})\s?:\s?(\d{1,3})(?:\s?[-–]\s?(\d{1,3}))?",
  );

  static int? _number(String? s) {
    if (s == null) return null;
    final t = s.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t == '1' || t == 'i' || t == 'first' || t == '1st') return 1;
    if (t == '2' || t == 'ii' || t == 'second' || t == '2nd') return 2;
    if (t == '3' || t == 'iii' || t == 'third' || t == '3rd') return 3;
    return null;
  }

  int? _englishBook(String? numberPart, String? saint, String name) {
    final n = _number(numberPart);
    final base = _key(name);
    if (n != null) return _english['$n $base'];
    if (saint != null) return _english['saint $base'] ?? _english[base];
    return _english[base];
  }

  int? _tamilBook(String? numberPart, String name) {
    final n = _number(numberPart);
    var base = _taKey(name);
    // "இப்பொழுது ஆதியாகமம் 2:7": try the last word alone when two words don't match.
    for (var attempt = 0; attempt < 2; attempt++) {
      final full = n != null ? '$n $base' : base;
      final hit = _tamil[full];
      if (hit != null) return hit;
      // A short form: the start of exactly one book name ("தெச" -> தெசலோனிக்கேயர்).
      if (base.length >= 2) {
        final matches = <int>{};
        _tamil.forEach((k, v) {
          final kn = k.startsWith(RegExp(r'[123] ')) ? int.parse(k[0]) : null;
          final kb = kn != null ? k.substring(2) : k;
          if (kn == n && kb.startsWith(base)) matches.add(v);
        });
        if (matches.length == 1) return matches.first;
      }
      final parts = base.split(' ');
      if (parts.length < 2) break;
      base = parts.last;
    }
    return null;
  }

  List<ScriptureRef> find(String text) {
    final out = <ScriptureRef>[];
    for (final m in _enRe.allMatches(text)) {
      final book = _englishBook(m.group(1), m.group(2), m.group(3)!);
      if (book == null) continue;
      final ch = int.parse(m.group(4)!), v = int.parse(m.group(5)!);
      final last = m.group(6) != null ? int.parse(m.group(6)!) : v;
      out.add(ScriptureRef(m.start, m.end, book, ch, v, last < v ? v : last));
    }
    for (final m in _taRe.allMatches(text)) {
      final book = _tamilBook(m.group(1), m.group(3)!);
      if (book == null) continue;
      final ch = int.parse(m.group(4)!), v = int.parse(m.group(5)!);
      final last = m.group(6) != null ? int.parse(m.group(6)!) : v;
      // Underline only the reference itself, not a word in front of it ("இப்பொழுது").
      var start = m.start;
      final words = m.group(3)!.split(' ');
      if (words.length == 2 && _tamil[_taKey(m.group(3)!)] == null && m.group(1) == null && m.group(2) == null) {
        start = m.start + m.group(0)!.indexOf(words.last);
      }
      out.add(ScriptureRef(start, m.end, book, ch, v, last < v ? v : last));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }
}
