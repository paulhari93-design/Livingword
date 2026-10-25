import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Small settings store kept in one JSON file in the app's private folder.
/// (Replaces shared_preferences, which did not keep values in the Play Store build.)
///
/// Holds: theme, font size, Bible language, highlights and setup flags.
class Prefs {
  Prefs._();
  static final Prefs instance = Prefs._();

  Map<String, dynamic>? _data;
  File? _file;
  Future<void>? _loading;
  Future<void> _writing = Future.value();

  Future<void> _ensureLoaded() {
    if (_data != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _file = File('${dir.path}/settings.json');
      if (await _file!.exists()) {
        final decoded = jsonDecode(await _file!.readAsString());
        _data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } else {
        _data = <String, dynamic>{};
      }
    } catch (_) {
      _data = <String, dynamic>{};
    }
  }

  Future<void> _save() {
    // One write at a time, always the latest values; temp file then rename.
    _writing = _writing.then((_) async {
      final f = _file;
      if (f == null) return;
      try {
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode(_data), flush: true);
        await tmp.rename(f.path);
      } catch (_) {}
    });
    return _writing;
  }

  Future<String?> getString(String key) async {
    await _ensureLoaded();
    final v = _data![key];
    return v is String ? v : null;
  }

  Future<double?> getDouble(String key) async {
    await _ensureLoaded();
    final v = _data![key];
    return v is num ? v.toDouble() : null;
  }

  Future<bool?> getBool(String key) async {
    await _ensureLoaded();
    final v = _data![key];
    return v is bool ? v : null;
  }

  Future<void> set(String key, Object? value) async {
    await _ensureLoaded();
    if (value == null) {
      _data!.remove(key);
    } else {
      _data![key] = value;
    }
    await _save();
  }
}
