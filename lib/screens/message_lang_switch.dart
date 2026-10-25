import 'package:flutter/material.dart';

import '../data/library.dart';

/// [ தமிழ் | English ] switch for the messages (list and reader).
class MessageLangSwitch extends StatelessWidget {
  final String value; // 'ta', 'en' or 'both'
  final ValueChanged<String> onChanged;
  final bool showBoth; // offer Tamil above / English below

  const MessageLangSwitch({super.key, required this.value, required this.onChanged, this.showBoth = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: 'ta', label: Text('தமிழ்')),
            const ButtonSegment(value: 'en', label: Text('English')),
            if (showBoth)
              ButtonSegment(
                value: 'both',
                // When "Both" is chosen, ⋮ inside it picks Normal or Split view.
                label: value == 'both' ? const _BothLabel() : const Text('Both'),
              ),
          ],
          selected: {value},
          onSelectionChanged: (s) {
            if (s.first != value) onChanged(s.first);
          },
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
          valueListenable: messageSplit,
          builder: (_, split, __) => PopupMenuButton<bool>(
            tooltip: 'View',
            padding: EdgeInsets.zero,
            iconSize: 20,
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: messageSplit.set,
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
