import 'package:flutter/material.dart';

import '../data/library.dart';
import '../data/news.dart';
import '../data/profile.dart';
import '../l10n.dart';
import 'reader_screen.dart';

/// ⋮ → Notifications: the names of newly published messages. Opening this page
/// clears the orange dot.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  // What was new when this page opened. Seeing them clears them from Notifications.
  List<NewsItem>? _items;

  @override
  void initState() {
    super.initState();
    NewsStore.instance.takeAll().then((list) {
      if (mounted) setState(() => _items = list);
    });
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  Future<void> _open(NewsItem item) async {
    final info = await Library.instance.find(item.code, item.lang);
    if (!mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Tr('இந்தச் செய்தி இப்போது இல்லை / This message is no longer available')),
      );
      return;
    }
    final message = await Library.instance.message(info);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(message: message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Tr('அறிவிப்புகள் / Notifications')),
      body: Builder(
        builder: (context) {
          final items = _items;
          if (items == null) return const Center(child: CircularProgressIndicator());
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Tr('புதிய செய்திகள் எதுவும் இல்லை / No new messages yet', textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length + 1,
            separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Tr('புதிதாக வெளியிடப்பட்ட செய்திகள் / Newly published messages',
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
                );
              }
              final item = items[i - 1];
              final when = '${item.at.day} ${_months[item.at.month - 1]} ${item.at.year}';
              final lang = appProfile.englishOnly ? '' : (item.lang == 'en' ? 'English · ' : 'தமிழ் · ');
              return ListTile(
                leading: const Icon(Icons.fiber_new, color: Colors.orange, size: 30),
                title: Text(item.title),
                subtitle: Text('${item.code}  ·  $lang$when'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(item),
              );
            },
          );
        },
      ),
    );
  }
}
