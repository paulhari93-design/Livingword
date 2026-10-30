import 'local_files.dart';

/// A group of messages preached as a series (e.g. The Seven Seals), in order.
class SeriesInfo {
  final String en;
  final String ta;
  final List<String> codes;
  const SeriesInfo({required this.en, required this.ta, required this.codes});

  factory SeriesInfo.fromJson(Map<String, dynamic> j) => SeriesInfo(
        en: j['en'] as String? ?? '',
        ta: (j['ta'] as String?)?.trim().isNotEmpty == true ? j['ta'] as String : (j['en'] as String? ?? ''),
        codes: ((j['codes'] as List?) ?? const []).map((e) => (e as String).toUpperCase()).toList(),
      );

  String name(String lang) => lang == 'en' ? en : ta;
}

/// The series list (series.json, downloaded with the messages).
class SeriesStore {
  SeriesStore._();
  static final SeriesStore instance = SeriesStore._();

  List<SeriesInfo>? _cache;

  void reload() => _cache = null;

  Future<List<SeriesInfo>> all() async {
    final cached = _cache;
    if (cached != null) return cached;
    List? list;
    try {
      list = (await LocalFiles.instance.readJson('series.json')) as List?;
    } catch (_) {}
    final result = (list ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SeriesInfo.fromJson)
        .where((s) => s.codes.isNotEmpty)
        .toList();
    _cache = result;
    return result;
  }
}
