import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'local_files.dart';
import 'news.dart';
import 'series.dart';
import 'profile.dart';

/// Unpacks a compressed message (runs in a background isolate).
String _unpack(String z) => utf8.decode(gzip.decode(base64.decode(z)));

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

  /// Makes sure Firebase is connected (it may not have finished when the app opened).
  Future<void> _ready() async {
    if (Firebase.apps.isNotEmpty) return;
    final options = firebaseOptions;
    if (options != null) {
      try {
        await Firebase.initializeApp(options: options).timeout(const Duration(seconds: 20));
      } catch (_) {}
    }
    if (Firebase.apps.isEmpty) throw StateError('Could not connect to the server');
  }

  bool _configured = false;

  FirebaseFirestore get _db {
    final db = FirebaseFirestore.instance;
    if (!_configured) {
      _configured = true;
      // Don't keep a second copy of every downloaded message in Firestore's own cache:
      // the app saves them itself. (That cache made the phone very slow while hundreds
      // of new messages arrived.)
      try {
        db.settings = const Settings(persistenceEnabled: false);
      } catch (_) {}
    }
    return db;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _get(String path) =>
      _db.doc(path).get(const GetOptions(source: Source.server)).timeout(_timeout);

  // ---------------- messages ----------------

  bool _syncing = false;

  /// Downloads new messages (Tamil and English) and silently replaces corrected ones.
  /// [onProgress] gets (done, total) while downloading.
  Future<SyncResult>? _running;

  Future<SyncResult> syncMessages({void Function(int done, int total)? onProgress}) {
    // If a check is already running, wait for that one instead of starting another.
    return _running ??= _syncAll(onProgress: onProgress).whenComplete(() => _running = null);
  }

  Future<SyncResult> _syncAll({void Function(int done, int total)? onProgress}) async {
    _syncing = true;
    try {
      await _ready();
      // The series list (Year / Series tab): small, updated when it changes.
      try {
        await _syncSeries();
      } catch (_) {}
      // English-only readers: just the English messages.
      if (appProfile.englishOnly) return await _syncLang('en', onProgress: onProgress);
      // Tamil first (it must succeed); English is optional (may not be uploaded yet).
      final ta = await _syncLang('ta', onProgress: onProgress);
      var en = const SyncResult();
      try {
        en = await _syncLang('en', onProgress: onProgress);
      } catch (_) {}
      return SyncResult(
        newTitles: [...ta.newTitles, ...en.newTitles],
        newCodes: [...ta.newCodes, ...en.newCodes],
        corrected: ta.corrected + en.corrected,
      );
    } finally {
      _syncing = false;
    }
  }

  /// Firestore: catalog/messages + messages/<code> (Tamil),
  ///            catalog/messages_en + messages_en/<code> (English).
  Future<SyncResult> _syncLang(String lang, {void Function(int done, int total)? onProgress}) async {
    final files = LocalFiles.instance;
    final folder = lang == 'en' ? 'messages_en' : 'messages';
    final catalogDoc = await _get(lang == 'en' ? 'catalog/messages_en' : 'catalog/messages');
    final items = ((catalogDoc.data()?['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();

    final localList = ((await files.readJson('$folder/index.json')) as List?)
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

    // Fetch one message's text: the compressed copy (much smaller) when there is one.
    Future<String?> fetch(Map<String, dynamic> it) async {
      final code = it['code'] as String;
      if (it['z'] == true) {
        final z = (await _get('${folder}_z/$code')).data()?['z'] as String?;
        // Unpacking runs in the background, so the screen never freezes.
        if (z != null) return compute(_unpack, z);
      }
      return (await _get('$folder/$code')).data()?['json'] as String?;
    }

    // Several at a time, so hundreds of messages download quickly.
    const batch = 4;
    for (var start = 0; start < toFetch.length; start += batch) {
      final part = toFetch.sublist(start, (start + batch).clamp(0, toFetch.length));
      final texts = await Future.wait(part.map(fetch));
      for (var k = 0; k < part.length; k++) {
        final it = part[k];
        final json = texts[k];
        if (json == null) continue;
        final code = it['code'] as String;
        await files.writeString('$folder/$code.json', json);
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
      }
      onProgress?.call(done, toFetch.length);
      await Future<void>.delayed(const Duration(milliseconds: 30)); // let the screen breathe
    }

    // Remove messages that were taken off the cloud.
    final cloudCodes = items.map((e) => e['code']).toSet();
    for (final code in local.keys.toList()) {
      if (!cloudCodes.contains(code)) {
        local.remove(code);
        await files.delete('$folder/$code.json');
      }
    }

    final index = local.values.toList()
      ..sort((a, b) => (a['code'] as String).compareTo(b['code'] as String));
    if (index.isNotEmpty || localList.isNotEmpty) {
      await files.writeJson('$folder/index.json', index);
    }
    // Remember them for ⋮ → Notifications (orange dot).
    final now = DateTime.now();
    await NewsStore.instance.add([
      for (var i = 0; i < newCodes.length; i++)
        NewsItem(code: newCodes[i], title: newTitles[i], lang: lang, at: now),
    ]);
    return SyncResult(newTitles: newTitles, newCodes: newCodes, corrected: corrected);
  }

  // ---------------- Series ----------------

  /// catalog/series {version, json}: the message series, saved as series.json.
  Future<void> _syncSeries() async {
    final files = LocalFiles.instance;
    final snap = await _get('catalog/series');
    final data = snap.data();
    final json = data?['json'] as String?;
    final version = data?['version']?.toString();
    if (json == null || version == null) return;
    final mine = await files.readString('series.version');
    if (mine == version && await files.readString('series.json') != null) return;
    await files.writeString('series.json', json);
    await files.writeString('series.version', version);
    SeriesStore.instance.reload();
  }

  // ---------------- Feedback ----------------

  /// Sends one feedback (≤ 200 letters). Only the app owner can read feedback.
  Future<void> sendFeedback({
    required String text,
    String? name,
    String? contact,
    required Map<String, dynamic> about,
  }) async {
    await _ready();
    await _db.collection('feedback').add({
      'text': text,
      'name': name ?? '',
      'contact': contact ?? '',
      'seen': false,
      'createdAt': FieldValue.serverTimestamp(),
      ...about,
    }).timeout(_timeout);
  }

  // ---------------- Bible ----------------

  /// Downloads the Tamil Bible and the English KJV (66 + 66 books).
  Future<void> downloadBible({void Function(int done, int total)? onProgress}) async {
    await _ready();
    final files = LocalFiles.instance;
    final meta = await _get('catalog/bible');
    final booksJson = meta.data()?['books'] as String?;
    if (booksJson == null) throw StateError('Bible is not uploaded yet');

    final langs = appProfile.englishOnly ? const ['en'] : const ['ta', 'en'];
    final total = 66 * langs.length;
    var done = 0;
    onProgress?.call(0, total);
    for (final lang in langs) {
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
