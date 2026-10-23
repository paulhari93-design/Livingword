import 'package:flutter/material.dart';

import '../data/bible.dart';

/// [ தமிழ் | English | Both ] switch used on the book list and in the reader.
class BibleModeSwitch extends StatelessWidget {
  const BibleModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BibleMode>(
      valueListenable: bibleMode,
      builder: (_, mode, __) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<BibleMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: BibleMode.tamil, label: Text('தமிழ்')),
              ButtonSegment(value: BibleMode.english, label: Text('English')),
              ButtonSegment(value: BibleMode.both, label: Text('Both')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => bibleMode.set(s.first),
          ),
        ),
      ),
    );
  }
}
