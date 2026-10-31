import 'package:flutter/material.dart';

import '../data/profile.dart';
import '../data/reading_mode.dart';
import '../theme/reading_theme.dart';
import '../theme/text_settings.dart';

/// The "Aa" button in the reader: a panel from the bottom with Font and Layout (like
/// Kindle). Every choice shows at once on the message behind it.
Future<void> showReadingPanel(BuildContext context, {required String lang}) {
  final text = TextSettingsController.of(context);
  final theme = ThemeController.of(context);
  return showModalBottomSheet<void>(
    context: context,
    barrierColor: Colors.transparent, // the message stays visible above the panel
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReadingPanel(text: text, theme: theme, lang: lang),
  );
}

class _ReadingPanel extends StatelessWidget {
  const _ReadingPanel({required this.text, required this.theme, required this.lang});
  final TextSettingsController text;
  final ThemeController theme;
  final String lang;

  bool get _en => lang == 'en' || appProfile.englishOnly;
  String _say(String ta, String en) => _en ? en : ta;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.46;
    return DefaultTabController(
      length: 2,
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            TabBar(tabs: [
              Tab(text: _say('எழுத்துரு', 'Font')),
              Tab(text: _say('அமைப்பு', 'Layout')),
            ]),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([text, theme, pageMode]),
                builder: (context, _) => TabBarView(children: [_font(context), _layout(context)]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(s, style: Theme.of(context).textTheme.labelLarge),
      );

  // ---- Font: the fonts for this language, and the size ----
  Widget _font(BuildContext context) {
    final t = text.value;
    final scheme = Theme.of(context).colorScheme;
    final fonts = lang == 'en' ? englishFonts : tamilFonts;
    final chosen = lang == 'en' ? t.englishFont : t.tamilFont;
    final sample = lang == 'en' ? 'Aa' : 'அஆ';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: fonts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final f = fonts[i];
              final on = f.id == chosen;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => lang == 'en' ? text.setEnglishFont(f.id) : text.setTamilFont(f.id),
                child: Container(
                  width: 88,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: on ? scheme.primary : scheme.outlineVariant, width: on ? 2.5 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(sample,
                          style: TextStyle(
                              fontFamily: f.family,
                              fontStyle: f.italic ? FontStyle.italic : null,
                              fontSize: 26,
                              color: on ? scheme.primary : null)),
                      const SizedBox(height: 4),
                      Text(f.label.split(' / ').last.split(' · ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: on ? scheme.primary : null)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _label(context, _say('எழுத்து அளவு', 'Size')),
        Row(
          children: [
            const Text('A', style: TextStyle(fontSize: 14)),
            Expanded(
              child: Slider(
                min: TextSettingsController.minSize,
                max: TextSettingsController.maxSize,
                divisions: 13,
                value: t.size,
                label: t.size.round().toString(),
                onChanged: (v) => text.setSize(v, save: false),
                onChangeEnd: (v) => text.setSize(v),
              ),
            ),
            const Text('A', style: TextStyle(fontSize: 26)),
          ],
        ),
        _label(context, _say('எழுத்து நிறம்', 'Text colour')),
        Wrap(
          spacing: 14,
          children: [
            for (final c in textColors)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => text.setColor(c.id),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.id == t.color ? scheme.primary : scheme.outline,
                      width: c.id == t.color ? 3 : 1,
                    ),
                  ),
                  child: Text(_en ? 'A' : 'அ',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: c.forBrightness(Theme.of(context).brightness) ?? scheme.onSurface)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ---- Layout: page colour, line spacing, alignment, text colour, pages / scrolling ----
  Widget _layout(BuildContext context) {
    final t = text.value;
    final scheme = Theme.of(context).colorScheme;
    final pm = pageMode.value;
    Widget seg<T>(List<(T, IconData, String)> items, T value, ValueChanged<T> onPick) => SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [
            for (final (v, icon, label) in items) ButtonSegment(value: v, icon: Icon(icon), label: Text(label)),
          ],
          selected: {value},
          onSelectionChanged: (s) => onPick(s.first),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _label(context, _say('பக்க நிறம்', 'Page colour')),
        Wrap(
          spacing: 14,
          children: [
            for (final th in ReadingTheme.values)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => theme.set(th),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: th.background,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: th == theme.value ? scheme.primary : scheme.outline,
                      width: th == theme.value ? 3 : 1,
                    ),
                  ),
                  child: Text(_en ? 'A' : 'அ', style: TextStyle(color: th.text, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
        _label(context, _say('வரி இடைவெளி', 'Line spacing')),
        seg<double>([
          (lineSpacings[0], Icons.density_small, _say('குறைவு', 'Compact')),
          (lineSpacings[1], Icons.density_medium, _say('இயல்பு', 'Standard')),
          (lineSpacings[2], Icons.density_large, _say('அதிகம்', 'Large')),
        ], lineSpacings.contains(t.lineHeight) ? t.lineHeight : lineSpacings[1], text.setLineHeight),
        _label(context, _say('வரிசைப்படுத்தல்', 'Alignment')),
        seg<bool>([
          (false, Icons.format_align_left, _say('இடது', 'Left')),
          (true, Icons.format_align_justify, _say('இருபுறமும்', 'Justified')),
        ], t.justify, text.setJustify),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_say('பக்கம் திருப்புதல்', 'Page turning')),
          subtitle: Text(_say('அணைத்தால்: உருட்டி வாசித்தல்', 'Off: scrolling')),
          value: pm.on,
          onChanged: setPageTurning,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_say('பக்கம் திருப்பும் அசைவு', 'Page turn animation')),
          value: pm.animate,
          onChanged: pm.on ? (v) => pageMode.set(pm.copyWith(animate: v)) : null,
        ),
      ],
    );
  }
}
