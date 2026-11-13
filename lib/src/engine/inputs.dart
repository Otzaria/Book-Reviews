// קלט: זיהוי תפקיד כל קובץ (ספר / הערות / קישורים / כותרות חלופיות) ומיקומו (מקור + קטגוריה).

import 'dart:io';

import 'package:path/path.dart' as p;

import 'library.dart';
import 'rules.dart';

enum InputRole {
  book('ספר'),
  notes('הערות'),
  links('קישורים'),
  altToc('כותרות חלופיות'),
  unknown('לא נתמך');

  const InputRole(this.label);
  final String label;
}

/// קובץ שהמשתמש הוסיף. [addedRoot] = התיקייה שדרכה נוסף (null = קובץ בודד).
class InputSpec {
  const InputSpec(this.path, [this.addedRoot]);
  final String path;
  final String? addedRoot;

  Map<String, Object?> toJson() => {'path': path, 'root': addedRoot};
  static InputSpec fromJson(Map<String, Object?> j) => InputSpec(j['path'] as String, j['root'] as String?);
}

InputRole roleOf(String path) {
  final name = p.basename(path);
  final lower = name.toLowerCase();
  if (lower.endsWith('_links.json')) return InputRole.links;
  if (lower.endsWith('_alt_toc.json')) return InputRole.altToc;
  if (lower.endsWith('.txt')) {
    return bookTitleOf(p.basenameWithoutExtension(name)).startsWith('הערות על ') ? InputRole.notes : InputRole.book;
  }
  return InputRole.unknown;
}

/// קבצים רלוונטיים בתיקייה (רקורסיבית): כל ה-TXT וכל `*_links.json`, בלי `_headings.json` ו-`_alt_toc.json`.
List<String> scanFolder(String dir) {
  final out = <String>[];
  for (final e in Directory(dir).listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = p.split(p.relative(e.path, from: dir));
    if (rel.any((s) => s.startsWith('.'))) continue;
    final lower = p.basename(e.path).toLowerCase();
    if (lower.endsWith('.txt') || lower.endsWith('_links.json')) out.add(e.path);
  }
  out.sort();
  return out;
}

/// תיקיית `links` של המקור שבו נמצא הקובץ: `<מקור>/ספרים/…/X.txt` → `<מקור>/links`.
String? linksDirOf(String path) {
  final segs = p.split(p.normalize(p.absolute(path)));
  for (var i = segs.length - 2; i >= 1; i--) {
    if (segs[i] == 'ספרים') return p.joinAll([...segs.take(i), 'links']);
  }
  return null;
}

/// קבצים נלווים שקיימים על הדיסק לקובץ TXT שנבחר:
/// `הערות על X.txt` מאותה תיקייה (לספר), ו-`X_links.json` מתיקיית `links` של המקור
/// (לספר ולהערות שלו).
List<String> companionFiles(String path) {
  final role = roleOf(path);
  if (role != InputRole.book && role != InputRole.notes) return const [];
  final stem = p.basenameWithoutExtension(path);
  final stems = [stem];
  final out = <String>[];
  if (role == InputRole.book) {
    final notes = p.join(p.dirname(path), 'הערות על $stem.txt');
    if (File(notes).existsSync()) {
      out.add(notes);
      stems.add('הערות על $stem');
    }
  }
  final linksDir = linksDirOf(path);
  if (linksDir != null) {
    for (final s in stems) {
      for (final name in {'${s}_links.json', '${bookTitleOf(s)}_links.json'}) {
        final f = p.join(linksDir, name);
        if (File(f).existsSync()) {
          out.add(f);
          break;
        }
      }
    }
  }
  return out;
}

enum PlacementKind {
  libraryPath('לפי הנתיב (<מקור>/ספרים/אוצריא/…)'),
  libraryIndex('כמו הספר הקיים בספרייה'),
  baseBook('יחד עם ספר הבסיס'),
  folder('לפי התיקייה שנוספה'),
  fallback('ברירת מחדל');

  const PlacementKind(this.label);
  final String label;
}

class Placement {
  Placement(this.source, this.folders, this.kind, {this.libraryPath});
  final String source;

  /// שמות התיקיות הגולמיים (כמו בספרייה), מהשורש "אוצריא" ומטה.
  final List<String> folders;
  final PlacementKind kind;

  /// הקובץ המקביל בספרייה (כשהמיקום נלקח ממנה).
  final String? libraryPath;

  /// נתיב הקטגוריה כפי שיופיע במסד.
  List<String> get categoryTitles => [for (final f in folders) folderTitle(f)];
}

class PlacementDefaults {
  const PlacementDefaults({required this.category, required this.source});
  final String category;
  final String source;
  List<String> get categoryFolders => [
    for (final s in category.split(RegExp(r'[/\\]'))) if (ktTrim(s).isNotEmpty) ktTrim(s),
  ];
}

/// מיקום של כל קובצי ה-TXT ב-[inputs].
Map<String, Placement> placeInputs(List<InputSpec> inputs, LibraryIndex index, PlacementDefaults defaults) {
  final out = <String, Placement>{};
  final own = <String, bool>{};
  final libRoot = index.isEmpty ? null : p.normalize(p.absolute(index.libraryPath));
  for (final input in inputs) {
    final role = roleOf(input.path);
    if (role != InputRole.book && role != InputRole.notes) continue;
    final abs = p.normalize(p.absolute(input.path));
    final segs = p.split(abs);
    // 1. <מקור>/ספרים/אוצריא/…
    Placement? placed;
    for (var i = segs.length - 3; i >= 1; i--) {
      if (segs[i] == 'ספרים' && segs[i + 1] == 'אוצריא') {
        var source = segs[i - 1];
        if (libRoot != null && p.isWithin(libRoot, abs)) {
          source = p.split(p.relative(abs, from: libRoot)).first;
        }
        placed = Placement(source, segs.sublist(i + 2, segs.length - 1), PlacementKind.libraryPath);
        break;
      }
    }
    // 2. ספר שכבר קיים בספרייה
    if (placed == null) {
      final places = index.byTitle[bookTitleOf(p.basenameWithoutExtension(abs))];
      if (places != null && places.isNotEmpty) {
        final pl = places.first;
        placed = Placement(pl.source, pl.folders, PlacementKind.libraryIndex, libraryPath: pl.path);
      }
    }
    own[input.path] = placed != null;
    // 3. לפי התיקייה שנוספה / 4. ברירת מחדל
    placed ??= () {
      final root = input.addedRoot;
      if (root != null && p.isWithin(root, abs)) {
        final rel = p.split(p.relative(p.dirname(abs), from: root));
        final folders = rel.length == 1 && rel.first == '.' ? [p.basename(root)] : rel;
        return Placement(defaults.source, folders, PlacementKind.folder);
      }
      final cat = defaults.categoryFolders;
      return Placement(defaults.source, cat.isEmpty ? ['ספרים לבדיקה'] : cat, PlacementKind.fallback);
    }();
    out[input.path] = placed;
  }
  // הערות על X בלי מיקום משלהן: יחד עם X.
  final byTitle = <String, String>{};
  for (final input in inputs) {
    if (roleOf(input.path) == InputRole.book) {
      byTitle.putIfAbsent(bookTitleOf(p.basenameWithoutExtension(input.path)), () => input.path);
    }
  }
  for (final input in inputs) {
    if (roleOf(input.path) != InputRole.notes || own[input.path] == true) continue;
    final base = bookTitleOf(p.basenameWithoutExtension(input.path)).substring('הערות על '.length);
    final basePath = byTitle[base];
    if (basePath == null) continue;
    final b = out[basePath]!;
    out[input.path] = Placement(b.source, b.folders, PlacementKind.baseBook, libraryPath: b.libraryPath);
  }
  return out;
}
