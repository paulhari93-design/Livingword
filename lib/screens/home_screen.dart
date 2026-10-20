import 'package:flutter/material.dart';

import '../data/library.dart';
import '../models/message.dart';
import '../theme/reading_theme.dart';
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
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final list = await Library.instance.catalog();
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
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
        title: const Text('செய்திகள்'),
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
          Padding(
            padding: const EdgeInsets.all(12),
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
                    ? const Center(child: Text('No messages found'))
                    : ListView.separated(
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
        ],
      ),
    );
  }
}
