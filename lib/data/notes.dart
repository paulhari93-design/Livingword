import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// One of the user's notes (sermon notes).
class Note {
  final String id;
  String title;
  String body;
  int updated; // milliseconds since 1970

  Note({required this.id, required this.title, this.body = '', required this.updated});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'body': body, 'updated': updated};

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        updated: (j['updated'] as num?)?.toInt() ?? 0,
      );
}

/// All notes, saved on the phone. Listeners are told when anything changes.
class NotesStore extends ChangeNotifier {
  NotesStore._();
  static final NotesStore instance = NotesStore._();

  static const maxNotes = 50;
  static const _key = 'notes';
  static const _activeKey = 'active_note';

  List<Note> _notes = [];
  String? _activeId;
  bool _loaded = false;

  List<Note> get notes => List.unmodifiable(_notes);
  Note? get active {
    for (final n in _notes) {
      if (n.id == _activeId) return n;
    }
    return null;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await Prefs.instance.getString(_key);
      if (raw != null) {
        _notes = (jsonDecode(raw) as List).map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
      }
      _activeId = await Prefs.instance.getString(_activeKey);
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    await Prefs.instance.set(_key, jsonEncode(_notes.map((n) => n.toJson()).toList()));
    await Prefs.instance.set(_activeKey, _activeId);
  }

  /// Adds a note; returns null when there are already [maxNotes].
  Future<Note?> create(String title) async {
    await load();
    if (_notes.length >= maxNotes) return null;
    final note = Note(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
      updated: DateTime.now().millisecondsSinceEpoch,
    );
    _notes.add(note);
    await _save();
    return note;
  }

  Future<void> update(Note note, {String? title, String? body}) async {
    if (title != null) note.title = title.trim();
    if (body != null) note.body = body;
    note.updated = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> delete(Note note) async {
    _notes.removeWhere((n) => n.id == note.id);
    if (_activeId == note.id) _activeId = null;
    await _save();
  }

  /// "Prepare" a note: quotes sent from the Bible and Messages go into it.
  Future<void> setActive(Note? note) async {
    _activeId = note?.id;
    await _save();
  }

  /// Adds [quote] with its [reference] at the end of [note] (nothing is removed).
  Future<void> append(Note note, String quote, String reference) async {
    final entry = '“${quote.trim()}”\n— $reference';
    final body = note.body.trimRight();
    await update(note, body: body.isEmpty ? entry : '$body\n\n$entry');
  }
}
