import 'package:flutter/material.dart';

import '../data/bible.dart';
import '../data/library.dart';
import '../data/profile.dart';
import '../services/push.dart';
import '../l10n.dart';

/// Applies a profile: English-only readers always see English text.
Future<void> applyProfile(AppProfile p) async {
  await appProfile.set(p);
  if (p == AppProfile.englishOnly) {
    await messageLang.set('en');
    await bibleMode.set(BibleMode.english);
  }
  Push.updateTopics();
}

/// First install: choose what to read. Shown once, before the download screen.
/// [onChosen] continues (e.g. to the download screen).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.onChosen, this.firstRun = true});

  final void Function(BuildContext context, AppProfile profile) onChosen;
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget option(AppProfile p, IconData icon, String title, String subtitle) => Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await applyProfile(p);
              if (context.mounted) onChosen(context, p);
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(icon, size: 40, color: theme.colorScheme.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(tr(subtitle), style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  if (appProfile.value == p) Icon(Icons.check_circle, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !firstRun,
        title: const Text('Choose profile'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Tr('What would you like to read?\nநீங்கள் எதை வாசிக்க விரும்புகிறீர்கள்?',
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
            const SizedBox(height: 24),
            option(AppProfile.englishOnly, Icons.language, '1.  English only',
                'English Bible (KJV) and English messages.'),
            option(AppProfile.tamilEnglish, Icons.translate, '2.  English + Tamil',
                'தமிழ் மற்றும் ஆங்கில வேதாகமம், செய்திகள்.\nTamil and English Bible and messages.'),
            const SizedBox(height: 8),
            Text('You can change this later in ⋮ → Advanced settings.',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
