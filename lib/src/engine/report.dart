// הדוח שהבנייה מחזירה: לכל ספר, לכל קובץ קישורים ולכל קובץ הערות.

class NotesDecision {
  NotesDecision(this.notesTitle, this.baseTitle, this.merged, this.reason, this.linksFile);
  final String notesTitle;
  final String baseTitle;

  /// true = ההערות ימוזגו לתוך ספר הבסיס (line_note); false = ספר עצמאי.
  final bool merged;
  final String reason;
  final String? linksFile;
}

class BookReport {
  BookReport({
    required this.path,
    required this.rawStem,
    required this.title,
    required this.role,
    required this.source,
    required this.categoryPath,
    required this.placement,
  });

  final String path;
  final String rawStem;
  final String title;
  final String role;
  final String source;
  List<String> categoryPath;
  final String placement;
  int? bookId;
  bool isBaseBook = false;
  final titleChanges = <String>[];
  int totalLines = 0;
  int storedLines = 0;
  int headings = 0;
  int tocEntries = 0;
  final tocLevels = <int, int>{};
  final tocIssues = <String>[];
  final warnings = <String>[];
  final errors = <String>[];
  final linkFiles = <String>[];
  NotesDecision? notesDecision;

  /// לספר הערות שמוזג: שם ספר הבסיס.
  String? mergedInto;
  int mergedNotes = 0;
  int mergedNotesAppended = 0;
  int lineNotes = 0;
  int lineRefRows = 0;
  int lineDhRows = 0;
  int altTocStructures = 0;
  int contentHash = 0;

  bool metadataFound = false;
  List<String> authors = const [];
  String? generation;
  String? heShortDesc;
  String? heDesc;
  List<String> pubDates = const [];
  List<String> pubPlaces = const [];
  List<String> topics = const [];
  int orderIndex = 999;
  String? banner;
  int? protection;
  List<String> defaultCommentators = const [];

  bool get imported => bookId != null;

  /// מה חסר מהמטא-דאטה (לתצוגה).
  List<String> get missingMetadata => [
    if (!metadataFound) 'רשומה ב-metadata.json',
    if (authors.isEmpty) 'מחבר',
    if (generation == null) 'דור (book_info.csv)',
    if (heShortDesc == null) 'תיאור קצר',
    if (heDesc == null) 'תיאור מלא (heDescNew)',
    if (pubDates.isEmpty) 'שנת הדפסה',
    if (pubPlaces.isEmpty) 'מקום הדפסה',
  ];
}

class LinkFileReport {
  LinkFileReport({required this.fileName, required this.path, required this.origin, required this.sourceTitle});
  final String fileName;
  final String path;

  /// "נוסף" (על ידי המשתמש) או "מהספרייה".
  final String origin;
  final String sourceTitle;
  String? parseError;
  String? sourceProblem;
  int total = 0;
  int stored = 0;
  int duplicates = 0;
  int flipped = 0;
  int external = 0;
  int mergedIntoNotes = 0;
  int anchors = 0;
  int anchorsDropped = 0;
  int ranges = 0;
  int rangesDropped = 0;
  int connectionTypeMisspelled = 0;
  final dropped = <String, int>{};
  final byType = <String, int>{};
  final unknownTypes = <String, int>{};
  final missingTargets = <String, int>{};

  void bump(String reason) => dropped[reason] = (dropped[reason] ?? 0) + 1;
  int get droppedTotal => dropped.values.fold(0, (a, b) => a + b);
}

class BuildResult {
  BuildResult({
    required this.outPath,
    required this.version,
    required this.books,
    required this.lines,
    required this.categories,
    required this.links,
    required this.externalLinks,
    required this.lineNotes,
    required this.sizeBytes,
    required this.elapsedMs,
    required this.bookReports,
    required this.linkFiles,
    required this.notes,
    required this.warnings,
  });

  final String outPath;
  final int version;
  final int books;
  final int lines;
  final int categories;
  final int links;
  final int externalLinks;
  final int lineNotes;
  final int sizeBytes;
  final int elapsedMs;
  final List<BookReport> bookReports;
  final List<LinkFileReport> linkFiles;
  final List<NotesDecision> notes;
  final List<String> warnings;

  /// דוח טקסט מלא (ל-CLI ולהעתקה).
  String toText() {
    final b = StringBuffer()
      ..writeln('מסד: $outPath (גרסה $version)')
      ..writeln('ספרים: $books, שורות: $lines, קטגוריות: $categories, קישורים: $links, '
          'קישורים חיצוניים: $externalLinks, הערות שוליים (line_note): $lineNotes');
    for (final w in warnings) {
      b.writeln('! $w');
    }
    for (final r in bookReports) {
      b
        ..writeln()
        ..writeln('== ${r.title} [${r.role}]${r.imported ? '' : ' — לא נכנס למסד'}')
        ..writeln('   קובץ: ${r.path}')
        ..writeln('   מקור: ${r.source} | קטגוריה: ${r.categoryPath.join(' / ')} | מיקום: ${r.placement}');
      if (r.mergedInto != null) b.writeln('   מוזג כהערות שוליים לתוך "${r.mergedInto}"');
      if (r.notesDecision != null) {
        b.writeln('   החלטת הערות: ${r.notesDecision!.merged ? 'ימוזגו' : 'ספר עצמאי'} — ${r.notesDecision!.reason}');
      }
      for (final t in r.titleChanges) {
        b.writeln('   שם: $t');
      }
      if (r.imported) {
        b
          ..writeln('   שורות: ${r.totalLines} (נשמרו ${r.storedLines}), כותרות: ${r.tocEntries} '
              '${r.tocLevels.entries.map((e) => 'h${e.key}:${e.value}').join(' ')}'
              '${r.isBaseBook ? ', ספר בסיס' : ''}, orderIndex ${r.orderIndex}')
          ..writeln('   מחבר: ${r.authors.isEmpty ? '—' : r.authors.join('; ')} | דור: ${r.generation ?? '—'} | '
              'שנה: ${r.pubDates.isEmpty ? '—' : r.pubDates.join(', ')} | מקום: ${r.pubPlaces.isEmpty ? '—' : r.pubPlaces.join(', ')}')
          ..writeln('   תיאור קצר: ${r.heShortDesc ?? '—'}')
          ..writeln('   תיאור מלא: ${r.heDesc == null ? '—' : '${r.heDesc!.length} תווים'}')
          ..writeln('   באנר: ${r.banner?.replaceAll('\n', ' ') ?? '—'} | הגנה: ${r.protection ?? '—'} | נושאים: ${r.topics.join(', ')}')
          ..writeln('   line_note: ${r.lineNotes}, line_ref: ${r.lineRefRows}, line_dh: ${r.lineDhRows}, '
              'alt_toc: ${r.altTocStructures}, contentHash: ${r.contentHash}');
        if (r.mergedNotes > 0) b.writeln('   הערות שמוזגו: ${r.mergedNotes} (${r.mergedNotesAppended} בסוף השורה, בלי סימון תואם)');
        if (r.defaultCommentators.isNotEmpty) b.writeln('   מפרש ברירת מחדל: ${r.defaultCommentators.join(', ')}');
      }
      for (final t in r.tocIssues) {
        b.writeln('   תוכן עניינים: $t');
      }
      for (final e in r.errors) {
        b.writeln('   שגיאה: $e');
      }
      for (final w in r.warnings) {
        b.writeln('   אזהרה: $w');
      }
    }
    for (final l in linkFiles) {
      b
        ..writeln()
        ..writeln('== קישורים: ${l.fileName} (${l.origin})');
      if (l.parseError != null) {
        b.writeln('   הקובץ לא נקרא — המחולל טוען 0 קישורים ממנו: ${l.parseError}');
        continue;
      }
      if (l.sourceProblem != null) b.writeln('   ${l.sourceProblem}');
      b.writeln('   סה"כ ${l.total}, נשמרו ${l.stored}, כפולים ${l.duplicates}, הופכו ${l.flipped}, '
          'חיצוניים ${l.external}, למוזגו-כהערות ${l.mergedIntoNotes}, עוגנים ${l.anchors}, טווחים ${l.ranges}');
      if (l.byType.isNotEmpty) b.writeln('   לפי סוג: ${l.byType.entries.map((e) => '${e.key}=${e.value}').join(', ')}');
      for (final e in l.dropped.entries) {
        b.writeln('   נשמטו (${e.key}): ${e.value}');
      }
      if (l.connectionTypeMisspelled > 0) {
        b.writeln('   ${l.connectionTypeMisspelled} רשומות עם "Connection Type" — המחולל קורא רק "Conection Type" ולכן הן OTHER');
      }
      for (final e in l.unknownTypes.entries) {
        b.writeln('   סוג לא מוכר "${e.key}" (${e.value}) ← OTHER');
      }
      for (final e in l.missingTargets.entries.take(20)) {
        b.writeln('   יעד שאינו במסד: ${e.key} (${e.value})');
      }
    }
    return b.toString();
  }
}
