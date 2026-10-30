import 'package:flutter/material.dart';

import '../data/cloud.dart';
import '../data/library.dart';
import '../data/progress.dart';
import '../data/series.dart';
import '../models/message.dart';
import '../theme/reading_theme.dart';
import 'message_lang_switch.dart';
import 'reader_screen.dart';
import 'search_screen.dart';
import 'section_switch.dart';
import '../data/profile.dart';
import '../widgets/more_menu.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// How the list is shown: everything, by year, or by series.
enum _View { all, year, series }

class _HomeScreenState extends State<HomeScreen> {
  List<MessageInfo> _all = [];
  String _query = '';
  bool _loading = true;

  // Remembered while the app is open.
  static _View _view = _View.all;
  static String? _year; // '65' = the year opened in the Year view
  static int? _seriesIndex; // the series opened in the Series view
  List<SeriesInfo> _series = [];

  @override
  void initState() {
    super.initState();
    messageLang.addListener(_loadCatalog);
    _loadCatalog();
    SeriesStore.instance.all().then((s) {
      if (mounted) setState(() => _series = s);
    });
    ReadingProgress.instance.load();
  }

  @override
  void dispose() {
    messageLang.removeListener(_loadCatalog);
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final lang = messageLang.value == 'en' ? 'en' : 'ta'; // 'both' lists the Tamil titles
    var list = await Library.instance.catalog(lang: lang);
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = list.isEmpty; // show the spinner while fetching from the cloud
    });
    if (list.isNotEmpty) return;
    // Nothing on the phone yet in this language: fetch it now.
    try {
      await Cloud.instance.syncMessages();
    } catch (_) {}
    Library.instance.reload();
    list = await Library.instance.catalog(lang: lang);
    if (!mounted || (messageLang.value == 'en' ? 'en' : 'ta') != lang) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  /// Pull down on the list to check for new messages.
  Future<void> _refresh() async {
    try {
      await Cloud.instance.syncMessages();
    } catch (_) {}
    Library.instance.reload();
    SeriesStore.instance.reload();
    final list = await Library.instance.catalog();
    final series = await SeriesStore.instance.all();
    if (mounted) {
      setState(() {
        _all = list;
        _series = series;
      });
    }
  }

  Future<void> _open(MessageInfo info) async {
    final message = await Library.instance.message(info);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(message: message)),
    );
  }

  bool get _english => messageLang.value == 'en';
  String _say(String ta, String en) => _english ? en : ta;

  /// The messages of the open year / series (or all of them).
  List<MessageInfo> _scope() {
    if (_view == _View.year && _year != null) {
      return _all.where((m) => m.code.startsWith('$_year-')).toList();
    }
    if (_view == _View.series && _seriesIndex != null && _seriesIndex! < _series.length) {
      final byCode = {for (final m in _all) m.code.toUpperCase(): m};
      return [
        for (final c in _series[_seriesIndex!].codes)
          if (byCode[c] != null) byCode[c]!,
      ];
    }
    return _all;
  }

  bool get _inGroup =>
      (_view == _View.year && _year != null) ||
      (_view == _View.series && _seriesIndex != null && _seriesIndex! < _series.length);

  void _closeGroup() => setState(() {
        _year = null;
        _seriesIndex = null;
      });

  Widget _viewSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<_View>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: _View.all, label: Text(_say('அனைத்தும்', 'All'))),
            ButtonSegment(value: _View.year, label: Text(_say('ஆண்டு', 'Year'))),
            ButtonSegment(value: _View.series, label: Text(_say('தொகுப்பு', 'Series'))),
          ],
          selected: {_view},
          onSelectionChanged: (v) => setState(() {
            _view = v.first;
            _year = null;
            _seriesIndex = null;
          }),
        ),
      ),
    );
  }

  /// On the right of each message: a ring with how far it is read, ✓ when read to the end.
  Widget? _progressMark(MessageInfo m, ThemeData theme) {
    final id = m.lang == 'en' ? 'en_${m.code}' : m.code;
    final p = ReadingProgress.instance.of(id);
    final done = p >= ReadingProgress.done || (p < 0.02 && ReadingProgress.instance.timesRead(id) > 0);
    if (done) return Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 22);
    if (p < 0.02) return null;
    return SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        value: p,
        strokeWidth: 3,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
      ),
    );
  }

  Widget _messageList(List<MessageInfo> results) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListenableBuilder(
        listenable: ReadingProgress.instance,
        builder: (context, _) => ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final m = results[i];
            return ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(m.title),
              subtitle: Text(m.code),
              trailing: _progressMark(m, theme),
              onTap: () => _open(m),
            );
          },
        ),
      ),
    );
  }

  /// Years 1947–1965 that have messages in this language.
  Widget _yearList() {
    final counts = <String, int>{};
    for (final m in _all) {
      final y = m.code.length >= 2 ? m.code.substring(0, 2) : '';
      if (RegExp(r'^\d\d$').hasMatch(y)) counts[y] = (counts[y] ?? 0) + 1;
    }
    final years = counts.keys.toList()..sort();
    final theme = Theme.of(context);
    // A grid of years: 4 across on a phone, more on a wider screen.
    return LayoutBuilder(builder: (context, box) {
      final across = (box.maxWidth / 90).floor().clamp(4, 8);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: across,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
        ),
        itemCount: years.length,
        itemBuilder: (_, i) {
          final y = years[i];
          return Material(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _year = y),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    child: Text('19$y',
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                  ),
                  const SizedBox(height: 2),
                  // Shrinks to fit the tile (Tamil is longer, and some phones use big text).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_say('${counts[y]} செய்திகள்', '${counts[y]} messages'),
                          maxLines: 1, style: theme.textTheme.bodySmall),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  /// Series that have at least one message in this language.
  Widget _seriesList() {
    final have = {for (final m in _all) m.code.toUpperCase()};
    final rows = <(int, int)>[]; // (series index, how many here)
    for (var i = 0; i < _series.length; i++) {
      final n = _series[i].codes.where(have.contains).length;
      if (n > 0) rows.add((i, n));
    }
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_say('தொகுப்புகள் இன்னும் இல்லை', 'No series yet'), textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, k) {
        final (i, n) = rows[k];
        return ListTile(
          leading: const Icon(Icons.collections_bookmark_outlined),
          title: Text(_series[i].name(_english ? 'en' : 'ta')),
          subtitle: Text(_say('$n செய்திகள்', '$n messages')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _seriesIndex = i),
        );
      },
    );
  }

  /// "← 1965" / "← The Seven Seals": back to the list of years / series.
  Widget _groupHeader(ThemeData theme) {
    final title = _view == _View.year
        ? '19$_year'
        : _series[_seriesIndex!].name(_english ? 'en' : 'ta');
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: _closeGroup,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.arrow_back, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = _scope();
    final searching = _query.trim().isNotEmpty;
    final results = (searching || _view == _View.all || _inGroup ? scope : _all)
        .where((m) => m.matches(_query))
        .toList();

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!searching && !_inGroup && _view == _View.year) {
      body = _yearList();
    } else if (!searching && !_inGroup && _view == _View.series) {
      body = _seriesList();
    } else if (results.isEmpty) {
      body = Center(
        child: Text(
            _query.isEmpty && _english
                ? 'English messages are not available yet.\nCheck your internet connection and try again.'
                : _english
                    ? 'No messages found'
                    : 'செய்திகள் எதுவும் கிடைக்கவில்லை',
            textAlign: TextAlign.center),
      );
    } else {
      body = _messageList(results);
    }

    return PopScope(
      // Back inside a year / series goes to the list of years / series first.
      canPop: !_inGroup,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inGroup) _closeGroup();
      },
      child: Scaffold(
        appBar: AppBar(
          title: ValueListenableBuilder<String>(
            valueListenable: messageLang,
            // Shrinks the title to fit, so the whole Tamil name is always visible.
            builder: (_, lang, __) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(lang == 'en' ? 'Spoken Word' : 'உரைக்கப்பட்ட வார்த்தை'),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Search words in all messages',
              icon: const Icon(Icons.manage_search),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              ),
            ),
            const GoToBibleButton(),
            const MoreMenu(),
          ],
        ),
        body: Column(
          children: [
            const SizedBox(height: 8),
            if (!appProfile.englishOnly)
              ValueListenableBuilder<String>(
                valueListenable: messageLang,
                builder: (_, lang, __) =>
                    MessageLangSwitch(value: lang == 'en' ? 'en' : 'ta', onChanged: messageLang.set),
              ),
            _viewSwitch(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  // Shows how many messages are in this list, e.g. "Search 1204 messages…".
                  hintText: _english
                      ? 'Search ${scope.length} messages by name or code (e.g. 47-0508)'
                      : '${scope.length} செய்திகள் · தலைப்பு அல்லது வருடக்குறியீடு தேடல் (47-0508)',
                  hintMaxLines: 2,
                  // While searching: how many were found.
                  suffixText: searching ? '${results.length} / ${scope.length}' : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (_inGroup) _groupHeader(theme),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
