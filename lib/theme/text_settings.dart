import 'package:flutter/material.dart';

import '../data/prefs.dart';
import '../data/profile.dart';
import '../l10n.dart';

/// A reading font. [family] null = the phone's own font.
class ReadingFont {
  final String id;
  final String label;
  final String? family;
  final bool italic;
  const ReadingFont(this.id, this.label, this.family, {this.italic = false});
}

/// Tamil fonts that clearly look different from each other.
const tamilFonts = [
  ReadingFont('system', 'இயல்பு / Default', null),
  ReadingFont('noto_serif_tamil', 'Noto Serif · அச்சு', 'NotoSerifTamil'),
  ReadingFont('tiro_tamil', 'Tiro · புத்தகம்', 'TiroTamil'),
  ReadingFont('tiro_tamil_italic', 'Tiro Italic · சாய்வு', 'TiroTamil', italic: true),
  ReadingFont('mukta_malar', 'Mukta · நவீன', 'MuktaMalar'),
  ReadingFont('baloo_thambi', 'Baloo · உருண்டை', 'BalooThambi2'),
  ReadingFont('arima', 'Arima · அழகு', 'Arima'),
  ReadingFont('meera_inimai', 'Meera Inimai · மென்மை', 'MeeraInimai'),
  ReadingFont('kavivanar', 'Kavivanar · கையெழுத்து', 'Kavivanar'),
];

/// English reading fonts, upright and italic.
const englishFonts = [
  ReadingFont('system', 'Default', null),
  ReadingFont('lora', 'Lora', 'Lora'),
  ReadingFont('lora_italic', 'Lora Italic', 'Lora', italic: true),
  ReadingFont('merriweather', 'Merriweather', 'Merriweather'),
  ReadingFont('garamond', 'EB Garamond', 'EBGaramond'),
  ReadingFont('garamond_italic', 'Garamond Italic', 'EBGaramond', italic: true),
  ReadingFont('literata', 'Literata', 'Literata'),
  ReadingFont('literata_italic', 'Literata Italic', 'Literata', italic: true),
];

/// A text colour; [light] is used on light themes, [dark] on dark themes.
class TextColorChoice {
  final String id;
  final String label;
  final Color? light; // null = the theme's own text colour
  final Color? dark;
  const TextColorChoice(this.id, this.label, this.light, this.dark);

  Color? forBrightness(Brightness b) => b == Brightness.dark ? dark : light;
}

const textColors = [
  TextColorChoice('theme', 'இயல்பு / Default', null, null),
  TextColorChoice('sepia', 'Brown', Color(0xFF4E342E), Color(0xFFE8CBA8)),
  TextColorChoice('blue', 'Blue', Color(0xFF0D3B66), Color(0xFFA9CFF2)),
  TextColorChoice('green', 'Green', Color(0xFF1B4332), Color(0xFFADE3C3)),
  TextColorChoice('maroon', 'Maroon', Color(0xFF6D1A36), Color(0xFFF2B8C6)),
];

class TextSettings {
  final double size;
  final String tamilFont;
  final String englishFont;
  final String color;
  const TextSettings({this.size = 20, this.tamilFont = 'system', this.englishFont = 'system', this.color = 'theme'});

  TextSettings copyWith({double? size, String? tamilFont, String? englishFont, String? color}) => TextSettings(
        size: size ?? this.size,
        tamilFont: tamilFont ?? this.tamilFont,
        englishFont: englishFont ?? this.englishFont,
        color: color ?? this.color,
      );

  ReadingFont get _taFont => tamilFonts.firstWhere((f) => f.id == tamilFont, orElse: () => tamilFonts.first);
  ReadingFont get _enFont => englishFonts.firstWhere((f) => f.id == englishFont, orElse: () => englishFonts.first);
  String? get _ta => _taFont.family;
  String? get _en => _enFont.family;

  /// Font family for reading text in [lang] ('ta' or 'en'), with the other as fallback.
  String? family(String lang) => lang == 'en' ? _en : _ta;

  /// Italic when the chosen font for [lang] is an italic one.
  FontStyle? fontStyle(String lang) => (lang == 'en' ? _enFont : _taFont).italic ? FontStyle.italic : null;
  List<String>? fallback(String lang) {
    final other = lang == 'en' ? _ta : _en;
    return other == null ? null : [other];
  }

  /// The chosen text colour for this theme, or [themeColor].
  Color textColor(BuildContext context, Color themeColor) {
    final c = textColors.firstWhere((c) => c.id == color, orElse: () => textColors.first);
    return c.forBrightness(Theme.of(context).brightness) ?? themeColor;
  }

  /// Reading style for [lang] at [size] (default: the chosen size).
  TextStyle style(BuildContext context, String lang, Color themeColor, {double? fontSize, double height = 1.6}) =>
      TextStyle(
        fontSize: fontSize ?? size,
        height: height,
        color: textColor(context, themeColor),
        fontFamily: family(lang),
        fontFamilyFallback: fallback(lang),
        fontStyle: fontStyle(lang),
      );
}

/// The reading text settings for the whole app (size, fonts, colour), remembered.
class TextSettingsController extends ValueNotifier<TextSettings> {
  /// [prefix]: '' for the normal app, 'split_top_' / 'split_bottom_' for the split-view halves.
  TextSettingsController([this.prefix = '']) : super(const TextSettings());
  final String prefix;

  /// The text settings for this part of the screen (a split-view half has its own).
  static TextSettingsController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TextSettingsScope>()?.notifier ?? textSettings;

  static const double minSize = 14, maxSize = 40;

  Future<void> load() async {
    final p = Prefs.instance;
    value = TextSettings(
      size: (await p.getDouble('${prefix}font_size')) ?? 20,
      tamilFont: (await p.getString('${prefix}font_ta')) ?? 'system',
      englishFont: (await p.getString('${prefix}font_en')) ?? 'system',
      color: (await p.getString('${prefix}font_color')) ?? 'theme',
    );
  }

  void setSize(double size, {bool save = true}) {
    value = value.copyWith(size: size.clamp(minSize, maxSize).toDouble());
    if (save) Prefs.instance.set('${prefix}font_size', value.size);
  }

  void setTamilFont(String id) {
    value = value.copyWith(tamilFont: id);
    Prefs.instance.set('${prefix}font_ta', id);
  }

  void setEnglishFont(String id) {
    value = value.copyWith(englishFont: id);
    Prefs.instance.set('${prefix}font_en', id);
  }

  /// Back to the default size, fonts and colour.
  void reset() {
    value = const TextSettings();
    Prefs.instance.set('${prefix}font_size', value.size);
    Prefs.instance.set('${prefix}font_ta', value.tamilFont);
    Prefs.instance.set('${prefix}font_en', value.englishFont);
    Prefs.instance.set('${prefix}font_color', value.color);
  }

  void setColor(String id) {
    value = value.copyWith(color: id);
    Prefs.instance.set('${prefix}font_color', id);
  }
}

final textSettings = TextSettingsController();

/// True inside a split-view half (those have their own text settings).
bool _inSplitView(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<TextSettingsScope>() != null;

/// Gives a part of the screen its own text settings (used by the split view).
class TextSettingsScope extends InheritedNotifier<TextSettingsController> {
  const TextSettingsScope({super.key, required TextSettingsController controller, required super.child})
      : super(notifier: controller);
}

/// What the reader was showing last (a paragraph or verse), so the Text page
/// can preview the chosen size, fonts and colour on the real text.
final readingPreview = ValueNotifier<({String? ta, String? en})>((ta: null, en: null));

/// Sets the preview text for [lang] ('ta' or 'en'); long text is shortened.
void setReadingPreview({String? ta, String? en}) {
  String? cut(String? t) {
    if (t == null) return null;
    final x = t.replaceFirst(RegExp(r'^\d{1,3}[.\s]\s*'), '').trim();
    return x.length > 260 ? '${x.substring(0, 260)}…' : x;
  }

  final cur = readingPreview.value;
  readingPreview.value = (ta: cut(ta) ?? cur.ta, en: cut(en) ?? cur.en);
}

/// ⋮ → Text: size (A− / A+), Tamil font, English font, colour. Changes show at once.
void showTextSettings(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => const _TextPage(),
  ));
}

class _TextPage extends StatelessWidget {
  const _TextPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Tr('எழுத்து / Text')),
      // The preview is shown in normal reading only (the split view is too small for it).
      body: Column(
        children: [
          if (!_inSplitView(context)) const _Preview(),
          const Expanded(child: _TextSheet()),
        ],
      ),
    );
  }
}

class _TextSheet extends StatelessWidget {
  const _TextSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textSettings = TextSettingsController.of(context);
    return ValueListenableBuilder<TextSettings>(
      valueListenable: textSettings,
      builder: (context, t, _) {
        Widget fontChips(List<ReadingFont> fonts, String selected, String sample, void Function(String) onPick) =>
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in fonts)
                  ChoiceChip(
                    selected: f.id == selected,
                    onSelected: (_) => onPick(f.id),
                    label: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(sample,
                            style: TextStyle(
                                fontFamily: f.family,
                                fontStyle: f.italic ? FontStyle.italic : null,
                                fontSize: 18)),
                        Text(tr(f.label), style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
              ],
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tr('எழுத்து அளவு / Text size', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton.outlined(
                      tooltip: 'Smaller text',
                      onPressed: () => textSettings.setSize(t.size - 2),
                      icon: const Text('A−', style: TextStyle(fontSize: 16)),
                    ),
                    Expanded(
                      child: Slider(
                        min: TextSettingsController.minSize,
                        max: TextSettingsController.maxSize,
                        divisions: 13,
                        value: t.size,
                        label: t.size.round().toString(),
                        onChanged: (v) => textSettings.setSize(v, save: false),
                        onChangeEnd: (v) => textSettings.setSize(v),
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Bigger text',
                      onPressed: () => textSettings.setSize(t.size + 2),
                      icon: const Text('A+', style: TextStyle(fontSize: 20)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!appProfile.englishOnly) ...[
                  Tr('தமிழ் எழுத்துரு / Tamil font', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  fontChips(tamilFonts, t.tamilFont, 'விசுவாசம் கொண்டு', textSettings.setTamilFont),
                  const SizedBox(height: 16),
                ],
                Text('English font', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                fontChips(englishFonts, t.englishFont, 'Faith cometh by hearing', textSettings.setEnglishFont),
                const SizedBox(height: 16),
                Tr('எழுத்து நிறம் / Text colour', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final c in textColors)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => textSettings.setColor(c.id),
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.surface,
                                border: Border.all(
                                  color: c.id == t.color ? theme.colorScheme.primary : theme.colorScheme.outline,
                                  width: c.id == t.color ? 3 : 1,
                                ),
                              ),
                              child: Text(appProfile.englishOnly ? 'A' : 'அ',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: c.forBrightness(theme.brightness) ?? theme.colorScheme.onSurface)),
                            ),
                            const SizedBox(height: 4),
                            Text(c.label.split(' / ').last, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
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
}

/// The live preview at the top of the Text page: the text being read,
/// in the chosen size, fonts and colour.
class _Preview extends StatelessWidget {
  const _Preview();

  static const _sampleTa = 'தேவன் எல்லா காலங்களிலும் தம்முடைய ஜனங்களை வழிநடத்த ஒருவரை அனுப்பினார்.';
  static const _sampleEn = 'So then faith cometh by hearing, and hearing by the word of God.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<TextSettings>(
      valueListenable: TextSettingsController.of(context),
      builder: (context, t, _) => ValueListenableBuilder<({String? ta, String? en})>(
        valueListenable: readingPreview,
        builder: (context, p, _) {
          final base = theme.colorScheme.onSurface;
          return Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.38),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(bottom: BorderSide(color: theme.colorScheme.primary, width: 2)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tr('முன்னோட்டம் / Preview',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 6),
                  if (!appProfile.englishOnly) ...[
                    Text(p.ta ?? _sampleTa, style: t.style(context, 'ta', base)),
                    const SizedBox(height: 10),
                  ],
                  Text(p.en ?? _sampleEn, style: t.style(context, 'en', base)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
