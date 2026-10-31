import 'package:flutter/material.dart';

import '../l10n.dart';

import '../data/news.dart';
import '../screens/advanced_settings_screen.dart';
import '../screens/news_screen.dart';
import '../screens/notes_screen.dart';
import '../screens/feedback_screen.dart';
import '../screens/history_screen.dart';
import '../screens/marks_screen.dart';
import '../screens/read_along.dart';
import '../screens/split_app_screen.dart';
import '../theme/reading_theme.dart';
import '../theme/text_settings.dart';
import '../data/bible.dart';
import '../data/library.dart';
import '../data/profile.dart';

/// The ⋮ button at the right of the top bar.
///
/// Its words follow the language on screen: all Tamil when Tamil is shown, all English
/// when English is shown. Bible: Tamil tab → Tamil, English or Both → English.
/// English-only profile: English.
/// - Main menu ([homeOnly]): Notifications only.
/// - Split view: Read along (when both halves match), Text, Theme, Close split view.
/// - Elsewhere: Notifications, MyNotes, Save as PDF, Open in split view,
///   Advanced settings, and Feedback (always last).
class MoreMenu extends StatelessWidget {
  const MoreMenu({
    super.key,
    this.onPdf,
    this.pdfLabel,
    this.showNotes = true,
    this.splitTop,
    this.homeOnly = false,
    this.lang,
    this.bible = false,
    this.scrolling,
    this.onScrolling,
    this.showMarks = true,
  });

  /// Messages: true = scrolling, false = pages; null = no such option on this screen.
  final bool? scrolling;
  final ValueChanged<bool>? onScrolling;
  final bool showMarks; // false when "Bookmarks & highlights" is already a button on the bar

  final VoidCallback? onPdf; // null = no PDF option on this screen
  final String? pdfLabel; // "தமிழ் / English"
  final bool showNotes;
  final WidgetBuilder? splitTop; // "Open in split view": this screen on top, main menu below
  final bool homeOnly; // main menu: only Notifications
  final String? lang; // 'ta' / 'en'; null = the Messages language
  final bool bible; // Bible screens: Tamil tab → Tamil, English or Both → English

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([NewsStore.instance, messageLang, bibleMode, appProfile]),
      builder: (context, _) => _menu(context),
    );
  }

  Widget _menu(BuildContext context) {
    final shown = bible ? (bibleMode.value == BibleMode.tamil ? 'ta' : 'en') : (lang ?? messageLang.value);
    final english = appProfile.englishOnly || shown == 'en';
    // "தமிழ் / English" -> the part for the language on screen.
    String say(String both) {
      final parts = both.split(' / ');
      if (parts.length < 2) return both;
      return english ? parts.sublist(1).join(' / ') : parts.first;
    }

    final split = appSplitOpen.value;
    final unseen = !split && NewsStore.instance.unseen;
    // Orange dot on ⋮ (and on "Notifications") while new messages are unseen.
    Widget dot(Widget child, bool show) => Badge(
          isLabelVisible: show,
          smallSize: 10,
          backgroundColor: Colors.orange,
          child: child,
        );
    PopupMenuItem<String> item(String value, Widget icon, String title) => PopupMenuItem(
          value: value,
          child: ListTile(leading: icon, title: Text(say(title)), contentPadding: EdgeInsets.zero),
        );

    return PopupMenuButton<String>(
      icon: dot(const Icon(Icons.more_vert), unseen),
      onSelected: (v) {
        switch (v) {
          case 'notes':
            openNotes(context);
          case 'history':
            pushInLang(context, english ? 'en' : 'ta', const HistoryScreen());
          case 'marks':
            pushInLang(context, english ? 'en' : 'ta', const MarksScreen());
          case 'news':
            pushInLang(context, english ? 'en' : 'ta', const NewsScreen());
          case 'pdf':
            onPdf?.call();
          case 'close_split':
            closeAppSplit(context);
          case 'text':
            showTextSettings(context);
          case 'theme':
            showThemePicker(context);
          case 'read_along':
            ReadAlong.instance.setOn(true);
          case 'not_read_along':
            ReadAlong.instance.setOn(false);
          case 'split':
            final top = splitTop;
            if (top != null) openAppSplit(context, top: top);
          case 'feedback':
            pushInLang(context, english ? 'en' : 'ta', const FeedbackScreen());
          case 'scroll':
            onScrolling?.call(!(scrolling ?? false));
          case 'advanced':
            pushInLang(context, english ? 'en' : 'ta', const AdvancedSettingsScreen());
        }
      },
      itemBuilder: (_) {
        if (split) {
          // This half's own Text and Theme, read along, and closing the split.
          final list = <PopupMenuEntry<String>>[];
          // Read along: only when both halves show the same message (Tamil / English) or Bible book.
          if (ReadAlong.instance.canLink) {
            list.add(CheckedPopupMenuItem<String>(
              value: 'read_along',
              checked: ReadAlong.instance.on,
              child: Text(say('சேர்ந்து வாசி / Read along')),
            ));
            list.add(CheckedPopupMenuItem<String>(
              value: 'not_read_along',
              checked: !ReadAlong.instance.on,
              child: Text(say('தனியாக வாசி / Not read along')),
            ));
            list.add(const PopupMenuDivider());
          }
          list.add(item('text', const Icon(Icons.text_fields), 'எழுத்து / Text'));
          list.add(item('theme', const Icon(Icons.palette_outlined), 'தீம் / Theme'));
          list.add(item('close_split', const Icon(Icons.close_fullscreen), 'பிரிப்பை மூடு / Close split view'));
          return list;
        }
        final items = <PopupMenuEntry<String>>[
          item('news', dot(const Icon(Icons.notifications_outlined), unseen), 'அறிவிப்புகள் / Notifications'),
        ];
        if (homeOnly) return items;
        if (scrolling != null) {
          // Pages are the default; this switches to scrolling and back.
          items.insert(
            0,
            // Page turning on = pages (swipe left / right); off = scrolling.
            PopupMenuItem<String>(
              value: 'scroll',
              child: Row(
                children: [
                  const Icon(Icons.auto_stories_outlined),
                  const SizedBox(width: 12),
                  Expanded(child: Text(say('பக்கம் திருப்புதல் / Page turning'))),
                  IgnorePointer(child: Switch(value: !scrolling!, onChanged: (_) {})),
                ],
              ),
            ),
          );
        }
        if (showNotes) items.add(item('notes', const Icon(Icons.sticky_note_2_outlined), 'எனது குறிப்புகள் / MyNotes'));
        if (showMarks) {
          items.add(item('marks', const Icon(Icons.bookmarks_outlined), 'புக்மார்க் & ஹைலைட் / Bookmarks & highlights'));
        }
        items.add(item('history', const Icon(Icons.history), 'வரலாறு / History'));
        if (onPdf != null) {
          items.add(item('pdf', const Icon(Icons.picture_as_pdf_outlined), pdfLabel ?? 'PDF ஆக சேமி / Save as PDF'));
        }
        if (splitTop != null) {
          items.add(item('split', const Icon(Icons.splitscreen_outlined),
              'பிரிக்கப்பட்ட திரையில் திற / Open in split view'));
        }
        items.add(item('advanced', const Icon(Icons.tune), 'மேம்பட்ட அமைப்புகள் / Advanced settings'));
        // Feedback is always the last item.
        items.add(const PopupMenuDivider());
        items.add(item('feedback', const Icon(Icons.feedback_outlined), 'கருத்து தெரிவி / Feedback'));
        return items;
      },
    );
  }
}
