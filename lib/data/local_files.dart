import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'prefs.dart';
import 'profile.dart';

/// Files saved in the app's private folder on the phone (not visible to other apps).
///
///   messages/index.json      list of {code, title, file, version}
///   messages/<code>.json     {code, title, paragraphs}
///   bible/books.json         list of books
///   bible/ta/<NN>.json       Tamil book   {c: [[verse, ...], ...]}
///   bible/en/<NN>.json       English KJV  {c: [[verse, ...], ...]}
class LocalFiles {
  LocalFiles._();
  static final LocalFiles instance = LocalFiles._();

  Directory? _root;

  Future<Directory> root() async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    _root = Directory('${base.path}/content');
    await _root!.create(recursive: true);
    return _root!;
  }

  Future<File> file(String relativePath) async {
    final r = await root();
    final f = File('${r.path}/$relativePath');
    await f.parent.create(recursive: true);
    return f;
  }

  Future<bool> exists(String relativePath) async => (await file(relativePath)).exists();

  Future<String?> readString(String relativePath) async {
    final f = await file(relativePath);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  Future<dynamic> readJson(String relativePath) async {
    final s = await readString(relativePath);
    return s == null ? null : jsonDecode(s);
  }

  /// Writes through a temporary file so a half-finished download never leaves a broken file.
  Future<void> writeString(String relativePath, String content) async {
    final f = await file(relativePath);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }

  Future<void> writeJson(String relativePath, Object data) =>
      writeString(relativePath, jsonEncode(data));

  Future<void> delete(String relativePath) async {
    final f = await file(relativePath);
    if (await f.exists()) await f.delete();
  }

  // ---- simple flags ----

  static const _setupDoneKey = 'setup_done';
  static const _messagesOnKey = 'messages_downloaded';
  static const _bibleOnKey = 'bible_downloaded';

  Future<bool> _flag(String key) async => (await Prefs.instance.getBool(key)) ?? false;

  Future<void> _setFlag(String key, bool value) => Prefs.instance.set(key, value);

  /// True when at least one message is saved on the phone.
  Future<bool> get hasMessageFiles async {
    try {
      final list = await readJson(appProfile.englishOnly ? 'messages_en/index.json' : 'messages/index.json');
      return list is List && list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// True when the Bible is saved on the phone.
  Future<bool> get hasBibleFiles async {
    try {
      final books = await readJson('bible/books.json');
      return books is List &&
          books.isNotEmpty &&
          await exists(appProfile.englishOnly ? 'bible/en/01.json' : 'bible/ta/01.json');
    } catch (_) {
      return false;
    }
  }

  Future<bool> get setupDone async =>
      await _flag(_setupDoneKey) || await hasMessageFiles || await hasBibleFiles;
  Future<void> markSetupDone() => _setFlag(_setupDoneKey, true);

  /// Decided by the files themselves, so it can never get out of step.
  Future<bool> get messagesDownloaded => hasMessageFiles;
  Future<void> setMessagesDownloaded(bool v) => _setFlag(_messagesOnKey, v);

  Future<bool> get bibleDownloaded => hasBibleFiles;
  Future<void> setBibleDownloaded(bool v) => _setFlag(_bibleOnKey, v);
}
