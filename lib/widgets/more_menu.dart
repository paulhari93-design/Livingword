import 'package:flutter/material.dart';

import '../screens/notes_screen.dart';
import '../theme/reading_theme.dart';

/// The ⋮ button at the right of the top bar: Theme, MyNotes, Save as PDF.
class MoreMenu extends StatelessWidget {
  const MoreMenu({super.key, this.onPdf, this.pdfLabel, this.showNotes = true});

  final VoidCallback? onPdf; // null = no PDF option on this screen
  final String? pdfLabel;
  final bool showNotes;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        switch (v) {
          case 'theme':
            showThemePicker(context);
          case 'notes':
            openNotes(context);
          case 'pdf':
            onPdf?.call();
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'theme',
          child: ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('தீம் / Theme'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (showNotes)
          const PopupMenuItem(
            value: 'notes',
            child: ListTile(
              leading: Icon(Icons.sticky_note_2_outlined),
              title: Text('MyNotes'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (onPdf != null)
          PopupMenuItem(
            value: 'pdf',
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(pdfLabel ?? 'PDF ஆக சேமி / Save as PDF'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}
