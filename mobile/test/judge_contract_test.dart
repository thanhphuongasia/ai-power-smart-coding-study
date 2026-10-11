// Khoá INV-02/INV-03: seed Dart và backend/app/exercises.json phải khớp.
// Lệch thì học viên gõ đúng lời giải vẫn bị chấm sai (và bài bị khoá).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/domain/merge.dart';

void main() {
  // flutter test chạy với cwd = thư mục mobile/.
  final file = File('../backend/app/exercises.json');
  late Map<String, dynamic> backend;

  setUpAll(() {
    expect(file.existsSync(), isTrue, reason: 'Không thấy ${file.path}');
    backend = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('INV-03: tập exercise id của seed = tập key của exercises.json', () {
    final seedIds = uniqueExercises().map((e) => e.id).toSet();
    expect(seedIds, backend.keys.toSet());
  });

  test('INV-03: functionName = function của backend', () {
    for (final e in uniqueExercises()) {
      final entry = backend[e.id] as Map<String, dynamic>?;
      expect(entry, isNotNull, reason: 'backend thiếu ${e.id}');
      expect(e.functionName, entry!['function'], reason: e.id);
    }
  });

  test('INV-02: ghép lời giải từng ô vào template = solution của backend', () {
    for (final e in uniqueExercises()) {
      final entry = backend[e.id] as Map<String, dynamic>;
      final cells = {
        for (final b in e.blocks) b.label: b.acceptedAnswers.first,
      };
      final merged = mergeCells(e, cells).code;
      expect(merged, entry['solution'], reason: 'Lệch ở bài ${e.id}');
    }
  });
}
