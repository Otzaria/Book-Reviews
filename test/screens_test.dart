// בדיקת עשן למסכים: כל מסך נבנה בלי שגיאות (גלישה, חריגות) בגודל חלון רגיל.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_book_checker/src/controllers/app_controller.dart';
import 'package:otzaria_book_checker/src/engine/builder.dart';
import 'package:otzaria_book_checker/src/engine/inputs.dart';
import 'package:otzaria_book_checker/src/engine/validator.dart';
import 'package:otzaria_book_checker/src/screens/app_shell.dart';
import 'package:otzaria_book_checker/src/theme/app_theme.dart';

AppController _controller() {
  final c = AppController()..loaded = true;
  c.settings
    ..inputs = [
      const InputSpec(r'C:\ספרים\MoreBooks\ספרים\אוצריא\קבלה\ספר בדיקה.txt'),
      const InputSpec(r'C:\ספרים\MoreBooks\ספרים\אוצריא\קבלה\הערות על ספר בדיקה.txt'),
      const InputSpec(r'C:\ספרים\ספר בדיקה_links.json'),
    ]
    ..outDir = r'C:\ספרים';
  c.items = [
    for (final s in c.settings.inputs)
      InputItem(s, roleOf(s.path), roleOf(s.path) == InputRole.links ? null : Placement('MoreBooks', ['קבלה'], PlacementKind.libraryPath)),
  ];
  final book = BookReport(
    path: r'C:\ספרים\ספר בדיקה.txt',
    rawStem: 'ספר בדיקה',
    title: 'ספר בדיקה',
    role: 'ספר',
    source: 'MoreBooks',
    categoryPath: ['קבלה'],
    placement: 'לפי הנתיב',
  )
    ..bookId = 1
    ..totalLines = 120
    ..storedLines = 120
    ..tocEntries = 12
    ..authors = ['מחבר בדיקה']
    ..tocIssues.add('שורה 4: קפיצת רמה h1 → h3');
  final notes = NotesDecision('הערות על ספר בדיקה', 'ספר בדיקה', false, '3 שורות הערה שאין אליהן קישור', 'ספר בדיקה_links.json');
  c.lastResult = BuildResult(
    outPath: r'C:\ספרים\בדיקת המרות.db',
    version: 2,
    books: 2,
    lines: 200,
    categories: 1,
    links: 40,
    externalLinks: 3,
    lineNotes: 0,
    sizeBytes: 123456,
    elapsedMs: 900,
    bookReports: [book],
    linkFiles: [
      LinkFileReport(fileName: 'ספר בדיקה_links.json', path: 'x', origin: 'נוסף', sourceTitle: 'ספר בדיקה')
        ..total = 45
        ..stored = 40
        ..bump('שורת כותרת'),
    ],
    notes: [notes],
    warnings: const [],
  );
  c.lastValidation = ValidatorResult(0, 'RESULT: OK');
  return c;
}

Future<void> _loadFont(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) return;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

void main() {
  // SCREENSHOTS=1 flutter test --update-goldens test/screens_test.dart — תמונות לבדיקה ויזואלית (לא נשמרות במאגר).
  final shots = Platform.environment['SCREENSHOTS'] == '1';
  setUpAll(() async {
    if (!shots) return;
    await _loadFont('Segoe UI', r'C:\Windows\Fonts\segoeui.ttf');
    await _loadFont('Consolas', r'C:\Windows\Fonts\consola.ttf');
    final pub = '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev/fluentui_system_icons-1.1.273/lib/fonts';
    await _loadFont('packages/fluentui_system_icons/FluentSystemIcons-Regular', '$pub/FluentSystemIcons-Regular.ttf');
    await _loadFont('packages/fluentui_system_icons/FluentSystemIcons-Filled', '$pub/FluentSystemIcons-Filled.ttf');
  });
  for (final dark in [false, true]) {
    for (final i in [0, 1, 2]) {
      testWidgets('מסך $i ${dark ? 'כהה' : 'בהיר'}', (tester) async {
        tester.view.physicalSize = const Size(1280, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = _controller();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: (dark ? AppTheme.dark() : AppTheme.light()).copyWith(
              textTheme: (dark ? AppTheme.dark() : AppTheme.light()).textTheme.apply(fontFamily: shots ? 'Segoe UI' : null),
            ),
            home: Directionality(textDirection: TextDirection.rtl, child: AppShell(controller: c)),
          ),
        );
        await tester.pumpAndSettle();
        if (i == 2) {
          await tester.tap(find.byKey(const ValueKey('nav-settings')));
          await tester.pumpAndSettle();
        } else if (i == 1) {
          tester.widget<NavigationRail>(find.byType(NavigationRail)).onDestinationSelected!(1);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        if (shots) {
          await expectLater(find.byType(AppShell), matchesGoldenFile('goldens/screen_${i}_${dark ? 'dark' : 'light'}.png'));
        }
      });
    }
  }
}
