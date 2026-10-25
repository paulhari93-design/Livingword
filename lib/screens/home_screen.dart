import 'package:flutter/material.dart';

import '../data/cloud.dart';
import '../data/library.dart';
import '../models/message.dart';
import '../theme/reading_theme.dart';
import 'message_lang_switch.dart';
import 'reader_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MessageInfo> _all = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    messageLang.addListener(_loadCatalog);
    _loadCatalog();
  }

  @override
  void dispose() {
    messageLang.removeListener(_loadCatalog);
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final lang = messageLang.value;
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
    if (!mounted || messageLang.value != lang) return;
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
    final list = await Library.instance.catalog();
    if (mounted) setState(() => _all = list);
  }

  Future<void> _open(MessageInfo info) async {
    final message = await Library.instance.message(info);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(message: message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _all.where((m) => m.matches(_query)).toList();
    return Scaffold(
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
          const ThemeButton(),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          ValueListenableBuilder<String>(
            valueListenable: messageLang,
            builder: (_, lang, __) => MessageLangSwitch(value: lang, onChanged: messageLang.set),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or code (e.g. 47-0508)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : results.isEmpty
                    ? Center(
                        child: Text(_query.isEmpty && messageLang.value == 'en'
                            ? 'English messages are not available yet.\nCheck your internet connection and try again.'
                            : 'No messages found',
                            textAlign: TextAlign.center),
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final m = results[i];
                          return ListTile(
                            leading: const Icon(Icons.menu_book_outlined),
                            title: Text(m.title),
                            subtitle: Text(m.code),
                            onTap: () => _open(m),
                          );
                        },
                      ),
                      ),
          ),
        ],
      ),
    );
  }
}
