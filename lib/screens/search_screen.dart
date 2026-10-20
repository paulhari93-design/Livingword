import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/library.dart';
import '../models/message.dart';
import 'reader_screen.dart';

/// Result returned to the reader when a hit in the *same* message is tapped.
class JumpTo {
  final int paragraph;
  final String query;
  const JumpTo(this.paragraph, this.query);
}

/// Word / sentence search. Opened from the reader (with [current]) it offers
/// "This message" or "All messages". Opened from the home screen it searches all.
class SearchScreen extends StatefulWidget {
  final MessageInfo? current;
  const SearchScreen({super.key, this.current});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  late bool _onlyCurrent = widget.current != null;
  List<SearchHit> _hits = [];
  bool _searching = false;
  String _lastQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _run);
  }

  Future<void> _run() async {
    final q = _controller.text;
    if (normalizeQuery(q).length < 2) {
      setState(() {
        _hits = [];
        _lastQuery = '';
      });
      return;
    }
    setState(() => _searching = true);
    final hits = await Library.instance.search(
      q,
      only: _onlyCurrent ? widget.current : null,
    );
    if (!mounted || q != _controller.text) return;
    setState(() {
      _hits = hits;
      _lastQuery = normalizeQuery(q);
      _searching = false;
    });
  }

  Future<void> _open(SearchHit hit) async {
    final current = widget.current;
    if (current != null && hit.info.code == current.code) {
      Navigator.of(context).pop(JumpTo(hit.paragraph, _controller.text));
      return;
    }
    final message = await Library.instance.message(hit.info);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(
        message: message,
        initialParagraph: hit.paragraph,
        searchQuery: _controller.text,
      ),
    ));
  }

  /// A short piece of the paragraph around the match, with the match marked.
  Widget _snippet(SearchHit hit, TextStyle base) {
    final t = hit.text;
    final s = math.max(0, hit.matchStart - 40);
    final e = math.min(t.length, hit.matchStart + _lastQuery.length + 60);
    final piece = (s > 0 ? '…' : '') + t.substring(s, e) + (e < t.length ? '…' : '');
    final spans = <TextSpan>[];
    final matches = findMatches(piece, _lastQuery);
    var pos = 0;
    for (final m in matches) {
      spans.add(TextSpan(text: piece.substring(pos, m)));
      spans.add(TextSpan(
        text: piece.substring(m, m + _lastQuery.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFFB74D),
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));
      pos = m + _lastQuery.length;
    }
    spans.add(TextSpan(text: piece.substring(pos)));
    return Text.rich(TextSpan(style: base, children: spans), maxLines: 3, overflow: TextOverflow.ellipsis);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _hits.fold<int>(0, (a, h) => a + h.count);
    final messageCount = _hits.map((h) => h.info.code).toSet().length;

    return Scaffold(
      appBar: AppBar(title: const Text('தேடல் / Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'தமிழ் சொல் அல்லது வாக்கியம்',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    _run();
                  },
                ),
              ),
            ),
          ),
          if (widget.current != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('This message'), icon: Icon(Icons.article_outlined)),
                  ButtonSegment(value: false, label: Text('All messages'), icon: Icon(Icons.library_books_outlined)),
                ],
                selected: {_onlyCurrent},
                onSelectionChanged: (s) {
                  setState(() => _onlyCurrent = s.first);
                  _run();
                },
              ),
            ),
          if (_lastQuery.isNotEmpty && !_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _hits.isEmpty
                      ? 'No results'
                      : '$total matches in $messageCount message${messageCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.separated(
              itemCount: _hits.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final h = _hits[i];
                return ListTile(
                  title: _onlyCurrent
                      ? null
                      : Text('${h.info.code}  ${h.info.title}',
                          style: theme.textTheme.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: _snippet(h, theme.textTheme.bodyMedium!.copyWith(height: 1.5)),
                  trailing: Text('¶${h.paragraph + 1}', style: theme.textTheme.bodySmall),
                  onTap: () => _open(h),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
