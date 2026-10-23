import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import 'local_files.dart';

/// Result of checking the cloud for messages.
class SyncResult {
  final List<String> newTitles; // brand-new messages (shown to the user)
  final List<String> newCodes;
  final int corrected; // existing messages that were silently updated
  const SyncResult({this.newTitles = const [], this.newCodes = const [], this.corrected = 0});
  bool get hasNew => newTitles.isNotEmpty;
}

/// Downloads messages and the Bible from Firestore into the phone's private folder.
///
/// Firestore layout (written by tools/publish_books.py):
///   catalog/messages   {items: [{code, title, version}]}
///   messages/<code>    {code, title, version, json}
///   catalog/bible      {version, books}            books = books.json as text
///   bible_ta/<NN>      {json}
///   bible_en/<NN>      {json}
class Cloud {
  Cloud._();
  static final Cloud instance = Cloud._();

  static const _timeout = Duration(seconds: 30);

  bool get available => Firebase.apps.isNotEmpty;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<DocumentSnapshot<Map<String, dynamic>>> _get(String path) =>
      _db.doc(path).get(const GetOptions(source: Source.server)).timeout(_timeout);

  // ---------------- messages ----------------

  bool _syncing = false;

  /// Downloads new messages and silently replaces corrected ones.
  /// [onProgress] gets (done, total) while downloading.
  Future<SyncResult> syncMessages({void Function(int done, int total)? onProgress}) async {
    if (!available || _syncing) return const SyncResult();
    _syncing = true;
    try {
      final files = LocalFiles.instance;
      final catalogDoc = await _get('catalog/messages');
      final items = ((catalogDoc.data()?['items'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

      final localList = ((await files.readJson('messages/index.json')) as List?)
              ?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[];
      final local = {for (final e in localList) e['code'] as String: e};
      final firstDownload = local.isEmpty;

      final toFetch = items.where((it) {
        final mine = local[it['code']];
        return mine == null || mine['version'] != it['version'];
      }).toList();

      final newTitles = <String>[];
      final newCodes = <String>[];
      var corrected = 0;
      var done = 0;
      onProgress?.call(0, toFetch.length);

      for (final it in toFetch) {
        final code = it['code'] as String;
        final doc = await _get('messages/$code');
        final json = doc.data()?['json'] as String?;
        if (json == null) continue;
        await files.writeString('messages/$code.json', json);
        final isNew = !local.containsKey(code);
        local[code] = {
          'code': code,
          'title': it['title'],
          'file': '$code.json',
          'version': it['version'],
        };
        if (isNew && !firstDownload) {
          newTitles.add(it['title'] as String);
          newCodes.add(code);
        } else if (!isNew) {
          corrected++;
        }
        done++;
        onProgress?.call(done, toFetch.length);
      }

      // Remove messages that were taken off the cloud.
      final cloudCodes = items.map((e) => e['code']).toSet();
      for (final code in local.keys.toList()) {
        if (!cloudCodes.contains(code)) {
          local.remove(code);
          await files.delete('messages/$code.json');
        }
      }

      final index = local.values.toList()
        ..sort((a, b) => (a['code'] as String).compareTo(b['code'] as String));
      await files.writeJson('messages/index.json', index);
      return SyncResult(newTitles: newTitles, newCodes: newCodes, corrected: corrected);
    } finally {
      _syncing = false;
    }
  }

  // ---------------- Bible ----------------

  /// Downloads the Tamil Bible and the English KJV (66 + 66 books).
  Future<void> downloadBible({void Function(int done, int total)? onProgress}) async {
    if (!available) throw StateError('No connection to the server');
    final files = LocalFiles.instance;
    final meta = await _get('catalog/bible');
    final booksJson = meta.data()?['books'] as String?;
    if (booksJson == null) throw StateError('Bible is not uploaded yet');

    const total = 132;
    var done = 0;
    onProgress?.call(0, total);
    for (final lang in const ['ta', 'en']) {
      final snap = await _db
          .collection('bible_$lang')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(minutes: 3));
      for (final doc in snap.docs) {
        final json = doc.data()['json'] as String?;
        if (json == null) continue;
        await files.writeString('bible/$lang/${doc.id}.json', json);
        done++;
        onProgress?.call(done, total);
      }
    }
    await files.writeString('bible/books.json', booksJson);
    await files.setBibleDownloaded(true);
  }
}
