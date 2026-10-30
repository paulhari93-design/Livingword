import 'package:flutter/material.dart';

import '../theme/reading_theme.dart';
import '../data/profile.dart';
import '../theme/text_settings.dart';
import '../data/library.dart';
import '../services/volume_keys.dart';
import '../data/local_files.dart';
import 'download_screen.dart';
import 'profile_screen.dart';
import '../l10n.dart';
import '../data/reading_mode.dart';

/// ⋮ → Advanced settings.
class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Tr('மேம்பட்ட அமைப்புகள் / Advanced settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Tr('எழுத்து / Text'),
            subtitle: const Tr('அளவு, எழுத்துரு, நிறம் / Size, font, colour'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showTextSettings(context),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Tr('தீம் / Theme'),
            subtitle: const Tr('பின்னணி நிறம் / Background colours'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showThemePicker(context),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Tr('இயல்புநிலைக்கு மீட்டமை / Reset to default'),
            subtitle: const Tr('தீம், எழுத்துரு, அளவு, நிறம் / Theme, fonts, size, colour'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Tr('இயல்புநிலைக்கு மீட்டமைக்கவா? / Reset to default?'),
                  content: const Tr('தீம், எழுத்துரு, எழுத்து அளவு மற்றும் நிறம் மாறும். '
                      'ஹைலைட்கள் மற்றும் குறிப்புகள் மாறாது.\n\n'
                      'Theme, fonts, text size and colour go back to default. '
                      'Your highlights and notes are not changed.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Tr('ரத்து / Cancel')),
                    FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Tr('மீட்டமை / Reset')),
                  ],
                ),
              );
              if (ok != true) return;
              // Resets this part of the screen only (each split-view half has its own settings).
              TextSettingsController.of(context).reset();
              ThemeController.of(context).set(ReadingTheme.light);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Tr('இயல்புநிலை அமைக்கப்பட்டது / Back to default')),
                );
              }
            },
          ),
          ValueListenableBuilder<PageModeSettings>(
            valueListenable: pageMode,
            builder: (context, pm, _) => ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: const Tr('பக்க முறை / Page mode'),
              subtitle: Text(pm.on
                  ? tr('இயக்கத்தில் — பக்கங்களாக / On — pages')
                  : tr('அணைப்பில் — உருட்டி வாசித்தல் / Off — scrolling')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PageModeScreen()),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: VolumeKeys.enabled,
            builder: (context, on, _) => SwitchListTile(
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Tr('ஒலி பொத்தான்களால் பக்கம் / Volume keys turn pages'),
              subtitle: const Tr('ஒலி குறை = அடுத்த பக்கம், ஒலி கூட்டு = முந்தைய பக்கம் (ஒரு கை வாசிப்பு)\n'
                  'Volume down = next page, volume up = previous page (one-hand reading)'),
              value: on,
              onChanged: VolumeKeys.setEnabled,
            ),
          ),
          ValueListenableBuilder<AppProfile?>(
            valueListenable: appProfile,
            builder: (context, p, _) => ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Tr('சுயவிவரம் / Profile'),
              subtitle: Text(p == AppProfile.englishOnly ? 'English only' : 'English + Tamil'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProfileScreen(
                  firstRun: false,
                  onChosen: (ctx, _) async {
                    final nav = Navigator.of(ctx);
                    nav.pop();
                    Library.instance.reload();
                    // Download what the new profile needs, if it isn't on the phone yet.
                    final needMessages = !await LocalFiles.instance.hasMessageFiles;
                    final needBible = !await LocalFiles.instance.hasBibleFiles;
                    if (needMessages || needBible) {
                      await nav.push(MaterialPageRoute(
                        builder: (_) => DownloadScreen(offerMessages: needMessages, offerBible: needBible),
                      ));
                      Library.instance.reload();
                    }
                  },
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }
}


/// ⋮ → Advanced settings → Page mode.
class PageModeScreen extends StatelessWidget {
  const PageModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Tr('பக்க முறை / Page mode')),
      body: ValueListenableBuilder<PageModeSettings>(
        valueListenable: pageMode,
        builder: (context, pm, _) => ListView(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.swap_horiz),
              title: const Tr('இடம் / வலம் தள்ளி பக்கம் திருப்பு / Swipe left / right to turn pages'),
              subtitle: const Tr('செய்திகள் பக்கங்களாக. வெற்று இடத்தில் தொட்டால் தலைப்புப் பட்டியும் '
                  'எல்லாப் பக்கங்களும்; மீண்டும் தொட்டால் முழுத் திரை. அணைத்தால்: மேல் / கீழ் உருட்டி வாசித்தல்.\n'
                  'Messages as pages. Tap empty space for the title bar and all pages; tap again '
                  'for full screen. Off: scroll up / down.'),
              value: pm.on,
              onChanged: (v) => pageMode.set(pm.copyWith(on: v, sideways: true)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.animation),
              title: const Tr('பக்கம் திருப்பும் அசைவு / Page turn animation'),
              subtitle: const Tr('பக்கம் புத்தகம் போல மடிந்து திரும்பும். அணைத்தால்: அடுத்த பக்கம் உடனே தோன்றும்.\n'
                  'The page rolls over like a book. Off: the next page appears at once.'),
              value: pm.animate,
              onChanged: pm.on ? (v) => pageMode.set(pm.copyWith(animate: v)) : null,
            ),
          ],
        ),
      ),
    );
  }
}
