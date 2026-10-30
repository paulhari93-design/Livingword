import 'package:flutter/material.dart';

import '../data/bible.dart';
import '../data/bookmarks.dart';
import '../data/library.dart';
import '../data/prefs.dart';
import '../data/profile.dart';
import '../data/reader_store.dart';
import '../l10n.dart';
import '../models/highlight.dart';
import 'bible_reader_screen.dart';
import 'reader_screen.dart';

/// ⋮ → Bookmarks & highlights: every bookmark, and every highlight in all messages
/// and the Bible, in one place. Tap one to go straight there.
class MarksScreen extends StatelessWidget {
  const MarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Tr('புக்மார்க் & ஹைலைட் / Bookmarks & highlights'),
          bottom: TabBar(tabs: [
            Tab(icon: const Icon(Icons.bookmark_outline), text: tr('புக்மார்க் / Bookmarks')),
            Tab(icon: const Icon(Icons.border_color_outlined), text: tr('ஹைலைட் / Highlights')),
          ]),
        ),
        body: const TabBarView(children: [_BookmarksTab(), _HighlightsTab()]),
      ),
    );
  }
}

/// Opens a message at a paragraph, or the Bible at a verse.
Future<void> _openPlace(BuildContext context,
    {required String kind, required String lang, required String code, required int place, int verse = 0}) async {
  if (kind == 'bible') {
    final books = await Bible.instance.books();
    final n = int.tryParse(code);
    BibleBookInfo? book;
    for (final b in books) {
      if (b.number == n) book = b;
    }
    if (book == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BibleReaderScreen(book: book!, initialChapter: place, initialVerse: verse + 1),
    ));
    return;
  }
  final info = await Library.instance.find(code, lang);
  if (info == null || !context.mounted) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Tr('இந்தச் செய்தி இப்போது இல்லை / This message is no longer available')),
      );
    }
    return;
  }
  final message = await Library.instance.message(info);
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ReaderScreen(message: message, initialParagraph: place, flashParagraph: true),
  ));
}

/// Asks before deleting; true = delete.
Future<bool> _confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Tr('நீக்கவா? / Delete?'),
      content: Text(what, maxLines: 4, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Tr('வேண்டாம் / Cancel')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          icon: const Icon(Icons.delete_outline),
          onPressed: () => Navigator.pop(ctx, true),
          label: const Tr('நீக்கு / Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The 🗑 button at the end of each row.
Widget _deleteButton(VoidCallback onPressed) => IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: tr('நீக்கு / Delete'),
      onPressed: onPressed,
    );

class _BookmarksTab extends StatelessWidget {
  const _BookmarksTab();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: BookmarkStore.instance,
      builder: (context, _) => FutureBuilder<List<Bookmark>>(
        future: BookmarkStore.instance.all(),
        builder: (context, snap) {
          var list = snap.data;
          if (list == null) return const Center(child: CircularProgressIndicator());
          if (appProfile.englishOnly) list = list.where((b) => b.lang == 'en').toList();
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Tr(
                  'புக்மார்க் இன்னும் இல்லை. ஒரு வரியைத் தொட்டு 🔖 அழுத்தவும்.\n\n'
                  'No bookmarks yet. Tap a line, then 🔖.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          Future<void> delete(Bookmark b) async {
            if (await _confirmDelete(context, b.title)) BookmarkStore.instance.remove(b.id);
          }

          return ListView.separated(
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) {
                // How many of the 10 are used.
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Text(
                    '${list!.length} / ${BookmarkStore.max} · ${tr('நீக்க 🗑 அழுத்தவும் அல்லது இருமுறை தொடவும் / Tap 🗑 or double-tap to delete')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              final b = list![i - 1];
              return Dismissible(
                key: ValueKey(b.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red.shade400,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (_) => _confirmDelete(context, b.title),
                onDismissed: (_) => BookmarkStore.instance.remove(b.id),
                child: GestureDetector(
                  onDoubleTap: () => delete(b),
                  child: ListTile(
                  leading: Icon(b.kind == 'bible' ? Icons.menu_book_rounded : Icons.bookmark,
                      color: Theme.of(context).colorScheme.primary),
                  title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(b.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: _deleteButton(() => delete(b)),
                  onTap: () => _openPlace(context,
                      kind: b.kind, lang: b.lang, code: b.code, place: b.place, verse: b.verse),
                  onLongPress: () => delete(b),
                ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One highlight and where it is.
class _Mark {
  final String kind, lang, code, source;
  final int place, verse;
  final Highlight h;
  final String storeId; // where it is saved (ReaderStore)
  const _Mark(this.kind, this.lang, this.code, this.place, this.verse, this.source, this.h, this.storeId);
}

class _HighlightsTab extends StatefulWidget {
  const _HighlightsTab();

  @override
  State<_HighlightsTab> createState() => _HighlightsTabState();
}

class _HighlightsTabState extends State<_HighlightsTab> {
  List<_Mark>? _marks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ReaderStore();
    final books = {for (final b in await Bible.instance.books()) b.number: b};
    final english = appProfile.englishOnly;
    final out = <_Mark>[];
    final keys = (await Prefs.instance.keys()).where((k) => k.startsWith('highlights_')).toList()..sort();
    for (final key in keys) {
      final id = key.substring('highlights_'.length);
      List<Highlight> list;
      try {
        list = await store.loadHighlights(id);
      } catch (_) {
        continue;
      }
      if (list.isEmpty) continue;
      final bible = RegExp(r'^bible_(ta|en)_(\d+)_(\d+)$').firstMatch(id);
      if (bible != null) {
        final lang = bible.group(1)!;
        if (english && lang != 'en') continue;
        final book = books[int.parse(bible.group(2)!)];
        final ch = int.parse(bible.group(3)!);
        final name = book == null ? '' : (lang == 'en' ? book.english : book.tamil);
        for (final h in list) {
          out.add(_Mark('bible', lang, bible.group(2)!, ch, h.paragraph, '$name $ch:${h.paragraph + 1}', h, id));
        }
        continue;
      }
      final lang = id.startsWith('en_') ? 'en' : 'ta';
      if (english && lang != 'en') continue;
      final code = lang == 'en' ? id.substring(3) : id;
      final info = await Library.instance.find(code, lang);
      final title = info == null ? code : '${info.code} ${info.title}';
      for (final h in list) {
        out.add(_Mark('message', lang, code, h.paragraph, 0, title, h, id));
      }
    }
    if (mounted) setState(() => _marks = out);
  }

  Future<void> _delete(_Mark m) async {
    final words = (m.h.text ?? '').trim();
    if (!await _confirmDelete(context, words.isEmpty ? m.source : '“$words”\n— ${m.source}')) return;
    final store = ReaderStore();
    final list = await store.loadHighlights(m.storeId);
    list.removeWhere((h) =>
        h.paragraph == m.h.paragraph && h.start == m.h.start && h.end == m.h.end && h.style == m.h.style);
    await store.saveHighlights(m.storeId, list);
    HighlightEvents.instance.changed(m.storeId); // an open message / chapter updates too
    if (mounted) setState(() => _marks?.remove(m));
  }

  @override
  Widget build(BuildContext context) {
    final marks = _marks;
    if (marks == null) return const Center(child: CircularProgressIndicator());
    if (marks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Tr('ஹைலைட் இன்னும் இல்லை. / No highlights yet.', textAlign: TextAlign.center),
        ),
      );
    }
    final theme = Theme.of(context);
    return ListView.separated(
      itemCount: marks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = marks[i];
        final h = m.h;
        final words = (h.text ?? '').trim();
        return GestureDetector(
          onDoubleTap: () => _delete(m),
          child: ListTile(
          leading: h.style == MarkStyle.color
              ? CircleAvatar(radius: 10, backgroundColor: h.color.color)
              : Icon(h.style == MarkStyle.bold ? Icons.format_bold : Icons.format_underlined),
          title: Text(words.isEmpty ? '…' : words, maxLines: 3, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            m.kind == 'bible' ? m.source : '${m.source} · ${m.lang == 'en' ? 'English' : 'தமிழ்'}',
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _deleteButton(() => _delete(m)),
          onTap: () => _openPlace(context, kind: m.kind, lang: m.lang, code: m.code, place: m.place, verse: m.verse),
          onLongPress: () => _delete(m),
        ),
        );
      },
    );
  }
}
