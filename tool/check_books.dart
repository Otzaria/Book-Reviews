// בודק המרות לאוצריא, משורת הפקודה (אותו מנוע כמו בממשק):
//
//   dart run tool/check_books.dart --out x.db [--library <otzaria-library>] [--otzaria <repo>]
//       [--library-links] [--no-external] [--category <נתיב>] [--source <שם>] [--name <שם תצוגה>]
//       <קובץ או תיקייה> ...
//
// קוד יציאה: 0 = נבנה (והבודק עבר, אם הורץ), 1 = הבודק מצא שגיאה, 2 = הבנייה נכשלה, 64 = שימוש שגוי.

import 'dart:io';

import 'package:otzaria_book_checker/src/engine/builder.dart';
import 'package:otzaria_book_checker/src/engine/inputs.dart';
import 'package:otzaria_book_checker/src/engine/validator.dart';

Future<void> main(List<String> args) async {
  String? out, library = r'C:\Users\ADMIN\PROJECTS\otzaria-library', otzaria;
  var category = 'ספרים לבדיקה', source = 'בדיקה', name = 'בדיקת המרות';
  var libLinks = false, external = true;
  final inputs = <InputSpec>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String next() => i + 1 < args.length ? args[++i] : (throw ArgumentError('חסר ערך ל-$a'));
    switch (a) {
      case '--out':
        out = next();
      case '--library':
        library = next();
      case '--otzaria':
        otzaria = next();
      case '--category':
        category = next();
      case '--source':
        source = next();
      case '--name':
        name = next();
      case '--library-links':
        libLinks = true;
      case '--no-external':
        external = false;
      default:
        if (Directory(a).existsSync()) {
          inputs.addAll([for (final f in scanFolder(a)) InputSpec(f, a)]);
        } else {
          inputs.add(InputSpec(a));
        }
    }
  }
  if (out == null || inputs.isEmpty) {
    stderr.writeln('שימוש: dart run tool/check_books.dart --out x.db [אפשרויות] <קבצים/תיקיות>');
    exitCode = 64;
    return;
  }
  final BuildResult r;
  try {
    r = buildDatabase(
      BuildOptions(
        inputs: inputs,
        libraryPath: library ?? '',
        outPath: File(out).absolute.path,
        libraryId: 'chk-cli',
        displayName: name,
        defaultCategory: category,
        defaultSource: source,
        useLibraryLinks: libLinks,
        externalLinks: external,
      ),
    );
  } on BuildError catch (e) {
    stderr.writeln('הבנייה נכשלה: ${e.message}');
    exitCode = 2;
    return;
  }
  stdout.writeln(r.toText());
  if (otzaria != null) {
    final v = await runValidator(r.outPath, otzaria);
    stdout
      ..writeln()
      ..writeln('== בודק המסדים של אוצריא (קוד יציאה ${v.exitCode})')
      ..writeln(v.output);
    if (!v.ok) exitCode = 1;
  }
}
