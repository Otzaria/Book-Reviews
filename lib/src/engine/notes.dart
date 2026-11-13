// הערות שוליים: מיזוג "הערות על X" לתוך ספר הבסיס, ובניית line_note.
// תרגום נאמן של:
//  - generator/otzariasqlite/.../HearotCompanionMerge.kt
//  - generator/common/src/commonMain/.../notes/InlineNotes.kt
//  - generator/common/src/commonMain/.../notes/LineNoteRehydration.kt
//  - generator/common/src/jvmMain/.../notes/LineNoteIndex.kt (processLine)
// טווחים כאן הם [start, end) (ב-Kotlin IntRange כולל את הקצה).

import 'rules.dart';

const _ws = '[\\t\\n\\x0B\\f\\r ]'; // \s של Java

class Span {
  const Span(this.start, this.end);
  final int start;
  final int end;
  @override
  bool operator ==(Object other) => other is Span && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
  @override
  String toString() => '[$start,$end)';
}

// ───────────────────────── InlineNotes ─────────────────────────

class InlineNote {
  InlineNote(this.start, this.end, this.marker, this.body, this.plainSupTag);
  final int start;
  final int end;
  final String? marker;
  final String body;

  /// התגית הפותחת (מ-'<' עד '>' כולל) של sup מעגן בלי class.
  final Span? plainSupTag;
}

/// null = גוף הערה שנפתח בלי `</i>` תואם ([unclosedAt]).
class ParsedNotes {
  ParsedNotes(this.notes, [this.unclosedAt]);
  final List<InlineNote> notes;
  final int? unclosedAt;
}

abstract final class InlineNotes {
  static final noteOpen = RegExp('<i\\b[^>]*\\bclass$_ws*=$_ws*"footnote"[^>]*>', caseSensitive: false);
  static final _italicTag = RegExp('<i\\b[^>]*>|</i>', caseSensitive: false);
  static final _marker = RegExp(
    '<sup\\b[^>]*\\bclass$_ws*=$_ws*"footnote-marker"[^>]*>(.*?)</sup>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _anySup = RegExp('<sup\\b([^>]*)>(.*?)</sup>', caseSensitive: false, dotAll: true);
  static final _markerClass = RegExp('\\bclass$_ws*=$_ws*"footnote-marker"', caseSensitive: false);
  static final _classAttr = RegExp('$_ws*\\bclass$_ws*=$_ws*"[^"]*"', caseSensitive: false);

  // הכלל של הקוראים (האפליקציה), בסמנטיקת RegExp של Dart.
  static final _consumerMarker = RegExp('<sup\\b[^>]*\\bfootnote-marker\\b[^>]*>.*?</sup>', caseSensitive: false, dotAll: true);
  static final _consumerBodyStart = RegExp('\\s*<i\\b[^>]*\\bclass\\s*=\\s*"[^"]*\\bfootnote\\b', caseSensitive: false);

  static bool hasNotes(String line) => line.contains('footnote') && noteOpen.hasMatch(line);

  static ParsedNotes parse(String line) {
    if (!hasNotes(line)) return ParsedNotes(const []);
    final sups = _anySup.allMatches(line).toList();
    final supsByEnd = {for (final s in sups) s.end: s};
    final notes = <InlineNote>[];
    var cursor = 0;
    while (true) {
      final m = _firstFrom(noteOpen, line, cursor);
      if (m == null) break;
      final close = _matchingClose(line, m.start);
      if (close == null) return ParsedNotes(const [], m.start);
      if (sups.any((s) => m.start >= s.start && m.start < s.end)) {
        cursor = close.end;
        continue;
      }
      final sup = supsByEnd[_gapStart(line, m.start)];
      final plain = sup != null && !_markerClass.hasMatch(sup.group(1)!);
      notes.add(
        InlineNote(
          m.start,
          close.end,
          sup?.group(2),
          line.substring(m.end, close.start),
          plain ? Span(sup.start, line.indexOf('>', sup.start) + 1) : null,
        ),
      );
      cursor = close.end;
    }
    return ParsedNotes(notes);
  }

  static RegExpMatch? _firstFrom(RegExp re, String s, int from) {
    for (final m in re.allMatches(s, from)) {
      return m;
    }
    return null;
  }

  static String strip(String line, List<InlineNote> notes) {
    if (notes.isEmpty) return line;
    final out = StringBuffer();
    var cursor = 0;
    for (final note in notes) {
      final tag = note.plainSupTag;
      if (tag != null) {
        out.write(line.substring(cursor, tag.start));
        final attrs = line.substring(tag.start + 4, tag.end - 1);
        out
          ..write('<sup class="footnote-marker"')
          ..write(attrs.replaceAll(_classAttr, ''))
          ..write('>');
        cursor = tag.end;
      }
      out.write(line.substring(cursor, note.start));
      cursor = note.end;
    }
    out.write(line.substring(cursor));
    return out.toString();
  }

  static int countMarkers(String line) => !line.contains('footnote-marker') ? 0 : _marker.allMatches(line).length;

  static List<Span> markerRanges(String line) => [for (final m in _marker.allMatches(line)) Span(m.start, m.end)];

  static List<String> markers(String line) =>
      !line.contains('footnote-marker') ? const [] : [for (final m in _marker.allMatches(line)) m.group(1)!];

  static List<Span> consumerMarkerRanges(String line) {
    if (!line.toLowerCase().contains('footnote-marker')) return const [];
    return [
      for (final m in _consumerMarker.allMatches(line))
        if (_consumerBodyStart.matchAsPrefix(line, m.end) == null) Span(m.start, m.end),
    ];
  }

  /// טקסט פשוט (כותרות): כל גוף הערה וכל sup סימון מוסרים.
  static String stripMarkersAndBodies(String line) {
    if (!line.contains('footnote')) return line;
    final out = StringBuffer();
    var cursor = 0;
    while (true) {
      final open = _firstFrom(noteOpen, line, cursor);
      if (open == null) break;
      out.write(line.substring(cursor, open.start));
      cursor = _matchingClose(line, open.start)?.end ?? line.length;
    }
    out.write(line.substring(cursor));
    return out.toString().replaceAll(_marker, '');
  }

  static const _nbspEntities = ['&nbsp;', '&#160;', '&#xa0;'];

  static int _gapStart(String line, int end) {
    var at = end;
    while (at > 0) {
      final c = line.codeUnitAt(at - 1);
      if (ktCharIsWs(c) || c == 0xA0) {
        at--;
        continue;
      }
      String? entity;
      for (final e in _nbspEntities) {
        final from = at - e.length;
        if (from >= 0 && line.substring(from, at).toLowerCase() == e) {
          entity = e;
          break;
        }
      }
      if (entity == null) break;
      at -= entity.length;
    }
    return at;
  }

  static RegExpMatch? _matchingClose(String line, int openAt) {
    var depth = 0;
    for (final tag in _italicTag.allMatches(line, openAt)) {
      depth += tag.group(0)!.startsWith('</') ? -1 : 1;
      if (depth == 0) return tag;
    }
    return null;
  }
}

// ───────────────────────── LineNoteRehydration ─────────────────────────

class NoteAt {
  const NoteAt(this.charPos, this.body, this.hasMarker);
  final int charPos;
  final String body;
  final bool hasMarker;
}

abstract final class LineNoteRehydration {
  static const _open = '<i class="footnote">';
  static const _close = '</i>';
  static final _sup = RegExp('<sup\\b[^>]*>.*?</sup>', caseSensitive: false, dotAll: true);
  static final _inlineClose = RegExp(
    '</(?:b|i|em|strong|u|s|strike|span|sup|sub|small|big|font|del|ins|a|abbr|acronym|cite|code|dfn|kbd|q|samp|tt|var|mark|bdi|bdo|ruby|rt|rp)$_ws*>',
    caseSensitive: false,
  );

  static String rehydrate(String stored, List<NoteAt> notes) {
    if (notes.isEmpty) return stored;
    final out = StringBuffer();
    final sups = [for (final m in _sup.allMatches(stored)) Span(m.start, m.end)];
    final markers = notes.any((n) => n.hasMarker) ? InlineNotes.markerRanges(stored) : const <Span>[];
    var anchoredSeen = 0;
    var cursor = 0;
    for (final note in notes) {
      var at = _insertionPoint(stored, note.charPos, sups);
      if (note.hasMarker) {
        final marker = anchoredSeen < markers.length ? markers[anchoredSeen] : null;
        anchoredSeen++;
        if (marker != null && at <= marker.start && _onlyTagsBetween(stored, at, marker.start)) {
          at = _afterInlineClosings(stored, marker.end);
        }
      }
      if (at < cursor) at = cursor;
      out
        ..write(stored.substring(cursor, at))
        ..write(_open)
        ..write(note.body)
        ..write(_close);
      cursor = at;
    }
    out.write(stored.substring(cursor));
    return out.toString();
  }

  static int _afterInlineClosings(String html, int from) {
    var at = from;
    while (at < html.length) {
      final close = _inlineClose.matchAsPrefix(html, at);
      if (close == null) break;
      at = close.end;
    }
    return at;
  }

  static bool _onlyTagsBetween(String html, int from, int end) {
    var at = from;
    while (at < end) {
      if (html.codeUnitAt(at) != 0x3C) return false;
      final close = html.indexOf('>', at + 1);
      if (close < 0 || close >= end) return false;
      at = close + 1;
    }
    return at == end;
  }

  static int _insertionPoint(String html, int charPos, List<Span> sups) {
    var i = 0;
    if (charPos > 0) {
      var count = 0;
      var inTag = false;
      while (i < html.length && count < charPos) {
        final c = html.codeUnitAt(i);
        if (inTag) {
          if (c == 0x3E) inTag = false;
        } else if (c == 0x3C) {
          inTag = true;
        } else if (c == 0x26) {
          final end = html.length < i + 10 ? html.length : i + 10;
          var j = i + 1;
          while (j < end && html.codeUnitAt(j) != 0x3B) {
            j++;
          }
          count++;
          if (j < end) i = j;
        } else {
          count++;
        }
        i++;
      }
    }
    // Kotlin: i > first && i <= last (last כולל) ⇔ start < i < end.
    for (final s in sups) {
      if (i > s.start && i < s.end) {
        i = s.end;
        break;
      }
    }
    return _afterInlineClosings(html, i);
  }
}

// ───────────────────────── LineNoteIndex.processLine ─────────────────────────

class LineNoteRow {
  LineNoteRow(this.noteIndex, this.charPos, this.hasMarker, this.body);
  final int noteIndex;
  final int charPos;
  final bool hasMarker;
  final String body;
}

/// תוצאת עיבוד שורה אחת: [stripped] ו-[notes] כשהשורה השתנתה, אחרת [skipReason] (או null = אין הערות).
class LineNoteResult {
  LineNoteResult({this.stripped, this.notes = const [], this.skipReason, this.fatal = false});
  final String? stripped;
  final List<LineNoteRow> notes;
  final String? skipReason;

  /// במחולל הרשמי זה check() שמפיל את כל הבנייה.
  final bool fatal;
  bool get changed => stripped != null;
}

/// מעבד שורה שמכילה "footnote" (בלי תלות ברישיות) כמו `LineNotePass.processLine`.
LineNoteResult processLineNotes(String content) {
  final parsed = InlineNotes.parse(content);
  if (parsed.unclosedAt != null) {
    return LineNoteResult(skipReason: 'גוף הערה בלי </i> סוגר (מיקום ${parsed.unclosedAt}); השורה נשארת כמות שהיא');
  }
  final found = parsed.notes;
  if (found.isEmpty) return LineNoteResult();
  final stripped = InlineNotes.strip(content, found);
  if (InlineNotes.countMarkers(stripped) != found.where((n) => n.marker != null).length) {
    return LineNoteResult(skipReason: 'סימון sup בלי הערה אחריו; השורה נשארת כמות שהיא');
  }
  final consumer = InlineNotes.consumerMarkerRanges(stripped);
  final markers = InlineNotes.markerRanges(stripped);
  if (!_listEq(consumer, markers)) {
    return LineNoteResult(skipReason: 'כלל הסימונים של הקוראים אינו מוצא אותם sup (במחולל הרשמי: הבנייה נכשלת)', fatal: true);
  }
  if (!_listEq(InlineNotes.markers(stripped), [for (final n in found) ?n.marker])) {
    return LineNoteResult(skipReason: 'הסימונים שנשארו בשורה אינם משחזרים את סימוני ההערות (במחולל הרשמי: הבנייה נכשלת)', fatal: true);
  }
  final charPos = <int>[];
  var removedBefore = 0;
  for (final note in found) {
    final start = countVisibleChars(content, note.start);
    charPos.add(start - removedBefore);
    removedBefore += countVisibleChars(content, note.end) - start;
  }
  final moved = [for (var i = 0; i < found.length; i++) NoteAt(charPos[i], found[i].body, found[i].marker != null)];
  if (!_keepsOffsets(content, stripped, moved)) {
    return LineNoteResult(skipReason: 'בלי גופי ההערות השורה לא תמפה את מיקומי העוגנים בדיוק (במחולל הרשמי: הבנייה נכשלת)', fatal: true);
  }
  return LineNoteResult(
    stripped: stripped,
    notes: [for (var i = 0; i < found.length; i++) LineNoteRow(i, charPos[i], found[i].marker != null, found[i].body)],
  );
}

bool _keepsOffsets(String content, String stripped, List<NoteAt> notes) {
  final original = visibleUnits(content);
  final stored = visibleUnits(stripped);
  final spliced = <String>[];
  var cursor = 0;
  for (final note in notes) {
    if (note.charPos > stored.length) return false;
    spliced.addAll(stored.sublist(cursor, note.charPos));
    cursor = note.charPos;
    spliced.addAll(visibleUnits(note.body));
  }
  spliced.addAll(stored.sublist(cursor));
  return _listEq(spliced, original) && _listEq(visibleUnits(LineNoteRehydration.rehydrate(stripped, notes)), original);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ───────────────────────── HearotCompanionMerge ─────────────────────────

class MergeStats {
  int inPlace = 0;
  int appended = 0;
}

abstract final class HearotCompanionMerge {
  static const companionPrefix = 'הערות על ';
  static const _havroutaPrefix = 'הערות על חברותא';

  static bool isHavroutaBase(String baseTitle) => (companionPrefix + baseTitle).startsWith(_havroutaPrefix);
  static bool isMergeableCompanionTitle(String title) => title.startsWith(companionPrefix);

  static final _noteSmallSup = RegExp('^﻿?<small><sup>([^<]+)</sup>$_ws*');
  static final _noteSup = RegExp('^﻿?<sup(?:$_ws[^>]*)?>([^<]+)</sup>$_ws*');
  static final _noteBareNumber = RegExp('^﻿?([0-9]+)$_ws+');
  static final _noteBoldParen = RegExp('^﻿?<b>(\\([0-9]+[*א-ת]?\\))</b>$_ws*');
  static final _havroutaToken = RegExp('^\\([0-9]+[*א-ת]?\\)\$');

  static String stripFootnotes(String line) => InlineNotes.stripMarkersAndBodies(line);

  /// [notesByLine]: שורת בסיס (מ-0) → שורות הערה לפי סדר הקריאה. מספר השורות נשמר.
  static List<String> mergeLines(String bookTitle, List<String> baseLines, Map<int, List<String>> notesByLine, MergeStats stats) {
    if (notesByLine.isEmpty) return baseLines;
    final out = List<String>.of(baseLines);
    final havrouta = isHavroutaBase(bookTitle);
    final keys = notesByLine.keys.toList()..sort();
    for (final lineIdx in keys) {
      final notes = notesByLine[lineIdx]!;
      final original = out[lineIdx];
      final consumed = <Span>[];
      final placements = <(Span, String)>[];
      final appendix = StringBuffer();
      for (final note in notes) {
        final parsed = _parseLeadingMarker(note, havrouta);
        final anchor = parsed == null ? null : _findAnchor(original, parsed.$1, consumed, havrouta);
        if (parsed != null && anchor != null) {
          consumed.add(anchor);
          placements.add((anchor, '<sup class="footnote-marker">${parsed.$1}</sup><i class="footnote">${parsed.$2}</i>'));
          stats.inPlace++;
        } else {
          appendix
            ..write('<i class="footnote">')
            ..write(note.startsWith('﻿') ? note.substring(1) : note)
            ..write('</i>');
          stats.appended++;
        }
      }
      var line = original;
      placements.sort((a, b) => b.$1.start.compareTo(a.$1.start));
      for (final (range, html) in placements) {
        line = line.substring(0, range.start) + html + line.substring(range.end);
      }
      out[lineIdx] = line + appendix.toString();
    }
    return out;
  }

  static (String, String)? _parseLeadingMarker(String note, bool havrouta) {
    final small = _noteSmallSup.firstMatch(note);
    if (small != null) {
      final rest = ktTrimEnd(note.substring(small.group(0)!.length));
      if (rest.endsWith('</small>')) {
        return (small.group(1)!, ktTrimEnd(rest.substring(0, rest.length - '</small>'.length)));
      }
      return null;
    }
    final sup = _noteSup.firstMatch(note);
    if (sup != null) return (sup.group(1)!, note.substring(sup.group(0)!.length));
    final bare = _noteBareNumber.firstMatch(note);
    if (bare != null) return (bare.group(1)!, note.substring(bare.group(0)!.length));
    if (havrouta) {
      final bold = _noteBoldParen.firstMatch(note);
      if (bold != null) return (bold.group(1)!, note.substring(bold.group(0)!.length));
    }
    return null;
  }

  static Span? _findAnchor(String line, String token, List<Span> consumed, bool havrouta) {
    final esc = RegExp.escape(token);
    final patterns = [
      RegExp('<sup>$esc</sup>'),
      RegExp('<sup$_ws[^>]*>$esc</sup>'),
      RegExp('<small$_ws[^>]*>$_ws*$esc$_ws*</small>'),
      if (havrouta && _havroutaToken.hasMatch(token)) RegExp('<small>$esc</small>'),
    ];
    Span? best;
    for (final p in patterns) {
      for (final m in p.allMatches(line)) {
        final r = Span(m.start, m.end);
        if (consumed.any((c) => c.start < r.end && r.start < c.end)) continue;
        if (best == null || r.start < best.start) best = r;
      }
    }
    return best;
  }

  /// סיבה לכך ששורת הערה מקושרת אינה ניתנת למיזוג (`unmergeableNoteReason`), או null.
  static String? unmergeableNoteReason(String note) {
    if (ktIsBlank(note)) return 'שורת הערה ריקה מקושרת';
    if (note.contains('<i>') || note.contains('<i ') || note.contains('</i>')) {
      return 'הערה עם תגית <i> (שוברת את זיהוי ההערות באפליקציה)';
    }
    if (headingLineRegex.hasMatch(note)) return 'שורת כותרת מקושרת כהערה';
    return null;
  }
}
