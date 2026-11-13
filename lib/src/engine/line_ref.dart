// Pure-Dart port of the `line_ref` index builder of the official generator.
//
// Mirrors SeforimLibrary @ a193aa15d (files last touched in 88c2067):
//  - core/src/commonMain/kotlin/io/github/kdroidfilter/seforimlibrary/core/refs/RefKey.kt
//      -> [RefKey] (normalisation, partial keys, FNV-1a 64 hash)
//  - generator/common/src/jvmMain/kotlin/io/github/kdroidfilter/seforimlibrary/common/refs/BuildLineRefIndexCli.kt
//      -> [buildLineRefRows] / [analyzeLineRefs] (the per-book body of indexAllBooks)
//
// The Kotlin stage is per book: nothing in it is library-wide (the counters it
// logs are plain sums of the per-book values reported by [analyzeLineRefs]).
//
// JVM semantics reproduced on purpose (Dart differs by default):
//  - java.util.regex `\s` is ASCII [ \t\n\x0B\f\r] (Dart `\s` is Unicode), `\d` is ASCII;
//  - java `$` (no MULTILINE) also matches before one final line terminator;
//  - classes and quantifiers work on code points (Dart regexes use `unicode: true`);
//  - Kotlin `trim()` / `isBlank()` use Char.isWhitespace (Zs/Zl/Zp + \t..\r + \x1C..\x1F),
//    not Dart's White_Space set (Dart also strips U+0085 and U+FEFF);
//  - `encodeToByteArray()` = String.getBytes(UTF_8): an unpaired surrogate becomes '?'.
// No deliberate deviation.

/// Character class body for java.util.regex `\s` (ASCII only).
const String jWs = r'\t\n\x0B\f\r ';

/// java.util.regex `$` without MULTILINE: end of input, or before a final
/// line terminator (`\r\n`, `\n`, `\r`, U+0085, U+2028, U+2029), never between `\r` and `\n`.
const String jEnd = r'(?:$|(?=\r\n$)|(?=[\r\u0085  ]$)|(?<!\r)(?=\n$))';

RegExp jRegex(String pattern, {bool dotAll = false}) =>
    RegExp(pattern, unicode: true, dotAll: dotAll);

/// Kotlin/JVM `Char.isWhitespace()` = Character.isWhitespace || Character.isSpaceChar.
bool ktIsWhitespace(int c) {
  if (c <= 0x20) return c == 0x20 || (c >= 0x09 && c <= 0x0D) || (c >= 0x1C && c <= 0x1F);
  if (c < 0x00A0) return false;
  return c == 0x00A0 ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200A) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202F ||
      c == 0x205F ||
      c == 0x3000;
}

/// Kotlin `String.trim()`.
String ktTrim(String s) => ktTrimWhere(s, ktIsWhitespace);

/// Kotlin `String.trimEnd()`.
String ktTrimEnd(String s) {
  var end = s.length;
  while (end > 0 && ktIsWhitespace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(0, end);
}

/// Kotlin `String.trim(predicate)` (over UTF-16 code units).
String ktTrimWhere(String s, bool Function(int codeUnit) drop) {
  var start = 0;
  var end = s.length;
  while (start < end && drop(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && drop(s.codeUnitAt(end - 1))) {
    end--;
  }
  return (start == 0 && end == s.length) ? s : s.substring(start, end);
}

/// Kotlin `CharSequence.isBlank()`.
bool ktIsBlank(String s) {
  for (var i = 0; i < s.length; i++) {
    if (!ktIsWhitespace(s.codeUnitAt(i))) return false;
  }
  return true;
}

final RegExp _letterOrDigit = RegExp(r'^[\p{L}\p{Nd}]$', unicode: true);

/// Java `Character.isLetterOrDigit(char)` for one UTF-16 code unit
/// (a surrogate is never a letter or digit).
bool jIsLetterOrDigit(int c) {
  if (c < 0x80) {
    return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  }
  if (c >= 0x05D0 && c <= 0x05EA) return true; // Hebrew letters (hot path)
  if (c >= 0xD800 && c <= 0xDFFF) return false;
  return _letterOrDigit.hasMatch(String.fromCharCode(c));
}

/// UTF-8 bytes as Java `String.getBytes(UTF_8)` produces them.
List<int> jUtf8Bytes(String s) {
  final out = <int>[];
  final n = s.length;
  for (var i = 0; i < n; i++) {
    var c = s.codeUnitAt(i);
    if (c < 0x80) {
      out.add(c);
    } else if (c < 0x800) {
      out
        ..add(0xC0 | (c >> 6))
        ..add(0x80 | (c & 0x3F));
    } else if (c >= 0xD800 && c <= 0xDFFF) {
      if (c <= 0xDBFF && i + 1 < n) {
        final d = s.codeUnitAt(i + 1);
        if (d >= 0xDC00 && d <= 0xDFFF) {
          c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
          i++;
          out
            ..add(0xF0 | (c >> 18))
            ..add(0x80 | ((c >> 12) & 0x3F))
            ..add(0x80 | ((c >> 6) & 0x3F))
            ..add(0x80 | (c & 0x3F));
          continue;
        }
      }
      out.add(0x3F); // unpaired surrogate -> '?'
    } else {
      out
        ..add(0xE0 | (c >> 12))
        ..add(0x80 | ((c >> 6) & 0x3F))
        ..add(0x80 | (c & 0x3F));
    }
  }
  return out;
}

bool _listEq(List<String> a, int aLen, List<String> b) {
  if (aLen != b.length) return false;
  for (var i = 0; i < aLen; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Port of `io.github.kdroidfilter.seforimlibrary.core.refs.RefKey`.
abstract final class RefKey {
  static const Set<String> _locatorWords = {
    'פרק', 'פסוק', 'פסקה', 'סעיף', 'סימן', 'הלכה', 'משנה', 'מאמר', 'דף', 'עמוד', 'אות', //
  };

  // Hebrew-number-or-digits atom: (?:\d+|[א-ת]{1,3}(?:["'״׳][א-ת]{1,2})?)
  static const String _num = r'(?:\d+|[א-ת]{1,3}(?:[\x22\x27״׳][א-ת]{1,2})?)';

  // Group 1 = everything before the dash (Dart has no group offsets), group 2 = dash.
  static final RegExp _trailingRange = jRegex(
    '((?:^|[$jWs,.:])$_num[.:]?[$jWs]*)([-–־])[$jWs]*$_num[.:]?[$jWs]*$jEnd',
  );
  static final RegExp _points = jRegex(r'[֑-ׇ]');
  static final RegExp _nonWord = jRegex('[^a-zA-Z0-9֐-׿$jWs]');
  static final RegExp _whitespace = jRegex('[$jWs]+');
  static final RegExp _dafSideA = jRegex(
    '(?<![א-ת\x27\x22״׳])([א-ת]{1,3})\\.(?=[,$jWs]|$jEnd)',
  );
  static final RegExp _dafSideB = jRegex(
    '(?<![א-ת\x27\x22״׳])([א-ת]{1,3}):(?=[,$jWs]|$jEnd)',
  );
  static final RegExp _amudA =
      jRegex('(?<![א-ת])ע[\x22\x27״׳]א(?![א-ת])');
  static final RegExp _amudB =
      jRegex('(?<![א-ת])ע[\x22\x27״׳]ב(?![א-ת])');

  static String _expandDafMarks(String s) => s
      .replaceAllMapped(_dafSideA, (m) => '${m.group(1)} א')
      .replaceAllMapped(_dafSideB, (m) => '${m.group(1)} ב');

  /// Canonical tokens of [ref], in order.
  static List<String> tokens(String ref) {
    final range = _trailingRange.firstMatch(ref);
    final dash = range == null ? null : range.start + range.group(1)!.length;
    final head = (dash != null && dash > 0) ? ref.substring(0, dash) : ref;

    var cleaned = _expandDafMarks(head);
    cleaned = cleaned.replaceAll('־', ' ').replaceAll('׀', ' ').replaceAll('|', ' ');
    cleaned = cleaned.replaceAll(_points, '');
    cleaned = cleaned.replaceAll(_amudA, 'א');
    cleaned = cleaned.replaceAll(_amudB, 'ב');
    cleaned = cleaned
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('״', '')
        .replaceAll('׳', '');
    // Only ASCII letters, digits, the Hebrew block and ASCII whitespace survive,
    // so Dart's toLowerCase equals Kotlin's lowercase() (Locale.ROOT) here.
    cleaned = cleaned.replaceAll(_nonWord, ' ').toLowerCase();

    return cleaned
        .split(_whitespace)
        .where((t) => t.isNotEmpty && !_locatorWords.contains(t))
        .toList();
  }

  /// Canonical key of [ref], or `null` when nothing is left of it.
  static String? of(String ref) {
    final k = tokens(ref).join(' ');
    return k.isEmpty ? null : k;
  }

  static String? _suffixAfterTitleAlias(String heRef, Iterable<String> titleAliases) {
    String? longestMatch;
    for (final alias in titleAliases) {
      if (ktIsBlank(alias) || alias.length <= (longestMatch?.length ?? 0)) continue;
      if (!heRef.startsWith(alias)) continue;
      if (heRef.length > alias.length && jIsLetterOrDigit(heRef.codeUnitAt(alias.length))) continue;
      longestMatch = alias;
    }
    return longestMatch == null ? null : heRef.substring(longestMatch.length);
  }

  /// Whether [heRef] begins with one of [titleAliases], literally or after canonical tokenisation.
  static bool hasTitleAliasPrefix(String heRef, Iterable<String> titleAliases) {
    final aliases = titleAliases.toList();
    if (_suffixAfterTitleAlias(heRef, aliases) != null) return true;
    final heRefTokens = tokens(heRef);
    return aliases
        .map(tokens)
        .where((t) => t.isNotEmpty && t.length <= heRefTokens.length)
        .any((t) => _listEq(heRefTokens, t.length, t));
  }

  /// Canonical key of a line: [heRef] with the leading book-title prefix removed.
  static String? ofLine(String heRef, Iterable<String> titleAliases) {
    final aliases = titleAliases.toList();
    final suffix = _suffixAfterTitleAlias(heRef, aliases);
    if (suffix != null) return of(suffix);
    return ofLineTokens(tokens(heRef), aliases.map(tokens));
  }

  /// Equivalent to [ofLine] for already tokenised input.
  static String? ofLineTokens(List<String> heRefTokens, Iterable<List<String>> titleAliasTokens) {
    if (heRefTokens.isEmpty) return null;
    List<String>? longestMatch;
    for (final aliasTokens in titleAliasTokens) {
      if (aliasTokens.isEmpty || aliasTokens.length > heRefTokens.length) continue;
      if (!_listEq(heRefTokens, aliasTokens.length, aliasTokens)) continue;
      if (aliasTokens.length > (longestMatch?.length ?? 0)) longestMatch = aliasTokens;
    }
    final prefix = longestMatch;
    if (prefix == null) return heRefTokens.join(' ');
    if (prefix.length == heRefTokens.length) return null;
    return heRefTokens.sublist(prefix.length).join(' ');
  }

  static const String partialMarker = '~';

  /// Partial key of a typed reference.
  static String? partialOf(String ref) {
    final k = of(ref);
    return k == null ? null : '$partialMarker $k';
  }

  /// Partial keys of a line whose heRef, after the title, opens with named parts.
  static List<String> partialLineKeys(String heRef, Iterable<String> titleAliases) {
    final suffix = _suffixAfterTitleAlias(heRef, titleAliases.toList());
    if (suffix == null) return const [];
    final components = suffix.split(',').map(ktTrim).where((c) => c.isNotEmpty).toList();
    var named = components.indexWhere(isNumeralComponent);
    if (named < 0) named = components.length;
    final numeric = components.sublist(named);
    if (named == 0 || numeric.length < 2 || !numeric.every(isNumeralComponent)) return const [];
    final out = <String>[];
    for (var omitted = 1; omitted <= named; omitted++) {
      final p = partialOf(components.sublist(omitted).join(', '));
      if (p != null && !out.contains(p)) out.add(p);
    }
    return out;
  }

  static const Map<int, int> _numeralValues = {
    0x05D0: 1, 0x05D1: 2, 0x05D2: 3, 0x05D3: 4, 0x05D4: 5, 0x05D5: 6, 0x05D6: 7, //
    0x05D7: 8, 0x05D8: 9, 0x05D9: 10, 0x05DB: 20, 0x05DC: 30, 0x05DE: 40, 0x05E0: 50, //
    0x05E1: 60, 0x05E2: 70, 0x05E4: 80, 0x05E6: 90, 0x05E7: 100, 0x05E8: 200, //
    0x05E9: 300, 0x05EA: 400, //
  };

  /// A heRef component that is a location number rather than a name.
  static bool isNumeralComponent(String component) {
    final t = tokens(component);
    return t.isNotEmpty && t.every(isNumeralToken);
  }

  /// Digits, or Hebrew letters in non-increasing value order.
  static bool isNumeralToken(String token) {
    // Kotlin Char.isDigit is Unicode Nd, but tokens only hold [a-z0-9] and the
    // Hebrew block, which has no Nd digits, so ASCII is exact here.
    var allDigits = true;
    for (var i = 0; i < token.length; i++) {
      final c = token.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) {
        allDigits = false;
        break;
      }
    }
    if (allDigits) return true;
    if (token.length > 6) return false;
    int? prev;
    for (var i = 0; i < token.length; i++) {
      final v = _numeralValues[token.codeUnitAt(i)];
      if (v == null) return false;
      if (prev != null && prev < v) return false;
      prev = v;
    }
    return true;
  }

  /// FNV-1a 64-bit over the UTF-8 bytes of [refKey], as the signed Kotlin Long.
  /// (Dart VM ints are 64-bit two's complement and wrap like the JVM.)
  static int hash(String refKey) {
    var h = -3750763034362895579; // 14695981039346656037 as signed
    for (final b in jUtf8Bytes(refKey)) {
      h = (h ^ b) * 1099511628211;
    }
    return h;
  }
}

/// One `line_ref` row (the bookId is the caller's).
class LineRefRow {
  final int refKeyHash;
  final int lineIndex;
  const LineRefRow(this.refKeyHash, this.lineIndex);

  @override
  bool operator ==(Object other) =>
      other is LineRefRow && other.refKeyHash == refKeyHash && other.lineIndex == lineIndex;

  @override
  int get hashCode => Object.hash(refKeyHash, lineIndex);

  @override
  String toString() => 'LineRefRow($refKeyHash, $lineIndex)';
}

/// A full key that two lines of the book resolve to (the Kotlin AmbiguousLineRef).
class AmbiguousLineRef {
  final String heRef;
  final int firstLineIndex;
  final int secondLineIndex;
  const AmbiguousLineRef(this.heRef, this.firstLineIndex, this.secondLineIndex);

  @override
  bool operator ==(Object other) =>
      other is AmbiguousLineRef &&
      other.heRef == heRef &&
      other.firstLineIndex == firstLineIndex &&
      other.secondLineIndex == secondLineIndex;

  @override
  int get hashCode => Object.hash(heRef, firstLineIndex, secondLineIndex);

  @override
  String toString() => 'AmbiguousLineRef($heRef, $firstLineIndex, $secondLineIndex)';
}

/// Per-book result of the line_ref stage.
class LineRefBookReport {
  /// Rows as `INSERT OR IGNORE` leaves them, in insertion order.
  final List<LineRefRow> rows;

  /// Full keys / partial keys the Kotlin counts (before INSERT OR IGNORE).
  final int indexed;
  final int partialIndexed;

  /// Some line heRef does not start with the book title (Kotlin `titleMismatchBooks`).
  final bool hasTitleMismatch;
  final List<AmbiguousLineRef> ambiguous;

  const LineRefBookReport({
    required this.rows,
    required this.indexed,
    required this.partialIndexed,
    required this.hasTitleMismatch,
    required this.ambiguous,
  });
}

/// Per-book body of `indexAllBooks` (BuildLineRefIndexCli.kt).
///
/// [bookTitle] / [bookHeRef] are `book.title` / `book.heRef`; [lines] are the
/// book's `line` rows. Lines with a null or empty heRef are skipped and the
/// rest are processed in `lineIndex` order, exactly as the Kotlin SELECT does.
LineRefBookReport analyzeLineRefs({
  required String bookTitle,
  String? bookHeRef,
  required List<({int lineIndex, String? heRef})> lines,
}) {
  final aliases = [?bookHeRef, bookTitle].where((a) => !ktIsBlank(a)).toList();
  final selected = lines.where((l) => l.heRef != null && l.heRef!.isNotEmpty).toList();
  _stableSortBy(selected, (l) => l.lineIndex);

  final seen = <int>{};
  final seenAmbiguous = <int>{};
  final firstByHash = <int, (String, int)>{};
  final ambiguous = <AmbiguousLineRef>[];
  final rowSet = <LineRefRow>{};
  final rows = <LineRefRow>[];
  var hasTitleMismatch = false;
  var indexed = 0;
  var partialIndexed = 0;

  void insert(int hash, int lineIndex) {
    final row = LineRefRow(hash, lineIndex);
    if (rowSet.add(row)) rows.add(row);
  }

  for (final line in selected) {
    final heRef = line.heRef!;
    final lineIndex = line.lineIndex;
    if (!RefKey.hasTitleAliasPrefix(heRef, aliases)) hasTitleMismatch = true;
    final key = RefKey.ofLine(heRef, aliases);
    if (key == null) continue;
    final hash = RefKey.hash(key);
    if (!seen.add(hash)) {
      if (seenAmbiguous.add(hash)) {
        final first = firstByHash[hash] ?? (heRef, lineIndex);
        ambiguous.add(AmbiguousLineRef(first.$1, first.$2, lineIndex));
      }
    } else {
      firstByHash[hash] = (heRef, lineIndex);
    }
    insert(hash, lineIndex);
    indexed++;
    for (final partial in RefKey.partialLineKeys(heRef, aliases)) {
      insert(RefKey.hash(partial), lineIndex);
      partialIndexed++;
    }
  }

  return LineRefBookReport(
    rows: rows,
    indexed: indexed,
    partialIndexed: partialIndexed,
    hasTitleMismatch: hasTitleMismatch,
    ambiguous: ambiguous,
  );
}

/// The `line_ref` rows of one book (see [analyzeLineRefs]).
List<LineRefRow> buildLineRefRows({
  required String bookTitle,
  String? bookHeRef,
  required List<({int lineIndex, String? heRef})> lines,
}) =>
    analyzeLineRefs(bookTitle: bookTitle, bookHeRef: bookHeRef, lines: lines).rows;

void _stableSortBy<T>(List<T> list, int Function(T) key) {
  for (var i = 1; i < list.length; i++) {
    if (key(list[i - 1]) > key(list[i])) {
      // Not already sorted: fall back to a stable merge via indexed sort.
      final indexed = List.generate(list.length, (j) => (j, list[j]));
      indexed.sort((a, b) {
        final c = key(a.$2).compareTo(key(b.$2));
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
      for (var j = 0; j < list.length; j++) {
        list[j] = indexed[j].$2;
      }
      return;
    }
  }
}
