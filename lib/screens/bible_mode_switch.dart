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
            segments: [
              const ButtonSegment(value: BibleMode.tamil, label: Text('தமிழ்')),
              const ButtonSegment(value: BibleMode.english, label: Text('English')),
              ButtonSegment(
                value: BibleMode.both,
                // When "Both" is chosen, ⋮ inside it picks Normal or Split view.
                label: mode == BibleMode.both ? const _BothLabel() : const Text('Both'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => bibleMode.set(s.first),
          ),
        ),
      ),
    );
  }
}

/// "Both ⋮": the ⋮ opens Normal view / Split view.
class _BothLabel extends StatelessWidget {
  const _BothLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Both'),
        ValueListenableBuilder<bool>(
          valueListenable: bibleSplit,
          builder: (_, split, __) => PopupMenuButton<bool>(
            tooltip: 'View',
            padding: EdgeInsets.zero,
            iconSize: 20,
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: bibleSplit.set,
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: false,
                checked: !split,
                child: const Text('சாதாரண பார்வை / Normal view'),
              ),
              CheckedPopupMenuItem(
                value: true,
                checked: split,
                child: const Text('பிரிக்கப்பட்ட பார்வை / Split view'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
