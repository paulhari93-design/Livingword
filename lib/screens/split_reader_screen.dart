import 'package:flutter/material.dart';

import '../data/library.dart';
import '../models/message.dart';
import '../widgets/more_menu.dart';
import 'combined_reader_screen.dart';
import 'message_lang_switch.dart';
import 'reader_screen.dart';
import 'section_switch.dart';
import 'swipe.dart';

/// The paragraph in [to] that matches paragraph [p] of [from] (Tamil ↔ English),
/// using the matching saved with the Tamil message, else the same position.
int matchParagraph(Message from, Message to, int p) {
  if (to.paragraphs.isEmpty) return 0;
  int? target;
  if (from.lang != 'en') {
    final a = from.align;
    if (a != null && p < a.length) target = a[p];
  } else {
    final a = to.align;
    if (a != null && a.isNotEmpty) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] >= p) {
          target = i;
          break;
        }
      }
      target ??= a.length - 1;
    }
  }
  target ??= (p * to.paragraphs.length / (from.paragraphs.isEmpty ? 1 : from.paragraphs.length)).floor();
  return target.clamp(0, to.paragraphs.length - 1).toInt();
}

/// Connects the Tamil and English halves of the split view:
/// scrolling one moves the other to the matching paragraph, and marks stay in step.
class SplitLink {
  SplitLink(this.tamil, this.english);
  final Message tamil;
  final Message english;

  final Map<String, void Function(int paragraph, double fraction)> _follow = {};
  final Map<String, VoidCallback> _reload = {};
  final Map<String, void Function(double delta)> _font = {};
  final Map<String, int Function()> _where = {};

  void register(
    String lang, {
    required void Function(int paragraph, double fraction) follow,
    required VoidCallback reloadMarks,
    required void Function(double delta) changeFont,
    required int Function() currentParagraph,
  }) {
    _follow[lang] = follow;
    _reload[lang] = reloadMarks;
    _font[lang] = changeFont;
    _where[lang] = currentParagraph;
  }

  void unregister(String lang) {
    _follow.remove(lang);
    _reload.remove(lang);
    _font.remove(lang);
    _where.remove(lang);
  }

  /// The half in [lang] was scrolled by the user: move the other half along.
  void moved(String lang, int paragraph, double fraction) {
    final en = lang == 'en';
    final from = en ? english : tamil;
    final to = en ? tamil : english;
    final target = matchParagraph(from, to, paragraph);
    _follow[en ? 'ta' : 'en']?.call(target, fraction);
  }

  /// Marks were changed in [lang] (and copied to the other language): refresh the other half.
  void marksChanged(String lang) => _reload[lang == 'en' ? 'ta' : 'en']?.call();

  void changeFont(double delta) {
    for (final f in _font.values) {
      f(delta);
    }
  }

  int currentParagraph(String lang) => _where[lang]?.call() ?? 0;
}

/// Tamil on top, English below. Scroll either half; the other follows.
class SplitReaderScreen extends StatefulWidget {
  const SplitReaderScreen({super.key, required this.tamil, required this.english, this.initialTamilParagraph});

  final Message tamil;
  final Message english;
  final int? initialTamilParagraph;

  @override
  State<SplitReaderScreen> createState() => _SplitReaderScreenState();
}

class _SplitReaderScreenState extends State<SplitReaderScreen> {
  late final SplitLink _link = SplitLink(widget.tamil, widget.english);

  @override
  void initState() {
    super.initState();
    messageSplit.addListener(_viewChanged);
  }

  @override
  void dispose() {
    messageSplit.removeListener(_viewChanged);
    super.dispose();
  }

  /// "Both ⋮" → Normal view: one reader, Tamil paragraph with its English below.
  void _viewChanged() {
    if (!mounted || messageSplit.value) return;
    final p = _link.currentParagraph('ta');
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) =>
          CombinedReaderScreen(tamil: widget.tamil, english: widget.english, initialTamilParagraph: p),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Leaves the split view for one language, at the paragraph being read.
  Future<void> _single(String lang) async {
    final message = lang == 'en' ? widget.english : widget.tamil;
    final p = _link.currentParagraph(lang);
    await messageLang.set(lang);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => ReaderScreen(
        message: message,
        initialParagraph: p > 0 ? p : null,
        flashParagraph: p > 0,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Swipe: next / previous message, still split (or Tamil only if it has no English).
  Future<void> _goNeighbour(int step) async {
    final ta = await neighbourMessage(widget.tamil.code, 'ta', step);
    if (!mounted) return;
    if (ta == null) {
      showEndOfList(context, step > 0);
      return;
    }
    final enInfo = await Library.instance.find(ta.code, 'en');
    final en = enInfo == null ? null : await Library.instance.message(enInfo);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(slideRoute(
      en == null ? ReaderScreen(message: ta) : SplitReaderScreen(tamil: ta, english: en),
      forward: step > 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.tamil;
    final p0 = widget.initialTamilParagraph;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.title, overflow: TextOverflow.ellipsis),
              Text(t.code, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Smaller text',
            icon: const Text('A−', style: TextStyle(fontSize: 16)),
            onPressed: () => _link.changeFont(-2),
          ),
          IconButton(
            tooltip: 'Bigger text',
            icon: const Text('A+', style: TextStyle(fontSize: 22)),
            onPressed: () => _link.changeFont(2),
          ),
          const GoToBibleButton(),
          const MoreMenu(),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: MessageLangSwitch(
            value: 'both',
            showBoth: true,
            onChanged: (v) {
              if (v != 'both') _single(v);
            },
          ),
        ),
      ),
      body: MessageSwipe(
        onNext: () => _goNeighbour(1),
        onPrevious: () => _goNeighbour(-1),
        child: Column(
        children: [
          Expanded(
            child: ReaderScreen(
              message: widget.tamil,
              embedded: true,
              link: _link,
              initialParagraph: p0 != null && p0 > 0 ? p0 : null,
            ),
          ),
          Container(height: 7, color: theme.colorScheme.primary.withValues(alpha: 0.55)),
          Expanded(
            child: ReaderScreen(
              message: widget.english,
              embedded: true,
              link: _link,
              initialParagraph: p0 != null && p0 > 0 ? matchParagraph(t, widget.english, p0) : null,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
