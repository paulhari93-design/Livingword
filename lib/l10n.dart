import 'package:flutter/material.dart';

import 'data/profile.dart';

final _tamil = RegExp(r'[஀-௿]');

/// The language of the screens opened from ⋮ in a Tamil or English tab ('ta' / 'en'):
/// they show only that language. null = both.
final screenLang = ValueNotifier<String?>(null);

/// Opens [screen] in [lang] ('ta' / 'en'): its words (and of anything opened from it)
/// are in that language only, until it is closed.
Future<T?> pushInLang<T>(BuildContext context, String lang, Widget screen) async {
  final before = screenLang.value;
  screenLang.value = lang;
  try {
    return await Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));
  } finally {
    screenLang.value = before;
  }
}

/// Screen text is written "தமிழ் / English" (or a Tamil line, then an English line).
/// With the English-only profile (or an English screen) only the English part is shown;
/// on a Tamil screen only the Tamil part.
String tr(String s) {
  final lang = appProfile.englishOnly ? 'en' : screenLang.value;
  if (lang == null || !_tamil.hasMatch(s)) return s;
  if (lang == 'ta') return _tamilPart(s);
  final lines = <String>[];
  for (final line in s.split('\n')) {
    if (!_tamil.hasMatch(line)) {
      lines.add(line);
      continue;
    }
    final parts = line.split(' / ').where((p) => !_tamil.hasMatch(p)).toList();
    if (parts.isNotEmpty) lines.add(parts.join(' / '));
  }
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  return lines.join('\n').trim();
}

String _tamilPart(String s) {
  final lines = <String>[];
  for (final line in s.split('\n')) {
    if (line.trim().isEmpty) {
      lines.add(line);
      continue;
    }
    if (!_tamil.hasMatch(line)) continue; // the English line under a Tamil one
    final parts = line.split(' / ').where((p) => _tamil.hasMatch(p)).toList();
    lines.add(parts.join(' / '));
  }
  return lines.join('\n').trim();
}

/// A Text that follows the profile (see [tr]).
class Tr extends StatelessWidget {
  const Tr(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([appProfile, screenLang]),
        builder: (_, __) =>
            Text(tr(text), style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow),
      );
}
