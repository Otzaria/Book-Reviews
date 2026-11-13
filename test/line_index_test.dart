// Ports of the SeforimLibrary (a193aa15d) tests for the line_ref / line_dh builders:
//  - generator/common/src/jvmTest/.../refs/RefKeyParityTest.kt (+ resources/ref_key_fixtures.json)
//  - generator/common/src/jvmTest/.../refs/BuildLineRefIndexCliTest.kt
//  - generator/common/src/jvmTest/.../dh/DhKeyParityTest.kt (+ resources/dh_key_fixtures.json)
//  - generator/common/src/jvmTest/.../dh/DhExtractorTest.kt
//  - generator/common/src/jvmTest/.../dh/BuildLineDhIndexCliTest.kt
// The Kotlin tests about JDBC transactions (rollback on a failing trigger,
// DELETE of stale rows) have no counterpart in pure functions and are omitted.
// Fixture JSON is embedded verbatim.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_book_checker/src/engine/line_dh.dart';
import 'package:otzaria_book_checker/src/engine/line_ref.dart';

const String refKeyFixturesJson = r'''
{
  "refKeys": [
    {
      "input": "ישעיהו לב יא",
      "key": "ישעיהו לב יא",
      "hash": -1969793498803163639
    },
    {
      "input": "ישעיהו פרק לב פסוק יא",
      "key": "ישעיהו לב יא",
      "hash": -1969793498803163639
    },
    {
      "input": "ישעיהו לב, יא",
      "key": "ישעיהו לב יא",
      "hash": -1969793498803163639
    },
    {
      "input": "לב יא",
      "key": "לב יא",
      "hash": 7918991551423719685
    },
    {
      "input": "לב יא-יג",
      "key": "לב יא",
      "hash": 7918991551423719685
    },
    {
      "input": "לב יא - יג",
      "key": "לב יא",
      "hash": 7918991551423719685
    },
    {
      "input": "ישעיהו לב:יא-יג",
      "key": "ישעיהו לב יא",
      "hash": -1969793498803163639
    },
    {
      "input": "ברכות ב.-ג.",
      "key": "ברכות ב א",
      "hash": -6940304934149626022
    },
    {
      "input": "שער רביעי - שער הביטחון א א",
      "key": "שער רביעי שער הביטחון א א",
      "hash": 9071582228621099555
    },
    {
      "input": "ברכות ב.",
      "key": "ברכות ב א",
      "hash": -6940304934149626022
    },
    {
      "input": "ברכות ב., א",
      "key": "ברכות ב א א",
      "hash": -1278086905271074095
    },
    {
      "input": "ברכות ב ע\"א",
      "key": "ברכות ב א",
      "hash": -6940304934149626022
    },
    {
      "input": "ברכות ב ע״א",
      "key": "ברכות ב א",
      "hash": -6940304934149626022
    },
    {
      "input": "ברכות ב ע'א",
      "key": "ברכות ב א",
      "hash": -6940304934149626022
    },
    {
      "input": "ברכות ב עמוד ב",
      "key": "ברכות ב ב",
      "hash": -6940303834637997811
    },
    {
      "input": "שמיטה ויובל ג ו",
      "key": "שמיטה ויובל ג ו",
      "hash": 7404146365307781856
    },
    {
      "input": "שמיטה ויובל פרק ג הלכה ו",
      "key": "שמיטה ויובל ג ו",
      "hash": 7404146365307781856
    },
    {
      "input": "אורח חיים סימן א סעיף ב",
      "key": "אורח חיים א ב",
      "hash": 1199622973397031058
    },
    {
      "input": "ערוך השולחן סימן עא סעיף א",
      "key": "ערוך השולחן עא א",
      "hash": -9192306026795171561
    },
    {
      "input": "חידושי רע״א סימן א",
      "key": "חידושי רעא א",
      "hash": 6061358992846707353
    },
    {
      "input": "בְּרֵאשִׁית א, א",
      "key": "בראשית א א",
      "hash": -6279323615554970290
    }
  ],
  "lineKeys": [
    {
      "heRef": "ישעיהו לב, יא",
      "aliases": [
        "ישעיהו"
      ],
      "key": "לב יא",
      "hash": 7918991551423719685
    },
    {
      "heRef": "בראשית א, א",
      "aliases": [
        "בראשית"
      ],
      "key": "א א",
      "hash": 2075999474238368921
    },
    {
      "heRef": "רש\"י על בראשית א, א",
      "aliases": [
        "רש\"י על בראשית"
      ],
      "key": "א א",
      "hash": 2075999474238368921
    },
    {
      "heRef": "משנה תורה, הלכות שמיטה ויובל ג, ו",
      "aliases": [
        "משנה תורה, הלכות שמיטה ויובל"
      ],
      "key": "ג ו",
      "hash": -5551582144866057484
    },
    {
      "heRef": "ברכות ב., א",
      "aliases": [
        "ברכות"
      ],
      "key": "ב א א",
      "hash": -7407518444830233145
    },
    {
      "heRef": "יד דוד על השס א-ב 10",
      "aliases": [
        "יד דוד על השס א-ב",
        "יד דוד על השס"
      ],
      "key": "10",
      "hash": 574369514284255396
    },
    {
      "heRef": "מגדל־עז או תמת ישרים 10",
      "aliases": [
        "מגדל־עז או תמת ישרים"
      ],
      "key": "10",
      "hash": 574369514284255396
    },
    {
      "heRef": "כותרת–משנה ג-ו",
      "aliases": [
        "כותרת–משנה"
      ],
      "key": "ג",
      "hash": 786902912952177324
    },
    {
      "heRef": "פת לחם, שער רביעי - שער הביטחון, א, א",
      "aliases": [
        "פת לחם"
      ],
      "key": "שער רביעי שער הביטחון א א",
      "hash": 9071582228621099555
    },
    {
      "heRef": "ערוך השולחן, חושן משפט, עא, א",
      "aliases": [
        "ערוך השולחן"
      ],
      "key": "חושן משפט עא א",
      "hash": 5244935353916252895
    },
    {
      "heRef": "ישעיהו",
      "aliases": [
        "ישעיהו"
      ],
      "key": null
    }
  ],
  "partialLineKeys": [
    {
      "heRef": "טור, חושן משפט,  שט, ג",
      "aliases": [
        "טור"
      ],
      "keys": [
        {
          "key": "~ שט ג",
          "hash": -2758658417520453275
        }
      ]
    },
    {
      "heRef": "ליקוטי הלכות, אורח חיים, הלכות השכמת הבוקר,  א, א, א",
      "aliases": [
        "ליקוטי הלכות"
      ],
      "keys": [
        {
          "key": "~ הלכות השכמת הבוקר א א א",
          "hash": 4118206909074059642
        },
        {
          "key": "~ א א א",
          "hash": -7696753481314306146
        }
      ]
    },
    {
      "heRef": "ביאור, מבוא, סימן ז, א, א",
      "aliases": [
        "ביאור"
      ],
      "keys": [
        {
          "key": "~ ז א א",
          "hash": -6672735247281179992
        }
      ]
    },
    {
      "heRef": "חידושי הרשב\"א, ברכות, ב., א",
      "aliases": [
        "חידושי הרשב\"א"
      ],
      "keys": [
        {
          "key": "~ ב א א",
          "hash": 270077160363365273
        }
      ]
    },
    {
      "heRef": "ישעיהו לב, יא",
      "aliases": [
        "ישעיהו"
      ],
      "keys": []
    },
    {
      "heRef": "בית יוסף, אורח חיים, תקיב",
      "aliases": [
        "בית יוסף"
      ],
      "keys": []
    },
    {
      "heRef": "שם משמואל, נח, א, א",
      "aliases": [
        "שם משמואל"
      ],
      "keys": []
    },
    {
      "heRef": "ספר אחר, חושן משפט, שט, ג",
      "aliases": [
        "טור"
      ],
      "keys": []
    }
  ],
  "partialRefKeys": [
    {
      "input": "שט ג",
      "key": "~ שט ג",
      "hash": -2758658417520453275
    },
    {
      "input": "סימן שט סעיף ג",
      "key": "~ שט ג",
      "hash": -2758658417520453275
    },
    {
      "input": "שט, ג",
      "key": "~ שט ג",
      "hash": -2758658417520453275
    }
  ]
}
''';

const String dhKeyFixturesJson = r'''
{
  "normalize": [
    {
      "input": "עד סוף האשמורה הראשונה",
      "key": "עד סוף האשמורה הראשונה"
    },
    {
      "input": "בְּרֵאשִׁית.",
      "key": "בראשית"
    },
    {
      "input": "מאימתי קורין את שמע בערבין.",
      "key": "מאימתי קורין את שמע בערבין"
    },
    {
      "input": "וכל הנאכלים ליום אחד:",
      "key": "וכל הנאכלים ליום אחד"
    },
    {
      "input": "תוס' ד\"ה חייב וכו' בהקפת הראש חייב אף במספרים.",
      "key": "תוס דה חייב וכו בהקפת הראש חייב אף במספרים"
    },
    {
      "input": "אִם־כֵּ֫ן",
      "key": "אם כן"
    },
    {
      "input": "בית־השלחין",
      "key": "בית השלחין"
    },
    {
      "input": "  ליתני   דשחרית ברישא ",
      "key": "ליתני דשחרית ברישא"
    },
    {
      "input": "ע\"פ",
      "key": "עפ"
    },
    {
      "input": "סיפא ודאי פליגא אמתני׳",
      "key": "סיפא ודאי פליגא אמתני"
    },
    {
      "input": ".",
      "key": null
    },
    {
      "input": "ב.",
      "key": null
    },
    {
      "input": "",
      "key": null
    },
    {
      "input": "   ",
      "key": null
    }
  ]
}
''';

typedef RefLine = ({int lineIndex, String? heRef});
typedef DhLine = ({int lineIndex, String? content});

List<DhLine> dhLines(List<String> contents, {int start = 0}) => [
      for (var i = 0; i < contents.length; i++) (lineIndex: start + i, content: contents[i]),
    ];

/// Book defaults of the Kotlin test schema: source 'test', dependenceType
/// 'commentary', isBaseBook 0, no book_base_text, the shipped overrides.
LineDhBookReport dhBook(
  String title,
  List<String> contents, {
  String? dependenceType = 'commentary',
  bool isBaseBook = false,
  bool hasBaseText = false,
  Map<String, BookOverride>? overrides,
}) =>
    analyzeLineDh(
      bookTitle: title,
      sourceName: 'test',
      dependenceType: dependenceType,
      isBaseBook: isBaseBook,
      hasBaseText: hasBaseText,
      lines: dhLines(contents),
      overrides: overrides,
    );

String? key(String line, DhFormat format) => DhExtractor.extract(line, format)?.key;

void main() {
  // ── RefKeyParityTest ──────────────────────────────────────────────────────
  group('RefKey parity fixtures', () {
    final fixtures = jsonDecode(refKeyFixturesJson) as Map<String, dynamic>;

    test('refKeys match the shared fixtures', () {
      for (final o in (fixtures['refKeys'] as List).cast<Map<String, dynamic>>()) {
        final input = o['input'] as String;
        final k = RefKey.of(input);
        expect(k, o['key'], reason: "key for '$input'");
        if (k != null) expect(RefKey.hash(k), o['hash'], reason: "hash for '$input'");
      }
    });

    test('line keys match the shared fixtures', () {
      for (final o in (fixtures['lineKeys'] as List).cast<Map<String, dynamic>>()) {
        final heRef = o['heRef'] as String;
        final aliases = (o['aliases'] as List).cast<String>();
        final k = RefKey.ofLine(heRef, aliases);
        expect(k, o['key'], reason: "line key for '$heRef'");
        if (k != null) expect(RefKey.hash(k), o['hash'], reason: "hash for '$heRef'");
      }
    });

    test('partial line keys match the shared fixtures', () {
      for (final o in (fixtures['partialLineKeys'] as List).cast<Map<String, dynamic>>()) {
        final heRef = o['heRef'] as String;
        final aliases = (o['aliases'] as List).cast<String>();
        final expected = (o['keys'] as List).cast<Map<String, dynamic>>();
        final keys = RefKey.partialLineKeys(heRef, aliases);
        expect(keys, [for (final e in expected) e['key']], reason: "partial keys for '$heRef'");
        expect(keys.map(RefKey.hash).toList(), [for (final e in expected) e['hash']],
            reason: "partial hashes for '$heRef'");
      }
    });

    test('partial ref keys match the shared fixtures', () {
      for (final o in (fixtures['partialRefKeys'] as List).cast<Map<String, dynamic>>()) {
        final input = o['input'] as String;
        final k = RefKey.partialOf(input);
        expect(k, o['key'], reason: "partial key for '$input'");
        expect(RefKey.hash(k!), o['hash'], reason: "hash for '$input'");
      }
    });

    test('a heading line gets no key', () {
      expect(RefKey.ofLine('ישעיהו', ['ישעיהו']), isNull);
    });

    test('line token matching prefers the longest alias regardless of order', () {
      final heRef = RefKey.tokens('בית חדש ג');
      final short = RefKey.tokens('בית');
      final long = RefKey.tokens('בית חדש');
      expect(RefKey.ofLineTokens(heRef, [short, long]), 'ג');
      expect(RefKey.ofLineTokens(heRef, [long, short]), 'ג');
    });

    test('JVM-only details: ASCII \\s, java \$, Java UTF-8 of lone surrogates', () {
      // NBSP is not java \s: it is dropped by NON_WORD (becomes a separator) but
      // does not let a trailing range match after it.
      expect(RefKey.of('לב יא'), 'לב יא');
      // java `$` also matches before a final line terminator.
      expect(RefKey.of('לב יא-יג\n'), 'לב יא');
      expect(RefKey.of('ברכות ב. '), 'ברכות ב א');
      // String.getBytes(UTF_8) writes '?' for an unpaired surrogate.
      expect(RefKey.hash('\uD800'), RefKey.hash('?'));
      expect(RefKey.hash('a'), -5808556873153909620);
    });
  });

  // ── BuildLineRefIndexCliTest ──────────────────────────────────────────────
  group('line_ref per book', () {
    test('reports only books with line refs that do not start with a title alias', () {
      LineRefBookReport run(String title, List<RefLine> lines) =>
          analyzeLineRefs(bookTitle: title, bookHeRef: title, lines: lines);

      final reports = [
        run('ישעיהו', [(lineIndex: 0, heRef: 'ישעיהו'), (lineIndex: 1, heRef: 'ישעיהו לב, יא')]),
        run('כותרת', [(lineIndex: 0, heRef: 'כותרת')]),
        run('לא תואם', [(lineIndex: 0, heRef: 'ברכות ב., א')]),
        run('יד דוד על השס א-ב', [(lineIndex: 10, heRef: 'יד דוד על השס א-ב 10')]),
        run('מגדל־עז או תמת ישרים', [(lineIndex: 10, heRef: 'מגדל־עז או תמת ישרים 10')]),
        run('פת לחם', [
          (lineIndex: 10, heRef: 'פת לחם, שער רביעי - שער הביטחון, א, א'),
          (lineIndex: 11, heRef: 'פת לחם, שער רביעי - שער הביטחון, א, ב'),
          (lineIndex: 12, heRef: 'פת לחם, שער רביעי - שער הביטחון, א, א!'),
          (lineIndex: 13, heRef: 'פת לחם, שער רביעי - שער הביטחון, א, א?'),
        ]),
      ];
      final titles = ['ישעיהו', 'כותרת', 'לא תואם', 'יד דוד על השס א-ב', 'מגדל־עז או תמת ישרים', 'פת לחם'];

      expect([for (var i = 0; i < 6; i++) if (reports[i].hasTitleMismatch) titles[i]], ['לא תואם']);
      expect(reports.fold<int>(0, (s, r) => s + r.indexed), 8);
      expect(reports.fold<int>(0, (s, r) => s + r.ambiguous.length), 1);
      expect(reports[5].ambiguous, [const AmbiguousLineRef('פת לחם, שער רביעי - שער הביטחון, א, א', 10, 12)]);
      // Two full keys, plus "~ א א" / "~ א ב" without the named gate.
      expect(reports[5].rows.map((r) => r.refKeyHash).toSet().length, 4);
    });

    test('lines under a named part also get a partial key without it', () {
      final tur = analyzeLineRefs(bookTitle: 'טור', bookHeRef: 'טור', lines: [
        (lineIndex: 5, heRef: 'טור, חושן משפט,  שט, ג'),
        (lineIndex: 9, heRef: 'טור, יורה דעה,  שט, ג'),
      ]);
      final isaiah = analyzeLineRefs(
        bookTitle: 'ישעיהו',
        bookHeRef: 'ישעיהו',
        lines: [(lineIndex: 1, heRef: 'ישעיהו לב, יא')],
      );
      expect(tur.indexed + isaiah.indexed, 3);
      expect(tur.partialIndexed + isaiah.partialIndexed, 2);
      expect(tur.ambiguous.length + isaiah.ambiguous.length, 0, reason: 'partial keys are ambiguous by design');
      final h = RefKey.hash('~ שט ג');
      expect([for (final r in tur.rows) if (r.refKeyHash == h) r.lineIndex], [5, 9]);
    });

    test('null/empty heRefs are skipped, lines are read in lineIndex order, rows de-duplicated', () {
      final rows = buildLineRefRows(bookTitle: 'ספר', bookHeRef: 'ספר', lines: [
        (lineIndex: 3, heRef: 'ספר 4'),
        (lineIndex: 0, heRef: null),
        (lineIndex: 1, heRef: ''),
        (lineIndex: 2, heRef: 'ספר 3'),
        (lineIndex: 2, heRef: 'ספר 3'),
      ]);
      expect(rows, [LineRefRow(RefKey.hash('3'), 2), LineRefRow(RefKey.hash('4'), 3)]);
    });

    test('Otzaria-library shape: "<title> <n>" keyed by the number, headings get nothing', () {
      final rows = buildLineRefRows(bookTitle: 'ציצים ופרחים', bookHeRef: 'ציצים ופרחים', lines: [
        (lineIndex: 0, heRef: null),
        (lineIndex: 1, heRef: 'ציצים ופרחים 2'),
        (lineIndex: 2, heRef: 'ציצים ופרחים 3'),
      ]);
      expect(rows, [LineRefRow(RefKey.hash('2'), 1), LineRefRow(RefKey.hash('3'), 2)]);
    });
  });

  // ── DhKeyParityTest ───────────────────────────────────────────────────────
  test('DhKey: normalised dibburim match the shared fixtures', () {
    final fixtures = jsonDecode(dhKeyFixturesJson) as Map<String, dynamic>;
    for (final o in (fixtures['normalize'] as List).cast<Map<String, dynamic>>()) {
      final input = o['input'] as String;
      expect(DhKey.normalize(input), o['key'], reason: "key for '$input'");
    }
  });

  // ── DhExtractorTest ───────────────────────────────────────────────────────
  group('DhExtractor', () {
    test('dash-separated dibbur is extracted and normalised', () {
      expect(key('עד סוף האשמורה הראשונה – שליש הלילה כדמפרש בגמרא', DhFormat.dash), 'עד סוף האשמורה הראשונה');
    });
    test('plain hyphen works as separator too', () {
      expect(key('אי הכי סיפא דקתני שחרית ברישא - אי אמרת בשלמא דסמיך אקרא', DhFormat.dash),
          'אי הכי סיפא דקתני שחרית ברישא');
    });
    test("a daf's first comment ends its dibbur at the sentence break", () {
      expect(
        key('מאימתי קורין את שמע בערבין. משעה שהכהנים נכנסים לאכול בתרומתן – כהנים שנטמאו וטבלו', DhFormat.dash),
        'מאימתי קורין את שמע בערבין',
      );
    });
    test('maqaf does not separate a dibbur', () {
      expect(key('בית־השלחין שדה שצריך להשקותה', DhFormat.dash), isNull);
    });
    test('a line without a spaced dash yields nothing', () {
      expect(key('שורה רגילה בלי מפריד כלל', DhFormat.dash), isNull);
    });
    test('a dash with nothing after it yields nothing', () {
      expect(key('עד סוף האשמורה - ', DhFormat.dash), isNull);
    });
    test('an implausibly long dash prefix without a sentence break yields nothing', () {
      final prefix = ('מילים ' * 30).trim();
      expect(key('$prefix - פירוש', DhFormat.dash), isNull);
    });
    test('bold dibbur is extracted, nikud stripped', () {
      expect(key('<b>בְּרֵאשִׁית.</b> אָמַר רַבִּי יִצְחָק לֹא הָיָה צָרִיךְ', DhFormat.bold), 'בראשית');
    });
    test('whole-line bold is a decorated heading, not a dibbur', () {
      expect(key('<b>הדרן עלך מאימתי</b>', DhFormat.bold), isNull);
    });
    test('structural markers are not dibburim', () {
      for (final line in [
        "<b>מתני'</b> ביצה שנולדה ביום טוב",
        '<b>גמרא</b> במאי אוקימתא',
        '<b>(גמרא)</b> במאי אוקימתא',
        '<b>גמרא!</b> במאי אוקימתא',
        '<b>שם</b> ד"ה הורו, עד עפ"י ב"ד',
        '<b>תוד"ה</b> חייב, בהקפת הראש',
        '<b>ד״ה</b> הורו, עד עפ״י ב״ד',
        '<b>בד״ה</b> הורו, עד עפ״י ב״ד',
        '<b>תוד״ה</b> חייב, בהקפת הראש',
        "<b>בד''ה</b> אתנו ב''ד",
        "<b>רשי'</b> פירש כאן",
      ]) {
        expect(key(line, DhFormat.bold), isNull, reason: line);
      }
    });
    test('a genuine dibbur that resembles a marker without its quote marks survives', () {
      expect(key('<b>תודה.</b> הבא תודה על חטאתו', DhFormat.bold), 'תודה');
    });
    test('locator-style dibburim of super-commentaries are kept', () {
      expect(
        key('<b>תוס\' ד"ה חייב וכו\' בהקפת הראש חייב אף במספרים.</b> לפ"ז נראה דגם במלקט חייב', DhFormat.bold),
        'תוס דה חייב וכו בהקפת הראש חייב אף במספרים',
      );
    });
    test('bold mid-line is not a dibbur', () {
      expect(key('עיין רע"ב דאזיל בשטת הר"ש. <b>וקשיא</b> לי ביה', DhFormat.bold), isNull);
    });
    test('heading lines never carry a dibbur', () {
      expect(key('<h2>דף ב.</h2>', DhFormat.dash), isNull);
      expect(key('<h2>דף ב.</h2>', DhFormat.bold), isNull);
      expect(key('﻿<h1>רש"י על ברכות</h1>', DhFormat.bold), isNull);
    });
    test('display keeps points and quote marks, drops the closing period', () {
      expect(DhExtractor.extract('<b>בְּרֵאשִׁית.</b> אָמַר רַבִּי יִצְחָק לֹא הָיָה צָרִיךְ', DhFormat.bold),
          const Dh('בראשית', 'בְּרֵאשִׁית'));
      expect(DhExtractor.extract('א"ר וכו\' – פירוש הדברים', DhFormat.dash), const Dh('אר וכו', 'א"ר וכו\''));
    });
    test('display collapses inner whitespace like the key does', () {
      expect(DhExtractor.extract('עד  סוף\tהאשמורה – שליש הלילה', DhFormat.dash)?.display, 'עד סוף האשמורה');
    });
    test('lead-bold dibbur runs from the bold word to the closing marker', () {
      expect(key("<b>אין</b> שלום כו'. הכא ניחא דמשמע ליה דמשפט ושלום איירי", DhFormat.boldLead), 'אין שלום');
      expect(DhExtractor.extract("<b>אין</b> שלום כו'. הכא ניחא", DhFormat.boldLead)?.display, 'אין שלום');
    });
    test('lead-bold accepts וכו and וגו with a Hebrew geresh', () {
      expect(key('<b>וכתיב</b> ואצוה אתכם וגו׳. לפי פשוטו', DhFormat.boldLead), 'וכתיב ואצוה אתכם');
      expect(key('<b>אמר</b> ר"א למרק ב\' חזיונות וכו\'. סיפא דקרא', DhFormat.boldLead), 'אמר רא למרק ב חזיונות');
    });
    test('lead-bold yields nothing without a marker, or when the marker is too far', () {
      expect(key('<b>אין</b> שלום. הכא ניחא דמשמע ליה', DhFormat.boldLead), isNull);
      expect(
        key("<b>אין</b> שלום אמר ה' לרשעים ומשפט ושלום ואמת בשעריכם תשפטו ולא תשקרו כו'. ביאור", DhFormat.boldLead),
        isNull,
      );
    });
    test('lead-bold stops at a sentence break before the marker', () {
      expect(key("<b>האיש מקדש.</b> וידא אמר דא כו' דתנן", DhFormat.boldLead), isNull);
      expect(key('<b>רש"י ד"ה בסייף.</b> כדי שיהא שמאלו של עובד כוכבים כו\' ולא', DhFormat.boldLead), isNull);
    });
    test('lead-bold needs commentary text after the marker', () {
      for (final line in [
        "<b>אין</b> שלום כו'.",
        "<b>אין</b> שלום כו'",
        "<b>אין</b> שלום כו'. &nbsp;",
        "<b>אין</b> שלום כו'. <b>דבר אחר</b>",
        "<b>אין</b> שלום כו'. <small>פירוש</small>",
      ]) {
        expect(key(line, DhFormat.boldLead), isNull, reason: line);
      }
    });
    test('lead-bold does not fire on a plain bold dibbur', () {
      expect(key('<b>מאימתי קורין.</b> משעה שהכהנים נכנסין לאכול', DhFormat.boldLead), isNull);
    });
    test('marker inside the original bold dibbur never shortens it', () {
      const line = "<b>לעולם יכנס אדם בכי טוב ויצא כו' </b> מפורש פרק קמא דתענית";
      expect(key(line, DhFormat.boldLead), isNull);
      expect(key(line, DhFormat.bold), 'לעולם יכנס אדם בכי טוב ויצא כו');
    });
    test('lead-bold never crosses an HTML segment', () {
      expect(key("<b>אין</b> שלום <small>כו'. פירוש</small>", DhFormat.boldLead), isNull);
      expect(key("<b>אין</b> שלום <br> כו'. פירוש", DhFormat.boldLead), isNull);
      expect(key("<b>אין</b> שלום <b>נוסף</b> כו'. פירוש", DhFormat.boldLead), isNull);
    });
    test('lead-bold never crosses punctuation into commentary', () {
      expect(key("<b>אין</b> שלום: ועוד ביאור כו'. המשך", DhFormat.boldLead), isNull);
      expect(key("<b>אין:</b> שלום כו'. המשך", DhFormat.boldLead), isNull);
    });
    test('generated dash provenance preserves exact raw whitespace tail and extraction', () {
      for (final raw in [
        '  דִּבּוּר  ראשון   – פירוש\nועוד <i>ביאור</i>',
        'דיבור ראשון. ${'מילה ' * 8}– פירוש',
        "דיבור כו' – פירוש ועוד כו'. המשך",
      ]) {
        final generated = DhExtractor.boldDashDibbur(raw);
        expect(DhExtractor.sourceLineForIndex(generated), raw);
        expect(DhExtractor.boldDashDibbur(generated), generated);
        final expected = DhExtractor.extract(raw, DhFormat.dash);
        expect(expected, isNotNull);
        expect(DhExtractor.extract(generated, DhFormat.bold), expected);
        expect(DhExtractor.extract(generated, DhFormat.dash), expected);
        expect(DhExtractor.extract(generated, DhFormat.boldLead), isNull);
      }
    });
    test('only the exact generated dash marker and exact accepted span are trusted', () {
      for (final line in [
        '<b><b></b><i></i>דיבור – פירוש',
        '<b><b></b><i></i>דיבור</b> בלי מפריד',
        "<b><b></b><i></i>מתני'</b> – פירוש",
        '<b><b></b><i></i>דיבור </b> – פירוש',
        '<b><b></b><i></i>דיבור</b> נוסף – פירוש',
        '<b><b></b><i></i>דיבור. נוסף</b> ${'מילה ' * 8}– פירוש',
        '<b><b></b><i></i><i>דיבור</i></b> – פירוש',
        '<b><b></b><i class="other"></i>דיבור</b> – פירוש',
        '<b><i></i><b></b>דיבור</b> – פירוש',
        '<b><b>נוסף</b><i></i>דיבור</b> – פירוש',
        "<b data-seforim-dh='dash'>דיבור</b> – פירוש",
        '<B><b></b><i></i>דיבור</B> – פירוש',
        '<span><b><b></b><i></i>דיבור</b></span> – פירוש',
      ]) {
        expect(DhExtractor.sourceLineForIndex(line), line, reason: line);
        for (final format in DhFormat.values) {
          expect(DhExtractor.extract(line, format), isNull, reason: '$format: $line');
        }
      }
      const native = '<b>דיבור</b> – פירוש';
      expect(DhExtractor.sourceLineForIndex(native), native);
      expect(key(native, DhFormat.bold), 'דיבור');
      expect(key(native, DhFormat.dash), isNull);
    });
    test('generated numbering prefix does not hide a bold dibbur', () {
      expect(DhExtractor.extract('(א) <b>שיהא הוא מעורר השחר</b>. בשל"ה כתוב סוד לחבר יום ולילה', DhFormat.bold),
          const Dh('שיהא הוא מעורר השחר', 'שיהא הוא מעורר השחר'));
      expect(key('  (תתקצט) <b>ומיד</b>. ל"ד אלא ישהא מעט', DhFormat.bold), 'ומיד');
    });
    test('numbering prefix is excluded from a dash dibbur', () {
      expect(DhExtractor.extract('(א) לעבודת בוראו – כי לכך נברא האדם', DhFormat.dash),
          const Dh('לעבודת בוראו', 'לעבודת בוראו'));
      expect(key('(טו) השחר – בשל"ה כתב סוד', DhFormat.dash), 'השחר');
      expect(key('(מז) סימן – פירוש', DhFormat.dash), isNull);
    });
    test('numbering prefix before a generated dash envelope is removed from the key only', () {
      const raw = '(ב) השחר – בשל"ה כתב סוד';
      final generated = DhExtractor.boldDashDibbur(raw);
      expect(DhExtractor.sourceLineForIndex(generated), raw);
      expect(key(generated, DhFormat.bold), 'השחר');
      expect(DhExtractor.extract(generated, DhFormat.bold), DhExtractor.extract(raw, DhFormat.dash));
    });
    test('parenthesised words and non-canonical numerals are not stripped', () {
      for (final marker in ['כדור', 'שם', 'יה', 'יו', 'טוו', 'אא', 'הי', 'תתתק', 'א׳', 'ט"ו', 'ך', '1']) {
        expect(key('($marker) דיבור – פירוש', DhFormat.dash), DhKey.normalize('($marker) דיבור'), reason: marker);
      }
      expect(key('(כדור) <b>דיבור</b> פירוש', DhFormat.bold), isNull);
    });
    test('only the exact marker shape is stripped', () {
      expect(key('(א)<b>דיבור</b> פירוש', DhFormat.bold), isNull);
      expect(key('(א)\t<b>דיבור</b> פירוש', DhFormat.bold), isNull);
      expect(key('[א] <b>דיבור</b> פירוש', DhFormat.bold), isNull);
      expect(key('(א) (ב) <b>דיבור</b> פירוש', DhFormat.bold), isNull);
    });
    test('lines without a numbering prefix are unchanged', () {
      expect(key('<b>בראשית.</b> אמר רבי יצחק', DhFormat.bold), 'בראשית');
      expect(key('עד סוף האשמורה – שליש הלילה', DhFormat.dash), 'עד סוף האשמורה');
      expect(key("<b>אין</b> שלום כו'. הכא ניחא", DhFormat.boldLead), 'אין שלום');
    });
    test('JVM-only details: ASCII-only IGNORE_CASE and \\s', () {
      expect(DhExtractor.isHeadingLine('<H2>x</H2>'), isTrue);
      // U+017F folds to "s" only under Unicode case folding.
      expect(key('<ſmall><b>דיבור</b> פירוש', DhFormat.bold), isNull);
      expect(key('<SMALL><b>דיבור</b> פירוש', DhFormat.bold), 'דיבור');
      // NBSP around a dash is not java \s.
      expect(key('דיבור – פירוש', DhFormat.dash), isNull);
    });
  });

  // ── BuildLineDhIndexCliTest ───────────────────────────────────────────────
  group('line_dh per book', () {
    test('a dash-dominant book is indexed in dash format, headings skipped', () {
      final r = dhBook('רש"י על ברכות', [
        '<h1>רש"י על ברכות</h1>',
        '<h2>דף ב.</h2>',
        for (var i = 0; i < 12; i++) 'דיבור מספר $i – פירושו של הדיבור',
      ]);
      expect(r.outcome, LineDhOutcome.dash);
      expect(r.rows.length, 12);
      expect([for (final x in r.rows) (x.dhText, x.lineIndex)], [for (var i = 0; i < 12; i++) ('דיבור מספר $i', i + 2)]);
    });

    test('a bold-dominant book is indexed in bold format, display alongside the key', () {
      final r = dhBook('רש"י על בראשית', [for (var i = 0; i < 10; i++) '<b>דִּבּוּר $i.</b> פירוש כלשהו']);
      expect(r.outcome, LineDhOutcome.bold);
      expect(r.rows.length, 10);
      final row = r.rows.firstWhere((x) => x.lineIndex == 3);
      expect(row.dhText, 'דבור 3');
      expect(row.dhDisplay, 'דִּבּוּר 3');
    });

    test('a book with only incidental dashes stays out of the index', () {
      final r = dhBook('ספר רגיל', [
        for (var i = 0; i < 18; i++) 'שורת טקסט רגילה מספר $i בלי שום מפריד',
        'אחד - שניים',
        'שלוש - ארבע',
      ]);
      expect(r.outcome, LineDhOutcome.belowThreshold);
      expect(r.rows, isEmpty);
    });

    test('a dominant format below the absolute minimum stays out of the index', () {
      final r = dhBook('ספר קצר', [for (var i = 0; i < 5; i++) 'דיבור $i – פירוש']);
      expect(r.rows, isEmpty);
    });

    test('base texts are excluded even when dash extraction would dominate', () {
      final r = dhBook('בבא קמא', [for (var i = 0; i < 12; i++) 'הצד השוה $i – המשך הסוגיה'], isBaseBook: true);
      expect(r.outcome, LineDhOutcome.unreviewed);
      expect(r.rows, isEmpty);
    });

    test('a dependent commentary remains eligible when also marked as a base book', () {
      final r = dhBook('פירוש מסומן גם כבסיס', [for (var i = 0; i < 10; i++) '<b>דיבור $i.</b> פירוש'],
          isBaseBook: true, hasBaseText: true);
      expect(r.outcome, LineDhOutcome.bold);
      expect(r.rows.length, 10);
    });

    test('a book whose bold words are paragraph openers is dropped as noise', () {
      const words = ['והנה', 'ועוד', 'אמנם', 'ובזה', 'אך', 'אבל', 'אלא', 'ונראה', 'הנה', 'ומה', 'ולפ״ז', 'ולענ״ד'];
      final r = dhBook('שו"ת', [for (final w in words) '<b>$w</b> דברי המשיב בעניין השאלה']);
      expect(r.outcome, LineDhOutcome.noisy);
      expect(r.rows, isEmpty);
    });

    test('a book that bolds the same word in most paragraphs is dropped for low diversity', () {
      final r = dhBook('רלב"ג על התורה', [
        for (var i = 0; i < 18; i++) '<b>ופירש</b> הכתוב עניין מספר $i',
        '<b>ויאמר אלהים</b> פירוש',
        '<b>ויהי ערב</b> פירוש',
      ]);
      expect(r.outcome, LineDhOutcome.noisy);
      expect(r.rows, isEmpty);
    });

    test('a genuine one-word commentary with distinct non-opener words is kept', () {
      const words = ['בקר', 'ערב', 'תהום', 'רקיע', 'דשא', 'מאור', 'שרץ', 'כנף', 'בהמה', 'רמש', 'צלם', 'שבת'];
      final r = dhBook('מצודת ציון', [for (final w in words) '<b>$w.</b> ביאור המילה']);
      expect(r.outcome, LineDhOutcome.bold);
      expect(r.rows.map((x) => x.dhText).toList(), words);
    });

    test('a regular commentary with multi-word dibburim passes the noise gate', () {
      final r = dhBook('רש"י על שמות', [for (var i = 0; i < 12; i++) '<b>ואלה שמות בני $i</b> פירוש הפסוק']);
      expect(r.outcome, LineDhOutcome.bold);
      expect(r.rows.length, 12);
    });

    test('noise ratios are computed over the winning hits', () {
      final ratios = NoiseRatios.of(const [
        Dh('והנה', 'והנה'),
        Dh('והנה', 'וְהִנֵּה'),
        Dh('ולפז', 'ולפ״ז'),
        Dh('בראשית ברא', 'בראשית ברא'),
      ]);
      expect(ratios.distinctRatio, 0.75);
      expect(ratios.oneWordRatio, 0.75);
      expect(ratios.openerRatio, 0.75);
      expect(ratios.isNoisy, isTrue);
      expect(const NoiseRatios(1.0, 1.0, 0.05).isNoisy, isFalse);
      expect(const NoiseRatios(1.0, 0.95, 0.10).isNoisy, isFalse);
      expect(const NoiseRatios(1.0, 0.5, 0.20).isNoisy, isFalse);
      expect(const NoiseRatios(0.3, 0.0, 0.0).isNoisy, isFalse);
      expect(const NoiseRatios(0.3, 0.9, 0.0).isNoisy, isTrue);
    });

    test('a commentary that repeats the same verse phrase for several notes is kept', () {
      const phrases = ["אדם שעמלו בחכמה וגו'", 'יפה בעתו', "אם קהה הברזל וגו'", "טוב מלא כף וגו'"];
      final r = dhBook('תורה תמימה', [for (var i = 0; i < 12; i++) '<b>${phrases[i % 4]}.</b> ביאור $i']);
      expect(r.outcome, LineDhOutcome.bold);
      expect(r.rows.length, 12);
    });

    test('unclassified interleaved corpus is excluded by semantic policy', () {
      final r = dhBook('חברותא', [
        for (var i = 0; i < 10; i++) '<b>אבות מאי ניהו $i</b> מה הן האבות? הלוא הן <b>יציאות</b> הוצאות.',
        for (var i = 0; i < 10; i++) 'אך מקשה הגמרא $i: והרי <b>יציאות תרי</b> שתיים בלבד <b>הויין</b> אחת.',
      ], dependenceType: null);
      expect(r.outcome, LineDhOutcome.unreviewed);
      expect(r.rows, isEmpty);
    });

    test('reviewed CSV include admits an unclassified commentary', () {
      final r = dhBook('פירוש בדוק', [for (var i = 0; i < 10; i++) '<b>דיבור $i</b> פירוש'],
          dependenceType: null,
          overrides: {
            bookOverrideKey('test', 'פירוש בדוק'): const BookOverride(BookOverrideDecision.include, 'manually audited'),
          });
      expect(r.admittedByOverride, isTrue);
      expect(r.rows.length, 10);
    });

    test('CSV exclude wins over commentary metadata', () {
      final r = dhBook('פרשנות חריגה', [for (var i = 0; i < 10; i++) '<b>דיבור $i</b> פירוש'], overrides: {
        bookOverrideKey('test', 'פרשנות חריגה'):
            const BookOverride(BookOverrideDecision.exclude, 'audited as paragraph formatting'),
      });
      expect(r.outcome, LineDhOutcome.excludedByOverride);
      expect(r.rows, isEmpty);
    });

    test('linked midrash is eligible but linked targum is not', () {
      final midrash = dhBook('לקח טוב', [for (var i = 0; i < 10; i++) '<b>דיבור $i</b> פירוש'],
          dependenceType: 'midrash', hasBaseText: true);
      final targum = dhBook('תרגום', [for (var i = 0; i < 10; i++) '<b>תרגום $i</b> פירוש'],
          dependenceType: 'targum', hasBaseText: true);
      expect(midrash.rows.length, 10);
      expect(targum.rows, isEmpty);
      // Sefaria stores 'Midrash'/'Commentary' capitalised; the match ignores case.
      expect(dhBook('x', [for (var i = 0; i < 10; i++) '<b>דיבור $i</b> פירוש'], dependenceType: 'Commentary').rows.length,
          10);
    });

    test('a lead-bold book takes the full quotation, other bold lines keep the prefix', () {
      final r = dhBook('חידושי אגדות', [
        for (var i = 0; i < 8; i++) "<b>אין</b> שלום $i כו'. הכא ניחא דמשמע ליה",
        for (var i = 0; i < 2; i++) '<b>והיינו</b> דאמרי אינשי $i בין קני לאורבני',
      ]);
      expect(r.leadBook, isTrue);
      expect(r.outcome, LineDhOutcome.bold);
      final keys = r.rows.map((x) => x.dhText).toList();
      expect(keys.take(8).toList(), [for (var i = 0; i < 8; i++) 'אין שלום $i']);
      expect(keys.skip(8).toList(), ['והיינו', 'והיינו']);
    });

    test('a bold book with an occasional nearby marker stays a plain bold book', () {
      final r = dhBook('רש"י', [
        for (var i = 0; i < 19; i++) '<b>מאימתי קורין $i.</b> משעה שהכהנים נכנסין לאכול',
        "<b>ואמר</b> רבי כו'. פירוש",
      ]);
      expect(r.leadBook, isFalse);
      expect(r.outcome, LineDhOutcome.bold);
      expect(r.rows.length, 20);
      expect(r.rows.last.dhText, 'ואמר');
    });

    test('seven of ten lead hits do not promote the book', () {
      final r = dhBook('גבול lead', [
        for (var i = 0; i < 7; i++) "<b>מילה $i</b> שלום כו'. ביאור",
        for (var i = 0; i < 3; i++) '<b>דיבור $i</b> פירוש',
      ]);
      expect(r.leadBook, isFalse);
      expect(r.rows.take(7).map((x) => x.dhText).toList(), [for (var i = 0; i < 7; i++) 'מילה $i']);
    });

    test('a noisy majority format does not hide a clean qualifying format', () {
      final r = dhBook('שני פורמטים', [
        for (var i = 0; i < 10; i++) '<b>דיבור תקין $i</b> פירוש',
        for (var i = 0; i < 12; i++) 'והנה – המשך מספר $i',
      ]);
      expect(r.outcome, LineDhOutcome.bold);
      expect(r.rows.length, 10);
    });

    test('override CSV parser handles quoted commas and doubled quotes', () {
      final parsed = parseBookOverrides(
        'source,title,decision,reason\n'
        'MoreBooks,"פירוש, חלק א",include,"checked ""by hand"""\n',
      );
      expect(parsed[bookOverrideKey('MoreBooks', 'פירוש, חלק א')],
          const BookOverride(BookOverrideDecision.include, 'checked "by hand"'));
    });

    test('the embedded generator overrides parse (285 reviewed books)', () {
      expect(defaultLineDhBookOverrides.length, 285);
    });

    test('a plain dash book (rebuild case) yields the dash keys', () {
      final r = dhBook('ספר', [for (var i = 0; i < 10; i++) 'דיבור $i – פירוש']);
      expect([for (final x in r.rows) (x.dhText, x.lineIndex)], [for (var i = 0; i < 10; i++) ('דיבור $i', i)]);
    });

    test('generated formatting preserves raw format winners noise gates and native bold policy', () {
      final dash = [for (var i = 0; i < 12; i++) 'דיבור מקורי $i – פירוש הדיבור'];
      final bold = [for (var i = 0; i < 14; i++) '<b>דיבור מודגש $i</b> פירוש הדיבור'];
      final lead = [for (var i = 0; i < 14; i++) "<b>דיבור</b> מצוטט $i כו'. פירוש הדיבור"];
      final cases = [
        [...dash, '<b>גליון</b> הערה שאינה דיבור מצוטט'],
        [...dash, ...bold],
        [...dash, ...lead],
        [for (var i = 0; i < 12; i++) 'אחד – פירוש', '<b>ל"א</b> נוסח אחר'],
        [for (var i = 0; i < 9; i++) 'דיבור קטן $i – פירוש'],
      ];
      for (final rawLines in cases) {
        final original = dhBook('ספר מעורב', rawLines);
        final generated = dhBook('ספר מעורב', rawLines.map(DhExtractor.boldDashDibbur).toList());
        expect(generated.outcome, original.outcome);
        expect(generated.leadBook, original.leadBook);
        expect(generated.rows, original.rows);
      }
    });

    test('input order and null content follow the Kotlin SELECT', () {
      final lines = <DhLine>[
        for (var i = 9; i >= 0; i--) (lineIndex: i, content: '<b>דיבור $i</b> פירוש'),
        (lineIndex: 10, content: null),
      ];
      final rows = buildLineDhRows(
        bookTitle: 't',
        sourceName: 'test',
        dependenceType: 'commentary',
        isBaseBook: false,
        hasBaseText: false,
        lines: lines,
      );
      expect(rows.map((r) => r.lineIndex).toList(), [for (var i = 0; i < 10; i++) i]);
    });
  });
}
