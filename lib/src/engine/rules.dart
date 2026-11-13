// כללי המחולל הרשמי (SeforimLibrary) שאינם תלויים במסד: שמות, שורות, כותרות, ספירת תווים,
// סוגי קישור. כל פונקציה מצוינת עם המקור שלה ב-Kotlin, וסמנטיקת JVM נשמרת
// (`\s` של Java הוא ASCII בלבד, `trim()` של Kotlin אינו `trim()` של Dart).

import 'line_ref.dart' show jWs, ktIsBlank, ktIsWhitespace, ktTrim;

export 'line_ref.dart' show jWs, ktIsBlank, ktIsWhitespace, ktTrim, ktTrimEnd;

final _jWsRun = RegExp('[$jWs]+');

// ───────────────────────── שורות ─────────────────────────

/// `String.lines()` של Kotlin: מפריד ב-CRLF, LF או CR. שורה ריקה אחרונה נשמרת
/// ("א\n" → ["א", ""]).
List<String> ktLines(String text) => text.split(RegExp(r'\r\n|\n|\r'));

/// `Utf8Bom.stripFirstLine`: BOM מוסר רק מתחילת השורה הראשונה.
List<String> stripFirstLineBom(List<String> lines) {
  if (lines.isEmpty || lines.first.isEmpty || lines.first.codeUnitAt(0) != 0xFEFF) return lines;
  return [lines.first.substring(1), ...lines.skip(1)];
}

String stripBom(String text) => text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF ? text.substring(1) : text;

/// `Generator.detectHeaderLevel`: השורה מתחילה ב-`<h1`..`<h6` (בלי תלות ברישיות).
int detectHeaderLevel(String line) {
  if (line.length < 3 || line.codeUnitAt(0) != 0x3C) return 0;
  final h = line.codeUnitAt(1);
  if (h != 0x68 && h != 0x48) return 0;
  final d = line.codeUnitAt(2);
  return d >= 0x31 && d <= 0x36 ? d - 0x30 : 0;
}

/// `headingLineRegex` של מיזוג ההערות: `^﻿?<h[1-6]`, בלי תלות ברישיות.
final headingLineRegex = RegExp('^﻿?<h[1-6]', caseSensitive: false);

/// `buildOtzariaRef`: "<כותרת> <מספר שורה מ-1>".
String otzariaRef(String bookTitle, int lineIndex) => '${ktTrim(bookTitle)} ${lineIndex + 1}';

// ───────────────────────── שמות (CategoryKeys.kt) ─────────────────────────

/// `CategoryLabels.normalize`.
String normalizeLabel(String raw) {
  var s = ktTrim(raw);
  s = s.replaceAll('“', '"').replaceAll('”', '"');
  s = s.replaceAll('‘', "'").replaceAll('’', "'");
  s = s.replaceAll('"', '״');
  s = s.replaceAll("''", '״');
  s = s.replaceAll('׳׳', '״');
  s = s.replaceAll('`', '׳');
  s = s.replaceAll('׳', '׳');
  s = ktTrim(s.replaceAll(_jWsRun, ' '));
  return s;
}

final _corpusSuffix = RegExp('[$jWs]+על[$jWs]+(התנ"ך|התורה|התלמוד|המשנה|תנך|תורה|תלמוד|משנה)\$', caseSensitive: false);

/// `CategoryLabels.comparable`.
String comparableLabel(String raw) {
  final base = ktTrim(
    normalizeLabel(raw)
        .replaceAll('״', '')
        .replaceAll('"', '')
        .replaceAll('׳', '')
        .replaceAll("'", '')
        .replaceAll(_jWsRun, ' '),
  );
  return ktTrim(base.replaceAll(_corpusSuffix, ''));
}

/// `CategoryLabels.folderSegments` (תמיד מקטע אחד).
String folderTitle(String raw) {
  final cleaned = normalizeLabel(raw);
  switch (cleaned) {
    case 'תלמוד בבלי':
      return 'תלמוד בבלי';
    case 'תלמוד ירושלמי':
    case 'תלמוד ירושלים':
      return 'תלמוד ירושלמי';
    case 'תנך':
    case 'תנ"ך':
    case 'תנ״ך':
      return 'תנ״ך';
    case 'שות':
    case 'שו"ת':
    case 'שו״ת':
      return 'שו״ת';
  }
  return cleaned;
}

/// `CategoryLabels.bookTitle`: book.title של שם קובץ.
String bookTitleOf(String rawStem) {
  final base = normalizeLabel(rawStem);
  return base == 'תנך' || base == 'תנ"ך' ? 'תנ״ך' : base;
}

/// `Generator.stripQuotesForLookup`.
String stripQuotesForLookup(String title) =>
    ktTrim(title.replaceAll('״', '').replaceAll('"', '').replaceAll('׳', '').replaceAll("'", ''));

/// `normalizeCategoryPathSegment` (מפתח של sefaria_category_changes.csv).
String categoryPathSegment(String v) => ktTrim(v.replaceAll('"', '״'));

const _dependencyPrefixes = ['תלמוד בבלי ', 'תלמוד ירושלמי ', 'מסכת ', 'משנה ', 'ספר '];

/// `Generator.titleDeclaresDependencyOn`.
bool titleDeclaresDependencyOn(String dependantTitle, String baseTitle) {
  final normalized = comparableLabel(dependantTitle);
  final idx = normalized.lastIndexOf(' על ');
  if (idx < 0) return false;
  final declared = normalized.substring(idx + 4);
  if (ktIsBlank(declared)) return false;
  String key(String raw) {
    var value = comparableLabel(raw);
    while (true) {
      final prefix = _dependencyPrefixes.where(value.startsWith).firstOrNull;
      if (prefix == null) break;
      value = ktTrim(value.substring(prefix.length));
    }
    return value;
  }

  return key(declared) == key(baseTitle);
}

// ───────────────────────── מחברים ─────────────────────────

final _authorNikud = RegExp(r'[\u0591-\u05BD\u05BF-\u05C7]');
final _authorBidi = RegExp(r'[\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');
final _authorWs = RegExp(r'[\t\n\x0B\f\r \u00A0\u2000-\u200B\u202F\u205F\u3000]+');

/// `normalizeAuthorName` (AuthorNameNormalization.kt).
String normalizeAuthorName(String raw) =>
    ktTrim(raw.replaceAll(_authorNikud, '').replaceAll(_authorBidi, '').replaceAll(_authorWs, ' '));

// ───────────────────────── תווים נראים (HtmlCharCounter.kt) ─────────────────────────

/// `countVisibleChars(html, endExclusive)`: תגיות מדולגות, ישות = תו אחד.
int countVisibleChars(String html, [int? endExclusive]) {
  final end = endExclusive ?? html.length;
  if (html.isEmpty || end <= 0) return 0;
  var count = 0;
  var inTag = false;
  var i = 0;
  final len = end < html.length ? end : html.length;
  while (i < len) {
    final c = html.codeUnitAt(i);
    if (inTag) {
      if (c == 0x3E) inTag = false;
    } else if (c == 0x3C) {
      inTag = true;
    } else if (c == 0x26) {
      final stop = len < i + 10 ? len : i + 10;
      var j = i + 1;
      var terminated = false;
      while (j < stop) {
        if (html.codeUnitAt(j) == 0x3B) {
          terminated = true;
          break;
        }
        j++;
      }
      count++;
      if (terminated) i = j;
    } else {
      count++;
    }
    i++;
  }
  return count;
}

/// `visibleUnits`.
List<String> visibleUnits(String html) {
  final units = <String>[];
  var inTag = false;
  var i = 0;
  while (i < html.length) {
    final c = html.codeUnitAt(i);
    if (inTag) {
      if (c == 0x3E) inTag = false;
    } else if (c == 0x3C) {
      inTag = true;
    } else if (c == 0x26) {
      final stop = html.length < i + 10 ? html.length : i + 10;
      var j = i + 1;
      while (j < stop && html.codeUnitAt(j) != 0x3B) {
        j++;
      }
      if (j < stop) {
        units.add(html.substring(i, j + 1));
        i = j;
      } else {
        units.add('&');
      }
    } else {
      units.add(html[i]);
    }
    i++;
  }
  return units;
}

// ───────────────────────── טקסט כותרת (Generator.cleanHtml) ─────────────────────────

bool _isNikud(int c) => (c >= 0x05B0 && c <= 0x05BD) || c == 0x05C1 || c == 0x05C2 || c == 0x05C7;
bool _isTeamim(int c) => c >= 0x0591 && c <= 0x05AF;

/// `HebrewTextUtils.removeAllDiacritics`.
String removeAllDiacritics(String text) {
  final b = StringBuffer();
  for (final c in text.codeUnits) {
    if (!_isNikud(c) && !_isTeamim(c)) b.writeCharCode(c);
  }
  return b.toString();
}

/// `Generator.cleanHtml`: Jsoup.clean(Safelist.none) ← trim ← כיווץ רווחים ← מקף עליון לרווח ← בלי ניקוד וטעמים.
String cleanHtmlForToc(String html) {
  final cleaned = ktTrim(jsoupCleanNone(html)).replaceAll(_jWsRun, ' ');
  return removeAllDiacritics(cleaned.replaceAll('־', ' '));
}

const _namedEntities = <String, String>{
  'nbsp': ' ', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'shy': '­',
  'lrm': '‎', 'rlm': '‏', 'zwj': '‍', 'zwnj': '‌', 'ndash': '–', 'mdash': '—',
  'hellip': '…', 'laquo': '«', 'raquo': '»', 'copy': '©', 'reg': '®', 'middot': '·', 'bull': '•',
  'thinsp': ' ', 'ensp': ' ', 'emsp': ' ', 'lsquo': '‘', 'rsquo': '’', 'ldquo': '“',
  'rdquo': '”', 'sbquo': '‚', 'bdquo': '„', 'times': '×', 'divide': '÷', 'deg': '°', 'para': '¶',
  'sect': '§', 'prime': '′', 'Prime': '″', 'larr': '←', 'rarr': '→', 'uarr': '↑', 'darr': '↓',
};

/// הטקסט שמחזיר `Jsoup.clean(html, Safelist.none())`: כל התגיות מוסרות, הערות HTML ותוכן
/// script/style נזרקים, ישויות מפוענחות ואז `&`, `<`, `>` ורווח קשיח מקודדים מחדש
/// (מצב escape "base"), רצפי רווח (ASCII של Jsoup) מכווצים לרווח אחד.
String jsoupCleanNone(String html) {
  final out = StringBuffer();
  var pendingSpace = false;
  void emit(String s) {
    for (final c in s.runes) {
      final isWs = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;
      if (isWs) {
        pendingSpace = true;
        continue;
      }
      if (pendingSpace) {
        out.write(' ');
        pendingSpace = false;
      }
      switch (c) {
        case 0x26:
          out.write('&amp;');
        case 0x3C:
          out.write('&lt;');
        case 0x3E:
          out.write('&gt;');
        case 0xA0:
          out.write('&nbsp;');
        default:
          out.writeCharCode(c);
      }
    }
  }

  bool isAsciiLetter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  var i = 0;
  final n = html.length;
  while (i < n) {
    final c = html.codeUnitAt(i);
    if (c == 0x3C && i + 1 < n) {
      final d = html.codeUnitAt(i + 1);
      if (html.startsWith('<!--', i)) {
        final close = html.indexOf('-->', i + 4);
        i = close < 0 ? n : close + 3;
        continue;
      }
      if (d == 0x21 || d == 0x3F) {
        final close = html.indexOf('>', i + 2);
        i = close < 0 ? n : close + 1;
        continue;
      }
      final isClose = d == 0x2F && i + 2 < n && isAsciiLetter(html.codeUnitAt(i + 2));
      if (isAsciiLetter(d) || isClose) {
        // תגית: עד ה-'>' שמחוץ למירכאות של ערך תכונה.
        var j = i + 1;
        int? quote;
        var nameEnd = -1;
        while (j < n) {
          final e = html.codeUnitAt(j);
          if (quote != null) {
            if (e == quote) quote = null;
          } else if (e == 0x22 || e == 0x27) {
            quote = e;
          } else if (e == 0x3E) {
            break;
          } else if (nameEnd < 0 && (e == 0x20 || e == 0x09 || e == 0x0A || e == 0x0C || e == 0x0D || e == 0x2F)) {
            if (j > i + 1 + (isClose ? 1 : 0)) nameEnd = j;
          }
          j++;
        }
        if (nameEnd < 0) nameEnd = j;
        final name = html.substring(i + (isClose ? 2 : 1), nameEnd).toLowerCase();
        i = j >= n ? n : j + 1;
        if (!isClose && (name == 'script' || name == 'style')) {
          final close = html.toLowerCase().indexOf('</$name', i);
          i = close < 0 ? n : (html.indexOf('>', close) < 0 ? n : html.indexOf('>', close) + 1);
        }
        continue;
      }
      emit('<');
      i++;
      continue;
    }
    if (c == 0x26) {
      final (text, len) = _decodeEntity(html, i);
      emit(text);
      i += len;
      continue;
    }
    // תו רגיל, כולל זוגות surrogate.
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < n) {
      emit(html.substring(i, i + 2));
      i += 2;
    } else {
      emit(html[i]);
      i++;
    }
  }
  return out.toString();
}

(String, int) _decodeEntity(String s, int at) {
  final n = s.length;
  if (at + 1 < n && s.codeUnitAt(at + 1) == 0x23) {
    var j = at + 2;
    var hex = false;
    if (j < n && (s.codeUnitAt(j) == 0x78 || s.codeUnitAt(j) == 0x58)) {
      hex = true;
      j++;
    }
    final start = j;
    while (j < n) {
      final c = s.codeUnitAt(j);
      final ok = (c >= 0x30 && c <= 0x39) ||
          (hex && ((c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)));
      if (!ok) break;
      j++;
    }
    if (j == start) return ('&', 1);
    final code = int.tryParse(s.substring(start, j), radix: hex ? 16 : 10);
    final semi = j < n && s.codeUnitAt(j) == 0x3B;
    final len = j - at + (semi ? 1 : 0);
    if (code == null || code > 0x10FFFF || code == 0) return ('�', len);
    return (String.fromCharCode(code), len);
  }
  var j = at + 1;
  while (j < n) {
    final c = s.codeUnitAt(j);
    if (!((c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A))) break;
    j++;
  }
  final name = s.substring(at + 1, j);
  final semi = j < n && s.codeUnitAt(j) == 0x3B;
  final value = _namedEntities[name];
  if (value != null && (semi || const {'amp', 'lt', 'gt', 'quot', 'nbsp'}.contains(name))) {
    return (value, j - at + (semi ? 1 : 0));
  }
  return ('&', 1);
}

// ───────────────────────── סוגי קישור (Link.kt) ─────────────────────────

/// `ConnectionType`, בסדר ה-enum (המזהים במסד לפי הסדר הזה, מ-1).
enum ConnectionType {
  commentary('COMMENTARY'),
  superCommentary('SUPER_COMMENTARY'),
  targum('TARGUM'),
  reference('REFERENCE'),
  source('SOURCE'),
  midrash('MIDRASH'),
  quotation('QUOTATION'),
  mesoratHashas('MESORAT_HASHAS'),
  einMishpat('EIN_MISHPAT'),
  diburHamatchil('DIBUR_HAMATCHIL'),
  parshanut('PARSHANUT'),
  mishnahInTalmud('MISHNAH_IN_TALMUD'),
  related('RELATED'),
  other('OTHER'),
  linker('LINKER'),
  sifreiMitzvot('SIFREI_MITZVOT'),
  essay('ESSAY'),
  allusion('ALLUSION'),
  liturgy('LITURGY'),
  elucidation('ELUCIDATION'),
  explication('EXPLICATION'),
  law('LAW'),
  summary('SUMMARY'),
  footnotes('FOOTNOTES');

  const ConnectionType(this.dbName);
  final String dbName;

  /// `SOURCE_VIEW_TYPES`.
  static const sourceViewTypes = {
    commentary, superCommentary, targum, midrash, parshanut, diburHamatchil, einMishpat, elucidation, footnotes,
  };

  /// `fromKnownStringOrNull`: null = ערך לא מוכר (ש-`fromString` הופך ל-OTHER).
  static ConnectionType? fromKnown(String value) {
    final v = ktTrim(value).toLowerCase().replaceAll(' ', '_');
    switch (v) {
      case 'commentary':
        return commentary;
      case 'super_commentary':
      case 'supercommentary':
        return superCommentary;
      case 'targum':
        return targum;
      case 'reference':
        return reference;
      case 'source':
        return source;
      case 'midrash':
        return midrash;
      case 'quotation':
      case 'quotation_auto':
      case 'quotation_auto_tanakh':
        return quotation;
      case 'mesorat_hashas':
        return mesoratHashas;
      case 'ein_mishpat':
      case 'ein_mishpat_/_ner_mitsvah':
      case 'ein_mishpat_/_ner_mitzvah':
        return einMishpat;
      case 'dibur_hamatchil':
        return diburHamatchil;
      case 'parshanut':
        return parshanut;
      case 'mishnah_in_talmud':
        return mishnahInTalmud;
      case 'related':
      case 'related_passage':
        return related;
      case 'linker':
        return linker;
      case 'sifrei_mitzvot':
        return sifreiMitzvot;
      case 'essay':
        return essay;
      case 'allusion':
        return allusion;
      case 'liturgy':
        return liturgy;
      case 'ellucidation':
      case 'elucidation':
        return elucidation;
      case 'explication':
        return explication;
      case 'law':
        return law;
      case 'summary':
        return summary;
      case 'footnotes':
      case 'footnote':
        return footnotes;
      case '':
      case 'none':
      case 'other':
        return other;
    }
    return null;
  }

  static ConnectionType fromString(String value) => fromKnown(value) ?? other;
}

/// `anchorLabelFromHeRef`: "… אות ג" → "ג".
String? anchorLabelFromHeRef(String heRef) {
  final idx = heRef.lastIndexOf(' אות ');
  if (idx < 0) return null;
  final tail = ktTrim(heRef.substring(idx + 5));
  if (tail.isEmpty || tail.length > 6) return null;
  for (final c in tail.codeUnits) {
    final ok = (c >= 0x05D0 && c <= 0x05EA) || c == 0x22 || c == 0x05F3 || c == 0x05F4;
    if (!ok) return null;
  }
  return tail;
}

/// Kotlin `isNotBlank` על תווים: לפחות תו אחד שאינו רווח.
bool ktIsNotBlank(String s) => !ktIsBlank(s);

/// Kotlin `Char.isWhitespace` על תו בודד (נוחות).
bool ktCharIsWs(int codeUnit) => ktIsWhitespace(codeUnit);
