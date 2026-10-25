import 'package:flutter/material.dart';

/// [ தமிழ் | English ] switch for the messages (list and reader).
class MessageLangSwitch extends StatelessWidget {
  final String value; // 'ta' or 'en'
  final ValueChanged<String> onChanged;

  const MessageLangSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'ta', label: Text('தமிழ்')),
            ButtonSegment(value: 'en', label: Text('English')),
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
