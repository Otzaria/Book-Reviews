// Pure-Dart port of the `line_dh` (dibbur hamatchil) index builder of the
// official generator.
//
// Mirrors SeforimLibrary @ a193aa15d (files last touched in 88c2067):
//  - core/src/commonMain/kotlin/io/github/kdroidfilter/seforimlibrary/core/dh/DhKey.kt -> [DhKey]
//  - generator/common/src/jvmMain/kotlin/io/github/kdroidfilter/seforimlibrary/common/dh/DhExtractor.kt
//      -> [DhExtractor]
//  - generator/common/src/jvmMain/kotlin/io/github/kdroidfilter/seforimlibrary/common/dh/BuildLineDhIndexCli.kt
//      -> [buildLineDhRows] / [analyzeLineDh] (the per-book body of indexAllBooks),
//         [NoiseRatios], [parseBookOverrides], [mergeLeadHits]
//  - generator/common/src/jvmMain/resources/line_dh_book_overrides.csv
//      -> embedded in line_dh_overrides.dart ([defaultLineDhBookOverrides])
//
// The stage is per book; the only shared input is the reviewed overrides CSV,
// keyed by (source.name, book.title).
//
// Input text: `line.content` as it is in the DB when the stage runs. In the
// official pipeline buildLineDhIndex runs after buildLineNoteIndex
// (build.gradle.kts: `mustRunAfter(":generator-common:buildLineNoteIndex")`),
// so it reads the text with inline footnote bodies already moved to line_note.
//
// Same JVM-semantics notes as line_ref.dart (ASCII `\s`, java `$`, code-point
// regexes, Kotlin trim/isBlank/isLetterOrDigit). IGNORE_CASE without
// UNICODE_CASE is ASCII-only in Java, so the case-insensitive tags are spelled
// as explicit [xX] classes rather than Dart's Unicode case folding.
// No deliberate deviation.

import 'line_dh_overrides.dart';
import 'line_ref.dart';

/// Port of `io.github.kdroidfilter.seforimlibrary.core.dh.DhKey`.
abstract final class DhKey {
  static final RegExp _points = jRegex(r'[֑-ׇ]');
  static final RegExp _whitespace = jRegex('[$jWs]+');

  static bool _isEdge(int c) => _edgePunctuation.contains(c) || c == 0x20;

  /// Canonical form of [raw], or `null` when nothing usable is left.
  static String? normalize(String raw) {
    var s = raw.replaceAll('־', ' ').replaceAll('׀', ' ').replaceAll('|', ' ');
    s = s.replaceAll(_points, '');
    s = s.replaceAll('"', '').replaceAll("'", '').replaceAll('״', '').replaceAll('׳', '');
    s = ktTrim(s.replaceAll(_whitespace, ' '));
    s = ktTrimWhere(s, _isEdge);
    if (s.isEmpty) return null;
    return s.length >= 2 ? s : null;
  }
}

/// `.,:;?!()[]` as code units (DhKey / DhExtractor EDGE_PUNCTUATION).
final Set<int> _edgePunctuation = '.,:;?!()[]'.codeUnits.toSet();

enum DhFormat { bold, dash, boldLead }

/// One extracted dibbur: [key] is the DhKey form, [display] the printed form.
class Dh {
  final String key;
  final String display;
  const Dh(this.key, this.display);

  @override
  bool operator ==(Object other) => other is Dh && other.key == key && other.display == display;

  @override
  int get hashCode => Object.hash(key, display);

  @override
  String toString() => 'Dh($key, $display)';
}

/// Port of `io.github.kdroidfilter.seforimlibrary.common.dh.DhExtractor`.
abstract final class DhExtractor {
  static const int _maxDhLength = 100;

  static final RegExp _headingLine = jRegex('^﻿?[$jWs]*<[hH][1-6]');

  static final RegExp _boldPrefix = jRegex(
    '^﻿?[$jWs]*(?:<(?:[bB][iI][gG]|[sS][mM][aA][lL][lL]|[sS][pP][aA][nN][^>]*)>[$jWs]*)*'
    '<[bB]>[$jWs]*([^<]{1,$_maxDhLength}?)[$jWs]*</[bB]>(.*)$jEnd',
    dotAll: true,
  );

  static final RegExp _spacedDash = jRegex('[$jWs][-–—][$jWs]');
  static const String _sentenceBreak = '. ';
  static const int _longDashDh = 40;
  static final RegExp _tag = jRegex(r'<[^>]+>');
  static final RegExp _htmlEntity = jRegex(r'&(?:#\d+|#x[\da-fA-F]+|[A-Za-z][A-Za-z0-9]+);');
  static final RegExp _leadEndMarker = jRegex(
    '(?:^|[$jWs])(?:ו?כו|וגו)[\x27׳’]'
    '(?=[$jWs]|$jEnd|[.,:;)\\]])',
  );
  static const int _maxLeadWords = 10;
  static final RegExp _sentenceDelimiter = jRegex('[.:;?!][$jWs]');

  static const Set<String> _stopMarkers = {
    "מתני'", 'מתני', 'מתניתין', "גמ'", 'גמ', 'גמרא', 'שם', 'בא"ד', 'באד', //
    'ד"ה', 'בד"ה', 'תוד"ה', "תוס'", 'תוס', 'רש"י', "רשי'", 'רשי', 'פירש"י', //
    'הדרן', 'סליק', 'תשובה', 'שאלה', 'מכתב', 'הקדמה', 'הגה', 'הג"ה', //
    'פרק', 'משנה', 'הלכה', 'סימן', 'סעיף', 'ירושלמי', "וכו'", 'וכו', //
  };

  static final RegExp _points = jRegex(r'[֑-ׇ]');
  static final RegExp _whitespace = jRegex('[$jWs]+');

  static const String _generatedDashOpen = '<b><b></b><i></i>';
  static const String _generatedDashClose = '</b>';

  static final RegExp _numberingMarker = jRegex('^[$jWs]*\\(([א-ת]{1,5})\\) ');
  static final Set<String> _gematria1To999 = {for (var i = 1; i <= 999; i++) _gematria(i)};

  /// Extracts the dibbur of [line] in [format], or `null`.
  static Dh? extract(String line, DhFormat format) {
    final raw = _originalGeneratedDashLine(line);
    if (raw != null) {
      return format == DhFormat.boldLead ? null : _extractDash(_withoutNumberingMarker(raw));
    }
    final text = _withoutNumberingMarker(line);
    return switch (format) {
      DhFormat.bold => _extractBold(text),
      DhFormat.dash => _extractDash(text),
      DhFormat.boldLead => _extractBoldLead(text),
    };
  }

  static String _withoutNumberingMarker(String line) {
    final m = _numberingMarker.firstMatch(line);
    if (m == null) return line;
    return _gematria1To999.contains(m.group(1)) ? line.substring(m.end) : line;
  }

  static String _gematria(int value) {
    var n = value;
    final sb = StringBuffer();
    while (n >= 400) {
      sb.write('ת');
      n -= 400;
    }
    for (final (v, c) in const [(300, 'ש'), (200, 'ר'), (100, 'ק')]) {
      if (n >= v) {
        sb.write(c);
        n -= v;
      }
    }
    if (n == 15 || n == 16) {
      sb
        ..write('ט')
        ..write(n == 15 ? 'ו' : 'ז');
      return sb.toString();
    }
    if (n >= 10) {
      sb.write('יכלמנסעפצ'[n ~/ 10 - 1]);
      n %= 10;
    }
    if (n > 0) sb.write('אבגדהוזחט'[n - 1]);
    return sb.toString();
  }

  /// Bolds an accepted DASH prefix without changing its raw text or tail.
  static String boldDashDibbur(String line) {
    final end = dashDibburEnd(line);
    if (end == null) return line;
    final dibbur = ktTrimEnd(line.substring(0, end));
    return _generatedDashOpen + dibbur + _generatedDashClose + line.substring(dibbur.length);
  }

  /// Restores only the exact generated wrapper for index format statistics.
  static String sourceLineForIndex(String line) => _originalGeneratedDashLine(line) ?? line;

  static String? _originalGeneratedDashLine(String line) {
    if (!line.startsWith(_generatedDashOpen)) return null;
    final close = line.indexOf(_generatedDashClose, _generatedDashOpen.length);
    if (close < _generatedDashOpen.length || close - _generatedDashOpen.length > _maxDhLength) {
      return null;
    }
    final dibbur = line.substring(_generatedDashOpen.length, close);
    final raw = dibbur + line.substring(close + _generatedDashClose.length);
    final end = dashDibburEnd(raw);
    if (end == null) return null;
    return ktTrimEnd(raw.substring(0, end)) == dibbur ? raw : null;
  }

  /// `true` when [line] is a `<h1>`–`<h6>` heading.
  static bool isHeadingLine(String line) => _headingLine.hasMatch(line);

  static Dh? _extractBold(String line) {
    if (isHeadingLine(line)) return null;
    final m = _boldPrefix.firstMatch(line);
    if (m == null) return null;
    final rest = ktTrim(m.group(2)!.replaceAll(_tag, ''));
    if (rest.isEmpty) return null;
    return _accept(m.group(1)!);
  }

  static Dh? _extractBoldLead(String line) {
    if (isHeadingLine(line)) return null;
    final m = _boldPrefix.firstMatch(line);
    if (m == null) return null;
    final boldRaw = ktTrim(m.group(1)!);
    final rest = m.group(2)!;

    final marker = _leadEndMarker.firstMatch(rest);
    if (marker == null) return null;

    final firstTag = rest.indexOf('<');
    if (firstTag >= 0 && firstTag < marker.start) return null;

    final continuation = ktTrim(rest.substring(0, marker.start));
    if (continuation.isEmpty) return null;
    final rawDh = '$boldRaw $continuation';
    if (rawDh.length > _maxDhLength) return null;

    if (boldRaw.isNotEmpty && '.,:;?!'.contains(boldRaw[boldRaw.length - 1])) return null;
    if (_sentenceDelimiter.hasMatch(rawDh)) return null;
    // Kotlin Regex.split size = matches + 1 (keeps leading/trailing empties).
    if (_whitespace.allMatches(ktTrim(rawDh)).length + 1 > _maxLeadWords) return null;

    final commentaryStart = marker.end;
    var nextTag = rest.indexOf('<', commentaryStart);
    if (nextTag < 0) nextTag = rest.length;
    final commentary = ktTrim(rest.substring(commentaryStart, nextTag).replaceAll(_htmlEntity, ''));
    if (!commentary.codeUnits.any(jIsLetterOrDigit)) return null;

    final boldDh = _accept(boldRaw);
    if (boldDh == null) return null;
    final leadDh = _accept(rawDh);
    if (leadDh == null) return null;
    return leadDh.display.length > boldDh.display.length ? leadDh : null;
  }

  /// End (exclusive) of the DASH dibbur in [line], or `null`.
  static int? dashDibburEnd(String line) {
    final cut = _dashCut(line);
    if (cut == null) return null;
    return _accept(line.substring(0, cut)) != null ? cut : null;
  }

  static Dh? _extractDash(String line) {
    final cut = _dashCut(line);
    return cut == null ? null : _accept(line.substring(0, cut));
  }

  static int? _dashCut(String line) {
    if (isHeadingLine(line)) return null;
    final m = _spacedDash.firstMatch(line);
    if (m == null) return null;
    var end = m.start;
    // Kotlin lastIndexOf('<', end - 1) is -1 for a negative start index.
    if (end > _maxDhLength || (end - 1 >= 0 && line.lastIndexOf('<', end - 1) >= 0)) return null;
    if (ktIsBlank(line.substring(m.end))) return null;
    if (end > _longDashDh) {
      final cut = line.indexOf(_sentenceBreak);
      if (cut > 0 && cut + _sentenceBreak.length <= end) end = cut;
    }
    return end;
  }

  static bool _isEdge(int c) => _edgePunctuation.contains(c) || c == 0x20;

  static Dh? _accept(String rawDh) {
    final marker = ktTrimWhere(
      ktTrim(_foldQuotes(rawDh.replaceAll(_points, ''))),
      _isEdge,
    );
    if (_stopMarkers.contains(marker)) return null;
    final key = DhKey.normalize(rawDh);
    if (key == null) return null;
    final display = ktTrimWhere(rawDh.replaceAll(_whitespace, ' '), _isEdge);
    return Dh(key, display);
  }
}

/// The quote-mark folding shared by DhExtractor.accept and normalizeOpener.
String _foldQuotes(String s) => s
    .replaceAll('״', '"')
    .replaceAll('”', '"')
    .replaceAll('“', '"')
    .replaceAll('׳', "'")
    .replaceAll('’', "'")
    .replaceAll('‘', "'")
    .replaceAll("''", '"');

// ── BuildLineDhIndexCli ────────────────────────────────────────────────────

const double minCoverage = 0.4;
const int minLines = 10;
const double minDistinctRatio = 0.5;
const double distinctRuleOneWordRatio = 0.5;
const double maxOpenerRatio = 0.25;
const double leadShare = 0.75;

const Set<String> openers = {
  'והנה', 'עוד', 'אמנם', 'ובזה', 'ועוד', 'אך', 'אבל', 'אלא', 'ונראה', 'הנה', 'ומה', 'וכן', 'גם', //
  'ויש', 'ומעתה', 'וראיתי', 'ולפי', 'ואם', 'או', 'ועל', 'ודע', 'כל', 'ולכאורה', 'וזהו', 'וזה', //
  'איברא', 'ועתה', 'ולפ"ז', 'ומ"ש', 'ואמנם', 'וגם', 'אכן', 'והשתא', 'ובאמת', 'ולענ"ד', 'ונ"ל', //
  'ואפשר', 'ואולם', 'ובזה יש', 'ומ"מ', 'והא', 'תו', 'לא', 'אמר', 'ומיהו', 'והרי', 'אין', 'אי', //
  'מה', 'א"כ', 'ת"ל', 'שם', 'מ"ש', 'מ"מ', 'שלום', 'אודות', //
};

final RegExp _openerPoints = jRegex(r'[֑-ׇ]');

String normalizeOpener(String display) => ktTrim(_foldQuotes(display.replaceAll(_openerPoints, '')));

/// Per-book shape of the winning format's hits.
class NoiseRatios {
  final double distinctRatio;
  final double oneWordRatio;
  final double openerRatio;
  const NoiseRatios(this.distinctRatio, this.oneWordRatio, this.openerRatio);

  bool get isNoisy =>
      (distinctRatio < minDistinctRatio && oneWordRatio >= distinctRuleOneWordRatio) ||
      openerRatio >= maxOpenerRatio;

  factory NoiseRatios.of(List<Dh> hits) {
    if (hits.isEmpty) throw ArgumentError('noise ratios need at least one hit');
    final total = hits.length.toDouble();
    final distinct = hits.map((h) => h.key).toSet().length;
    final oneWord =
        hits.where((h) => ktTrim(h.display).split(' ').where((w) => w.isNotEmpty).length == 1).length;
    final opener = hits.where((h) => openers.contains(normalizeOpener(h.display))).length;
    return NoiseRatios(distinct / total, oneWord / total, opener / total);
  }

  @override
  String toString() => 'NoiseRatios(distinct=$distinctRatio, oneWord=$oneWordRatio, opener=$openerRatio)';
}

enum BookOverrideDecision { include, exclude }

class BookOverride {
  final BookOverrideDecision decision;
  final String reason;
  const BookOverride(this.decision, this.reason);

  @override
  bool operator ==(Object other) =>
      other is BookOverride && other.decision == decision && other.reason == reason;

  @override
  int get hashCode => Object.hash(decision, reason);
}

/// Override map key: `'$source\u0000$title'` (see [bookOverrideKey]).
String bookOverrideKey(String source, String title) => '$source\u0000$title';

const String _overridesResource = '/line_dh_book_overrides.csv';

/// Port of `parseBookOverrides`; throws [FormatException] where Kotlin `require` fails.
Map<String, BookOverride> parseBookOverrides(String csv) {
  void require(bool ok, String msg) {
    if (!ok) throw FormatException(msg);
  }

  // Kotlin lineSequence(): split on \r\n, \n or \r.
  final records = csv
      .split(RegExp(r'\r\n|\n|\r'))
      .map(ktTrim)
      .where((r) => r.isNotEmpty && !r.startsWith('#'))
      .toList();
  require(records.isNotEmpty, '$_overridesResource is empty');
  final header = _parseCsvRecord(records.first);
  require(
    header.length == 4 &&
        header[0] == 'source' &&
        header[1] == 'title' &&
        header[2] == 'decision' &&
        header[3] == 'reason',
    '$_overridesResource has an invalid header',
  );
  final overrides = <String, BookOverride>{};
  for (var index = 0; index < records.length - 1; index++) {
    final fields = _parseCsvRecord(records[index + 1]);
    final line = index + 2;
    require(fields.length == 4, '$_overridesResource:$line must have 4 fields');
    final source = ktTrim(fields[0]);
    final title = ktTrim(fields[1]);
    require(source.isNotEmpty && title.isNotEmpty, '$_overridesResource:$line has an empty source or title');
    final decision = switch (ktTrim(fields[2]).toUpperCase()) {
      'INCLUDE' => BookOverrideDecision.include,
      'EXCLUDE' => BookOverrideDecision.exclude,
      final other => throw FormatException('No enum constant BookOverrideDecision.$other'),
    };
    final reason = ktTrim(fields[3]);
    require(reason.isNotEmpty, '$_overridesResource:$line has no audit reason');
    final key = bookOverrideKey(source, title);
    require(!overrides.containsKey(key), '$_overridesResource:$line duplicates ($source, $title)');
    overrides[key] = BookOverride(decision, reason);
  }
  return overrides;
}

List<String> _parseCsvRecord(String record) {
  final fields = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var index = 0;
  while (index < record.length) {
    final ch = record[index];
    if (ch == '"' && quoted && index + 1 < record.length && record[index + 1] == '"') {
      field.write('"');
      index++;
    } else if (ch == '"') {
      quoted = !quoted;
    } else if (ch == ',' && !quoted) {
      fields.add(field.toString());
      field.clear();
    } else {
      field.write(ch);
    }
    index++;
  }
  if (quoted) throw FormatException('Unterminated quoted field in $_overridesResource');
  fields.add(field.toString());
  return fields;
}

/// The overrides shipped with the generator (embedded CSV), parsed once.
final Map<String, BookOverride> defaultLineDhBookOverrides = parseBookOverrides(lineDhBookOverridesCsv);

/// Bold hits of a lead book, with the lead quotation replacing the bare prefix where it exists.
List<(int, Dh)> mergeLeadHits(List<(int, Dh)> bold, List<(int, Dh)> lead) {
  final leadByLine = <int, Dh>{for (final (i, dh) in lead) i: dh};
  return [for (final (i, dh) in bold) (i, leadByLine[i] ?? dh)];
}

/// Kotlin `String?.equals(other, ignoreCase = true)` for a non-null ASCII [other].
bool _ktEqualsIgnoreCase(String? a, String b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x == y) continue;
    final ux = x.toUpperCase();
    final uy = y.toUpperCase();
    if (ux.length == 1 && ux == uy) continue;
    if (ux.length == 1 && ux.toLowerCase() == uy.toLowerCase()) continue;
    return false;
  }
  return true;
}

/// One `line_dh` row (the bookId is the caller's).
class LineDhRow {
  final String dhText;
  final int lineIndex;
  final String dhDisplay;
  const LineDhRow(this.dhText, this.lineIndex, this.dhDisplay);

  @override
  bool operator ==(Object other) =>
      other is LineDhRow &&
      other.dhText == dhText &&
      other.lineIndex == lineIndex &&
      other.dhDisplay == dhDisplay;

  @override
  int get hashCode => Object.hash(dhText, lineIndex, dhDisplay);

  @override
  String toString() => 'LineDhRow($dhText, $lineIndex, $dhDisplay)';
}

/// Why a book got (or did not get) rows — the Kotlin report counters.
enum LineDhOutcome {
  /// CSV `exclude` (counted nowhere in the Kotlin report).
  excludedByOverride,

  /// Not commentary/linked midrash by metadata and not in the CSV (`unreviewedBooks`).
  unreviewed,

  /// No format reached MIN_LINES / MIN_COVERAGE (`skippedBooks` when contentLines > 0).
  belowThreshold,

  /// Every qualifying format failed the noise gate (`noisyBooks`).
  noisy,

  /// Indexed in bold format (`boldBooks`, plus `leadBooks` when [LineDhBookReport.leadBook]).
  bold,

  /// Indexed in dash format (`dashBooks`).
  dash,
}

class LineDhBookReport {
  /// Rows as `INSERT OR IGNORE` on (bookId, dhText, lineIndex) leaves them, in insertion order.
  final List<LineDhRow> rows;
  final LineDhOutcome outcome;

  /// Admitted by a CSV `include` (`overrideBooks`) rather than by metadata (`metadataBooks`).
  final bool admittedByOverride;
  final int contentLines;
  final int boldHits;
  final int boldLeadHits;
  final int dashHits;
  final bool leadBook;

  /// Ratios of the winner, or of the largest rejected format when [outcome] is noisy.
  final NoiseRatios? ratios;

  const LineDhBookReport({
    required this.rows,
    required this.outcome,
    this.admittedByOverride = false,
    this.contentLines = 0,
    this.boldHits = 0,
    this.boldLeadHits = 0,
    this.dashHits = 0,
    this.leadBook = false,
    this.ratios,
  });
}

class _Candidate {
  final List<(int, Dh)> hits;
  final NoiseRatios ratios;
  final bool bold;
  _Candidate(this.hits, this.ratios, this.bold);
}

/// Per-book body of `indexAllBooks` (BuildLineDhIndexCli.kt).
///
/// [sourceName] is `source.name`, [dependenceType] `book.dependenceType`,
/// [isBaseBook] `book.isBaseBook != 0`, [hasBaseText] `EXISTS book_base_text`
/// for the book. [lines] are the book's `(lineIndex, content)` rows (null
/// content is skipped, order is lineIndex as in the Kotlin SELECT).
/// [overrides] defaults to the embedded generator CSV.
LineDhBookReport analyzeLineDh({
  required String bookTitle,
  required String sourceName,
  String? dependenceType,
  required bool isBaseBook,
  required bool hasBaseText,
  required List<({int lineIndex, String? content})> lines,
  Map<String, BookOverride>? overrides,
}) {
  final override = (overrides ?? defaultLineDhBookOverrides)[bookOverrideKey(sourceName, bookTitle)];
  final metadataEligible = (!isBaseBook || hasBaseText) &&
      (_ktEqualsIgnoreCase(dependenceType, 'commentary') ||
          (_ktEqualsIgnoreCase(dependenceType, 'midrash') && hasBaseText));
  switch (override?.decision) {
    case BookOverrideDecision.exclude:
      return const LineDhBookReport(rows: [], outcome: LineDhOutcome.excludedByOverride);
    case BookOverrideDecision.include:
      break;
    case null:
      if (!metadataEligible) {
        return const LineDhBookReport(rows: [], outcome: LineDhOutcome.unreviewed);
      }
  }
  final admittedByOverride = override?.decision == BookOverrideDecision.include;

  final sorted = lines.where((l) => l.content != null).toList();
  _stableSortByLineIndex(sorted);

  var contentLines = 0;
  final bold = <(int, Dh)>[];
  final boldLead = <(int, Dh)>[];
  final dash = <(int, Dh)>[];
  for (final l in sorted) {
    final content = DhExtractor.sourceLineForIndex(l.content!);
    if (ktIsBlank(content) || DhExtractor.isHeadingLine(content)) continue;
    contentLines++;
    final b = DhExtractor.extract(content, DhFormat.bold);
    if (b != null) {
      bold.add((l.lineIndex, b));
      final lead = DhExtractor.extract(content, DhFormat.boldLead);
      if (lead != null) boldLead.add((l.lineIndex, lead));
    }
    final d = DhExtractor.extract(content, DhFormat.dash);
    if (d != null) dash.add((l.lineIndex, d));
  }

  final leadBook = bold.isNotEmpty && boldLead.length >= leadShare * bold.length;
  final boldHits = leadBook ? mergeLeadHits(bold, boldLead) : bold;

  _Candidate? qualify(List<(int, Dh)> hits, bool isBold) {
    if (contentLines > 0 && hits.length >= minLines && hits.length / contentLines >= minCoverage) {
      return _Candidate(hits, NoiseRatios.of([for (final h in hits) h.$2]), isBold);
    }
    return null;
  }

  final qualified = [?qualify(boldHits, true), ?qualify(dash, false)];
  _Candidate? winner;
  for (final c in qualified.where((c) => !c.ratios.isNoisy)) {
    // maxWithOrNull(compareBy { size }.thenBy { bold }): replaces only on a strictly greater element.
    if (winner == null ||
        c.hits.length > winner.hits.length ||
        (c.hits.length == winner.hits.length && c.bold && !winner.bold)) {
      winner = c;
    }
  }

  LineDhBookReport report(LineDhOutcome outcome, {List<LineDhRow> rows = const [], NoiseRatios? ratios}) =>
      LineDhBookReport(
        rows: rows,
        outcome: outcome,
        admittedByOverride: admittedByOverride,
        contentLines: contentLines,
        boldHits: bold.length,
        boldLeadHits: boldLead.length,
        dashHits: dash.length,
        leadBook: leadBook,
        ratios: ratios,
      );

  if (winner == null && qualified.isEmpty) return report(LineDhOutcome.belowThreshold);
  if (winner == null) {
    // qualified.maxBy { size }: first maximum wins.
    var rejected = qualified.first;
    for (final c in qualified.skip(1)) {
      if (c.hits.length > rejected.hits.length) rejected = c;
    }
    return report(LineDhOutcome.noisy, ratios: rejected.ratios);
  }

  final seen = <String>{};
  final rows = <LineDhRow>[];
  for (final (lineIndex, dh) in winner.hits) {
    if (seen.add('${dh.key}\u0000$lineIndex')) rows.add(LineDhRow(dh.key, lineIndex, dh.display));
  }
  return report(winner.bold ? LineDhOutcome.bold : LineDhOutcome.dash, rows: rows, ratios: winner.ratios);
}

/// The `line_dh` rows of one book (see [analyzeLineDh]).
List<LineDhRow> buildLineDhRows({
  required String bookTitle,
  required String sourceName,
  String? dependenceType,
  required bool isBaseBook,
  required bool hasBaseText,
  required List<({int lineIndex, String? content})> lines,
  Map<String, BookOverride>? overrides,
}) =>
    analyzeLineDh(
      bookTitle: bookTitle,
      sourceName: sourceName,
      dependenceType: dependenceType,
      isBaseBook: isBaseBook,
      hasBaseText: hasBaseText,
      lines: lines,
      overrides: overrides,
    ).rows;

void _stableSortByLineIndex(List<({int lineIndex, String? content})> list) {
  for (var i = 1; i < list.length; i++) {
    if (list[i - 1].lineIndex > list[i].lineIndex) {
      final indexed = List.generate(list.length, (j) => (j, list[j]));
      indexed.sort((a, b) {
        final c = a.$2.lineIndex.compareTo(b.$2.lineIndex);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      for (var j = 0; j < list.length; j++) {
        list[j] = indexed[j].$2;
      }
      return;
    }
  }
}
