import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:path/path.dart' as p;

import '../engine/inputs.dart';

String _home() => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';

/// הגדרות התוכנה, נשמרות ב-%APPDATA%\OtzariaBookChecker\settings.json.
class Settings {
  String libraryPath = p.join(_home(), 'PROJECTS', 'otzaria-library');
  String otzariaRepo = p.join(_home(), 'PROJECTS', 'otzaria');
  String outDir = p.join(_home(), 'Documents');
  String displayName = 'בדיקת המרות';
  String author = '';
  String defaultCategory = 'ספרים לבדיקה';
  String defaultSource = 'בדיקה';
  bool useLibraryLinks = false;
  bool externalLinks = true;
  bool runValidator = true;
  ThemeMode themeMode = ThemeMode.system;
  List<InputSpec> inputs = [];

  /// שם הקובץ נגזר משם המסד (תווים שאסורים בשם קובץ מוחלפים).
  String get fileName {
    final name = displayName.trim().replaceAll(RegExp(r'[<>:"/\|?*]'), '-').replaceAll(RegExp(r'[. ]+$'), '');
    return name.isEmpty ? '' : '$name.db';
  }

  String get outPath => outDir.isEmpty || fileName.isEmpty ? '' : p.join(outDir, fileName);

  Map<String, Object?> toJson() => {
    'libraryPath': libraryPath,
    'otzariaRepo': otzariaRepo,
    'outDir': outDir,
    'displayName': displayName,
    'author': author,
    'defaultCategory': defaultCategory,
    'defaultSource': defaultSource,
    'useLibraryLinks': useLibraryLinks,
    'externalLinks': externalLinks,
    'runValidator': runValidator,
    'themeMode': themeMode.name,
    'inputs': [for (final i in inputs) i.toJson()],
  };

  static Settings fromJson(Map<String, Object?> j) {
    final s = Settings();
    String str(String k, String d) => j[k] is String && (j[k] as String).isNotEmpty ? j[k] as String : d;
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    s.libraryPath = str('libraryPath', s.libraryPath);
    s.otzariaRepo = str('otzariaRepo', s.otzariaRepo);
    s.outDir = str('outDir', s.outDir);
    s.displayName = str('displayName', s.displayName);
    s.author = j['author'] is String ? j['author'] as String : '';
    s.defaultCategory = str('defaultCategory', s.defaultCategory);
    s.defaultSource = str('defaultSource', s.defaultSource);
    s.useLibraryLinks = b('useLibraryLinks', false);
    s.externalLinks = b('externalLinks', true);
    s.runValidator = b('runValidator', true);
    s.themeMode = ThemeMode.values.firstWhere((m) => m.name == j['themeMode'], orElse: () => ThemeMode.system);
    final inputs = j['inputs'];
    if (inputs is List) {
      s.inputs = [
        for (final i in inputs)
          if (i is Map && i['path'] is String) InputSpec.fromJson(i.cast<String, Object?>()),
      ];
    }
    return s;
  }
}

class SettingsStore {
  SettingsStore._();

  static String configDir() {
    final env = Platform.environment;
    if (Platform.isWindows && env['APPDATA'] != null) return p.join(env['APPDATA']!, 'OtzariaBookChecker');
    return p.join(_home(), '.config', 'OtzariaBookChecker');
  }

  static File get _file => File(p.join(configDir(), 'settings.json'));

  static Future<Settings> load() async {
    try {
      final f = _file;
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, Object?>) return Settings.fromJson(j);
      }
    } catch (_) {}
    return Settings();
  }

  static Future<void> save(Settings s) async {
    final f = _file;
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(s.toJson()));
    await tmp.rename(f.path);
  }
}
