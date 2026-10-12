/// Khối "Out[n]:" của tab Code: kết quả judge, code đã ghép (cột nguồn A/B/C)
/// và danh sách test.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/judge_client.dart';
import '../../domain/merge.dart';
import '../../shared/widgets.dart';

/// Lỗi của judge rơi vào đâu trong code đã ghép (INV-05).
class ErrorOrigin {
  const ErrorOrigin({this.label, this.locked = false});

  /// Ô học viên gây lỗi (A/B/C); null nếu không xác định hoặc ở dòng khoá.
  final String? label;

  /// Dòng lỗi thuộc phần khoá của template.
  final bool locked;
}

/// `error.line` (1-based, trong code đã gửi) → `lineOrigin[line-1]`.
/// Không có dòng / dòng ngoài phạm vi → [ErrorOrigin] rỗng.
ErrorOrigin errorOrigin(MergedCode merged, JudgeError? error) {
  final line = error?.line;
  if (line == null || line < 1 || line > merged.lineOrigin.length) {
    return const ErrorOrigin();
  }
  final origin = merged.lineOrigin[line - 1];
  return origin == null
      ? const ErrorOrigin(locked: true)
      : ErrorOrigin(label: origin);
}

class RunResultView extends StatelessWidget {
  const RunResultView({
    super.key,
    required this.result,
    required this.merged,
    required this.runIndex,
    required this.onRetry,
  });

  final JudgeResult result;
  final MergedCode merged;
  final int runIndex;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            'Out[$runIndex]:',
            style: AppText.code.copyWith(fontSize: 11, color: p.danger),
          ),
        ),
        Expanded(
          child: Column(
            key: const Key('run-result'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.status == JudgeStatus.unavailable)
                _unavailable(context)
              else ...[
                _badge(context),
                ..._errorLines(context),
                const SizedBox(height: AppSpace.s2),
                _mergedCode(context),
                if (result.tests.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.s2),
                  _tests(context),
                ],
                if (result.stdout.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpace.s2),
                  const SectionLabel('STDOUT'),
                  Text(
                    result.stdout,
                    key: const Key('run-stdout'),
                    style: AppText.code,
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _unavailable(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('run-unavailable'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chưa chấm được lúc này',
          style: AppText.label.copyWith(color: p.danger),
        ),
        const SizedBox(height: AppSpace.s1),
        Text(
          result.unavailableReason ?? 'Không kết nối được máy chấm.',
          style: AppText.caption.copyWith(color: p.inkMuted),
        ),
        const SizedBox(height: AppSpace.s2),
        GhostButton(
          key: const Key('retry-button'),
          label: 'Thử lại',
          onPressed: onRetry,
        ),
      ],
    );
  }

  Widget _badge(BuildContext context) {
    final p = context.palette;
    final passedCount = result.tests.where((t) => t.passed).length;
    final total = result.tests.length;
    final String text;
    final bool good;
    switch (result.status) {
      case JudgeStatus.passed:
        text = '$passedCount/$total test đạt';
        good = true;
      case JudgeStatus.failed:
        text = total == 0 ? 'Chưa đạt' : '$passedCount/$total test đạt';
        good = false;
      case JudgeStatus.error:
        text = result.error?.kind == 'syntax'
            ? 'Lỗi cú pháp'
            : 'Lỗi khi chạy code';
        good = false;
      case JudgeStatus.timeout:
        text = 'Chạy quá thời gian';
        good = false;
      case JudgeStatus.unavailable:
        text = '';
        good = false;
    }
    final color = good ? p.primary : p.danger;
    return Container(
      key: const Key('run-badge'),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s2, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(text, style: AppText.label.copyWith(color: color)),
    );
  }

  List<Widget> _errorLines(BuildContext context) {
    final p = context.palette;
    final e = result.error;
    if (e == null) return const [];
    final origin = errorOrigin(merged, e);
    return [
      const SizedBox(height: AppSpace.s1),
      Text(
        e.line != null ? 'Dòng ${e.line}: ${e.message}' : e.message,
        key: const Key('run-error'),
        style: AppText.code.copyWith(fontSize: 12, color: p.danger),
      ),
      if (origin.locked)
        Text(
          'Lỗi ở phần có sẵn (thường do ô phía trên).',
          key: const Key('run-error-locked'),
          style: AppText.caption.copyWith(color: p.inkMuted),
        ),
    ];
  }

  Widget _mergedCode(BuildContext context) {
    final p = context.palette;
    final lines = merged.code.split('\n');
    final cells = {for (final o in merged.lineOrigin) ?o};
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('merged-code'),
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        title: Text('Code đã ghép từ ${cells.length} ô', style: AppText.label),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.s1),
            decoration: BoxDecoration(
              color: p.codeSurface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              children: [
                for (var i = 0; i < lines.length; i++)
                  Row(
                    key: Key('merged-line-$i'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        alignment: Alignment.center,
                        color:
                            i < merged.lineOrigin.length &&
                                merged.lineOrigin[i] != null
                            ? p.codeInk.withValues(alpha: 0.18)
                            : null,
                        child: Text(
                          i < merged.lineOrigin.length
                              ? (merged.lineOrigin[i] ?? '')
                              : '',
                          key: Key('merged-origin-$i'),
                          style: AppText.code.copyWith(
                            fontSize: 12,
                            color: p.codeInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.s2),
                      Expanded(
                        child: Text(
                          lines[i],
                          style: AppText.code.copyWith(
                            fontSize: 12,
                            color: p.codeInk,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tests(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('run-tests'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < result.tests.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.s1),
            child: Row(
              key: Key('test-$i'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  result.tests[i].passed ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: result.tests[i].passed ? p.primary : p.danger,
                ),
                const SizedBox(width: AppSpace.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '>>> ${result.tests[i].call}',
                        style: AppText.code.copyWith(fontSize: 12),
                      ),
                      Text(
                        result.tests[i].actual ?? '(không có kết quả)',
                        style: AppText.code.copyWith(
                          fontSize: 12,
                          color: result.tests[i].passed ? p.inkMuted : p.danger,
                        ),
                      ),
                      if (!result.tests[i].passed)
                        Text(
                          'mong đợi: ${result.tests[i].expected}',
                          key: Key('test-expected-$i'),
                          style: AppText.code.copyWith(
                            fontSize: 12,
                            color: p.inkMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
