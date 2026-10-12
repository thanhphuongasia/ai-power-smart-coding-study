/// Màn LÀM TASK của Phase 2: đề, gợi ý, ô viết (có bản nháp), nộp, lịch sử
/// lần thử và feedback.
///
/// INV-03: màn này hiển thị ĐÚNG bản chấm mà API trả cho từng lần thử. Việc
/// `reviewed` (Claude chấm qua MCP) thắng `auto` (chấm sơ bằng từ khoá) do
/// server quyết; client không trộn hai bản, không tự tính điểm.
/// INV-04: task khoá/xong do server quyết (`SdTask.unlocked/done`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../data/sd_repository.dart';
import '../../domain/sd_models.dart';
import 'block_renderer.dart';
import 'context_screen.dart';
import 'sd_docs_screen.dart' show SdErrorView;

/// Trần câu trả lời, tính theo BYTE UTF-8 (khớp server).
const int kSdAnswerMaxBytes = 8192;

/// Gom nhiều lần gõ thành một lần ghi bản nháp.
const Duration kSdDraftDebounce = Duration(milliseconds: 400);

const Color _kErrorColor = Color(0xFFD64545);
const Color _kOkColor = Color(0xFF2E9E4F);

/// Khoá lưu bản nháp trong SharedPreferences.
String sdDraftKey(String docId, String taskId) => 'sd-draft:$docId:$taskId';

typedef _AttemptsKey = ({String docId, String taskId});

/// Lịch sử lần thử của một task, mới nhất trước. Riêng của màn này.
class _AttemptsNotifier extends AsyncNotifier<List<SdAttempt>> {
  _AttemptsNotifier(this.key);

  final _AttemptsKey key;

  @override
  Future<List<SdAttempt>> build() =>
      ref.watch(sdRepositoryProvider).listAttempts(key.docId, key.taskId);

  /// Chèn lần thử vừa nộp lên đầu (không phải tải lại).
  void insert(SdAttempt a) {
    final cur = state.value;
    if (cur == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData([a, ...cur.where((x) => x.id != a.id)]);
  }
}

final _attemptsProvider = AsyncNotifierProvider.autoDispose
    .family<_AttemptsNotifier, List<SdAttempt>, _AttemptsKey>(
      _AttemptsNotifier.new,
      retry: sdRetry,
    );

/// Số byte UTF-8 của [s] (chữ có dấu tính 2–3 byte).
int sdUtf8Length(String s) => utf8.encode(s).length;

String _fmtScore(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toString();

/// Thông điệp cho lỗi khi nộp. Mọi lỗi đều không làm mất bản nháp.
String _submitErrorMessage(Object e) {
  if (e is SdApiException) {
    switch (e.statusCode) {
      case 409:
        return 'Task này chưa mở';
      case 429:
        return 'Hôm nay bạn đã nộp tối đa 20 lần cho task này';
      case 422:
        return 'Câu trả lời chưa hợp lệ';
    }
  }
  return 'Không gửi được. Bản nháp vẫn còn, thử lại sau';
}

class SdTaskScreen extends ConsumerWidget {
  const SdTaskScreen({super.key, required this.docId, required this.taskId});

  final String docId;
  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(sdDocProvider(docId));
    return Scaffold(
      key: const Key('sd-task-screen'),
      backgroundColor: kSdBarColor,
      body: doc.when(
        loading: () => const SdPaperFrame(
          barCenter: SizedBox.shrink(),
          child: Center(child: CircularProgressIndicator(color: kSdGreen)),
        ),
        error: (e, _) => SdPaperFrame(
          barCenter: const SizedBox.shrink(),
          child: SdErrorView(
            error: e,
            onRetry: () => ref.invalidate(sdDocProvider(docId)),
          ),
        ),
        data: (d) {
          final i = d.tasks.indexWhere((t) => t.id == taskId);
          if (i < 0) {
            return const SdPaperFrame(
              barCenter: SizedBox.shrink(),
              child: Center(
                child: Text('Không tìm thấy task', key: Key('sd-task-missing')),
              ),
            );
          }
          final done = d.tasks.where((t) => t.done).length;
          return SdPaperFrame(
            backKey: const Key('sd-task-back'),
            barCenter: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      key: const Key('sd-task-progress'),
                      minHeight: 6,
                      value: d.tasks.isEmpty ? 0 : done / d.tasks.length,
                      color: kSdGreen,
                      backgroundColor: const Color(0xFF263145),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Task ${i + 1}/${d.tasks.length}',
                  key: const Key('sd-task-index'),
                  style: AppText.caption.copyWith(color: Colors.white70),
                ),
              ],
            ),
            child: _TaskBody(
              key: ValueKey('${d.id}/$taskId/${d.tasks[i].unlocked}'),
              docId: d.id,
              task: d.tasks[i],
              next: i + 1 < d.tasks.length ? d.tasks[i + 1] : null,
            ),
          );
        },
      ),
    );
  }
}

class _TaskBody extends ConsumerStatefulWidget {
  const _TaskBody({
    super.key,
    required this.docId,
    required this.task,
    required this.next,
  });

  final String docId;
  final SdTask task;
  final SdTask? next;

  @override
  ConsumerState<_TaskBody> createState() => _TaskBodyState();
}

class _TaskBodyState extends ConsumerState<_TaskBody> {
  final _text = TextEditingController();
  Timer? _debounce;
  bool _restoring =
      false; // đang gán chữ từ bản nháp/xoá sau nộp: không ghi lại
  bool _draftReady =
      false; // đã đọc xong bản nháp cũ (chưa xong thì đừng xoá nó)
  bool _sending = false;
  String? _error;
  final _hintOpen = <int>{};
  final _attemptOpen = <int, bool>{}; // ghi đè mặc định (mới nhất mở sẵn)

  String get _key => sdDraftKey(widget.docId, widget.task.id);
  _AttemptsKey get _akey => (docId: widget.docId, taskId: widget.task.id);

  @override
  void initState() {
    super.initState();
    if (widget.task.unlocked) {
      _text.addListener(_onChanged);
      unawaited(_restoreDraft());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Ghi nốt bản nháp (kể cả khi chưa hết debounce). Không dùng `ref` ở đây.
    if (widget.task.unlocked && (_draftReady || _text.text.isNotEmpty)) {
      unawaited(_writeDraft(_key, _text.text));
    }
    _text.dispose();
    super.dispose();
  }

  static Future<void> _writeDraft(String key, String text) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (text.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, text);
      }
    } catch (_) {
      // Không ghi được bản nháp thì thôi; không chặn người dùng.
    }
  }

  Future<void> _restoreDraft() async {
    String? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getString(_key);
    } catch (_) {}
    if (!mounted) return;
    _draftReady = true;
    // Người dùng đã gõ trước khi đọc xong → giữ chữ đang gõ.
    if (saved == null || _text.text.isNotEmpty) return;
    _restoring = true;
    _text.text = saved;
    _restoring = false;
    setState(() {}); // cập nhật bộ đếm + nút nộp
  }

  void _onChanged() {
    if (_restoring) return;
    setState(() => _error = null);
    final key = _key;
    _debounce?.cancel();
    _debounce = Timer(kSdDraftDebounce, () {
      unawaited(_writeDraft(key, _text.text));
    });
  }

  Future<void> _submit() async {
    final text = _text.text;
    setState(() {
      _sending = true;
      _error = null;
    });
    final repo = ref.read(sdRepositoryProvider);
    final key = _key;
    try {
      final attempt = await repo.submitAttempt(
        widget.docId,
        widget.task.id,
        text,
      );
      _debounce?.cancel();
      // Nộp thành công mới xoá nháp.
      await _writeDraft(key, '');
      if (!mounted) return;
      _restoring = true;
      _text.clear();
      _restoring = false;
      ref.read(_attemptsProvider(_akey).notifier).insert(attempt);
      // Task kế có thể vừa mở khoá, tiến độ doc/danh sách đổi.
      ref.invalidate(sdDocProvider(widget.docId));
      ref.invalidate(sdDocsProvider);
      setState(() => _sending = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _submitErrorMessage(e);
      });
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(_attemptsProvider(_akey));
    ref.invalidate(sdDocProvider(widget.docId)); // feedback có thể đổi `done`
    try {
      await ref.read(_attemptsProvider(_akey).future);
    } catch (_) {}
  }

  void _goNext() {
    final next = widget.next;
    if (next != null && next.unlocked) {
      context.pushReplacement('/design/${widget.docId}/tasks/${next.id}');
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final children = <Widget>[
      Text('PHASE 2 · THỰC CHIẾN', style: sdKickerStyle()),
      const SizedBox(height: 8),
      Text(
        task.name,
        key: const Key('sd-task-name'),
        style: const TextStyle(
          fontFamily: kSansFamily,
          fontSize: 26,
          height: 1.25,
          color: kPaperInk,
          fontWeight: FontWeight.w800,
          fontVariations: [FontVariation('wght', 800)],
        ),
      ),
      const SizedBox(height: 20),
    ];

    if (!task.unlocked) {
      children.add(
        const Text(
          'Task này chưa mở. Làm task trước để mở khoá.',
          key: Key('sd-task-locked'),
          style: TextStyle(
            fontFamily: kSerifFamily,
            fontSize: kBodySize,
            height: 1.7,
            color: kPaperMuted,
          ),
        ),
      );
    } else {
      children.addAll(_unlockedChildren(task));
    }

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 56),
      children: children,
    );
    return task.unlocked
        ? RefreshIndicator(onRefresh: _refresh, child: list)
        : list;
  }

  List<Widget> _unlockedChildren(SdTask task) {
    final bytes = sdUtf8Length(_text.text);
    final tooLong = bytes > kSdAnswerMaxBytes;
    final canSubmit = !_sending && !tooLong && _text.text.trim().isNotEmpty;
    final attempts = ref.watch(_attemptsProvider(_akey));
    final list = attempts.value;

    return [
      if (task.prompt != null && task.prompt!.isNotEmpty) ...[
        Text(
          task.prompt!,
          key: const Key('sd-task-prompt'),
          style: const TextStyle(
            fontFamily: kSerifFamily,
            fontSize: kBodySize,
            height: 1.7,
            color: kPaperInk,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 20),
      ],
      for (var i = 0; i < task.hints.length; i++) _hint(i, task.hints[i]),
      if (task.hints.isNotEmpty) const SizedBox(height: 12),
      TextField(
        key: const Key('sd-task-input'),
        controller: _text,
        readOnly: _sending,
        minLines: 8,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(
          fontFamily: kSerifFamily,
          fontSize: 17,
          height: 1.5,
          color: kPaperInk,
        ),
        decoration: InputDecoration(
          hintText: 'Viết câu trả lời của bạn…',
          hintStyle: const TextStyle(color: kPaperMuted),
          filled: true,
          fillColor: const Color(0xFFF4F5F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPaperLine),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPaperLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kSdGreen, width: 2),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$bytes/$kSdAnswerMaxBytes',
          key: const Key('sd-task-counter'),
          style: AppText.caption.copyWith(
            color: tooLong ? _kErrorColor : kPaperMuted,
          ),
        ),
      ),
      if (tooLong)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Câu trả lời quá dài (tối đa $kSdAnswerMaxBytes byte)',
            key: Key('sd-task-too-long'),
            style: TextStyle(color: _kErrorColor),
          ),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _error!,
            key: const Key('sd-task-error'),
            style: const TextStyle(color: _kErrorColor),
          ),
        ),
      const SizedBox(height: 12),
      SdPaperButton(
        key: const Key('sd-task-submit'),
        label: _sending ? 'Đang chấm…' : 'Chấm bài',
        onPressed: canSubmit ? _submit : null,
      ),
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(child: Text('LỊCH SỬ LẦN THỬ', style: sdKickerStyle())),
          TextButton(
            key: const Key('sd-task-refresh'),
            onPressed: _refresh,
            child: const Text('Làm mới'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (list != null) ...[
        if (list.isEmpty)
          const Text(
            'Chưa có lần thử nào',
            key: Key('sd-attempts-empty'),
            style: TextStyle(color: kPaperMuted),
          ),
        for (var i = 0; i < list.length; i++)
          _AttemptCard(
            attempt: list[i],
            open: _attemptOpen[list[i].id] ?? i == 0,
            onToggle: () => setState(
              () => _attemptOpen[list[i].id] =
                  !(_attemptOpen[list[i].id] ?? i == 0),
            ),
          ),
      ] else if (attempts.hasError)
        Column(
          key: const Key('sd-attempts-error'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Không tải được lịch sử lần thử',
              style: TextStyle(color: _kErrorColor),
            ),
            TextButton(
              key: const Key('sd-attempts-retry'),
              onPressed: () => ref.invalidate(_attemptsProvider(_akey)),
              child: const Text('Thử lại'),
            ),
          ],
        )
      else
        const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(color: kSdGreen),
          ),
        ),
      if (task.refSectionId != null) ...[
        const SizedBox(height: 16),
        SdPaperButton(
          key: const Key('sd-task-ref'),
          label: 'Xem đáp án mẫu',
          primary: false,
          onPressed: () => context.push(
            '/design/${widget.docId}/read?section=${Uri.encodeQueryComponent(task.refSectionId!)}',
          ),
        ),
      ],
      if (widget.next != null && list != null && list.isNotEmpty) ...[
        const SizedBox(height: 12),
        SdPaperButton(
          key: const Key('sd-task-next'),
          label: 'Task tiếp theo',
          onPressed: _goNext,
        ),
      ],
    ];
  }

  Widget _hint(int i, String text) {
    final open = _hintOpen.contains(i);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4D6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: Key('sd-hint-$i'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() {
                open ? _hintOpen.remove(i) : _hintOpen.add(i);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: kPaperInk,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Gợi ý ${i + 1}',
                        style: AppText.label.copyWith(color: kPaperInk),
                      ),
                    ),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: kPaperInk,
                    ),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text(
                  text,
                  key: Key('sd-hint-text-$i'),
                  style: const TextStyle(
                    fontFamily: kSerifFamily,
                    fontSize: 16,
                    height: 1.6,
                    color: kPaperInk,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Một lần thử: hiển thị đúng dữ liệu API trả (INV-03), không tự tính gì.
class _AttemptCard extends StatelessWidget {
  const _AttemptCard({
    required this.attempt,
    required this.open,
    required this.onToggle,
  });

  final SdAttempt attempt;
  final bool open;
  final VoidCallback onToggle;

  String get _sourceLabel => switch (attempt.source) {
    'auto' => 'Chấm sơ bằng từ khoá',
    'reviewed' => 'Claude đã chấm',
    final s => s,
  };

  @override
  Widget build(BuildContext context) {
    final a = attempt;
    final feedback = a.feedback;
    return Padding(
      key: Key('sd-attempt-${a.n}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: kPaperLine, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: Key('sd-attempt-head-${a.n}'),
              borderRadius: BorderRadius.circular(14),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lần ${a.n} · ${_fmtScore(a.score)} điểm',
                            style: AppText.label.copyWith(color: kPaperInk),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _sourceLabel,
                            key: Key('sd-attempt-source-${a.n}'),
                            style: AppText.caption.copyWith(
                              color: a.source == 'reviewed'
                                  ? _kOkColor
                                  : kPaperMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: kPaperMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final it in a.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.ok ? '✓' : '✗',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: it.ok ? _kOkColor : _kErrorColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.text,
                                    style: const TextStyle(
                                      fontFamily: kSerifFamily,
                                      fontSize: 16,
                                      height: 1.5,
                                      color: kPaperInk,
                                    ),
                                  ),
                                  if (it.note.isNotEmpty)
                                    Text(
                                      it.note,
                                      style: AppText.caption.copyWith(
                                        color: kPaperMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (feedback != null && feedback.isNotEmpty)
                      Container(
                        key: Key('sd-attempt-feedback-${a.n}'),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF7EE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          feedback,
                          style: const TextStyle(
                            fontFamily: kSerifFamily,
                            fontSize: 16,
                            height: 1.6,
                            color: kPaperInk,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
