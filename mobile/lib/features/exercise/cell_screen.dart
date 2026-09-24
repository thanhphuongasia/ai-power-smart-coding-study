/// Màn Cell: làm MỘT block kiểu Jupyter — prompt, editor có gợi ý, Run,
/// output, hint 3 mức, và dialog "vẫn đang làm chứ?" khi ngồi im.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../app/theme.dart';
import '../../data/seed.dart';
import '../../domain/answer_checker.dart';
import '../../domain/models.dart';
import '../../shared/widgets.dart';
import 'code_input.dart';
import 'session_controller.dart';
import 'session_providers.dart';

class CellScreen extends ConsumerStatefulWidget {
  const CellScreen({
    super.key,
    required this.exerciseId,
    required this.blockIndex,
  });

  final String exerciseId;
  final int blockIndex;

  @override
  ConsumerState<CellScreen> createState() => _CellScreenState();
}

class _CellScreenState extends ConsumerState<CellScreen> {
  RunResult? _result;
  bool _idleDialogOpen = false;

  Exercise get _exercise => exerciseById(widget.exerciseId);
  Block get _block => _exercise.blocks[widget.blockIndex];

  @override
  void initState() {
    super.initState();
    // Lưu ý BẮT BUỘC (T-04): start() sau frame đầu, và build() phải
    // ref.watch(sessionProvider) suốt vòng đời màn — nếu không, autoDispose
    // huỷ Timer ngay lập tức và idle/timeout không bao giờ chạy.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(sessionProvider(widget.exerciseId).notifier).start();
    });
  }

  void _runCode(String code) {
    final result = ref
        .read(sessionProvider(widget.exerciseId).notifier)
        .run(widget.blockIndex, code);
    setState(() => _result = result);
  }

  void _goNextOrFinish() {
    final total = _exercise.blocks.length;
    final isLast = widget.blockIndex + 1 >= total;
    if (isLast) {
      context.pop();
    } else {
      context.pushReplacement(
        '/exercise/${widget.exerciseId}/block/${widget.blockIndex + 1}',
      );
    }
  }

  void _showHintSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      builder: (sheetContext) {
        return Consumer(builder: (context, ref, _) {
          final progress = ref.watch(progressProvider)[widget.exerciseId];
          final used = progress?.hintsUsed[_block.id] ?? 0;
          const levelLabels = ['Mờ', 'Vừa', 'Rõ'];

          return Padding(
            padding: const EdgeInsets.all(AppSpace.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gợi ý',
                  style: AppText.title.copyWith(color: AppColors.accent),
                ),
                const SizedBox(height: AppSpace.s4),
                if (used == 0)
                  Text(
                    'Chưa mở gợi ý nào.',
                    style: AppText.body.copyWith(color: AppColors.inkMuted),
                  ),
                for (var i = 0; i < used && i < _block.hints.length; i++)
                  Container(
                    key: Key('hint-level-$i'),
                    margin: const EdgeInsets.only(bottom: AppSpace.s2),
                    padding: const EdgeInsets.all(AppSpace.s2),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.accent),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          levelLabels[i],
                          style: AppText.label.copyWith(color: AppColors.accent),
                        ),
                        const SizedBox(height: AppSpace.s1),
                        Text(
                          _block.hints[i],
                          style: AppText.body.copyWith(color: AppColors.accent),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpace.s2),
                Text(
                  'Còn ${3 - used} lần',
                  style: AppText.caption.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(height: AppSpace.s4),
                if (used < 3)
                  PrimaryButton(
                    key: const Key('hint-reveal-more'),
                    label: 'Gợi ý rõ hơn',
                    icon: Icons.lightbulb,
                    onPressed: () => ref
                        .read(progressProvider.notifier)
                        .useHint(widget.exerciseId, _block.id),
                  ),
              ],
            ),
          );
        });
      },
    );
  }

  void _showIdleDialog() {
    if (_idleDialogOpen) return;
    _idleDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer(builder: (context, ref, _) {
          final session = ref.watch(sessionProvider(widget.exerciseId));
          return AlertDialog(
            title: const Text('Vẫn đang làm chứ?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Không có thao tác trong 2 phút. Code của bạn đã được lưu.',
                ),
                const SizedBox(height: AppSpace.s2),
                Text(
                  'Tự thoát sau ${session.idleCountdownSeconds}s',
                  key: const Key('idle-countdown'),
                  style: AppText.caption.copyWith(color: AppColors.danger),
                ),
              ],
            ),
            actions: [
              GhostButton(
                key: const Key('idle-rest-button'),
                label: 'Nghỉ',
                onPressed: () {
                  _idleDialogOpen = false;
                  Navigator.of(dialogContext).pop();
                  if (mounted) context.pop();
                },
              ),
              PrimaryButton(
                key: const Key('idle-resume-button'),
                label: 'Tiếp tục',
                onPressed: () {
                  ref
                      .read(sessionProvider(widget.exerciseId).notifier)
                      .resume();
                  _idleDialogOpen = false;
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          );
        });
      },
    ).then((_) => _idleDialogOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _exercise;
    final block = _block;
    final total = exercise.blocks.length;
    final progressMap = ref.watch(progressProvider);
    final progress = progressMap[widget.exerciseId] ??
        const ExerciseProgress(completedBlocks: 0, drafts: {}, hintsUsed: {});
    final hintsUsed = progress.hintsUsed[block.id] ?? 0;
    final draft = progress.drafts[block.id] ?? '';

    final session = ref.watch(sessionProvider(widget.exerciseId));

    ref.listen(sessionProvider(widget.exerciseId), (previous, next) {
      if (next.phase == SessionPhase.timedOut &&
          previous?.phase != SessionPhase.timedOut) {
        if (_idleDialogOpen) {
          _idleDialogOpen = false;
          Navigator.of(context, rootNavigator: true).pop();
        }
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu tiến độ')),
        );
      } else if (next.phase == SessionPhase.idle &&
          previous?.phase != SessionPhase.idle) {
        _showIdleDialog();
      }
    });

    final knownIdentifiers = knownIdentifiersFor(exercise, widget.blockIndex);
    final passed = _result?.passed ?? false;
    // Bàn phím mở → header/progress bar chiếm chỗ quý giá nhất (viewInsets
    // co lại chỉ còn vài trăm dp). Ưu tiên: dòng code đang gõ > thanh gợi ý +
    // phím ký hiệu > nút Run — đề bài/block đã xong được phép co lại/cuộn.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    final promptScroll = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.blockIndex; i++)
            _DoneBlockPreview(block: exercise.blocks[i]),
          if (widget.blockIndex > 0) const SizedBox(height: AppSpace.s4),
          Text(block.prompt, style: AppText.body),
          const SizedBox(height: AppSpace.s2),
        ],
      ),
    );

    final codeInput = CodeInput(
      initialCode: draft,
      knownIdentifiers: knownIdentifiers,
      vocab: block.vocab,
      onChanged: (code) => ref
          .read(progressProvider.notifier)
          .saveDraft(widget.exerciseId, block.id, code),
      onActivity: () =>
          ref.read(sessionProvider(widget.exerciseId).notifier).activity(),
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            if (keyboardOpen)
              _CompactHeader(
                title: block.title,
                subtitle: 'Block ${widget.blockIndex + 1}/$total',
                onBack: () => context.pop(),
              )
            else ...[
              ScreenHeader(
                title: block.title,
                subtitle: 'Block ${widget.blockIndex + 1}/$total',
                trailing: TimerPill(
                  session.elapsed,
                  warning: session.phase != SessionPhase.active,
                ),
                onBack: () => context.pop(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.s4,
                  vertical: AppSpace.s2,
                ),
                child: ThinProgressBar(value: widget.blockIndex / total),
              ),
            ],
            if (keyboardOpen) ...[
              // Đề bài/block đã xong chỉ được phần nhỏ, co lại hoặc cuộn —
              // editor lấy phần lớn còn lại (flex 3) để đủ chỗ cho gợi ý +
              // phím ký hiệu ngay trên bàn phím.
              Expanded(flex: 1, child: promptScroll),
              Expanded(flex: 3, child: codeInput),
            ] else ...[
              Expanded(child: promptScroll),
              SizedBox(height: 200, child: codeInput),
            ],
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpace.s4,
                vertical: keyboardOpen ? AppSpace.s1 : AppSpace.s2,
              ),
              child: Row(
                children: [
                  HintButton(used: hintsUsed, onPressed: _showHintSheet),
                  const Spacer(),
                  PrimaryButton(
                    key: const Key('run-button'),
                    label: 'Run',
                    icon: Icons.play_arrow,
                    onPressed: () => _runCode(draft),
                  ),
                ],
              ),
            ),
            if (_result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.s4,
                  0,
                  AppSpace.s4,
                  AppSpace.s2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ResultBadge(passed: passed),
                    const SizedBox(height: AppSpace.s2),
                    Text(
                      _result!.output,
                      style: AppText.code.copyWith(
                        color: passed ? AppColors.ink : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            if (passed)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.s4,
                  0,
                  AppSpace.s4,
                  AppSpace.s4,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: PrimaryButton(
                    key: const Key('next-block-button'),
                    label: widget.blockIndex + 1 >= total
                        ? 'Xong bài'
                        : 'Block tiếp',
                    icon: Icons.arrow_forward,
                    onPressed: _goNextOrFinish,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Header thu gọn dùng khi bàn phím đang mở: chỉ back + tên block trên một
/// dòng, không progress bar, không TimerPill — nhường chỗ cho editor.
class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.s4,
        vertical: AppSpace.s1,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Icon(Icons.arrow_back, size: 20),
          ),
          const SizedBox(width: AppSpace.s2),
          Expanded(
            child: Text(
              '$title · $subtitle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneBlockPreview extends StatelessWidget {
  const _DoneBlockPreview({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final code =
        block.acceptedAnswers.isNotEmpty ? block.acceptedAnswers.first : '';
    final indented = code
        .split('\n')
        .map((line) => '${' ' * (block.indentLevel * 4)}$line')
        .join('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, size: 16, color: AppColors.primary),
          const SizedBox(width: AppSpace.s2),
          Expanded(
            child: Text(
              indented,
              style: AppText.code.copyWith(color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
