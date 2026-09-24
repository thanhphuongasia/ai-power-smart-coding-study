import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/domain/answer_checker.dart';
import 'package:smart_coding_study/domain/models.dart';

void main() {
  group('normalizeCode', () {
    test('bỏ khoảng trắng thừa và đổi nháy đơn thành nháy kép', () {
      final a = normalizeCode("chunks = []");
      final b = normalizeCode("chunks  =    [ ]");
      expect(a, b);
    });

    test('nháy đơn và nháy kép coi như giống nhau', () {
      final a = normalizeCode("print('hello')");
      final b = normalizeCode('print("hello")');
      expect(a, b);
    });

    test('giữ thụt tương đối giữa các dòng', () {
      const code = 'for i in range(0, len(text), size):\n'
          '    chunks.append(text[i:i + size])';
      final normalized = normalizeCode(code);
      final lines = normalized.split('\n');
      expect(lines.length, 2);
      // Dòng 2 phải thụt thêm 4 so với dòng 1 (dòng 1 thụt 0 sau dedent).
      final indentLine1 = lines[0].length - lines[0].trimLeft().length;
      final indentLine2 = lines[1].length - lines[1].trimLeft().length;
      expect(indentLine1, 0);
      expect(indentLine2, 4);
    });

    test('dedent bỏ thụt nền chung nhưng giữ chênh lệch', () {
      // Cả 2 dòng cùng thụt thêm 8 (giả lập nằm trong thân hàm) — sau dedent
      // vẫn phải còn đúng 4 khoảng cách tương đối.
      const code = '        for i in range(0, len(text), size):\n'
          '            chunks.append(text[i:i + size])';
      final normalized = normalizeCode(code);
      final lines = normalized.split('\n');
      final indentLine1 = lines[0].length - lines[0].trimLeft().length;
      final indentLine2 = lines[1].length - lines[1].trimLeft().length;
      expect(indentLine1, 0);
      expect(indentLine2, 4);
    });

    test('bỏ dòng trống', () {
      const code = 'chunks = []\n\n\n';
      final normalized = normalizeCode(code);
      expect(normalized, 'chunks=[]');
    });

    test('thụt dòng 2 bằng tab (\\t) được coi bằng 4 space', () {
      const code = 'for i in range(0, len(text), size):\n'
          '\tchunks.append(text[i:i + size])';
      final normalized = normalizeCode(code);
      final lines = normalized.split('\n');
      expect(lines.length, 2);
      // Dòng 2 phải thụt 4 space (tab được đổi thành 4 space)
      final indentLine2 = lines[1].length - lines[1].trimLeft().length;
      expect(indentLine2, 4);
    });

    test('thụt dòng 2 bằng 2 tabs (8 space) được coi khác 4 space', () {
      const code = 'for i in range(0, len(text), size):\n'
          '\t\tchunks.append(text[i:i + size])';
      final normalized = normalizeCode(code);
      final lines = normalized.split('\n');
      expect(lines.length, 2);
      // 2 tabs = 8 spaces, khác 4 spaces
      final indentLine2 = lines[1].length - lines[1].trimLeft().length;
      expect(indentLine2, 8);
    });
  });

  group('runBlock', () {
    final defBlock = Block(
      id: 'blk-def',
      title: 'Khai báo hàm',
      prompt: 'Viết dòng khai báo hàm split_chunks.',
      indentLevel: 0,
      acceptedAnswers: const ['def split_chunks(text, size):'],
      expectedOutput: 'Đã khai báo hàm split_chunks.',
      hints: const ['Hint 1', 'Hint 2', 'Hint 3'],
      vocab: const ['def'],
    );

    test('khác khoảng trắng/nháy vẫn pass', () {
      final result = runBlock('def   split_chunks(text,size):', defBlock);
      expect(result.passed, isTrue);
      expect(result.output, defBlock.expectedOutput);
    });

    test('sai tên hàm thì fail', () {
      final result = runBlock('def split_chunk(text, size):', defBlock);
      expect(result.passed, isFalse);
      expect(result.output, isNotEmpty);
    });

    test('thiếu dấu hai chấm thì fail', () {
      final result = runBlock('def split_chunks(text, size)', defBlock);
      expect(result.passed, isFalse);
    });

    final loopBlock = Block(
      id: 'blk-loop',
      title: 'Cắt đoạn văn bản',
      prompt: 'Viết vòng for cắt text thành các đoạn theo size.',
      indentLevel: 1,
      acceptedAnswers: const [
        'for i in range(0, len(text), size):\n'
            '    chunks.append(text[i:i + size])',
      ],
      expectedOutput: 'Đã cắt text thành các đoạn.',
      hints: const ['Hint 1', 'Hint 2', 'Hint 3'],
      vocab: const ['range', 'len', 'append'],
    );

    test('thụt dòng 2 sai thì fail (không thụt thêm)', () {
      const wrongIndentCode = 'for i in range(0, len(text), size):\n'
          'chunks.append(text[i:i + size])';
      // Cả 2 dòng cùng mức thụt (không thụt thêm dòng 2) → phải fail.
      final result = runBlock(wrongIndentCode, loopBlock);
      expect(result.passed, isFalse);
    });

    test('thụt dòng 2 đúng thêm 4 space thì pass', () {
      const correctCode = 'for i in range(0, len(text), size):\n'
          '    chunks.append(text[i:i + size])';
      final result = runBlock(correctCode, loopBlock);
      expect(result.passed, isTrue);
    });

    test('ngoặc đóng thừa do auto-close thì fail, không nuốt lỗi', () {
      const extraParenCode = 'for i in range(0, len(text), size):\n'
          '    chunks.append(text[i:i + size]))';
      final result = runBlock(extraParenCode, loopBlock);
      expect(result.passed, isFalse);
    });

    test('thụt dòng 2 bằng tab (\\t) khi đáp án dùng 4 space thì pass', () {
      const tabIndentCode = 'for i in range(0, len(text), size):\n'
          '\tchunks.append(text[i:i + size])';
      // loopBlock acceptedAnswers dùng 4 spaces
      final result = runBlock(tabIndentCode, loopBlock);
      expect(result.passed, isTrue);
    });

    test('thụt dòng 2 bằng 2 tabs (8 space) khi đáp án 4 space thì fail', () {
      const overIndentCode = 'for i in range(0, len(text), size):\n'
          '\t\tchunks.append(text[i:i + size])';
      // 2 tabs = 8 spaces, khác 4 spaces
      final result = runBlock(overIndentCode, loopBlock);
      expect(result.passed, isFalse);
    });
  });
}
