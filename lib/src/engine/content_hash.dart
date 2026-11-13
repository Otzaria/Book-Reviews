// book.contentHash של סכמה 7 — תרגום של BookContentHash.kt.
//
// SHA-256 על: התג FORMAT_TAG; לכל שורה לפי lineIndex: 'L', lineIndex (i64), אורך UTF-8 (i32), הטקסט;
// לכל line_note לפי (lineIndex, noteIndex): 'N', lineIndex, noteIndex, charPos (i64 כל אחד),
// סימון (0, או 1 + i32 אורך + UTF-8 של ה-sup התואם בשורה), גוף (i32 אורך + UTF-8).
// הערך: 8 הבתים הראשונים כ-i64 חתום big-endian; 0 הופך ל-1.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'notes.dart';

const contentHashFormatTag = 'seforim-book-content-v1';

class HashLine {
  const HashLine(this.lineIndex, this.text, [this.notes = const []]);
  final int lineIndex;
  final String text;
  final List<LineNoteRow> notes;
}

/// [lines] — השורות שנשמרו בספר (כולל ה-line_note שלהן), בכל סדר.
int bookContentHash(List<HashLine> lines) {
  final sorted = List<HashLine>.of(lines)..sort((a, b) => a.lineIndex.compareTo(b.lineIndex));
  final out = BytesBuilder(copy: false);
  void i64(int v) => out.add((ByteData(8)..setInt64(0, v)).buffer.asUint8List());
  void i32(int v) => out.add((ByteData(4)..setInt32(0, v)).buffer.asUint8List());
  out.add(utf8.encode(contentHashFormatTag));
  final markers = <int, List<List<int>>>{};
  for (final l in sorted) {
    final bytes = utf8.encode(l.text);
    if (l.notes.isNotEmpty) {
      final expected = l.notes.where((n) => n.hasMarker).length;
      final found = InlineNotes.markers(l.text);
      if (found.length != expected) {
        throw StateError('line ${l.lineIndex}: $expected line_note rows with a marker, ${found.length} marker sups');
      }
      markers[l.lineIndex] = [for (final m in found) utf8.encode(m)];
    }
    out.addByte(0x4C);
    i64(l.lineIndex);
    i32(bytes.length);
    out.add(bytes);
  }
  for (final l in sorted) {
    var k = 0;
    for (final n in [...l.notes]..sort((a, b) => a.noteIndex.compareTo(b.noteIndex))) {
      out.addByte(0x4E);
      i64(l.lineIndex);
      i64(n.noteIndex);
      i64(n.charPos);
      if (!n.hasMarker) {
        out.addByte(0);
      } else {
        final m = markers[l.lineIndex]![k++];
        out.addByte(1);
        i32(m.length);
        out.add(m);
      }
      final body = utf8.encode(n.body);
      i32(body.length);
      out.add(body);
    }
  }
  final digest = sha256.convert(out.takeBytes()).bytes;
  final v = ByteData.sublistView(Uint8List.fromList(digest.sublist(0, 8))).getInt64(0);
  return v == 0 ? 1 : v;
}
