import 'dart:async';

import 'package:flutter/material.dart';

import '../data/notes.dart';
import '../services/pdf_export.dart';
import '../widgets/more_menu.dart';
import 'section_switch.dart';
import '../l10n.dart';

/// Opens MyNotes.
void openNotes(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotesScreen()));
}

/// Adds a quote (with its reference) to the prepared note.
/// If no note is prepared yet, asks which note to use.
Future<void> sendToNotes(BuildContext context, String quote, String reference) async {
  final store = NotesStore.instance;
  await store.load();
  if (!context.mounted) return;
  var note = store.active;
  if (note == null) {
    note = await _pickNote(context);
    if (note == null) return;
    await store.setActive(note);
  }
  await store.append(note, quote, reference);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Tr('குறிப்பில் சேர்க்கப்பட்டது / Added to "${note.title}"'),
    duration: const Duration(seconds: 2),
  ));
}

/// Lets the user choose a note (or make a new one) to send quotes to.
Future<Note?> _pickNote(BuildContext context) async {
  final store = NotesStore.instance;
  return showModalBottomSheet<Note>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Tr('எந்த குறிப்பில் சேர்க்க? / Add to which note?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final (i, n) in store.notes.indexed)
            ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(n.title),
              onTap: () => Navigator.of(ctx).pop(n),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Tr('புதிய குறிப்பு / New note'),
            onTap: () async {
              final title = await _askTitle(ctx);
              if (title == null) return;
              final n = await store.create(title);
              if (ctx.mounted) Navigator.of(ctx).pop(n);
            },
          ),
        ],
      ),
    ),
  );
}

/// PDF blocks for one note: its title, then its text line by line.
/// Lines that start with "—" (references of sent quotes) are shown in grey italics.
List<PdfBlock> _noteBlocks(Note n) {
  final blocks = <PdfBlock>[
    PdfBlock(TextSpan(text: n.title, style: PdfExport.title), align: TextAlign.center, lineBelow: true),
  ];
  for (final line in n.body.split('\n')) {
    final isRef = line.trimLeft().startsWith('—');
    blocks.add(PdfBlock(
      TextSpan(
        text: line.isEmpty ? ' ' : line,
        style: isRef
            ? PdfExport.body.copyWith(fontStyle: FontStyle.italic, color: const Color(0xFF555555))
            : PdfExport.body,
      ),
      spaceAfter: line.trim().isEmpty ? 0 : 2,
    ));
  }
  return blocks;
}

/// Asks for a note title. Returns null if cancelled.
Future<String?> _askTitle(BuildContext context, {String initial = '', bool rename = false}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(rename ? 'பெயர் மாற்று / Rename' : 'புதிய குறிப்பு / New note')),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: tr('தலைப்பு / Title')),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
        },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Tr('ரத்து / Cancel')),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.of(ctx).pop(v);
          },
          child: Text(tr(rename ? 'சேமி / Save' : 'உருவாக்கு / Create')),
        ),
      ],
    ),
  );
}

/// The list of notes: 1, 2, 3 …
/// Tap = open. Double tap or long press = options (prepare, rename, delete).
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _store = NotesStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    if (_store.notes.length >= NotesStore.maxNotes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Tr('அதிகபட்சம் 50 குறிப்புகள் / You can keep up to 50 notes')));
      return;
    }
    final title = await _askTitle(context);
    if (title != null) await _store.create(title);
  }

  void _open(Note n) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(note: n)));
  }

  Future<void> _options(Note n) async {
    final isActive = _store.active?.id == n.id;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(n.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: Icon(isActive ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(tr(isActive
                  ? 'தயாரிப்பை நிறுத்து / Stop preparing this note'
                  : 'இந்த குறிப்பை தயார் செய் / Prepare this note')),
              subtitle: isActive
                  ? null
                  : const Tr('வசனங்களும் மேற்கோள்களும் இதில் சேர்க்கப்படும்\n'
                      'Verses and quotes you send will be added here'),
              onTap: () => Navigator.of(ctx).pop('prepare'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Tr('பெயர் மாற்று / Rename'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Tr('நீக்கு / Delete'),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'prepare':
        await _store.setActive(isActive ? null : n);
        if (!mounted || isActive) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Tr('"${n.title}" தயார். வேதாகமம் அல்லது செய்தியில் வரியைத் தட்டி 📝 அழுத்தவும்.\n'
              'Ready. In the Bible or a message, tap a line, then 📝.'),
          duration: const Duration(seconds: 4),
        ));
      case 'rename':
        final t = await _askTitle(context, initial: n.title, rename: true);
        if (t != null) await _store.update(n, title: t);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Tr('"${n.title}" நீக்கவா? / Delete?'),
            content: const Tr('இதை திரும்பப் பெற முடியாது. / This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Tr('ரத்து / Cancel')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Tr('நீக்கு / Delete')),
            ],
          ),
        );
        if (ok == true) await _store.delete(n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = _store.notes;
    final activeId = _store.active?.id;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyNotes'),
        actions: [
          const GoToBibleButton(),
          const GoToMessagesButton(),
          MoreMenu(
            showNotes: false,
            pdfLabel: 'எல்லா குறிப்புகளும் PDF ஆக / All notes as PDF',
            onPdf: () {
              if (notes.isEmpty) return;
              PdfExport.saveWithMessages(
                context,
                fileName: 'MyNotes.pdf',
                blocks: [
                  for (final (i, n) in notes.indexed) ...[
                    if (i > 0) const PdfBlock(TextSpan(text: ' '), spaceAfter: 24),
                    ..._noteBlocks(n),
                  ],
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: Tr('புதிய குறிப்பு / New note  (${notes.length}/${NotesStore.maxNotes})'),
              ),
            ),
          ),
          Expanded(
            child: notes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Tr(
                        'குறிப்புகள் இல்லை. ＋ அழுத்தி புதிய குறிப்பை உருவாக்கவும்.\n\n'
                        'No notes yet. Tap + to make one.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: notes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = notes[i];
                      final active = n.id == activeId;
                      return InkWell(
                        onTap: () => _open(n),
                        onDoubleTap: () => _options(n),
                        onLongPress: () => _options(n),
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: n.body.trim().isEmpty
                              ? null
                              : Text(n.body.trim(), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: active
                              ? Chip(
                                  avatar: Icon(Icons.push_pin, size: 16, color: theme.colorScheme.primary),
                                  label: const Tr('தயார் / Ready'),
                                  visualDensity: VisualDensity.compact,
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One note: tap the title to rename; the text is saved as you type.
class NoteEditorScreen extends StatefulWidget {
  final Note note;
  const NoteEditorScreen({super.key, required this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final _controller = TextEditingController(text: widget.note.body);
  Timer? _timer;
  final _store = NotesStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_external);
  }

  /// A quote was added from elsewhere: show it.
  void _external() {
    if (!mounted) return;
    if (_controller.text != widget.note.body && _timer == null) {
      _controller.text = widget.note.body;
    }
    setState(() {});
  }

  void _changed(String v) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), _save);
  }

  void _save() {
    _timer?.cancel();
    _timer = null;
    if (_controller.text != widget.note.body) {
      _store.update(widget.note, body: _controller.text);
    }
  }

  @override
  void dispose() {
    _save();
    _store.removeListener(_external);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () async {
            final t = await _askTitle(context, initial: n.title, rename: true);
            if (t != null) await _store.update(n, title: t);
          },
          child: Text(n.title, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          const GoToBibleButton(),
          const GoToMessagesButton(),
          MoreMenu(
            showNotes: false,
            onPdf: () {
              _save();
              PdfExport.saveWithMessages(
                context,
                fileName: PdfExport.fileName(n.title),
                blocks: _noteBlocks(n),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _controller,
            onChanged: _changed,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 18, height: 1.6),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: tr('இங்கே எழுதுங்கள்… / Write here…'),
            ),
          ),
        ),
      ),
    );
  }
}
