import 'content_types.dart';

final _tagRe = RegExp(r'<[^>]*>');
final _spaceRe = RegExp(r'\s+');

String stripHtml(String html, {bool trim = true}) {
  final text = html
      .replaceAll(_tagRe, ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(_spaceRe, ' ');
  return trim ? text.trim() : text;
}

/// Splits "A, B ,C" into ["A", "B", "C"].
List<String> splitCodes(Object? value) => value is String
    ? value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
    : const [];

/// One object entry of the knowledge space.
class Entry {
  Entry(this.type, this.json);

  final ContentType type;
  final Map<String, dynamic> json;

  String get erc => json['externalReferenceCode'] as String? ?? '${json['id']}';
  String get title => (json['title'] as String?)?.trim().isNotEmpty == true
      ? json['title'] as String
      : erc;
  String get code {
    final id = type.idField == null ? null : text(type.idField!);
    return id == null || id.isEmpty ? erc : id;
  }

  DateTime? get dateModified =>
      DateTime.tryParse(json['dateModified'] as String? ?? '');

  String? get lifecycleKey => _pick('lifecycleStatus')?['key'] as String?;
  String? get lifecycleName => _pick('lifecycleStatus')?['name'] as String?;
  String? get confidentialityKey => _pick('confidentiality')?['key'] as String?;
  String? get confidentialityName =>
      _pick('confidentiality')?['name'] as String?;

  List<String> get tags => splitCodes(json['tags']);

  Map<String, dynamic>? _pick(String key) {
    final v = json[key];
    return v is Map<String, dynamic> ? v : null;
  }

  /// Display value of a field: picklist name, formatted date or raw string.
  String? text(String key) {
    final v = json[key];
    if (v == null) return null;
    if (v is Map) {
      final name = v['name'] as String?;
      return name == null || name.isEmpty ? null : name;
    }
    if (v is String) {
      if (v.trim().isEmpty) return null;
      if (_isoDate.hasMatch(v)) return formatDate(DateTime.parse(v));
      return v;
    }
    return '$v';
  }

  /// Stable value used for filtering (picklist key or raw string).
  String? facetValue(String key) {
    final v = json[key];
    if (v is Map) {
      final k = v['key'] as String?;
      return k == null || k.isEmpty ? null : k;
    }
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  late final String searchText = [
    title,
    erc,
    code,
    json['tags'],
    for (final f in type.facts) text(f.key),
    for (final s in type.sections)
      if (json[s.key] is String) stripHtml(json[s.key] as String),
  ].whereType<String>().join(' \u0001 ').toLowerCase();

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}T');
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
