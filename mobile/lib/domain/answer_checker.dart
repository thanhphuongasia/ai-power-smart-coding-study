import 'models.dart';

/// Kết quả chấm một block.
class RunResult {
  const RunResult({required this.passed, required this.output});

  final bool passed;
  final String output;
}

/// Chuẩn hoá code Python để so khớp đáp án, bỏ qua khác biệt không quan
/// trọng (khoảng trắng thừa, dấu nháy đơn/kép) nhưng GIỮ thụt tương đối
/// giữa các dòng — vì thụt trong Python mang ý nghĩa cấu trúc.
///
/// Các bước:
/// 1. Bỏ khoảng trắng cuối mỗi dòng (rstrip), bỏ dòng trống.
/// 2. Dedent: trừ đi thụt nền chung nhỏ nhất trong số các dòng còn lại,
///    giữ nguyên chênh lệch thụt tương đối giữa các dòng.
/// 3. Gộp khoảng trắng thừa bên trong mỗi dòng thành một khoảng trắng.
/// 4. Bỏ khoảng trắng quanh dấu `( ) [ ] , : =` và các toán tử số học/so
///    sánh (`+ - * / % < > ! & | ^`).
/// 5. Đổi dấu nháy đơn `'` thành nháy kép `"`.
///
/// Không tự cân bằng ngoặc — ngoặc đóng thừa do auto-close vẫn còn trong
/// kết quả, nên vẫn khiến so khớp thất bại đúng như mong đợi.
String normalizeCode(String code) {
  final rawLines = code.split('\n');
  // Đổi tab thành 4 space (tab == 4 space trong Python norm)
  final tabExpanded = rawLines
      .map((line) => line.replaceAll('\t', '    '))
      .toList();
  final rtrimmed = tabExpanded
      .map((line) => line.replaceAll(RegExp(r'\s+$'), ''))
      .toList();
  final nonBlank = rtrimmed.where((line) => line.trim().isNotEmpty).toList();
  if (nonBlank.isEmpty) return '';

  final indents = nonBlank
      .map((line) => line.length - line.trimLeft().length)
      .toList();
  final baseIndent = indents.reduce((a, b) => a < b ? a : b);

  final normalizedLines = <String>[];
  for (final line in nonBlank) {
    final leading = line.length - line.trimLeft().length;
    final relativeIndent = leading - baseIndent;

    var content = line.trim();
    // Gộp khoảng trắng thừa.
    content = content.replaceAll(RegExp(r'[ \t]+'), ' ');
    // Bỏ khoảng trắng quanh dấu câu/toán tử.
    content = content.replaceAllMapped(
      RegExp(r'\s*([()\[\],:=+\-*/%<>!&|^])\s*'),
      (match) => match[1]!,
    );
    // Đổi nháy đơn thành nháy kép.
    content = content.replaceAll("'", '"');

    normalizedLines.add('${' ' * relativeIndent}$content');
  }

  return normalizedLines.join('\n');
}

/// Chấm code người dùng nhập cho [block]. `passed` khi khớp một trong các
/// [Block.acceptedAnswers] sau khi chuẩn hoá; sai thì trả thông báo tiếng
/// Việt để người học tự sửa.
RunResult runBlock(String code, Block block) {
  final normalizedInput = normalizeCode(code);
  final matched = block.acceptedAnswers.any(
    (answer) => normalizeCode(answer) == normalizedInput,
  );

  if (matched) {
    return RunResult(passed: true, output: block.expectedOutput);
  }

  return const RunResult(
    passed: false,
    output: 'Chưa đúng, kiểm tra lại cú pháp và thụt lề rồi thử lại.',
  );
}
