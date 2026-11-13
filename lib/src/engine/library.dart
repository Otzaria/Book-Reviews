// נתוני otzaria-library שהמחולל הרשמי קורא: מיקום הספרים (BOOK_ROOTS), תיקיות הקישורים,
// metadata.json וקובצי ForDB. הכול לקריאה בלבד.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'rules.dart';

/// עותק של BOOK_ROOTS מ-manual_links_packaging.py (משמש כשאי אפשר לקרוא את הקובץ).
const defaultBookRoots = [
  'Ben-YehudaToOtzaria/ספרים/אוצריא',
  'DictaToOtzaria/ערוך/ספרים/אוצריא',
  'OnYourWayToOtzaria/ספרים/אוצריא',
  'OraytaToOtzaria/ספרים/אוצריא',
  'tashmaToOtzaria/ספרים/אוצריא',
  'sefariaToOtzaria/sefaria_export/ספרים/אוצריא',
  'sefariaToOtzaria/sefaria_api/ספרים/אוצריא',
  'MoreBooks/ספרים/אוצריא',
  'KSK/ספרים/אוצריא',
  'wikiJewishBooksToOtzaria/ספרים/אוצריא',
  'wikisourceToOtzaria/ספרים/אוצריא',
  'ToratEmetToOtzaria/ספרים/אוצריא',
  'pninimToOtzaria/ספרים/אוצריא',
  'National-LibraryToOtzaria/ספרים/אוצריא',
  'yam-HaHachmaToOtzaria/ספרים/אוצריא',
  'BeitAharonVeYisraelToOtzaria/ספרים/אוצריא',
];

/// מקורות שהמחולל מדלג עליהם (source-blacklist.txt).
const sourceBlacklist = ['sefariaToOtzaria', 'wiki_jewish_books'];

/// תיקיות עליונות שנמחקות לפני הבנייה (otzaria-folder-to-remove.txt).
const foldersToRemove = ['אודות התוכנה', 'אודות על התוכנה', 'הודעה חשובה'];

/// קורא את BOOK_ROOTS מתוך manual_links_packaging.py.
List<String> readBookRoots(String libraryPath) {
  try {
    final src = File(p.join(libraryPath, 'manual_links_packaging.py')).readAsStringSync();
    final m = RegExp(r'BOOK_ROOTS\s*=\s*\(([^)]*)\)').firstMatch(src);
    if (m == null) return defaultBookRoots;
    final roots = [for (final q in RegExp(r'"([^"]+)"').allMatches(m.group(1)!)) q.group(1)!];
    return roots.isEmpty ? defaultBookRoots : roots;
  } catch (_) {
    return defaultBookRoots;
  }
}

/// מיקום של ספר בספרייה: מקור + נתיב תיקיות (שמות גולמיים) אחרי "אוצריא".
class LibraryPlace {
  LibraryPlace(this.source, this.folders, this.path, this.root);
  final String source;
  final List<String> folders;
  final String path;

  /// השורש מתוך BOOK_ROOTS (יחסי לספרייה).
  final String root;
}

/// אינדקס הספרייה: מיקום כל ספר נארז, קובצי הקישורים וה-alt_toc.
class LibraryIndex {
  LibraryIndex._(this.libraryPath, this.roots, this.byTitle, this.linkFiles, this.altTocFiles, this.linksRoots);

  final String libraryPath;
  final List<String> roots;

  /// book.title (מנורמל) → כל המיקומים.
  final Map<String, List<LibraryPlace>> byTitle;

  /// שם קובץ `<x>_links.json` → נתיב (מתיקיות הקישורים הנארזות).
  final Map<String, String> linkFiles;

  /// שם קובץ `<x>_alt_toc.json` → נתיב.
  final Map<String, String> altTocFiles;
  final List<String> linksRoots;

  static LibraryIndex empty() => LibraryIndex._('', const [], const {}, const {}, const {}, const []);

  bool get isEmpty => libraryPath.isEmpty;

  static LibraryIndex scan(String libraryPath) {
    if (libraryPath.isEmpty || !Directory(libraryPath).existsSync()) return empty();
    final roots = readBookRoots(libraryPath);
    final byTitle = <String, List<LibraryPlace>>{};
    for (final root in roots) {
      final dir = Directory(p.joinAll([libraryPath, ...root.split('/')]));
      if (!dir.existsSync()) continue;
      final source = root.split('/').first;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is! File || p.extension(e.path).toLowerCase() != '.txt') continue;
        final rel = p.split(p.relative(e.path, from: dir.path));
        final title = bookTitleOf(p.basenameWithoutExtension(e.path));
        (byTitle[title] ??= []).add(LibraryPlace(source, rel.sublist(0, rel.length - 1), e.path, root));
      }
    }
    final linksRoots = <String>[];
    try {
      final cfg = jsonDecode(File(p.join(libraryPath, 'manual_links_sync.json')).readAsStringSync());
      for (final r in (cfg['links_roots'] as List)) {
        if (r is Map && r['expected_state'] == 'present' && r['path'] is String) linksRoots.add(r['path'] as String);
      }
    } catch (_) {
      for (final root in roots) {
        linksRoots.add('${root.split('/').first}/links');
      }
    }
    final linkFiles = <String, String>{};
    for (final lr in linksRoots) {
      final d = Directory(p.joinAll([libraryPath, ...lr.split('/')]));
      if (!d.existsSync()) continue;
      for (final f in d.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (name.endsWith('_links.json')) linkFiles.putIfAbsent(name, () => f.path);
      }
    }
    final altTocFiles = <String, String>{};
    for (final root in roots) {
      final parts = root.split('/');
      final idx = parts.indexOf('ספרים');
      final base = idx > 0 ? parts.sublist(0, idx) : [parts.first];
      final d = Directory(p.joinAll([libraryPath, ...base, 'alt_toc']));
      if (!d.existsSync()) continue;
      for (final f in d.listSync().whereType<File>()) {
        final name = p.basename(f.path);
        if (name.endsWith('_alt_toc.json')) altTocFiles.putIfAbsent(name, () => f.path);
      }
    }
    return LibraryIndex._(libraryPath, roots, byTitle, linkFiles, altTocFiles, linksRoots);
  }
}

// ───────────────────────── CSV של ForDB ─────────────────────────

/// `parseForDbCsvRecords` אחרי readLines + join("\n"): מירכאה פותחת שדה רק בתחילתו,
/// רשומה ריקה לגמרי בלי תחביר CSV נזרקת.
List<List<String>> parseForDbCsv(String text) {
  text = stripBom(text).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final records = <List<String>>[];
  var fields = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  var syntax = false;
  void endField() {
    fields.add(sb.toString());
    sb.clear();
  }

  void endRecord() {
    endField();
    if (fields.any((f) => f.isNotEmpty) || syntax) records.add(fields);
    fields = <String>[];
    syntax = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        sb.write(c);
      }
    } else if (c == '"' && sb.isEmpty) {
      inQuotes = true;
      syntax = true;
    } else if (c == ',') {
      syntax = true;
      endField();
    } else if (c == '\n') {
      endRecord();
    } else {
      sb.write(c);
    }
  }
  if (inQuotes) throw const FormatException('שדה במירכאות שלא נסגר');
  if (sb.isNotEmpty || fields.isNotEmpty) endRecord();
  return records;
}

// ───────────────────────── המטא-דאטה ─────────────────────────

class BookMeta {
  BookMeta(this.raw);
  final Map<String, Object?> raw;
  String get title => raw['title'] is String ? raw['title'] as String : '';
  String? _s(String k) => raw[k] is String ? raw[k] as String : null;
  String? get heShortDesc => _s('heShortDesc');
  String? get pubDate => raw['pubDate'] is String ? raw['pubDate'] as String : (raw['pubDate'] is num ? '${raw['pubDate']}' : null);
  String? get pubPlace => _s('pubPlace');
  double? get order => raw['order'] is num ? (raw['order'] as num).toDouble() : null;

  /// `resolveAuthorNames`.
  List<String> get authorNames {
    final list = raw['authors'];
    if (list is List) {
      final fromList = <String>[];
      for (final a in list) {
        if (a is String && ktTrim(a).isNotEmpty && !fromList.contains(ktTrim(a))) fromList.add(ktTrim(a));
      }
      if (fromList.isNotEmpty) return fromList;
    }
    final a = _s('author');
    return a == null || ktTrim(a).isEmpty ? const [] : [ktTrim(a)];
  }
}

class Description {
  Description(this.heShortDesc, this.heDesc);
  final String? heShortDesc;
  final String? heDesc;
}

class CategoryDescEdit {
  CategoryDescEdit(this.shortEdit, this.longEdit);

  /// null = להשאיר, '' = למחוק ([מחק]), אחרת ערך חדש.
  final String? shortEdit;
  final String? longEdit;
}

class BannerRow {
  BannerRow(this.id, this.source, this.book, this.text);
  final int id;
  final String source;
  final String book;
  final String text;
}

class ProtectionRow {
  ProtectionRow(this.source, this.book, this.level);
  final String source;
  final String book;
  final int level;
}

/// מטא-דאטה מהספרייה: metadata.json + ForDB.
class LibraryMeta {
  LibraryMeta();

  /// metadata.json כמו `associateBy { it.title }` (כפילות: האחרון גובר).
  final Map<String, BookMeta> metadata = {};

  /// כותרות אחרי trim → הכותרת הגולמית (לאבחון רווחים מיותרים).
  final Map<String, String> metadataTrimmed = {};

  /// book_info.csv: כותרת → דור (אחרי הכרעת רוב), ושמות הדורות לפי סדר ההכנסה של המחולל
  /// (הדור שנבחר לכל ספר, לפי סדר ההופעה הראשונה של הספר בקובץ).
  final Map<String, String> generationByTitle = {};
  final Map<String, List<String>> generationConflicts = {};
  final List<String> generationNames = [];

  /// all_metadata.json.
  final Map<String, (List<int>, String?)> bulk = {};

  /// sefaria_metadata_changes.csv.
  final Map<String, Description> descriptions = {};

  /// sefaria_category_changes.csv: נתיב קנוני → עריכות.
  final Map<String, CategoryDescEdit> categoryEdits = {};

  final List<BannerRow> banners = [];
  final List<ProtectionRow> protections = [];
  final List<String> errors = [];
  final List<String> loaded = [];

  static LibraryMeta load(String libraryPath) {
    final m = LibraryMeta();
    if (libraryPath.isEmpty) return m;
    String? read(String rel) {
      final f = File(p.joinAll([libraryPath, ...rel.split('/')]));
      if (!f.existsSync()) {
        m.errors.add('לא נמצא: $rel');
        return null;
      }
      m.loaded.add(rel);
      return utf8.decode(f.readAsBytesSync(), allowMalformed: true);
    }

    void guard(String what, void Function() fn) {
      try {
        fn();
      } catch (e) {
        m.errors.add('$what: $e');
      }
    }

    guard('metadata.json', () {
      final text = read('metadata.json');
      if (text == null) return;
      final j = jsonDecode(stripBom(text));
      final list = j is List ? j : (j is Map ? j.values.toList() : const []);
      for (final e in list) {
        if (e is! Map) continue;
        final meta = BookMeta(e.cast<String, Object?>());
        if (j is Map) {
          // מבנה מפה: המפתח הוא הכותרת.
        }
        m.metadata[meta.title] = meta;
        m.metadataTrimmed[ktTrim(meta.title)] = meta.title;
      }
      if (j is Map) {
        m.metadata
          ..clear()
          ..addAll({for (final e in j.entries) if (e.value is Map) '${e.key}': BookMeta((e.value as Map).cast<String, Object?>())});
      }
    });

    guard('ForDB/book_info.csv', () {
      final text = read('ForDB/book_info.csv');
      if (text == null) return;
      final rows = parseForDbCsv(text);
      const header = ['bookName', 'authorName', 'generationName', 'subGenerationName', 'startYear', 'endYear'];
      if (rows.isEmpty || rows.first.join(',') != header.join(',')) {
        throw const FormatException('כותרת לא צפויה');
      }
      final byTitle = <String, List<String>>{};
      for (final f in rows.skip(1)) {
        if (f.length != header.length || f[0].isEmpty) continue;
        if (f[2].isEmpty) continue;
        (byTitle[f[0]] ??= []).add(f[2]);
      }
      for (final e in byTitle.entries) {
        final counts = <String, int>{};
        for (final g in e.value) {
          counts[g] = (counts[g] ?? 0) + 1;
        }
        final best = counts.values.reduce((a, b) => a > b ? a : b);
        final chosen = e.value.firstWhere((g) => counts[g] == best);
        m.generationByTitle[e.key] = chosen;
        if (!m.generationNames.contains(chosen)) m.generationNames.add(chosen);
        if (counts.length > 1) m.generationConflicts[e.key] = counts.keys.toList();
      }
    });

    guard('ForDB/all_metadata.json', () {
      final text = read('ForDB/all_metadata.json');
      if (text == null) return;
      for (final e in (jsonDecode(stripBom(text)) as List)) {
        if (e is! Map) continue;
        final title = _jsonString(e['title']);
        if (title == null) continue;
        final dates = <int>[];
        final pd = e['pubDate'];
        if (pd is List) {
          for (final d in pd) {
            final v = d is int ? d : (d is String ? int.tryParse(d) : null);
            if (v != null) dates.add(v);
          }
        }
        m.bulk[title] = (dates, _jsonString(e['pubPlaceStringHe']));
      }
    });

    guard('ForDB/sefaria_metadata_changes.csv', () {
      final text = read('ForDB/sefaria_metadata_changes.csv');
      if (text == null) return;
      final rows = parseForDbCsv(text);
      for (final r in rows.skip(1)) {
        final cols = [for (final c in r) ktTrim(c)];
        final title = cols.length > 1 && !ktIsBlank(cols[1]) ? cols[1] : null;
        if (title == null) continue;
        String? col(int i) => i < cols.length && !ktIsBlank(cols[i]) ? cols[i] : null;
        m.descriptions[title] = Description(col(3), col(5));
      }
    });

    guard('ForDB/sefaria_category_changes.csv', () {
      final text = read('ForDB/sefaria_category_changes.csv');
      if (text == null) return;
      String? edit(String raw) {
        final v = ktTrim(raw);
        if (v.isEmpty) return null;
        return v == '[מחק]' ? '' : v;
      }

      for (final r in parseForDbCsv(text).skip(1)) {
        if (r.length != 5 || ktIsBlank(r[0])) continue;
        m.categoryEdits[r[0]] = CategoryDescEdit(edit(r[3]), edit(r[4]));
      }
    });

    guard('ForDB/book_banners.csv', () {
      final text = read('ForDB/book_banners.csv');
      if (text == null) return;
      final rows = parseForDbCsv(text);
      for (final r in rows.skip(1)) {
        if (r.length != 4 || ktIsBlank(r[1])) continue;
        final id = int.tryParse(r[0]);
        if (id == null || id < 1 || ktIsBlank(r[3])) continue;
        m.banners.add(BannerRow(id, r[1], r[2], r[3]));
      }
    });

    guard('ForDB/book_protection.csv', () {
      final text = read('ForDB/book_protection.csv');
      if (text == null) return;
      for (final r in parseForDbCsv(text).skip(1)) {
        if (r.length != 3 || ktIsBlank(r[0])) continue;
        final level = int.tryParse(ktTrim(r[2]));
        if (level == null || level < 1) continue;
        m.protections.add(ProtectionRow(r[0], r[1], level));
      }
    });
    return m;
  }

  static String? _jsonString(Object? v) {
    if (v == null) return null;
    final s = ktTrim(v is String ? v : '$v');
    return ktIsBlank(s) ? null : s;
  }

  /// `metadata[rawStem] ?: metadata[title] ?: metadata[stripQuotes(rawStem)]`.
  BookMeta? lookup(String rawStem, String title) =>
      metadata[rawStem] ?? metadata[title] ?? metadata[stripQuotesForLookup(rawStem)];

  /// רשומה שנמצאת רק אחרי הסרת רווחים מיותרים מהכותרת (המחולל הרשמי לא ימצא אותה).
  BookMeta? lookupTrimmedOnly(String rawStem, String title) {
    for (final k in [rawStem, title, stripQuotesForLookup(rawStem)]) {
      final raw = metadataTrimmed[ktTrim(k)];
      if (raw != null && raw != k) return metadata[raw];
    }
    return null;
  }
}

// ───────────────────────── קובצי קישורים ─────────────────────────

class LinkEntry {
  LinkEntry({
    required this.heRef2,
    required this.lineIndex1,
    required this.path2,
    required this.lineIndex2,
    required this.connectionType,
    this.start,
    this.end,
    this.lineIndex1End,
    this.lineIndex2End,
    this.usesConnectionTypeSpelling = false,
  });
  final String heRef2;
  final double lineIndex1;
  final String path2;
  final double lineIndex2;
  final String connectionType;
  final double? start, end, lineIndex1End, lineIndex2End;

  /// הרשומה כתבה "Connection Type" (בלי "Conection Type"), שהמחולל מתעלם ממנו.
  final bool usesConnectionTypeSpelling;
}

class LinkFileParse {
  LinkFileParse(this.entries, this.error);
  final List<LinkEntry> entries;

  /// null = תקין. אחרת המחולל הרשמי קורא 0 קישורים מכל הקובץ.
  final String? error;
}

/// `parseLinksFromJson`: רשימת אובייקטים בקפדנות של kotlinx (ignoreUnknownKeys, coerceInputValues).
/// כל רשומה פגומה מפילה את כל הקובץ (0 קישורים).
LinkFileParse parseLinksJson(String raw) {
  final Object? j;
  try {
    j = jsonDecode(stripBom(raw));
  } catch (e) {
    return LinkFileParse(const [], 'JSON לא תקין: $e');
  }
  if (j is! List) {
    return LinkFileParse(const [], j is Map ? 'מבנה מפה (פורמט דיקטה) — המחולל אינו ממיר אותו ומדלג' : 'אינו רשימה');
  }
  double? num_(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(ktTrim(v));
    return null;
  }

  final out = <LinkEntry>[];
  for (var i = 0; i < j.length; i++) {
    final e = j[i];
    String fail(String why) => 'רשומה ${i + 1}: $why';
    if (e is! Map) return LinkFileParse(const [], fail('אינה אובייקט'));
    final he = e['heRef_2'];
    if (he is! String) return LinkFileParse(const [], fail(he == null ? 'חסר heRef_2' : 'heRef_2 אינו מחרוזת'));
    final path = e['path_2'];
    if (path is! String) return LinkFileParse(const [], fail('חסר path_2'));
    final l1 = num_(e['line_index_1']), l2 = num_(e['line_index_2']);
    if (l1 == null || l2 == null) return LinkFileParse(const [], fail('line_index_1/line_index_2 חסר או לא מספרי'));
    final ct = e['Conection Type'];
    if (ct != null && ct is! String) return LinkFileParse(const [], fail('"Conection Type" אינו מחרוזת'));
    double? opt(String k) {
      final v = e[k];
      if (v == null) return null;
      return num_(v) ?? double.nan;
    }

    final s = opt('start'), en = opt('end'), e1 = opt('line_index_1_end'), e2 = opt('line_index_2_end');
    if ([s, en, e1, e2].any((v) => v != null && v.isNaN)) return LinkFileParse(const [], fail('ערך מספרי לא תקין'));
    out.add(
      LinkEntry(
        heRef2: he,
        lineIndex1: l1,
        path2: path,
        lineIndex2: l2,
        connectionType: (ct as String?) ?? '',
        start: s,
        end: en,
        lineIndex1End: e1,
        lineIndex2End: e2,
        usesConnectionTypeSpelling: !e.containsKey('Conection Type') && e.containsKey('Connection Type'),
      ),
    );
  }
  return LinkFileParse(out, null);
}

/// כותרת היעד של path_2 (`linkTargetTitleOf`): החלק האחרון, בלי הסיומת.
String linkTargetTitle(String path2) {
  final last = path2.contains('\\') ? path2.split('\\').last : path2.split('/').last;
  final dot = last.lastIndexOf('.');
  return dot < 0 ? last : last.substring(0, dot);
}

/// Kotlin `Double.toInt()`: קיטום לכיוון 0, NaN → 0.
int ktToInt(double v) => v.isNaN ? 0 : v.truncate();
