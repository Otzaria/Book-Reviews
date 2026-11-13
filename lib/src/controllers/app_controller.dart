import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../engine/builder.dart';
import '../engine/inputs.dart';
import '../engine/library.dart';
import '../engine/validator.dart';
import '../services/jobs.dart';
import '../services/settings_store.dart';

/// פעולה ארוכה שרצה עכשיו.
class Activity {
  Activity(this.title);
  String title;
  String detail = '';
  double? progress;
  bool cancelled = false;
}

/// פריט ברשימת הקלט, עם התפקיד והמיקום שזוהו.
class InputItem {
  InputItem(this.spec, this.role, this.placement);
  final InputSpec spec;
  final InputRole role;
  final Placement? placement;
  String get path => spec.path;
  String get name => p.basename(spec.path);
  bool get exists => File(spec.path).existsSync();
}

class AppController extends ChangeNotifier {
  Settings settings = Settings();
  bool loaded = false;

  Activity? activity;
  BuildResult? lastResult;
  ValidatorResult? lastValidation;
  bool validating = false;

  LibraryIndex _index = LibraryIndex.empty();
  bool indexing = false;
  String? libraryError;
  List<InputItem> items = const [];

  String? lastMessage;
  bool lastMessageIsError = false;

  bool get busy => activity != null || validating;
  ThemeMode get themeMode => settings.themeMode;
  bool get libraryReady => !_index.isEmpty;
  int get libraryBookCount => _index.byTitle.length;

  /// מה חסר כדי לבנות (null = אפשר לבנות).
  String? get buildBlocker {
    if (!items.any((i) => i.role == InputRole.book || i.role == InputRole.notes)) return 'הוסיפו לפחות קובץ ספר אחד (TXT)';
    if (settings.outPath.isEmpty) return 'בחרו היכן לשמור את המסד';
    if (settings.displayName.trim().isEmpty) return 'תנו שם לספרייה';
    return null;
  }

  Future<void> init() async {
    settings = await SettingsStore.load();
    if (settings.libraryId.isEmpty) settings.libraryId = newLibraryId();
    loaded = true;
    _refreshItems();
    notifyListeners();
    await _save();
    unawaited(reindex());
  }

  Future<void> _save() => SettingsStore.save(settings).catchError((_) {});

  void _changed() {
    notifyListeners();
    _save();
  }

  void showMessage(String msg, {bool error = false}) {
    lastMessage = msg;
    lastMessageIsError = error;
    notifyListeners();
  }

  void clearMessage() {
    lastMessage = null;
    notifyListeners();
  }

  // ─── קלט ──────────────────────────────────────────────────────────

  void _refreshItems() {
    final placements = placeInputs(
      settings.inputs,
      _index,
      PlacementDefaults(category: settings.defaultCategory, source: settings.defaultSource),
    );
    items = [for (final s in settings.inputs) InputItem(s, roleOf(s.path), placements[s.path])];
  }

  Set<String> _knownInputs() => {for (final s in settings.inputs) p.normalize(s.path).toLowerCase()};

  /// מוסיף לרשימה את קובצי ההערות והקישורים של [paths] (ראו [companionFiles]); מחזיר כמה נוספו.
  int _addCompanions(Iterable<String> paths, Set<String> known, [String? root]) {
    var added = 0;
    for (final path in paths) {
      for (final c in companionFiles(path)) {
        if (known.add(p.normalize(c).toLowerCase())) {
          // קובץ הערות מאותה תיקייה שומר על התיקייה שדרכה נוסף הספר.
          settings.inputs.add(InputSpec(c, roleOf(c) == InputRole.links ? null : root));
          added++;
        }
      }
    }
    return added;
  }

  static String _companionNote(int n) => n == 0 ? '' : ' נוספו אוטומטית גם $n קובצי הערות/קישורים נלווים.';

  void addFiles(Iterable<String> paths) {
    var added = 0, skipped = 0;
    final known = _knownInputs();
    final chosen = <String>[];
    for (final path in paths) {
      if (Directory(path).existsSync()) {
        addFolder(path);
        continue;
      }
      if (roleOf(path) == InputRole.unknown) {
        skipped++;
        continue;
      }
      chosen.add(path);
      if (known.add(p.normalize(path).toLowerCase())) {
        settings.inputs.add(InputSpec(path));
        added++;
      }
    }
    final companions = _addCompanions(chosen, known);
    _refreshItems();
    _changed();
    if (skipped > 0) {
      showMessage('$skipped קבצים דולגו: רק TXT, ‎_links.json‎ ו-‎_alt_toc.json‎ נתמכים.${_companionNote(companions)}');
    } else if (companions > 0) {
      showMessage('נוספו $added קבצים.${_companionNote(companions)}');
    } else if (added == 0) {
      showMessage('הקבצים כבר ברשימה.');
    }
  }

  void addFolder(String dir) {
    final files = scanFolder(dir);
    final known = _knownInputs();
    var added = 0;
    for (final f in files) {
      if (known.add(p.normalize(f).toLowerCase())) {
        settings.inputs.add(InputSpec(f, dir));
        added++;
      }
    }
    final companions = _addCompanions(files, known, dir);
    _refreshItems();
    _changed();
    showMessage(
      added + companions == 0
          ? 'לא נמצאו קבצים חדשים בתיקייה.'
          : 'נוספו $added קבצים מהתיקייה ${p.basename(dir)}.${_companionNote(companions)}',
    );
  }

  void removeInput(String path) {
    settings.inputs.removeWhere((s) => s.path == path);
    _refreshItems();
    _changed();
  }

  void clearInputs() {
    settings.inputs = [];
    _refreshItems();
    _changed();
  }

  // ─── הגדרות ───────────────────────────────────────────────────────

  void setThemeMode(ThemeMode m) {
    settings.themeMode = m;
    _changed();
  }

  Future<void> setLibraryPath(String path) async {
    settings.libraryPath = path;
    _changed();
    await reindex();
  }

  Future<void> reindex() async {
    final path = settings.libraryPath;
    if (path.isEmpty || !Directory(path).existsSync()) {
      _index = LibraryIndex.empty();
      libraryError = path.isEmpty ? 'לא נבחרה תיקיית otzaria-library' : 'התיקייה לא נמצאה: $path';
      _refreshItems();
      notifyListeners();
      return;
    }
    indexing = true;
    libraryError = null;
    notifyListeners();
    try {
      _index = await runJob(indexJob, path);
      if (_index.byTitle.isEmpty) libraryError = 'לא נמצאו ספרים בתיקייה (האם זו otzaria-library?)';
    } catch (e) {
      _index = LibraryIndex.empty();
      libraryError = 'סריקת הספרייה נכשלה: $e';
    }
    indexing = false;
    _refreshItems();
    notifyListeners();
  }

  void setOtzariaRepo(String v) {
    settings.otzariaRepo = v;
    _changed();
  }

  void setOutDir(String dir) {
    settings.outDir = dir;
    _changed();
  }

  void setOutName(String name) {
    settings.outName = name;
    _changed();
  }

  void setDisplayName(String v) {
    settings.displayName = v;
    _changed();
  }

  void setAuthor(String v) {
    settings.author = v;
    _changed();
  }

  void setDefaultCategory(String v) {
    settings.defaultCategory = v;
    _refreshItems();
    _changed();
  }

  void setDefaultSource(String v) {
    settings.defaultSource = v;
    _refreshItems();
    _changed();
  }

  void setUseLibraryLinks(bool v) {
    settings.useLibraryLinks = v;
    _changed();
  }

  void setExternalLinks(bool v) {
    settings.externalLinks = v;
    _changed();
  }

  void setRunValidator(bool v) {
    settings.runValidator = v;
    _changed();
  }

  void regenerateLibraryId() {
    settings.libraryId = newLibraryId();
    _changed();
  }

  // ─── בנייה ────────────────────────────────────────────────────────

  void cancelActivity() {
    activity?.cancelled = true;
    notifyListeners();
  }

  Future<bool> build() async {
    final blocker = buildBlocker;
    if (blocker != null) {
      showMessage(blocker, error: true);
      return false;
    }
    if (busy) return false;
    final s = settings;
    final opts = BuildOptions(
      inputs: List.of(s.inputs),
      libraryPath: s.libraryPath,
      outPath: s.outPath,
      libraryId: s.libraryId,
      displayName: s.displayName.trim(),
      author: s.author.trim(),
      defaultCategory: s.defaultCategory,
      defaultSource: s.defaultSource,
      useLibraryLinks: s.useLibraryLinks,
      externalLinks: s.externalLinks,
    );
    final a = activity = Activity('בונה את המסד');
    lastMessage = null;
    lastValidation = null;
    notifyListeners();
    try {
      lastResult = await runJob(
        buildJob,
        opts,
        onProgress: (t, d, f) {
          a
            ..title = t
            ..detail = d
            ..progress = f;
          notifyListeners();
        },
        isCancelled: () => a.cancelled,
      );
    } on BuildCancelled {
      showMessage('הבנייה בוטלה.');
      return false;
    } on BuildError catch (e) {
      showMessage(e.message, error: true);
      return false;
    } catch (e) {
      showMessage('שגיאה: $e', error: true);
      return false;
    } finally {
      activity = null;
      notifyListeners();
    }
    if (s.runValidator) await validate();
    return true;
  }

  /// מריץ את בודק המסדים של אוצריא על המסד האחרון.
  Future<void> validate() async {
    final r = lastResult;
    if (r == null || validating) return;
    validating = true;
    notifyListeners();
    try {
      lastValidation = await runValidator(r.outPath, settings.otzariaRepo);
    } finally {
      validating = false;
      notifyListeners();
    }
  }

  /// פותח את סייר הקבצים על הקובץ או התיקייה.
  static Future<void> reveal(String path) async {
    try {
      if (Platform.isWindows) {
        if (File(path).existsSync()) {
          await Process.run('explorer.exe', ['/select,', path]);
        } else {
          await Process.run('explorer.exe', [path]);
        }
      } else if (Platform.isMacOS) {
        await Process.run('open', File(path).existsSync() ? ['-R', path] : [path]);
      } else {
        await Process.run('xdg-open', [File(path).existsSync() ? p.dirname(path) : path]);
      }
    } catch (_) {}
  }
}
