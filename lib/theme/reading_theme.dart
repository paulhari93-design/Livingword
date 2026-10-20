import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reading themes users can pick from.
enum ReadingTheme {
  light('Light', Color(0xFFFFFFFF), Color(0xFF111111), Brightness.light),
  dark('Dark', Color(0xFF000000), Color(0xFFF2F2F2), Brightness.dark),
  sepia('Sepia', Color(0xFFF4ECD8), Color(0xFF5B4636), Brightness.light),
  green('Calm green', Color(0xFFCCE8CF), Color(0xFF1F3B23), Brightness.light),
  navy('Night blue', Color(0xFF0F1B2D), Color(0xFFE3E8EF), Brightness.dark);

  const ReadingTheme(this.label, this.background, this.text, this.brightness);
  final String label;
  final Color background;
  final Color text;
  final Brightness brightness;

  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3F51B5),
      brightness: brightness,
    ).copyWith(surface: background, onSurface: text);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: text.withValues(alpha: 0.15),
    );
  }
}

/// Holds the current theme for the whole app and remembers it.
class ThemeController extends ValueNotifier<ReadingTheme> {
  ThemeController() : super(ReadingTheme.light);
  static const _key = 'reading_theme';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    value = ReadingTheme.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ReadingTheme.light,
    );
  }

  Future<void> set(ReadingTheme theme) async {
    value = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, theme.name);
  }
}

final themeController = ThemeController();

/// Palette button for app bars: opens the theme picker.
class ThemeButton extends StatelessWidget {
  const ThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Theme',
      icon: const Icon(Icons.palette_outlined),
      onPressed: () => showModalBottomSheet(
        context: context,
        builder: (_) => const _ThemePicker(),
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReadingTheme>(
      valueListenable: themeController,
      builder: (context, current, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final t in ReadingTheme.values)
                    _ThemeSwatch(
                      theme: t,
                      selected: t == current,
                      onTap: () => themeController.set(t),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme, required this.selected, required this.onTap});
  final ReadingTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 60,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? accent : Colors.grey.shade400,
                  width: selected ? 3 : 1,
                ),
              ),
              child: Text('அ',
                  style: TextStyle(color: theme.text, fontSize: 20, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            Text(theme.label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
