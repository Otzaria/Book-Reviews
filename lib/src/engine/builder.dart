// בונה מסד ספרים אישי (סכמה 7) לפי כללי המחולל הרשמי של אוצריא (SeforimLibrary), עבור הקבצים
// שהמשתמש הוסיף בלבד, עם המטא-דאטה מ-otzaria-library (metadata.json ו-ForDB). המסד עומד בפני
// עצמו: שום נתון בו אינו תלוי בספרייה הרשמית.
//
// סדר השלבים כמו ב-generateSeforimDb:
//   appendOtzaria (תוכנית מיזוג הערות → קטגוריות → ספרים, שורות, תוכן עניינים → קישורים →
//   alt_toc → category_closure) → generateHavroutaLinks (רק ההערות כמפרש ברירת מחדל) →
//   seedGenerations → seedAllMetadata → seedBookNotices → buildLineNoteIndex → buildLineRefIndex →
//   buildLineDhIndex → splitLineContent → stampSchemaVersion (contentHash).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'content_hash.dart';
import 'inputs.dart';
import 'library.dart';
import 'line_dh.dart';
import 'line_ref.dart' show buildLineRefRows;
import 'notes.dart';
import 'official_categories.dart';
import 'official_schema.dart';
import 'priority_list.dart';
import 'report.dart';
import 'rules.dart';

export 'report.dart';

class BuildCancelled implements Exception {
  @override
  String toString() => 'הפעולה בוטלה';
}

class BuildError implements Exception {
  BuildError(this.message);
  final String message;
  @override
  String toString() => message;
}

class BuildOptions {
  BuildOptions({
    required this.inputs,
    required this.libraryPath,
    required this.outPath,
    required this.libraryId,
    required this.displayName,
    this.author = '',
    this.defaultCategory = 'ספרים לבדיקה',
    this.defaultSource = 'בדיקה',
    this.useLibraryLinks = false,
    this.externalLinks = true,
  });

  final List<InputSpec> inputs;
  final String libraryPath;
  final String outPath;
  final String libraryId;
  final String displayName;
  final String author;
  final String defaultCategory;
  final String defaultSource;

  /// גם `<כותרת>_links.json` ו-`<כותרת>_alt_toc.json` שבספרייה, לספרים שנוספו.
  final bool useLibraryLinks;

  /// קישור לספר שאינו במסד ← external_link לספרייה הרשמית.
  final bool externalLinks;
}

typedef ProgressFn = void Function(String title, String detail, double? fraction);

// ───────────────────────── מבני עבודה ─────────────────────────

class _Line {
  _Line(this.index, this.content);
  final int index;
  String content;
  int id = 0;
  String? heRef;
  int? tocEntryId;
  int charCount = 0;
  int? lineTocEntryId;
  List<LineNoteRow> notes = const [];
}

class _Toc {
  _Toc(this.id, this.parentId, this.text, this.level, this.lineId);
  final int id;
  final int? parentId;
  final String text;
  final int level;
  final int lineId;
  bool isLastChild = false;
  bool hasChildren = false;
}

class _Book {
  _Book(this.input, this.path, this.rawStem, this.title, this.placement, this.report);
  final InputSpec input;
  final String path;
  final String rawStem;
  final String title;
  final Placement placement;
  final BookReport report;
  int id = 0;
  int categoryId = 0;
  bool isBaseBook = false;
  int orderIndex = 999;
  String? heShortDesc;
  String? heDesc;
  BookMeta? meta;
  int totalLines = 0;
  bool hasAltStructures = false;
  final lines = <_Line>[];
  final tocs = <_Toc>[];

  /// lineIndex → שורה שנשמרה (null = לא נשמרה: כותרת ריקה).
  late List<_Line?> byIndex;
  final headingIndexes = <int>{};
  final authors = <String>[];
  final pubPlaces = <String>[];
  final pubDates = <String>[];
  final topics = <String>[];
  String fileName = '';
}

class _LinkFile {
  _LinkFile(this.path, this.origin);
  final String path;
  final String origin;
  String get fileName => p.basename(path);
  late final String rawText = utf8.decode(File(path).readAsBytesSync(), allowMalformed: true);
  late final LinkFileParse parsed = parseLinksJson(rawText);
}

class _Link {
  _Link(this.id, this.sourceBook, this.targetBook, this.sourceLine, this.targetLine, this.type);
  final int id;
  final _Book sourceBook;
  final _Book targetBook;
  final _Line sourceLine;
  final _Line targetLine;
  final ConnectionType type;
}

// ───────────────────────── הבנייה ─────────────────────────

BuildResult buildDatabase(BuildOptions o, {ProgressFn? progress, void Function()? checkCancel}) {
  final clock = Stopwatch()..start();
  void say(String t, [String d = '', double? f]) => progress?.call(t, d, f);
  void cancelPoint() => checkCancel?.call();
  final warnings = <String>[];

  if (o.inputs.isEmpty) throw BuildError('לא נוספו קבצים.');
  if (o.outPath.isEmpty) throw BuildError('לא נבחר קובץ פלט.');

  say('קורא את otzaria-library', o.libraryPath);
  final index = LibraryIndex.scan(o.libraryPath);
  final meta = LibraryMeta.load(o.libraryPath);
  if (index.isEmpty) {
    warnings.add('תיקיית otzaria-library לא נמצאה (${o.libraryPath}): בלי מיקום מהספרייה ובלי מטא-דאטה.');
  }
  for (final e in meta.errors) {
    warnings.add('otzaria-library: $e');
  }
  cancelPoint();

  // ── קלט ──
  final defaults = PlacementDefaults(category: o.defaultCategory, source: o.defaultSource);
  final placements = placeInputs(o.inputs, index, defaults);
  final books = <_Book>[];
  final seenTitles = <String, _Book>{};
  final linkFiles = <String, _LinkFile>{};
  final altTocFiles = <String, String>{};
  final skippedReports = <BookReport>[];
  for (final input in o.inputs) {
    final role = roleOf(input.path);
    if (!File(input.path).existsSync()) {
      warnings.add('הקובץ לא נמצא: ${input.path}');
      continue;
    }
    switch (role) {
      case InputRole.links:
        linkFiles.putIfAbsent(p.basename(input.path), () => _LinkFile(input.path, 'נוסף'));
      case InputRole.altToc:
        altTocFiles.putIfAbsent(p.basename(input.path), () => input.path);
      case InputRole.book:
      case InputRole.notes:
        final rawStem = p.basenameWithoutExtension(input.path);
        final title = bookTitleOf(rawStem);
        final pl = placements[input.path]!;
        final report = BookReport(
          path: input.path,
          rawStem: rawStem,
          title: title,
          role: role.label,
          source: pl.source,
          categoryPath: pl.categoryTitles,
          placement: pl.kind.label,
        );
        final dup = seenTitles[title];
        if (dup != null) {
          report.errors.add('כפילות: כבר נוסף ספר בשם "$title" (${dup.path}). נשמר הראשון בלבד.');
          skippedReports.add(report);
          continue;
        }
        final b = _Book(input, input.path, rawStem, title, pl, report)..fileName = p.basename(input.path);
        seenTitles[title] = b;
        books.add(b);
      case InputRole.unknown:
        warnings.add('סוג קובץ לא נתמך: ${input.path}');
    }
  }
  if (books.isEmpty) throw BuildError('אין ספרים (קבצי TXT) בקלט.');
  if (o.useLibraryLinks && !index.isEmpty) {
    for (final b in books) {
      final lib = index.linkFiles['${b.rawStem}_links.json'] ?? index.linkFiles['${b.title}_links.json'];
      if (lib != null && !linkFiles.containsKey(p.basename(lib))) {
        linkFiles[p.basename(lib)] = _LinkFile(lib, 'מהספרייה');
      }
      final at = index.altTocFiles['${b.rawStem}_alt_toc.json'] ?? index.altTocFiles['${b.title}_alt_toc.json'];
      if (at != null) altTocFiles.putIfAbsent(p.basename(at), () => at);
    }
  }
  final sortedLinkFiles = linkFiles.values.toList()..sort((a, b) => a.fileName.compareTo(b.fileName));

  // ── קריאת הספרים ──
  final fileLines = <_Book, List<String>>{};
  for (final b in books) {
    final text = utf8.decode(File(b.path).readAsBytesSync(), allowMalformed: true);
    fileLines[b] = stripFirstLineBom(ktLines(text));
    if (text.startsWith('version https://git-lfs')) b.report.errors.add('הקובץ הוא מצביע Git LFS ולא ספר.');
  }

  // ── תוכנית מיזוג ההערות (buildHearotMergePlans) ──
  say('בודק מיזוג הערות');
  final byNormTitle = {for (final b in books) b.title: b};
  final plans = <String, Map<int, List<String>>>{};
  final mergedTitles = <String>{};
  final notesDecisions = <NotesDecision>[];
  String? libraryAmbiguity(String title) {
    final places = index.byTitle[title];
    if (places == null) return null;
    final rels = {for (final pl in places) [...pl.folders, p.basename(pl.path)].join('/')};
    return rels.length > 1 ? 'בספרייה יש ${rels.length} קבצים בשם הזה (המחולל לא ימזג)' : null;
  }

  for (final lf in sortedLinkFiles) {
    final stem = lf.fileName.substring(0, lf.fileName.length - '.json'.length);
    final baseTitle = bookTitleOf(stem.endsWith('_links') ? stem.substring(0, stem.length - 6) : stem);
    final allEntries = lf.parsed.entries;
    final companion = allEntries
        .where((e) => HearotCompanionMerge.isMergeableCompanionTitle(bookTitleOf(linkTargetTitle(e.path2))))
        .toList();
    if (companion.isEmpty) continue;
    final base = byNormTitle[baseTitle];
    final groups = <String, List<LinkEntry>>{};
    for (final e in companion) {
      (groups[bookTitleOf(linkTargetTitle(e.path2))] ??= []).add(e);
    }
    final hearotTitles = groups.keys.toList()..sort();
    void standalone(String hearot, String reason) =>
        notesDecisions.add(NotesDecision(hearot, baseTitle, false, reason, lf.fileName));
    if (base == null) {
      for (final h in hearotTitles) {
        standalone(h, 'ספר הבסיס "$baseTitle" לא נוסף');
      }
      continue;
    }
    final baseAmb = libraryAmbiguity(baseTitle);
    if (baseAmb != null) {
      for (final h in hearotTitles) {
        standalone(h, 'ספר הבסיס: $baseAmb');
      }
      continue;
    }
    final baseLines = fileLines[base]!;
    for (final hearotTitle in hearotTitles) {
      final hearot = byNormTitle[hearotTitle];
      if (hearot == null) {
        standalone(hearotTitle, 'קובץ ההערות לא נוסף');
        continue;
      }
      final amb = libraryAmbiguity(hearotTitle);
      if (amb != null) {
        standalone(hearotTitle, amb);
        continue;
      }
      final seen = <(double, double)>{};
      final entries = [
        for (final e in groups[hearotTitle]!)
          if (seen.add((e.lineIndex1, e.lineIndex2))) e,
      ];
      if (entries.any((e) => e.lineIndex1End != null || e.lineIndex2End != null)) {
        standalone(hearotTitle, 'יש קישורי טווח (line_index_*_end) להערות');
        continue;
      }
      final hearotLines = fileLines[hearot]!;
      final bad = entries.where(
        (e) =>
            ktToInt(e.lineIndex1) - 1 < 0 ||
            ktToInt(e.lineIndex1) - 1 >= baseLines.length ||
            ktToInt(e.lineIndex2) - 1 < 0 ||
            ktToInt(e.lineIndex2) - 1 >= hearotLines.length,
      );
      if (bad.isNotEmpty) {
        final e = bad.first;
        standalone(hearotTitle, 'קישור מחוץ לטווח הקבצים (למשל ${ktToInt(e.lineIndex1)} → ${ktToInt(e.lineIndex2)})');
        continue;
      }
      final referenced = {for (final e in entries) ktToInt(e.lineIndex2) - 1};
      final unlinked = <int>[
        for (var j = 0; j < hearotLines.length; j++)
          if (!referenced.contains(j) && ktIsNotBlank(hearotLines[j]) && !headingLineRegex.hasMatch(hearotLines[j]))
            j + 1,
      ];
      if (unlinked.isNotEmpty) {
        standalone(
          hearotTitle,
          '${unlinked.length} שורות הערה שאין אליהן קישור '
          '(שורות ${unlinked.take(8).join(', ')}${unlinked.length > 8 ? '…' : ''})',
        );
        continue;
      }
      String? badNote;
      int? badLine;
      for (final j in referenced) {
        badNote = HearotCompanionMerge.unmergeableNoteReason(hearotLines[j]);
        if (badNote != null) {
          badLine = j + 1;
          break;
        }
      }
      if (badNote != null) {
        standalone(hearotTitle, '$badNote (שורה $badLine בקובץ ההערות)');
        continue;
      }
      final noteLineIdxs = {for (final e in entries) ktToInt(e.lineIndex1) - 1};
      final withFootnotes = noteLineIdxs.where((i) => baseLines[i].contains('class="footnote')).toList()..sort();
      if (withFootnotes.isNotEmpty) {
        standalone(hearotTitle, 'שורת בסיס כבר מכילה הערות מוטמעות (שורה ${withFootnotes.first + 1})');
        continue;
      }
      final anchored = allEntries.where((e) => e.start != null && noteLineIdxs.contains(ktToInt(e.lineIndex1) - 1));
      if (anchored.isNotEmpty) {
        standalone(
          hearotTitle,
          'קישור עם עוגן מילה (start) על שורת בסיס שמקבלת הערה (שורה ${ktToInt(anchored.first.lineIndex1)})',
        );
        continue;
      }
      final perLine = plans.putIfAbsent(baseTitle, () => <int, List<String>>{});
      final sortedEntries = [...entries];
      stableSort(sortedEntries, (a, b) => a.lineIndex2.compareTo(b.lineIndex2));
      for (final e in sortedEntries) {
        (perLine[ktToInt(e.lineIndex1) - 1] ??= []).add(hearotLines[ktToInt(e.lineIndex2) - 1]);
      }
      mergedTitles.add(hearotTitle);
      notesDecisions.add(
        NotesDecision(hearotTitle, baseTitle, true, '${entries.length} הערות ימוזגו כהערות שוליים בתוך הספר', lf.fileName),
      );
    }
  }
  for (final b in books) {
    if (b.report.role != InputRole.notes.label) continue;
    final d = notesDecisions.where((d) => d.notesTitle == b.title).firstOrNull;
    b.report.notesDecision = d ??
        NotesDecision(
          b.title,
          b.title.substring('הערות על '.length),
          false,
          'אין קובץ <בסיס>_links.json עם קישורים לקובץ ההערות הזה',
          null,
        );
  }

  // ── בדיקות שהמחולל היה מדלג בגללן ──
  for (final b in books) {
    if (sourceBlacklist.any((s) => comparableLabel(s) == comparableLabel(b.placement.source))) {
      b.report.errors.add('המקור "${b.placement.source}" ברשימה השחורה של המחולל: הספר לא ייכנס לספרייה הרשמית.');
    }
    if (b.placement.folders.isNotEmpty && foldersToRemove.contains(b.placement.folders.first)) {
      b.report.errors.add('התיקייה "${b.placement.folders.first}" נמחקת לפני הבנייה הרשמית: הספר לא ייכנס.');
    }
    final libDup = libraryAmbiguity(b.title);
    if (libDup != null) b.report.warnings.add(libDup.replaceAll(' (המחולל לא ימזג)', ''));
  }

  // ── קטגוריות וספרים, בסדר המעבר של המחולל ──
  final imported = [
    for (final b in books)
      if (!mergedTitles.contains(b.title)) b,
  ];
  for (final b in books) {
    if (mergedTitles.contains(b.title)) {
      b.report.mergedInto = b.report.notesDecision?.baseTitle;
      skippedReports.add(b.report);
    }
  }
  final orderedBooks = _traversalOrder(imported);

  final categories = <_Category>[];
  final catByKey = <String, _Category>{};
  _Category ensureCategories(List<String> rawFolders) {
    _Category? parent;
    for (final raw in rawFolders) {
      var title = folderTitle(raw);
      final cmp = comparableLabel(title);
      final key = '${parent?.id ?? 0}\u0000$cmp';
      var c = catByKey[key];
      if (c == null) {
        // findExistingCategory מול העץ הרשמי: תיקייה נכנסת לקטגוריה קיימת בשם בר-השוואה.
        final parentOfficial = parent == null ? '' : parent.officialPath;
        String? officialPath;
        if (parentOfficial != null) {
          final match = officialChildren(parentOfficial).where((t) => comparableLabel(t) == cmp).firstOrNull;
          if (match != null) {
            title = match;
            officialPath = parentOfficial.isEmpty ? match : '$parentOfficial/$match';
          }
        }
        c = _Category(categories.length + 1, parent?.id, title, parent == null ? 0 : parent.level + 1, parent)
          ..officialPath = officialPath;
        categories.add(c);
        catByKey[key] = c;
      }
      parent = c;
    }
    return parent!;
  }

  // ── טקסט, שורות ותוכן עניינים ──
  final tocTextIds = <String, int>{};
  var nextLineId = 1;
  var nextTocId = 1;
  var bookNo = 0;
  final booksByTitle = <String, _Book>{};
  for (final b in orderedBooks) {
    cancelPoint();
    bookNo++;
    say('מעבד ספרים', b.title, bookNo / (orderedBooks.length + 1));
    final cat = ensureCategories(b.placement.folders);
    b.categoryId = cat.id;
    b.id = bookNo;
    b.report.categoryPath = cat.path;
    if (cat.path.join('/') != b.placement.categoryTitles.join('/')) {
      b.report.titleChanges.add(
        'קטגוריה: "${b.placement.categoryTitles.join('/')}" ← "${cat.path.join('/')}" (כמו הקטגוריה הקיימת בספרייה הרשמית)',
      );
    }
    b.report.bookId = b.id;
    final relPath = [...b.placement.folders, b.fileName].join('/');
    b.isBaseBook = priorityBookPaths.contains(relPath);
    b.report.isBaseBook = b.isBaseBook;
    if (b.title != b.rawStem) b.report.titleChanges.add('"${b.rawStem}" ← "${b.title}"');
    booksByTitle[b.title] = b;

    // מטא-דאטה מ-metadata.json
    final m = meta.lookup(b.rawStem, b.title);
    b.meta = m;
    if (m == null) {
      final t = meta.lookupTrimmedOnly(b.rawStem, b.title);
      if (t != null) {
        b.report.errors.add(
          'ב-metadata.json הכותרת כתובה עם רווח מיותר ("${t.title}"): המחולל הרשמי לא ימצא את הרשומה, '
          'ולכן גם כאן היא לא נלקחה.',
        );
      }
    }
    for (final a in m?.authorNames ?? const <String>[]) {
      final n = normalizeAuthorName(a);
      if (!b.authors.contains(n)) b.authors.add(n);
    }
    if (m?.pubPlace != null) b.pubPlaces.add(m!.pubPlace!);
    if (m?.pubDate != null) b.pubDates.add(m!.pubDate!);
    b.heShortDesc = m?.heShortDesc;
    b.orderIndex = m?.order == null ? 999 : m!.order!.truncate();
    final full = ['אוצריא', ...b.placement.folders];
    b.topics.addAll(full.sublist(full.length >= 2 ? full.length - 2 : 0));

    // מיזוג הערות
    var lines = fileLines[b]!;
    final plan = plans[b.title];
    if (plan != null) {
      final stats = MergeStats();
      lines = HearotCompanionMerge.mergeLines(b.title, lines, plan, stats);
      b.report.mergedNotes = stats.inPlace + stats.appended;
      b.report.mergedNotesAppended = stats.appended;
    }
    b.totalLines = lines.length;
    b.byIndex = List<_Line?>.filled(lines.length, null);

    // processLinesWithTocEntries
    final parentStack = <int, int>{};
    final entriesByParent = <int?, List<_Toc>>{};
    int? owner;
    var lastLevel = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final level = detectHeaderLevel(line);
      if (level > 0) {
        parentStack.removeWhere((k, _) => k >= level);
        final plain = cleanHtmlForToc(HearotCompanionMerge.stripFootnotes(line));
        if (ktIsBlank(plain)) {
          b.report.tocIssues.add('שורה ${i + 1}: כותרת ריקה (h$level) — המחולל משמיט את השורה כולה מהמסד');
          continue;
        }
        if (lastLevel > 0 && level > lastLevel + 1) {
          b.report.tocIssues.add('שורה ${i + 1}: קפיצת רמה h$lastLevel → h$level');
        } else if (lastLevel == 0 && level > 1) {
          b.report.tocIssues.add('שורה ${i + 1}: הכותרת הראשונה היא h$level (לא h1)');
        }
        lastLevel = level;
        int? parentId;
        for (var l = level - 1; l >= 1; l--) {
          if (parentStack.containsKey(l)) {
            parentId = parentStack[l];
            break;
          }
        }
        final ln = _Line(i, line)
          ..id = nextLineId++
          ..charCount = countVisibleChars(line);
        final toc = _Toc(nextTocId++, parentId, plain, level, ln.id);
        tocTextIds.putIfAbsent(plain, () => tocTextIds.length + 1);
        b.tocs.add(toc);
        parentStack[level] = toc.id;
        (entriesByParent[parentId] ??= []).add(toc);
        owner = toc.id;
        ln
          ..tocEntryId = toc.id
          ..lineTocEntryId = toc.id;
        b.lines.add(ln);
        b.byIndex[i] = ln;
        b.headingIndexes.add(i);
      } else {
        final ln = _Line(i, line)
          ..id = nextLineId++
          ..heRef = otzariaRef(b.title, i)
          ..charCount = countVisibleChars(line)
          ..lineTocEntryId = owner;
        b.lines.add(ln);
        b.byIndex[i] = ln;
      }
    }
    final parentIds = {for (final t in b.tocs) ?t.parentId};
    for (final t in b.tocs) {
      t.hasChildren = parentIds.contains(t.id);
    }
    for (final list in entriesByParent.values) {
      list.last.isLastChild = true;
    }
    b.report
      ..totalLines = b.totalLines
      ..storedLines = b.lines.length
      ..headings = b.headingIndexes.length
      ..tocEntries = b.tocs.length;
    for (final t in b.tocs) {
      b.report.tocLevels[t.level] = (b.report.tocLevels[t.level] ?? 0) + 1;
    }
    if (b.tocs.isEmpty) b.report.tocIssues.add('אין כותרות (h1–h6): לספר לא יהיה תוכן עניינים');
    final leading = b.lines.where((l) => l.lineTocEntryId == null).length;
    if (b.tocs.isNotEmpty && leading > 0) {
      b.report.tocIssues.add('$leading שורות לפני הכותרת הראשונה (אינן משויכות לאף כותרת)');
    }
  }

  // ── קישורים (processLinks) ──
  say('מעבד קישורים');
  final links = <_Link>[];
  final linkKeys = <(int, int, ConnectionType), _Link>{};
  final anchors = <(int, int, int), (int?, String?)>{}; // (linkId, side, charStart) → (charEnd, label)
  final ranges = <(int, int), (_Line, int)>{}; // (linkId, side) → (endLine, endLineIndex)
  final coverage = <(int, int, int)>{}; // (lineId, linkId, side)
  final externals = <List<Object?>>[];
  final linkReports = <LinkFileReport>[];
  for (final lf in sortedLinkFiles) {
    cancelPoint();
    final stem = lf.fileName.substring(0, lf.fileName.length - '.json'.length);
    final rawSource = stem.endsWith('_links') ? stem.substring(0, stem.length - 6) : stem;
    final rep = LinkFileReport(fileName: lf.fileName, path: lf.path, origin: lf.origin, sourceTitle: rawSource);
    linkReports.add(rep);
    if (lf.parsed.error != null) {
      rep.parseError = lf.parsed.error;
      continue;
    }
    final entries = lf.parsed.entries;
    rep.total = entries.length;
    rep.connectionTypeMisspelled = entries.where((e) => e.usesConnectionTypeSpelling).length;
    final source = booksByTitle[rawSource];
    if (source == null) {
      final norm = bookTitleOf(rawSource);
      rep.sourceProblem = mergedTitles.contains(norm)
          ? 'ספר המקור מוזג כהערות לתוך ספר אחר'
          : booksByTitle.containsKey(norm)
          ? 'שם הקובץ אינו זהה לכותרת הספר במסד ("$norm"): המחולל מחפש לפי שם הקובץ כמות שהוא, ולא יטען את הקישורים'
          : 'ספר המקור "$rawSource" אינו במסד';
      rep.dropped['ספר המקור לא במסד'] = entries.length;
      continue;
    }
    source.report.linkFiles.add(lf.fileName);
    for (final e in entries) {
      final targetTitle = linkTargetTitle(e.path2);
      final target = booksByTitle[targetTitle];
      final declared = ConnectionType.fromString(e.connectionType);
      if (ConnectionType.fromKnown(e.connectionType) == null) {
        rep.unknownTypes[e.connectionType] = (rep.unknownTypes[e.connectionType] ?? 0) + 1;
      }
      final srcIdx = ktToInt(e.lineIndex1) - 1 < 0 ? 0 : ktToInt(e.lineIndex1) - 1;
      final tgtIdx = ktToInt(e.lineIndex2) - 1 < 0 ? 0 : ktToInt(e.lineIndex2) - 1;
      if (target == null) {
        final norm = bookTitleOf(targetTitle);
        if (HearotCompanionMerge.isMergeableCompanionTitle(norm)) {
          if (mergedTitles.contains(norm)) {
            rep.mergedIntoNotes++;
          } else {
            rep.bump('יעד "הערות על" שאינו במסד (המחולל מדלג בשקט)');
          }
          continue;
        }
        rep.missingTargets[targetTitle] = (rep.missingTargets[targetTitle] ?? 0) + 1;
        if (!o.externalLinks) {
          rep.bump('ספר היעד אינו במסד');
          continue;
        }
        final sl = srcIdx < source.byIndex.length ? source.byIndex[srcIdx] : null;
        if (sl == null) {
          rep.bump('שורת מקור מחוץ לטווח');
          continue;
        }
        if (source.headingIndexes.contains(srcIdx)) {
          rep.bump('שורת כותרת');
          continue;
        }
        if (declared == ConnectionType.linker) {
          rep.bump('סוג linker (לא מיובא)');
          continue;
        }
        externals.add([source.id, srcIdx, 'official', norm, null, tgtIdx, _externalType(declared, source, norm)]);
        rep.external++;
        continue;
      }
      final sl = srcIdx < source.byIndex.length ? source.byIndex[srcIdx] : null;
      final tl = tgtIdx < target.byIndex.length ? target.byIndex[tgtIdx] : null;
      if (sl == null || tl == null) {
        rep.bump(sl == null ? 'שורת מקור מחוץ לטווח' : 'שורת יעד מחוץ לטווח');
        continue;
      }
      if (source.headingIndexes.contains(srcIdx) || target.headingIndexes.contains(tgtIdx)) {
        rep.bump('שורת כותרת');
        continue;
      }
      if (declared == ConnectionType.linker) {
        rep.bump('סוג linker (לא מיובא)');
        continue;
      }
      final nonBaseIntoBase =
          ConnectionType.sourceViewTypes.contains(declared) && target.isBaseBook && !source.isBaseBook;
      final reversed = nonBaseIntoBase && titleDeclaresDependencyOn(source.title, target.title);
      final flip = declared == ConnectionType.source || reversed;
      final stored = declared == ConnectionType.source
          ? ConnectionType.commentary
          : (nonBaseIntoBase && !reversed ? ConnectionType.other : declared);
      final sBook = flip ? target : source, tBook = flip ? source : target;
      final sLine = flip ? tl : sl, tLine = flip ? sl : tl;
      final key = (sLine.id, tLine.id, stored);
      var link = linkKeys[key];
      if (link == null) {
        link = _Link(links.length + 1, sBook, tBook, sLine, tLine, stored);
        links.add(link);
        linkKeys[key] = link;
        rep.byType[stored.dbName] = (rep.byType[stored.dbName] ?? 0) + 1;
        if (flip) rep.flipped++;
        rep.stored++;
      } else {
        rep.duplicates++;
      }
      if (!flip && e.start != null) {
        final rawStart = ktToInt(e.start!);
        final content = sl.content;
        if (rawStart < 0 || rawStart > content.length) {
          rep.anchorsDropped++;
        } else {
          final rawEnd = e.end == null ? null : ktToInt(e.end!);
          final end = rawEnd != null && rawEnd >= rawStart && rawEnd <= content.length ? rawEnd : null;
          final k = (link.id, 0, countVisibleChars(content, rawStart));
          if (!anchors.containsKey(k)) {
            anchors[k] = (end == null ? null : countVisibleChars(content, end), anchorLabelFromHeRef(e.heRef2));
            rep.anchors++;
          }
        }
      }
      final linkId = link.id;
      void rangeSide(double? rawEnd, _Book book, int startIdx, int side) {
        if (rawEnd == null) return;
        final endIdx = ktToInt(rawEnd) - 1;
        if (endIdx == startIdx) return;
        final endLine = endIdx > startIdx && endIdx < book.byIndex.length ? book.byIndex[endIdx] : null;
        if (endLine == null || book.headingIndexes.contains(endIdx)) {
          rep.rangesDropped++;
          return;
        }
        ranges[(linkId, side)] = (endLine, endIdx);
        rep.ranges++;
        for (var idx = startIdx + 1; idx <= endIdx; idx++) {
          final covered = book.byIndex[idx];
          if (covered == null || book.headingIndexes.contains(idx)) continue;
          coverage.add((covered.id, linkId, side));
        }
      }

      if (flip) {
        rangeSide(e.lineIndex2End, target, tgtIdx, 0);
        rangeSide(e.lineIndex1End, source, srcIdx, 1);
      } else {
        rangeSide(e.lineIndex1End, source, srcIdx, 0);
        rangeSide(e.lineIndex2End, target, tgtIdx, 1);
      }
    }
  }

  // ── alt_toc ──
  final altStructures = <_AltStructure>[];
  final altFiles = altTocFiles.keys.toList()..sort();
  for (final name in altFiles) {
    final title = name.substring(0, name.length - '_alt_toc.json'.length);
    final book = booksByTitle[title];
    if (book == null) {
      warnings.add('$name: ספר "$title" אינו במסד — הקובץ דולג');
      continue;
    }
    try {
      final j = jsonDecode(stripBom(utf8.decode(File(altTocFiles[name]!).readAsBytesSync(), allowMalformed: true)));
      final built = <String, _AltStructure>{};
      for (final s in (j as List)) {
        final st = _AltStructure.build(book, s as Map, tocTextIds);
        if (st == null) {
          built.remove((s['key'] ?? '').toString());
          continue;
        }
        built[st.key] = st;
      }
      altStructures.addAll(built.values);
      book.hasAltStructures = built.isNotEmpty;
      book.report.altTocStructures = built.length;
    } catch (e) {
      book.report.warnings.add('$name: JSON לא תקין ($e) — המחולל מדלג על הקובץ');
    }
  }

  // ── הערות כמפרש ברירת מחדל (setHearotAsDefaultCommentators) ──
  final defaultPairs = <(int, int)>{};
  for (final l in links) {
    if (l.type == ConnectionType.footnotes || l.targetBook.title == 'הערות על ${l.sourceBook.title}') {
      defaultPairs.add((l.sourceBook.id, l.targetBook.id));
    }
  }
  final defaultCommentators = defaultPairs.toList()
    ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  if (defaultCommentators.isEmpty && orderedBooks.any((b) => b.title.startsWith('הערות על '))) {
    warnings.add(
      'יש ספר "הערות על" עצמאי, אבל אין אף קישור FOOTNOTES מספר בסיס אליו: במחולל הרשמי זו שגיאה שמפילה את הבנייה '
      '(ההערות לא ייפתחו לצד אף ספר).',
    );
  }

  // ── seedAllMetadata: תיאורים, שנת ומקום הדפסה ──
  for (final b in orderedBooks) {
    final key = ktTrim(b.title);
    final bulk = meta.bulk[key];
    final desc = meta.descriptions[key];
    if (desc != null) {
      if (desc.heShortDesc != null) b.heShortDesc = desc.heShortDesc;
      if (desc.heDesc != null) b.heDesc = desc.heDesc;
    }
    if (bulk != null) {
      for (final y in bulk.$1) {
        if (!b.pubDates.contains('$y')) b.pubDates.add('$y');
      }
      if (bulk.$2 != null && !b.pubPlaces.contains(bulk.$2)) b.pubPlaces.add(bulk.$2!);
    }
  }

  // ── seedBookNotices ──
  final bannerOf = <int, BannerRow>{};
  final protectionOf = <int, int>{};
  void resolveNotices<T>(List<T> rows, String Function(T) src, String Function(T) book, void Function(_Book, T) apply) {
    for (final r in rows.where((r) => book(r).isEmpty)) {
      for (final b in orderedBooks.where((b) => b.placement.source == src(r))) {
        apply(b, r);
      }
    }
    for (final r in rows.where((r) => book(r).isNotEmpty)) {
      for (final b in orderedBooks.where((b) => b.placement.source == src(r) && b.title == book(r))) {
        apply(b, r);
      }
    }
  }

  resolveNotices<BannerRow>(meta.banners, (r) => r.source, (r) => r.book, (b, r) => bannerOf[b.id] = r);
  resolveNotices<ProtectionRow>(
    meta.protections,
    (r) => r.source,
    (r) => r.book,
    (b, r) => protectionOf[b.id] = r.level,
  );

  // ── buildLineNoteIndex ──
  say('מעביר הערות שוליים ל-line_note');
  for (final b in orderedBooks) {
    for (final l in b.lines) {
      if (!l.content.toLowerCase().contains('footnote')) continue;
      final r = processLineNotes(l.content);
      if (r.changed) {
        l.content = r.stripped!;
        l.notes = r.notes;
        l.charCount = countVisibleChars(l.content);
        b.report.lineNotes += r.notes.length;
      } else if (r.skipReason != null) {
        (r.fatal ? b.report.errors : b.report.warnings).add('שורה ${l.index + 1}: ${r.skipReason}');
      }
    }
  }

  // ── line_ref, line_dh, contentHash ──
  say('בונה אינדקס הפניות ודיבור המתחיל');
  final lineRefRows = <List<Object?>>[];
  final lineDhRows = <List<Object?>>[];
  final hashes = <int, int>{};
  for (final b in orderedBooks) {
    cancelPoint();
    final refs = buildLineRefRows(
      bookTitle: b.title,
      bookHeRef: b.title,
      lines: [for (final l in b.lines) (lineIndex: l.index, heRef: l.heRef)],
    );
    for (final r in refs) {
      lineRefRows.add([b.id, r.refKeyHash, r.lineIndex]);
    }
    final dh = buildLineDhRows(
      bookTitle: b.title,
      sourceName: b.placement.source,
      isBaseBook: b.isBaseBook,
      hasBaseText: false,
      lines: [for (final l in b.lines) (lineIndex: l.index, content: l.content)],
    );
    for (final r in dh) {
      lineDhRows.add([b.id, r.dhText, r.lineIndex, r.dhDisplay]);
    }
    b.report.lineRefRows = refs.length;
    b.report.lineDhRows = dh.length;
    hashes[b.id] = bookContentHash([for (final l in b.lines) HashLine(l.index, l.content, l.notes)]);
    b.report.contentHash = hashes[b.id]!;
  }

  // ── כתיבת המסד ──
  say('כותב את המסד');
  final prev = readSchemaMeta(o.outPath);
  final version = prev != null && prev['library_id'] == o.libraryId
      ? (int.tryParse(prev['db_version'] ?? '') ?? 0) + 1
      : 1;
  final tmp = '${o.outPath}.part';
  for (final f in [tmp, '$tmp-journal', '$tmp-wal', '$tmp-shm']) {
    if (File(f).existsSync()) File(f).deleteSync();
  }
  File(tmp).parent.createSync(recursive: true);
  Database? db;
  try {
    db = sqlite3.open(tmp);
    db.execute('PRAGMA journal_mode=OFF');
    db.execute('PRAGMA synchronous=OFF');
    db.execute('PRAGMA foreign_keys=OFF');
    for (final ddl in officialTables.values) {
      db.execute(ddl);
    }
    for (final ddl in officialIndexes) {
      db.execute(ddl);
    }
    db.execute(externalLinkDdl);
    db.execute(externalLinkIndexDdl);
    db.execute('BEGIN');
    final ins = _Inserter(db);

    ins.run('INSERT INTO schema_meta(key,value) VALUES (?,?)', [
      ['library_id', o.libraryId],
      ['library_name', o.displayName],
      ['display_name', o.displayName],
      ['db_version', '$version'],
      ['db_schema_version', '7'],
      ['description', 'ספרים לבדיקה, נבנו לפי כללי המחולל הרשמי (בודק המרות לאוצריא)'],
      ['author', o.author],
    ]);
    ins.run('INSERT INTO connection_type(id,name) VALUES (?,?)', [
      for (final t in ConnectionType.values) [t.index + 1, t.dbName],
    ]);
    final sourceIds = <String, int>{};
    for (final b in orderedBooks) {
      sourceIds.putIfAbsent(b.placement.source, () => sourceIds.length + 1);
    }
    ins.run('INSERT INTO source(id,name) VALUES (?,?)', [
      for (final e in sourceIds.entries) [e.value, e.key],
    ]);
    for (final c in categories) {
      final edit = meta.categoryEdits[c.canonicalPath];
      if (edit != null) {
        if (edit.shortEdit != null) c.heShortDesc = edit.shortEdit!.isEmpty ? null : edit.shortEdit;
        if (edit.longEdit != null) c.heDesc = edit.longEdit!.isEmpty ? null : edit.longEdit;
      }
    }
    ins.run('INSERT INTO category(id,parentId,title,level,orderIndex,heShortDesc,heDesc) VALUES (?,?,?,?,999,?,?)', [
      for (final c in categories) [c.id, c.parentId, c.title, c.level, c.heShortDesc, c.heDesc],
    ]);
    ins.run('INSERT INTO category_closure(ancestorId,descendantId) VALUES (?,?)', [
      for (final c in categories) ...[
        [c.id, c.id],
        for (var a = c.parent; a != null; a = a.parent) [a.id, c.id],
      ],
    ]);
    ins.run(
      'INSERT INTO book(id,categoryId,sourceId,title,heRef,heShortDesc,heDesc,orderIndex,totalLines,isBaseBook,'
      'hasAltStructures,contentHash) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        for (final b in orderedBooks)
          [
            b.id,
            b.categoryId,
            sourceIds[b.placement.source],
            b.title,
            b.title,
            b.heShortDesc,
            b.heDesc,
            b.orderIndex,
            b.totalLines,
            b.isBaseBook ? 1 : 0,
            b.hasAltStructures ? 1 : 0,
            hashes[b.id],
          ],
      ],
    );
    final authorIds = <String, int>{}, topicIds = <String, int>{};
    final placeIds = <String, int>{}, dateIds = <String, int>{};
    for (final b in orderedBooks) {
      for (final a in b.authors) {
        authorIds.putIfAbsent(a, () => authorIds.length + 1);
      }
      for (final t in b.topics) {
        topicIds.putIfAbsent(t, () => topicIds.length + 1);
      }
      for (final x in b.pubPlaces) {
        placeIds.putIfAbsent(x, () => placeIds.length + 1);
      }
      for (final d in b.pubDates) {
        dateIds.putIfAbsent(d, () => dateIds.length + 1);
      }
    }
    List<List<Object?>> idRows(Map<String, int> m) => [
      for (final e in m.entries) [e.value, e.key],
    ];
    ins.run('INSERT INTO author(id,name) VALUES (?,?)', idRows(authorIds));
    ins.run('INSERT INTO topic(id,name) VALUES (?,?)', idRows(topicIds));
    ins.run('INSERT INTO pub_place(id,name) VALUES (?,?)', idRows(placeIds));
    ins.run('INSERT INTO pub_date(id,date) VALUES (?,?)', idRows(dateIds));
    ins.run('INSERT OR IGNORE INTO book_author(bookId,authorId) VALUES (?,?)', [
      for (final b in orderedBooks)
        for (final a in b.authors) [b.id, authorIds[a]],
    ]);
    ins.run('INSERT OR IGNORE INTO book_topic(bookId,topicId) VALUES (?,?)', [
      for (final b in orderedBooks)
        for (final t in b.topics) [b.id, topicIds[t]],
    ]);
    ins.run('INSERT OR IGNORE INTO book_pub_place(bookId,pubPlaceId) VALUES (?,?)', [
      for (final b in orderedBooks)
        for (final x in b.pubPlaces) [b.id, placeIds[x]],
    ]);
    ins.run('INSERT OR IGNORE INTO book_pub_date(bookId,pubDateId) VALUES (?,?)', [
      for (final b in orderedBooks)
        for (final x in b.pubDates) [b.id, dateIds[x]],
    ]);
    // דורות (seedGenerations): כל שמות הדורות של book_info.csv, בסדר ההכנסה של המחולל
    final genIds = <String, int>{};
    for (final g in meta.generationNames) {
      genIds[g] = genIds.length + 1;
    }
    ins.run('INSERT INTO generation(id,name) VALUES (?,?)', idRows(genIds));
    ins.run('INSERT INTO book_generation(bookId,generationId) VALUES (?,?)', [
      for (final b in orderedBooks)
        if (meta.generationByTitle[b.title] != null) [b.id, genIds[meta.generationByTitle[b.title]]],
    ]);
    // שורות ותוכן עניינים (tocText של alt_toc כבר במילון)
    ins.run('INSERT INTO tocText(id,text) VALUES (?,?)', idRows(tocTextIds));
    ins.run(
      'INSERT INTO tocEntry(id,bookId,parentId,textId,level,lineId,isLastChild,hasChildren) VALUES (?,?,?,?,?,?,?,?)',
      [
        for (final b in orderedBooks)
          for (final t in b.tocs)
            [
              t.id,
              b.id,
              t.parentId,
              tocTextIds[t.text],
              t.level,
              t.lineId,
              t.isLastChild ? 1 : 0,
              t.hasChildren ? 1 : 0,
            ],
      ],
    );
    ins.run('INSERT INTO line(id,bookId,lineIndex,heRef,tocEntryId,charCount) VALUES (?,?,?,?,?,?)', [
      for (final b in orderedBooks)
        for (final l in b.lines) [l.id, b.id, l.index, l.heRef, l.tocEntryId, l.charCount],
    ]);
    ins.run('INSERT INTO line_content(id,content) VALUES (?,?)', [
      for (final b in orderedBooks)
        for (final l in b.lines) [l.id, l.content],
    ]);
    ins.run('INSERT INTO line_toc(lineId,tocEntryId) VALUES (?,?)', [
      for (final b in orderedBooks)
        for (final l in b.lines)
          if (l.lineTocEntryId != null) [l.id, l.lineTocEntryId],
    ]);
    ins.run('INSERT INTO line_note(lineId,noteIndex,charPos,hasMarker,body) VALUES (?,?,?,?,?)', [
      for (final b in orderedBooks)
        for (final l in b.lines)
          for (final n in l.notes) [l.id, n.noteIndex, n.charPos, n.hasMarker ? 1 : 0, n.body],
    ]);
    ins.run(
      'INSERT INTO link(id,sourceBookId,targetBookId,sourceLineId,targetLineId,targetLineIndex,targetBookOrderIndex,'
      'connectionTypeId,baseProvenance) VALUES (?,?,?,?,?,?,?,?,0)',
      [
        for (final l in links)
          [
            l.id,
            l.sourceBook.id,
            l.targetBook.id,
            l.sourceLine.id,
            l.targetLine.id,
            l.targetLine.index,
            l.targetBook.orderIndex,
            l.type.index + 1,
          ],
      ],
    );
    ins.run('INSERT INTO link_anchor(linkId,side,charStart,charEnd,label) VALUES (?,?,?,?,?)', [
      for (final e in anchors.entries) [e.key.$1, e.key.$2, e.key.$3, e.value.$1, e.value.$2],
    ]);
    ins.run('INSERT INTO link_range(linkId,side,endLineId,endLineIndex) VALUES (?,?,?,?)', [
      for (final e in ranges.entries) [e.key.$1, e.key.$2, e.value.$1.id, e.value.$2],
    ]);
    ins.run('INSERT INTO link_coverage(lineId,linkId,side) VALUES (?,?,?)', [
      for (final c in coverage) [c.$1, c.$2, c.$3],
    ]);
    ins.run(
      'INSERT INTO external_link(sourceBookId,sourceLineIndex,targetSource,targetTitle,targetRef,targetLineIndex,'
      'connectionType) VALUES (?,?,?,?,?,?,?)',
      externals,
    );
    final positions = <int, int>{};
    ins.run('INSERT INTO default_commentator(bookId,commentatorBookId,position) VALUES (?,?,?)', [
      for (final pr in defaultCommentators) [pr.$1, pr.$2, positions[pr.$1] = (positions[pr.$1] ?? -1) + 1],
    ]);
    var altEntryId = 1;
    for (var si = 0; si < altStructures.length; si++) {
      final s = altStructures[si];
      final sid = si + 1;
      ins.run('INSERT INTO alt_toc_structure(id,bookId,key,title,heTitle) VALUES (?,?,?,?,?)', [
        [sid, s.book.id, s.key, s.title, s.heTitle],
      ]);
      final ids = <_AltNode, int>{};
      for (final n in s.nodes) {
        ids[n] = altEntryId++;
      }
      ins.run(
        'INSERT INTO alt_toc_entry(id,structureId,parentId,textId,level,lineId,isLastChild,hasChildren) '
        'VALUES (?,?,?,?,?,?,?,?)',
        [
          for (final n in s.nodes)
            [
              ids[n],
              sid,
              n.parent == null ? null : ids[n.parent],
              tocTextIds[n.heTitle],
              n.level,
              n.line.id,
              n.isLastChild ? 1 : 0,
              n.hasChildren ? 1 : 0,
            ],
        ],
      );
      ins.run('INSERT INTO line_alt_toc(lineId,structureId,altTocEntryId) VALUES (?,?,?)', [
        for (final e in s.lineMap(ids)) [e.$1, sid, e.$2],
      ]);
    }
    final bannerTexts = <int, String>{};
    for (final r in bannerOf.values) {
      bannerTexts[r.id] = r.text;
    }
    ins.run('INSERT INTO banner(id,text) VALUES (?,?)', [
      for (final id in (bannerTexts.keys.toList()..sort())) [id, bannerTexts[id]],
    ]);
    ins.run('INSERT INTO book_banner(bookId,bannerId) VALUES (?,?)', [
      for (final id in (bannerOf.keys.toList()..sort())) [id, bannerOf[id]!.id],
    ]);
    ins.run('INSERT INTO book_protection(bookId,level) VALUES (?,?)', [
      for (final id in (protectionOf.keys.toList()..sort())) [id, protectionOf[id]],
    ]);
    ins.run('INSERT OR IGNORE INTO line_ref(bookId,refKeyHash,lineIndex) VALUES (?,?,?)', lineRefRows);
    ins.run('INSERT OR IGNORE INTO line_dh(bookId,dhText,lineIndex,dhDisplay) VALUES (?,?,?,?)', lineDhRows);

    // book_has_links ודגלי החיבור (updateBookHasLinksTable + recomputeHasSourceConnection)
    db.execute('INSERT OR IGNORE INTO book_has_links(bookId,hasSourceLinks,hasTargetLinks) SELECT id,0,0 FROM book');
    db.execute('UPDATE book_has_links SET hasSourceLinks=1 WHERE bookId IN (SELECT DISTINCT sourceBookId FROM link)');
    db.execute('UPDATE book_has_links SET hasTargetLinks=1 WHERE bookId IN (SELECT DISTINCT targetBookId FROM link)');
    for (final (type, col) in [
      ('TARGUM', 'hasTargumConnection'),
      ('REFERENCE', 'hasReferenceConnection'),
      ('COMMENTARY', 'hasCommentaryConnection'),
      ('OTHER', 'hasOtherConnection'),
    ]) {
      db.execute(
        'UPDATE book SET $col=1 WHERE id IN (SELECT DISTINCT bId FROM ('
        'SELECT sourceBookId AS bId FROM link l JOIN connection_type ct ON ct.id=l.connectionTypeId '
        "WHERE ct.name='$type' UNION SELECT targetBookId AS bId FROM link l "
        "JOIN connection_type ct ON ct.id=l.connectionTypeId WHERE ct.name='$type'))",
      );
    }
    final sv = ConnectionType.sourceViewTypes.map((t) => "'${t.dbName}'").join(',');
    db.execute(
      'UPDATE book SET hasSourceConnection = (id IN (SELECT l.targetBookId FROM link l JOIN connection_type ct '
      'ON ct.id = l.connectionTypeId WHERE ct.name IN ($sv) AND l.sourceBookId != l.targetBookId))',
    );
    db.execute('COMMIT');
    cancelPoint();

    final fk = db.select('PRAGMA foreign_key_check');
    if (fk.isNotEmpty) {
      warnings.add('foreign_key_check: ${fk.length} הפרות (למשל ${fk.first.values.join(', ')})');
    }
    say('מכווץ ובודק את הקובץ');
    db.execute('PRAGMA journal_mode=DELETE');
    db.execute('VACUUM');
    final ok = db.select('PRAGMA integrity_check').first.values.first;
    db.close();
    db = null;
    if (ok != 'ok') throw BuildError('בדיקת תקינות המסד נכשלה: $ok');
    final out = File(o.outPath);
    if (out.existsSync()) out.deleteSync();
    File(tmp).renameSync(o.outPath);
  } finally {
    db?.close();
    final t = File(tmp);
    if (t.existsSync()) {
      try {
        t.deleteSync();
      } catch (_) {}
    }
  }

  // ── דוח מטא-דאטה ──
  for (final b in orderedBooks) {
    final r = b.report;
    r.metadataFound = b.meta != null;
    r.authors = b.authors;
    r.generation = meta.generationByTitle[b.title];
    if (meta.generationConflicts[b.title] != null) {
      r.warnings.add(
        'book_info.csv: כמה דורות לספר (${meta.generationConflicts[b.title]!.join(' / ')}); נבחר "${r.generation}"',
      );
    }
    r.heShortDesc = b.heShortDesc;
    r.heDesc = b.heDesc;
    r.pubDates = b.pubDates;
    r.pubPlaces = b.pubPlaces;
    r.topics = b.topics;
    r.orderIndex = b.orderIndex;
    r.banner = bannerOf[b.id] == null ? null : '#${bannerOf[b.id]!.id}: ${bannerOf[b.id]!.text}';
    r.protection = protectionOf[b.id];
    r.defaultCommentators = [
      for (final pr in defaultCommentators)
        if (pr.$1 == b.id) orderedBooks.firstWhere((x) => x.id == pr.$2).title,
    ];
  }
  return BuildResult(
    outPath: o.outPath,
    version: version,
    books: orderedBooks.length,
    lines: orderedBooks.fold(0, (s, b) => s + b.lines.length),
    categories: categories.length,
    links: links.length,
    externalLinks: externals.length,
    lineNotes: orderedBooks.fold(0, (s, b) => s + b.report.lineNotes),
    sizeBytes: File(o.outPath).lengthSync(),
    elapsedMs: clock.elapsedMilliseconds,
    bookReports: [for (final b in orderedBooks) b.report, ...skippedReports],
    linkFiles: linkReports,
    notes: notesDecisions,
    warnings: warnings,
  );
}

/// הטיפוס שמוצג לקורא בספר שלנו כשהיעד בספרייה הרשמית (אותה משמעות כמו בטבלת link).
String _externalType(ConnectionType declared, _Book source, String targetTitle) {
  if (declared == ConnectionType.source) return 'SOURCE';
  final targetIsBase = priorityBookPaths.any((pth) {
    final name = pth.split('/').last;
    return bookTitleOf(name.substring(0, name.length - 4)) == targetTitle;
  });
  final nonBaseIntoBase = ConnectionType.sourceViewTypes.contains(declared) && targetIsBase && !source.isBaseBook;
  if (nonBaseIntoBase) return titleDeclaresDependencyOn(source.title, targetTitle) ? 'SOURCE' : 'OTHER';
  return declared.dbName;
}

const externalLinkDdl = '''CREATE TABLE external_link (
  sourceBookId INTEGER NOT NULL,
  sourceLineIndex INTEGER NOT NULL,
  targetSource TEXT,
  targetTitle TEXT NOT NULL,
  targetRef TEXT,
  targetLineIndex INTEGER,
  connectionType TEXT
)''';
const externalLinkIndexDdl = 'CREATE INDEX idx_external_link_source ON external_link(sourceBookId, sourceLineIndex)';

class _Inserter {
  _Inserter(this.db);
  final Database db;
  void run(String sql, List<List<Object?>> rows) {
    if (rows.isEmpty) return;
    final st = db.prepare(sql);
    try {
      for (final r in rows) {
        st.execute(r);
      }
    } finally {
      st.close();
    }
  }
}

class _Category {
  _Category(this.id, this.parentId, this.title, this.level, this.parent);
  final int id;
  final int? parentId;
  final String title;
  final int level;
  final _Category? parent;
  String? heShortDesc;
  String? heDesc;

  /// הנתיב המקביל בעץ הרשמי, או null כשאין קטגוריה כזאת שם.
  String? officialPath;
  List<String> get path => [...?parent?.path, title];
  String get canonicalPath => path.map(categoryPathSegment).join('/');
}

Map<String, List<String>>? _officialChildren;

/// שמות הקטגוריות הישירות תחת [parentPath] ('' = שורש) בעץ הרשמי.
List<String> officialChildren(String parentPath) {
  final map = _officialChildren ??= () {
    final m = <String, List<String>>{};
    for (final path in officialCategoryPaths) {
      final i = path.lastIndexOf('/');
      (m[i < 0 ? '' : path.substring(0, i)] ??= []).add(i < 0 ? path : path.substring(i + 1));
    }
    return m;
  }();
  return map[parentPath] ?? const [];
}

/// סדר המעבר של המחולל: ספרי priority.txt קודם (לפי סדר הרשימה), ואז מעבר על העץ כשבכל
/// תיקייה התיקיות והקבצים ממוינים יחד לפי השם.
List<_Book> _traversalOrder(List<_Book> books) {
  final out = <_Book>[];
  final rest = <_Book>[...books];
  for (final pth in priorityBookPaths) {
    final hit = rest.where((b) => [...b.placement.folders, b.fileName].join('/') == pth).firstOrNull;
    if (hit != null) {
      out.add(hit);
      rest.remove(hit);
    }
  }
  int cmp(_Book a, _Book b) {
    final pa = [...a.placement.folders, a.fileName], pb = [...b.placement.folders, b.fileName];
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final c = pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return pa.length.compareTo(pb.length);
  }

  stableSort(rest, cmp);
  return out..addAll(rest);
}

void stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

// ───────────────────────── alt_toc ─────────────────────────

class _AltNode {
  _AltNode(this.heTitle, this.level, this.line, this.lineIndex, this.parent);
  final String heTitle;
  final int level;
  final _Line line;
  final int lineIndex;
  final _AltNode? parent;
  bool isLastChild = false;
  bool hasChildren = false;
}

class _AltStructure {
  _AltStructure(this.book, this.key, this.title, this.heTitle);
  final _Book book;
  final String key;
  final String? title;
  final String? heTitle;
  final nodes = <_AltNode>[];

  /// `buildAltTocStructure`; null = אין אף ערך (המבנה נמחק).
  static _AltStructure? build(_Book book, Map j, Map<String, int> tocTextIds) {
    final key = j['key'];
    if (key is! String) throw const FormatException('חסר key');
    if (ktIsBlank(key)) return null;
    final s = _AltStructure(book, key, j['title'] as String?, j['heTitle'] as String?);
    final byParent = <_AltNode?, List<_AltNode>>{};
    bool add(Map node, int level, _AltNode? parent) {
      final he = node['heTitle'];
      final line = node['line'];
      if (he is! String || line is! num) throw const FormatException('ערך בלי heTitle או line');
      final idx = line.toDouble().truncate() - 1;
      final ln = idx >= 0 && idx < book.byIndex.length ? book.byIndex[idx] : null;
      if (ln == null) return false;
      tocTextIds.putIfAbsent(he, () => tocTextIds.length + 1);
      final n = _AltNode(he, level, ln, idx, parent);
      s.nodes.add(n);
      (byParent[parent] ??= []).add(n);
      var hasChild = false;
      for (final c in (node['children'] as List? ?? const [])) {
        if (add(c as Map, level + 1, n)) hasChild = true;
      }
      n.hasChildren = hasChild;
      return true;
    }

    var any = false;
    for (final n in (j['nodes'] as List? ?? const [])) {
      if (add(n as Map, 0, null)) any = true;
    }
    if (!any) return null;
    for (final list in byParent.values) {
      list.last.isLastChild = true;
    }
    return s;
  }

  /// כל שורה → הערך האחרון שעוגן בשורה הקודמת לה או בה.
  List<(int, int)> lineMap(Map<_AltNode, int> ids) {
    final anchorByLine = <int, int>{};
    for (final n in nodes) {
      anchorByLine[n.lineIndex] = ids[n]!;
    }
    final keys = anchorByLine.keys.toList()..sort();
    final out = <(int, int)>[];
    var ai = 0;
    int? current;
    for (var i = 0; i < book.totalLines; i++) {
      while (ai < keys.length && keys[ai] <= i) {
        current = anchorByLine[keys[ai]];
        ai++;
      }
      if (current == null) continue;
      final ln = book.byIndex[i];
      if (ln == null) continue;
      out.add((ln.id, current));
    }
    return out;
  }
}

// ───────────────────────── עזרים ─────────────────────────

/// schema_meta של מסד קיים, או null.
Map<String, String>? readSchemaMeta(String path) {
  if (!File(path).existsSync()) return null;
  Database? db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readOnly);
    return {for (final r in db.select('SELECT key, value FROM schema_meta')) r['key'] as String: '${r['value']}'};
  } catch (_) {
    return null;
  } finally {
    db?.close();
  }
}

/// מזהה ספרייה חדש: `chk-<base36>`.
String newLibraryId() => 'chk-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

String formatBytes(int b) {
  if (b < 1024) return '$b בתים';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)}MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)}GB';
}
