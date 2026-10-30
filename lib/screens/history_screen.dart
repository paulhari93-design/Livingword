import 'package:flutter/material.dart';

import '../data/library.dart';
import '../data/profile.dart';
import '../data/progress.dart';
import '../l10n.dart';
import 'reader_screen.dart';

/// ⋮ → வரலாறு / History: how many messages have been read, and every message
/// opened with how far it is read and how many times it was read to the end.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _Row {
  final HistoryEntry e;
  final String title;
  const _Row(this.e, this.title);
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<_Row>? _rows;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    ReadingProgress.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    ReadingProgress.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    await ReadingProgress.instance.load();
    final english = appProfile.englishOnly;
    final rows = <_Row>[];
    for (final e in ReadingProgress.instance.entries()) {
      if (english && e.lang != 'en') continue;
      final info = await Library.instance.find(e.code, e.lang);
      if (info == null) continue; // no longer on the phone
      rows.add(_Row(e, info.title));
    }
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _open(HistoryEntry e) async {
    final info = await Library.instance.find(e.code, e.lang);
    if (info == null || !mounted) return;
    final message = await Library.instance.message(info);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(message: message, initialParagraph: e.paragraph > 0 ? e.paragraph : null),
    ));
  }

  Widget _stat(ThemeData theme, String number, String label) => Expanded(
        child: Column(
          children: [
            Text(number,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
            const SizedBox(height: 2),
            Tr(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _rows;
    Widget body;
    if (rows == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (rows.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Tr('இன்னும் எந்தச் செய்தியும் வாசிக்கப்படவில்லை. / Nothing read yet.',
              textAlign: TextAlign.center),
        ),
      );
    } else {
      final read = rows.where((r) => r.e.timesRead > 0).length;
      final times = rows.fold<int>(0, (n, r) => n + r.e.timesRead);
      final reading = rows.where((r) => r.e.progress > 0.02 && r.e.progress < ReadingProgress.done).length;
      body = ListView.separated(
        itemCount: rows.length + 1,
        separatorBuilder: (_, i) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == 0) {
            // Totals.
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: Row(
                children: [
                  _stat(theme, '$read', 'வாசித்து முடித்தவை\nMessages read'),
                  _stat(theme, '$reading', 'வாசித்துக்கொண்டிருப்பவை\nReading now'),
                  _stat(theme, '$times', 'மொத்த முறை\nTimes read'),
                ],
              ),
            );
          }
          final r = rows[i - 1];
          final e = r.e;
          final pct = (e.progress * 100).round();
          final d = e.lastOpened;
          final lang = appProfile.englishOnly ? '' : (e.lang == 'en' ? 'English · ' : 'தமிழ் · ');
          return InkWell(
            onTap: () => _open(e),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(r.title,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      if (e.timesRead > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 14, color: theme.colorScheme.onPrimaryContainer),
                              const SizedBox(width: 3),
                              Text(
                                e.lang == 'en' || appProfile.englishOnly
                                    ? '${e.timesRead}×'
                                    : '${e.timesRead} முறை',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${e.code} · $lang${d.day} ${_months[d.month - 1]} ${d.year}',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: e.progress,
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 40,
                        child: Text('$pct%', textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Tr('வரலாறு / History')),
      body: body,
    );
  }
}
