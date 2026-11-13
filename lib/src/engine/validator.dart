// מריץ את בודק המסדים האישיים של אוצריא: `dart run tool/validate_personal_db.dart <db>`
// מתוך מאגר הקוד של אוצריא.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class ValidatorResult {
  ValidatorResult(this.exitCode, this.output, {this.command = ''});
  final int exitCode;
  final String output;
  final String command;

  /// 0 = תקין, 1 = בעיה חוסמת, אחר = הבודק לא רץ.
  bool get ok => exitCode == 0;
  bool get ran => exitCode == 0 || exitCode == 1;
}

/// הפקודה של dart: מה-SDK של Flutter (FLUTTER_ROOT / PATH / מיקום מוכר), או `dart` מה-PATH.
String? findDart() {
  final env = Platform.environment;
  final exe = Platform.isWindows ? 'dart.bat' : 'dart';
  final candidates = <String>[
    if (env['FLUTTER_ROOT'] != null) p.join(env['FLUTTER_ROOT']!, 'bin', exe),
    if (Platform.isWindows && env['USERPROFILE'] != null) p.join(env['USERPROFILE']!, 'flutter', 'bin', exe),
    r'C:\flutter\bin\dart.bat',
    r'C:\src\flutter\bin\dart.bat',
  ];
  for (final dir in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    candidates.add(p.join(dir, exe));
    if (Platform.isWindows) candidates.add(p.join(dir, 'dart.exe'));
  }
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

Future<ValidatorResult> runValidator(String dbPath, String otzariaRepo, {Duration timeout = const Duration(minutes: 5)}) async {
  final tool = File(p.join(otzariaRepo, 'tool', 'validate_personal_db.dart'));
  if (!tool.existsSync()) {
    return ValidatorResult(-2, 'לא נמצא ${tool.path}.\nבחרו בהגדרות את תיקיית מאגר הקוד של אוצריא (otzaria).');
  }
  if (!File(p.join(otzariaRepo, '.dart_tool', 'package_config.json')).existsSync()) {
    return ValidatorResult(-3, 'במאגר אוצריא לא הורצה עדיין `flutter pub get` (חסר .dart_tool/package_config.json).');
  }
  final dart = findDart();
  if (dart == null) {
    return ValidatorResult(-4, 'לא נמצא Dart/Flutter SDK (dart.bat). התקינו Flutter או הוסיפו את flutter\\bin ל-PATH.');
  }
  final args = ['run', 'tool/validate_personal_db.dart', dbPath];
  try {
    final proc = await Process.start(dart, args, workingDirectory: otzariaRepo, runInShell: Platform.isWindows);
    final out = StringBuffer();
    final done = Future.wait([
      proc.stdout.transform(utf8.decoder).forEach(out.write),
      proc.stderr.transform(utf8.decoder).forEach(out.write),
    ]);
    final code = await proc.exitCode.timeout(timeout, onTimeout: () {
      proc.kill();
      return -5;
    });
    await done.timeout(const Duration(seconds: 5), onTimeout: () => const []);
    return ValidatorResult(code, out.toString().trim(), command: '$dart ${args.join(' ')}');
  } catch (e) {
    return ValidatorResult(-6, 'הרצת הבודק נכשלה: $e');
  }
}
