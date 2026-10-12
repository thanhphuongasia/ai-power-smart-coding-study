/// Vẽ MỘT thẻ nội dung System Design (text/table/code/diagram/callout) trên
/// tờ giấy trắng của màn đọc. Màu ở đây là hằng riêng của tờ giấy, KHÔNG lấy
/// từ `context.palette`: tờ giấy luôn trắng kể cả khi app ở chế độ tối.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/sd_models.dart';

/// Font serif của phần thân bài đọc (khai ở pubspec.yaml).
const String kSerifFamily = 'SourceSerif4';

/// Màu tờ giấy và chữ trên giấy (không đổi theo theme).
const Color kPaperColor = Color(0xFFFFFFFF);
const Color kPaperInk = Color(0xFF2B3340);
const Color kPaperMuted = Color(0xFF6B7585);
const Color kPaperLine = Color(0xFFE5E8EE);
const Color _kCodeBg = Color(0xFFF4F5F7);
const Color _kInlineCodeBg = Color(0xFFEEF0F3);
const Color _kCalloutBg = Color(0xFFFFF4D6);

/// Cỡ chữ thân bài.
const double kBodySize = 19;

TextStyle _serif({bool bold = false, double size = kBodySize}) => TextStyle(
  fontFamily: kSerifFamily,
  fontSize: size,
  height: 1.7,
  color: kPaperInk,
  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  fontVariations: [FontVariation('wght', bold ? 700 : 400)],
);

TextStyle _sans({
  required double size,
  double height = 1.5,
  int weight = 500,
  Color color = kPaperInk,
}) => TextStyle(
  fontFamily: kSansFamily,
  fontSize: size,
  height: height,
  color: color,
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontVariations: [FontVariation('wght', weight.toDouble())],
);

// ───────────────────────── Phân tích (hàm thuần) ─────────────────────────

/// Một đoạn chữ trong dòng: thường, đậm hoặc mã.
enum InlineStyle { plain, bold, code }

class InlineSeg {
  const InlineSeg(this.text, this.style);
  final String text;
  final InlineStyle style;

  @override
  bool operator ==(Object other) =>
      other is InlineSeg && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);

  @override
  String toString() => 'InlineSeg($text, $style)';
}

/// Tách `**đậm**` và `` `mã` `` khỏi chữ thường. Dấu không có cặp đóng được
/// giữ nguyên như chữ thường. Trong mã không phân tích thêm.
List<InlineSeg> parseInline(String text) {
  final out = <InlineSeg>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      out.add(InlineSeg(buf.toString(), InlineStyle.plain));
      buf.clear();
    }
  }

  var i = 0;
  while (i < text.length) {
    if (text.startsWith('`', i)) {
      final end = text.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        out.add(InlineSeg(text.substring(i + 1, end), InlineStyle.code));
        i = end + 1;
        continue;
      }
    } else if (text.startsWith('**', i)) {
      final end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        flush();
        out.add(InlineSeg(text.substring(i + 2, end), InlineStyle.bold));
        i = end + 2;
        continue;
      }
    }
    buf.write(text[i]);
    i++;
  }
  flush();
  return out;
}

enum MdKind { paragraph, bullets, numbered }

/// Một khối markdown nhẹ: đoạn văn (một mục) hoặc danh sách (nhiều mục).
class MdBlock {
  const MdBlock(this.kind, this.items);
  final MdKind kind;
  final List<String> items;
}

final _bulletRe = RegExp(r'^\s*[-*]\s+(.*)$');
final _numberedRe = RegExp(r'^\s*\d+\.\s+(.*)$');

/// Chia thân thẻ text thành đoạn văn / danh sách gạch đầu dòng / đánh số.
/// Dòng trống ngăn các khối; các dòng liền nhau của đoạn văn nối bằng '\n'.
List<MdBlock> parseBlocks(String body) {
  final blocks = <MdBlock>[];
  MdKind? kind;
  var items = <String>[];
  void flush() {
    if (kind != null) blocks.add(MdBlock(kind!, items));
    kind = null;
    items = <String>[];
  }

  for (final line in body.split('\n')) {
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    final bullet = _bulletRe.firstMatch(line);
    final numbered = _numberedRe.firstMatch(line);
    if (bullet != null || numbered != null) {
      final want = bullet != null ? MdKind.bullets : MdKind.numbered;
      if (kind != want) flush();
      kind = want;
      items.add((bullet ?? numbered)!.group(1)!.trim());
    } else if (kind == MdKind.paragraph) {
      items[0] = '${items[0]}\n${line.trim()}';
    } else if ((kind == MdKind.bullets || kind == MdKind.numbered) &&
        line.startsWith(RegExp(r'\s'))) {
      // Dòng thụt vào tiếp nối mục danh sách trước đó.
      items[items.length - 1] = '${items.last} ${line.trim()}';
    } else {
      flush();
      kind = MdKind.paragraph;
      items.add(line.trim());
    }
  }
  flush();
  return blocks;
}

final _sepCellRe = RegExp(r'^:?-{3,}:?$');

/// Bảng markdown → các hàng ô. Bỏ dòng phân cách `---`; chấp nhận dòng không
/// có '|' đầu/cuối. Dòng trống bị bỏ.
List<List<String>> parseTable(String body) {
  final rows = <List<String>>[];
  for (final raw in body.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('|')) line = line.substring(1);
    if (line.endsWith('|')) line = line.substring(0, line.length - 1);
    final cells = [for (final c in line.split('|')) c.trim()];
    if (cells.every(_sepCellRe.hasMatch)) continue;
    rows.add(cells);
  }
  return rows;
}

// ───────────────────────────── Widget ─────────────────────────────

/// Một thẻ: tiêu đề (nếu [showTitle]) + thân theo `kind`.
class SdBlockView extends StatelessWidget {
  const SdBlockView({super.key, required this.card, this.showTitle = true});

  final SdCard card;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final body = switch (card.kind) {
      'table' => _TableBlock(body: card.body),
      'code' => _CodeBlock(code: card.body, label: card.lang),
      'diagram' => _CodeBlock(code: card.body, label: 'Sơ đồ'),
      'callout' => _Callout(body: card.body),
      _ => _TextBlock(body: card.body),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle && card.title.isNotEmpty) ...[
          Text(card.title, style: _sans(size: 22, height: 1.3, weight: 800)),
          const SizedBox(height: 12),
        ],
        body,
      ],
    );
  }
}

/// Chữ có đậm / mã trong dòng theo [parseInline].
TextSpan inlineSpan(String text, TextStyle base) {
  return TextSpan(
    style: base,
    children: [
      for (final seg in parseInline(text))
        switch (seg.style) {
          InlineStyle.plain => TextSpan(text: seg.text),
          InlineStyle.bold => TextSpan(
            text: seg.text,
            style: base.copyWith(
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation('wght', 700)],
            ),
          ),
          InlineStyle.code => TextSpan(
            text: seg.text,
            style: TextStyle(
              fontFamily: kMonoFamily,
              fontSize: (base.fontSize ?? kBodySize) * 0.85,
              backgroundColor: _kInlineCodeBg,
              fontWeight: FontWeight.w400,
            ),
          ),
        },
    ],
  );
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.body, this.style});
  final String body;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? _serif();
    final blocks = parseBlocks(body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var b = 0; b < blocks.length; b++) ...[
          if (b > 0) const SizedBox(height: 12),
          switch (blocks[b].kind) {
            MdKind.paragraph => Text.rich(
              inlineSpan(blocks[b].items.first, base),
            ),
            _ => _ListBlock(block: blocks[b], base: base),
          },
        ],
      ],
    );
  }
}

class _ListBlock extends StatelessWidget {
  const _ListBlock({required this.block, required this.base});
  final MdBlock block;
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    final numbered = block.kind == MdKind.numbered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < block.items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(numbered ? '${i + 1}.' : '•', style: base),
                ),
                Expanded(child: Text.rich(inlineSpan(block.items[i], base))),
              ],
            ),
          ),
      ],
    );
  }
}

class _TableBlock extends StatelessWidget {
  const _TableBlock({required this.body});
  final String body;

  @override
  Widget build(BuildContext context) {
    final rows = parseTable(body);
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final cell = _serif(size: 16);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: const TableBorder(
          horizontalInside: BorderSide(color: kPaperLine),
        ),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              children: [
                for (var c = 0; c < cols; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text.rich(
                        inlineSpan(
                          c < rows[r].length ? rows[r][c] : '',
                          r == 0
                              ? cell.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontVariations: const [
                                    FontVariation('wght', 700),
                                  ],
                                )
                              : cell,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, this.label});
  final String code;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCodeBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null && label!.isNotEmpty) ...[
            Text(
              label!,
              style: _sans(size: 12, weight: 700, color: kPaperMuted),
            ),
            const SizedBox(height: 6),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              code,
              softWrap: false,
              style: AppText.code.copyWith(color: kPaperInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.body});
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kCalloutBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _TextBlock(body: body, style: _sans(size: 16, height: 1.55)),
    );
  }
}
