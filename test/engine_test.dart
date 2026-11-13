// בדיקות המנוע: כללי השמות, השורות, תוכן העניינים, הקישורים, מיזוג ההערות ו-contentHash.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_book_checker/src/engine/builder.dart';
import 'package:otzaria_book_checker/src/engine/content_hash.dart';
import 'package:otzaria_book_checker/src/engine/inputs.dart';
import 'package:otzaria_book_checker/src/engine/library.dart';
import 'package:otzaria_book_checker/src/engine/notes.dart';
import 'package:otzaria_book_checker/src/engine/rules.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

late Directory tmp;

String write(String rel, String content) {
  final f = File(p.join(tmp.path, rel))..parent.createSync(recursive: true);
  f.writeAsStringSync(content);
  return f.path;
}

BuildResult build(List<String> files, {bool external = true, String? root}) => buildDatabase(
  BuildOptions(
    inputs: [for (final f in files) InputSpec(f, root)],
    libraryPath: '',
    outPath: p.join(tmp.path, 'out.db'),
    libraryId: 'chk-test',
    displayName: 'בדיקה',
    externalLinks: external,
  ),
);

Database openOut() => sqlite3.open(p.join(tmp.path, 'out.db'), mode: OpenMode.readOnly);

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('chk_test_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('שמות (CategoryKeys.kt)', () {
    test('גרשיים, גרש ורווחים', () {
      expect(bookTitleOf('שו"ת הרשב"א'), 'שו״ת הרשב״א');
      expect(bookTitleOf("מהר''ם"), 'מהר״ם');
      expect(bookTitleOf('מהר׳׳ם'), 'מהר״ם');
      expect(bookTitleOf('ר`ת'), 'ר׳ת');
      expect(bookTitleOf('“קובץ”'), '״קובץ״');
      expect(bookTitleOf('  שם   עם\tרווחים '), 'שם עם רווחים');
      expect(bookTitleOf('תנך'), 'תנ״ך');
      expect(bookTitleOf("רש'י"), "רש'י", reason: 'גרש בודד נשמר כמות שהוא');
    });
    test('תיקיות', () {
      expect(folderTitle('תלמוד ירושלים'), 'תלמוד ירושלמי');
      expect(folderTitle('שות'), 'שו״ת');
      expect(folderTitle('תנ"ך'), 'תנ״ך');
      expect(comparableLabel('רמח״ל'), comparableLabel('רמחל'));
    });
    test('titleDeclaresDependencyOn', () {
      expect(titleDeclaresDependencyOn('פירוש על מסכת ברכות', 'ברכות'), isTrue);
      expect(titleDeclaresDependencyOn('פירוש על ברכות', 'שבת'), isFalse);
    });
    test('שם מחבר', () {
      expect(normalizeAuthorName(' חיים  בן עֲטַר\u200F '), 'חיים בן עטר');
      expect(normalizeAuthorName('ברוך תאומים-פרנקל'), 'ברוך תאומים-פרנקל');
    });
  });

  group('שורות וכותרות', () {
    test('lines() של Kotlin', () {
      expect(ktLines('א\nב\n'), ['א', 'ב', '']);
      expect(ktLines('א\r\nב\rג'), ['א', 'ב', 'ג']);
      expect(stripFirstLineBom(['\uFEFF<h1>א</h1>', 'ב']), ['<h1>א</h1>', 'ב']);
    });
    test('רמת כותרת', () {
      expect(detectHeaderLevel('<h1>א</h1>'), 1);
      expect(detectHeaderLevel('<H3 class="x">א</H3>'), 3);
      expect(detectHeaderLevel('<header>'), 0);
      expect(detectHeaderLevel(' <h2>א</h2>'), 0);
    });
    test('תווים נראים', () {
      expect(countVisibleChars('<b>אב</b>&amp;ג'), 4);
      expect(countVisibleChars('a & b'), 5);
      expect(countVisibleChars('<b>אב</b>ג', 3), 0);
      expect(countVisibleChars('<b>אב</b>ג', 5), 2);
    });
    test('טקסט כותרת (Jsoup.clean + ניקוי)', () {
      expect(cleanHtmlForToc('<h2>פרק א־ב <small>(הערה)</small></h2>'), 'פרק א ב (הערה)');
      expect(cleanHtmlForToc('<h2>בְּרֵאשִׁית &amp; X</h2>'), 'בראשית &amp; X');
      expect(cleanHtmlForToc('<h3>א&nbsp;ב</h3>'), 'א&nbsp;ב');
      expect(cleanHtmlForToc('<h3>&quot;שם&quot;</h3>'), '"שם"');
      expect(cleanHtmlForToc('<h2>  </h2>'), '');
    });
  });

  group('סוגי קישור', () {
    test('fromString', () {
      expect(ConnectionType.fromString('Commentary'), ConnectionType.commentary);
      expect(ConnectionType.fromString('quotation_auto_tanakh'), ConnectionType.quotation);
      expect(ConnectionType.fromString('footnote'), ConnectionType.footnotes);
      expect(ConnectionType.fromString(''), ConnectionType.other);
      expect(ConnectionType.fromString('bla'), ConnectionType.other);
      expect(ConnectionType.fromKnown('bla'), isNull);
      expect(ConnectionType.footnotes.index + 1, 24);
    });
    test('קובץ קישורים: רשומה פגומה מפילה את כל הקובץ', () {
      expect(parseLinksJson('[{"line_index_1":1,"line_index_2":1,"path_2":"a.txt"}]').error, isNotNull);
      final ok = parseLinksJson('\uFEFF[{"heRef_2":"x","line_index_1":"2","line_index_2":1,"path_2":"a.txt","Connection Type":"commentary"}]');
      expect(ok.error, isNull);
      expect(ok.entries.single.lineIndex1, 2);
      expect(ok.entries.single.connectionType, '');
      expect(ok.entries.single.usesConnectionTypeSpelling, isTrue);
      expect(linkTargetTitle(r'C:\x\ספר.txt'), 'ספר');
      expect(linkTargetTitle('a/b/ספר א.ב.txt'), 'ספר א.ב');
    });
  });

  group('הערות', () {
    test('mergeLines: סימון במקום, ובלי סימון — בסוף השורה', () {
      final stats = MergeStats();
      final out = HearotCompanionMerge.mergeLines(
        'ספר',
        ['טקסט<sup>1</sup> ועוד<sup>1</sup>', 'שורה'],
        {
          0: ['1 הערה ראשונה', '<sup>1</sup> הערה שנייה'],
          1: ['בלי מספר'],
        },
        stats,
      );
      expect(
        out[0],
        'טקסט<sup class="footnote-marker">1</sup><i class="footnote">הערה ראשונה</i> ועוד'
        '<sup class="footnote-marker">1</sup><i class="footnote">הערה שנייה</i>',
      );
      expect(out[1], 'שורה<i class="footnote">בלי מספר</i>');
      expect(stats.inPlace, 2);
      expect(stats.appended, 1);
    });
    test('line_note: הגוף יוצא מהשורה ונשמר עם מיקומו', () {
      final r = processLineNotes('אב<sup class="footnote-marker">1</sup><i class="footnote">גוף</i> גד');
      expect(r.changed, isTrue);
      expect(r.stripped, 'אב<sup class="footnote-marker">1</sup> גד');
      expect(r.notes.single.charPos, 3);
      expect(r.notes.single.hasMarker, isTrue);
      expect(r.notes.single.body, 'גוף');
    });
  });

  test('contentHash זהה למימוש Python עצמאי (hash_ref.py)', () {
    expect(bookContentHash(const [HashLine(0, '<h1>ספר</h1>'), HashLine(1, 'שורה א'), HashLine(2, '')]), -8210558120734402375);
    expect(
      bookContentHash([
        const HashLine(0, '<h1>ספר</h1>'),
        HashLine(1, 'טקסט<sup class="footnote-marker">1</sup> המשך', [LineNoteRow(0, 4, true, 'גוף ההערה')]),
      ]),
      -2760984285487612131,
    );
    expect(bookContentHash(const []), 6680358728597189694);
  });

  group('בנייה', () {
    test('שורות, heRef, תוכן עניינים, כותרת ריקה', () {
      final book = write(
        'לב/ספרים/אוצריא/קטגוריה/תת/ספר בדיקה.txt',
        '\uFEFF<h1>ספר בדיקה</h1>\nשורה\n<h3>קפיצה</h3>\nא\n<h2> </h2>\n<h2>שני</h2>\nב\n',
      );
      final r = build([book]);
      expect(r.books, 1);
      final db = openOut();
      final lines = db.select('SELECT lineIndex, heRef, tocEntryId FROM line ORDER BY lineIndex');
      expect([for (final l in lines) l['lineIndex']], [0, 1, 2, 3, 5, 6, 7], reason: 'כותרת ריקה (שורה 5) אינה נשמרת');
      expect(lines[1]['heRef'], 'ספר בדיקה 2');
      expect(lines[0]['heRef'], isNull);
      expect(lines[0]['tocEntryId'], isNotNull);
      expect(db.select('SELECT totalLines FROM book').single['totalLines'], 8);
      final toc = db.select(
        'SELECT t.level, x.text, (SELECT x2.text FROM tocEntry p JOIN tocText x2 ON x2.id=p.textId WHERE p.id=t.parentId) AS par, '
        't.isLastChild, t.hasChildren FROM tocEntry t JOIN tocText x ON x.id=t.textId ORDER BY t.id',
      );
      expect([for (final t in toc) (t['level'], t['text'], t['par'])], [
        (1, 'ספר בדיקה', null),
        (3, 'קפיצה', 'ספר בדיקה'),
        (2, 'שני', 'ספר בדיקה'),
      ]);
      expect(toc[0]['hasChildren'], 1);
      expect(toc[2]['isLastChild'], 1);
      expect(db.select('SELECT COUNT(*) AS n FROM line_toc').single['n'], 7);
      final src = db.select('SELECT s.name, c.title FROM book b JOIN source s ON s.id=b.sourceId JOIN category c ON c.id=b.categoryId').single;
      expect(src['name'], 'לב');
      expect(src['title'], 'תת');
      expect(db.select("SELECT value FROM schema_meta WHERE key='db_schema_version'").single['value'], '7');
      expect(db.select('PRAGMA journal_mode').single.values.first, 'delete');
      db.close();
      expect(r.bookReports.single.tocIssues.any((t) => t.contains('קפיצת רמה')), isTrue);
    });

    test('קישורים: היפוך source, דילוג על כותרת וטווח, סוגים, קישור חיצוני', () {
      final base = write('a/בסיס.txt', '<h1>בסיס</h1>\nא\nב\nג\n');
      final com = write('a/פירוש על בסיס.txt', '<h1>פירוש</h1>\nפ1\nפ2\n');
      final links = write('a/פירוש על בסיס_links.json', '''[
        {"heRef_2":"x","line_index_1":2,"line_index_2":2,"path_2":"בסיס.txt","Conection Type":"source"},
        {"heRef_2":"x","line_index_1":1,"line_index_2":2,"path_2":"בסיס.txt","Conection Type":"source"},
        {"heRef_2":"x","line_index_1":3,"line_index_2":99,"path_2":"בסיס.txt","Conection Type":"source"},
        {"heRef_2":"x","line_index_1":3,"line_index_2":3,"path_2":"בסיס.txt","Conection Type":"linker"},
        {"heRef_2":"x","line_index_1":3,"line_index_2":3,"path_2":"בסיס.txt","Conection Type":"weird"},
        {"heRef_2":"x","line_index_1":2,"line_index_2":5,"path_2":"ספר רשמי.txt","Conection Type":"source"}
      ]''');
      final r = build([base, com, links]);
      final db = openOut();
      final rows = db.select(
        'SELECT sb.title AS s, tb.title AS t, sl.lineIndex AS sli, tl.lineIndex AS tli, ct.name AS type, l.targetLineIndex '
        'FROM link l JOIN book sb ON sb.id=l.sourceBookId JOIN book tb ON tb.id=l.targetBookId '
        'JOIN line sl ON sl.id=l.sourceLineId JOIN line tl ON tl.id=l.targetLineId JOIN connection_type ct ON ct.id=l.connectionTypeId ORDER BY l.id',
      );
      expect([for (final x in rows) (x['s'], x['t'], x['sli'], x['tli'], x['type'])], [
        ('בסיס', 'פירוש על בסיס', 1, 1, 'COMMENTARY'),
        ('פירוש על בסיס', 'בסיס', 2, 2, 'OTHER'),
      ]);
      final ext = db.select('SELECT * FROM external_link').single;
      expect(ext['targetTitle'], 'ספר רשמי');
      expect(ext['sourceLineIndex'], 1);
      expect(ext['targetLineIndex'], 4);
      expect(ext['connectionType'], 'SOURCE');
      expect(db.select('SELECT hasCommentaryConnection, hasSourceConnection FROM book WHERE title=?', ['בסיס']).single.values, [1, 0]);
      expect(db.select('SELECT hasSourceConnection FROM book WHERE title=?', ['פירוש על בסיס']).single.values, [1]);
      db.close();
      final rep = r.linkFiles.single;
      expect(rep.dropped['שורת כותרת'], 1);
      expect(rep.dropped['שורת יעד מחוץ לטווח'], 1);
      expect(rep.dropped['סוג linker (לא מיובא)'], 1);
      expect(rep.unknownTypes['weird'], 1);
      expect(rep.external, 1);
    });

    test('הערות על X: מיזוג כשכל שורות ההערות מקושרות', () {
      final base = write('a/ספר.txt', '<h1>ספר</h1>\nטקסט<sup>1</sup> כאן\nעוד<sup>2</sup>\n');
      final notes = write('a/הערות על ספר.txt', '1 הערה א\n2 הערה ב\n');
      final links = write('a/ספר_links.json', '''[
        {"heRef_2":"הערות","line_index_1":2,"line_index_2":1,"path_2":"הערות על ספר.txt","Conection Type":"footnotes"},
        {"heRef_2":"הערות","line_index_1":3,"line_index_2":2,"path_2":"הערות על ספר.txt","Conection Type":"footnotes"}
      ]''');
      final r = build([base, notes, links]);
      expect(r.notes.single.merged, isTrue);
      expect(r.books, 1);
      final db = openOut();
      expect(db.select('SELECT COUNT(*) AS n FROM line_note').single['n'], 2);
      expect(db.select('SELECT COUNT(*) AS n FROM link').single['n'], 0);
      final c = db.select('SELECT c.content FROM line l JOIN line_content c ON c.id=l.id WHERE l.lineIndex=1').single;
      expect(c['content'], 'טקסט<sup class="footnote-marker">1</sup> כאן');
      db.close();
    });

    test('הערות על X: נשאר ספר עצמאי כששורת הערה אינה מקושרת', () {
      final base = write('a/ספר.txt', '<h1>ספר</h1>\nטקסט<sup>1</sup>\n');
      final notes = write('a/הערות על ספר.txt', '1 הערה א\nהערה בלי קישור\n');
      final links = write('a/ספר_links.json', '''[
        {"heRef_2":"הערות","line_index_1":2,"line_index_2":1,"path_2":"הערות על ספר.txt","Conection Type":"footnotes"}
      ]''');
      final r = build([base, notes, links]);
      final d = r.notes.single;
      expect(d.merged, isFalse);
      expect(d.reason, contains('שורות הערה שאין אליהן קישור'));
      expect(r.books, 2);
      final db = openOut();
      expect(db.select("SELECT ct.name FROM link l JOIN connection_type ct ON ct.id=l.connectionTypeId").single['name'], 'FOOTNOTES');
      expect(db.select('SELECT COUNT(*) AS n FROM default_commentator').single['n'], 1);
      db.close();
    });
  });

  group('מיקום', () {
    test('לפי תיקייה שנוספה וברירת מחדל', () {
      final root = p.join(tmp.path, 'שלי');
      final a = write('שלי/ספר א.txt', 'x');
      final b = write('שלי/הלכה/ספר ב.txt', 'x');
      final loose = write('ספר ג.txt', 'x');
      final pl = placeInputs(
        [InputSpec(a, root), InputSpec(b, root), InputSpec(loose)],
        LibraryIndex.empty(),
        const PlacementDefaults(category: 'ספרים לבדיקה/משנה', source: 'בדיקה'),
      );
      expect(pl[a]!.folders, ['שלי']);
      expect(pl[b]!.folders, ['הלכה']);
      expect(pl[loose]!.folders, ['ספרים לבדיקה', 'משנה']);
      expect(pl[loose]!.source, 'בדיקה');
    });

    test('קבצים נלווים: הערות מאותה תיקייה וקישורים מ-<מקור>/links', () {
      final book = write('מקור/ספרים/אוצריא/עזר/טובת מראה.txt', 'x');
      final notes = write('מקור/ספרים/אוצריא/עזר/הערות על טובת מראה.txt', 'x');
      final links = write('מקור/links/טובת מראה_links.json', '[]');
      final notesLinks = write('מקור/links/הערות על טובת מראה_links.json', '[]');
      final other = write('מקור/ספרים/אוצריא/עזר/ספר אחר.txt', 'x');
      expect(linksDirOf(book), p.join(tmp.path, 'מקור', 'links'));
      List<String> norm(List<String> l) => [for (final x in l) p.normalize(x)];
      expect(norm(companionFiles(book)), norm([notes, links, notesLinks]));
      expect(norm(companionFiles(notes)), norm([notesLinks]));
      expect(companionFiles(other), isEmpty);
      expect(companionFiles(links), isEmpty);
      expect(companionFiles(write('ספר ד.txt', 'x')), isEmpty);
    });
  });

  // בדיקה על הנתונים האמיתיים — רק כשהמאגרים קיימים במחשב (מדולג ב-CI).
  final library = Platform.environment['OTZARIA_LIBRARY'] ?? r'C:\Users\ADMIN\PROJECTS\otzaria-library';
  final dir = p.join(library, 'BeitAharonVeYisraelToOtzaria', 'ספרים', 'אוצריא', 'תנך', 'דרשות ודרושים');
  test('נתונים אמיתיים: יד דוד מתמזג וה-contentHash כמו במסד הרשמי', () {
    final r = buildDatabase(
      BuildOptions(
        inputs: [
          InputSpec(p.join(dir, 'יד דוד - רבי דוד אופנהיים.txt')),
          InputSpec(p.join(dir, 'הערות על יד דוד - רבי דוד אופנהיים.txt')),
          InputSpec(p.join(library, 'BeitAharonVeYisraelToOtzaria', 'links', 'יד דוד - רבי דוד אופנהיים_links.json')),
        ],
        libraryPath: library,
        outPath: p.join(tmp.path, 'yad.db'),
        libraryId: 'chk-test',
        displayName: 'בדיקה',
      ),
    );
    final b = r.bookReports.first;
    expect(b.mergedNotes, 6);
    expect(b.lineNotes, 6);
    expect(b.authors, ['רבי דוד אופנהיים']);
    expect(b.generation, 'אחרונים');
    // הערך במסד הרשמי (db_version 36) לספר הזה.
    expect(b.contentHash, -3689955779985100830);
  }, skip: Directory(dir).existsSync() ? false : 'otzaria-library אינה במחשב');
}
