import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<bool> _flag(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setFlag(String key, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, value);
    } catch (_) {}
  }

  Future<bool> get setupDone => _flag(_setupDoneKey);
  Future<void> markSetupDone() => _setFlag(_setupDoneKey, true);

  Future<bool> get messagesDownloaded => _flag(_messagesOnKey);
  Future<void> setMessagesDownloaded(bool v) => _setFlag(_messagesOnKey, v);

  Future<bool> get bibleDownloaded => _flag(_bibleOnKey);
  Future<void> setBibleDownloaded(bool v) => _setFlag(_bibleOnKey, v);
}
