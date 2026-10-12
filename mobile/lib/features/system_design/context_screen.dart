/// Màn BỐI CẢNH của Phase 2 (Thực chiến): đọc đề tổng thể rồi bắt đầu task.
///
/// Cùng khung với màn đọc: thanh trên tối + tờ giấy trắng bo góc, serif. Khung
/// ([SdPaperFrame]) và nút ([SdPaperButton]) được dùng lại ở màn làm task.
///
/// INV-04: mở/khoá do SERVER quyết (`phase2Unlocked`, `SdTask.unlocked/done`);
/// màn này chỉ chọn task để mở, không tự tính khoá.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/sd_repository.dart';
import '../../domain/sd_models.dart';
import 'block_renderer.dart';
import 'sd_docs_screen.dart' show SdErrorView;

/// Nền thanh trên (hằng riêng của màn Phase 2, không theo theme).
const Color kSdBarColor = Color(0xFF0B1220);
const Color kSdGreen = Color(0xFF58CC02);

/// TextButton trên tờ giấy: màu cố định (giấy luôn trắng) để ở theme tối chữ
/// không thành xanh nhạt trên nền trắng.
final ButtonStyle sdPaperTextButtonStyle = TextButton.styleFrom(
  foregroundColor: kPaperInk,
  disabledForegroundColor: kPaperMuted,
);

/// Làm mới sdDocProvider lỗi mà đã có dữ liệu cũ: màn giữ nội dung cũ (dùng
/// `skipError: true` ở `when`), chỉ báo nhỏ bằng SnackBar.
void sdListenRefreshError(WidgetRef ref, BuildContext context, String docId) {
  ref.listen<AsyncValue<SdDoc>>(sdDocProvider(docId), (_, next) {
    if (next is AsyncError<SdDoc> && next.hasValue) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Không làm mới được')));
    }
  });
}

/// Kicker nhỏ in hoa phía trên tiêu đề.
TextStyle sdKickerStyle() => const TextStyle(
  fontFamily: kSansFamily,
  fontSize: 12,
  letterSpacing: 1,
  color: kPaperMuted,
  fontWeight: FontWeight.w700,
  fontVariations: [FontVariation('wght', 700)],
);

/// Khung dùng chung: thanh trên navy (nút quay lại + [barCenter]) và tờ giấy
/// trắng bo góc 28px. [child] tự lo việc cuộn.
class SdPaperFrame extends StatelessWidget {
  const SdPaperFrame({
    super.key,
    required this.barCenter,
    required this.child,
    this.backKey = const Key('sd-phase2-back'),
  });

  final Widget barCenter;
  final Widget child;
  final Key backKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                IconButton(
                  key: backKey,
                  tooltip: 'Quay lại',
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(child: barCenter),
                const SizedBox(width: 16),
              ],
            ),
          ),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: kPaperColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nút trên tờ giấy: màu cố định (giấy luôn trắng, không theo theme tối).
class SdPaperButton extends StatelessWidget {
  const SdPaperButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    );
    const text = TextStyle(
      fontFamily: kSansFamily,
      fontSize: 15,
      fontWeight: FontWeight.w800,
      fontVariations: [FontVariation('wght', 800)],
    );
    final minSize = const Size.fromHeight(48);
    return primary
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: kSdGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: kPaperLine,
              disabledForegroundColor: kPaperMuted,
              minimumSize: minSize,
              shape: shape,
              textStyle: text,
            ),
            child: Text(label, textAlign: TextAlign.center),
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: kPaperInk,
              disabledForegroundColor: kPaperMuted,
              side: const BorderSide(color: kPaperLine, width: 2),
              minimumSize: minSize,
              shape: shape,
              textStyle: text,
            ),
            child: Text(label, textAlign: TextAlign.center),
          );
  }
}

/// Task mà nút "Bắt đầu" mở: task đầu tiên mở và chưa xong; nếu không có thì
/// task đầu (tất cả đã xong → cho làm lại/xem lại). Rỗng → null.
SdTask? sdStartTask(SdDoc doc) {
  for (final t in doc.tasks) {
    if (t.unlocked && !t.done) return t;
  }
  return doc.tasks.isEmpty ? null : doc.tasks.first;
}

class SdContextScreen extends ConsumerWidget {
  const SdContextScreen({super.key, required this.docId});

  final String docId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(sdDocProvider(docId));
    sdListenRefreshError(ref, context, docId);
    return Scaffold(
      key: const Key('sd-context'),
      backgroundColor: kSdBarColor,
      body: SdPaperFrame(
        barCenter: const SizedBox.shrink(),
        child: doc.when(
          skipError: true, // làm mới lỗi: giữ nội dung cũ
          loading: () =>
              const Center(child: CircularProgressIndicator(color: kSdGreen)),
          error: (e, _) => SdErrorView(
            error: e,
            onRetry: () => ref.invalidate(sdDocProvider(docId)),
          ),
          data: (d) => _ContextBody(doc: d),
        ),
      ),
    );
  }
}

class _ContextBody extends StatelessWidget {
  const _ContextBody({required this.doc});

  final SdDoc doc;

  @override
  Widget build(BuildContext context) {
    final start = sdStartTask(doc);
    final children = <Widget>[
      Text('PHASE 2 · THỰC CHIẾN · BỐI CẢNH', style: sdKickerStyle()),
      const SizedBox(height: 8),
      Text(
        doc.title,
        style: const TextStyle(
          fontFamily: kSansFamily,
          fontSize: 26,
          height: 1.25,
          color: kPaperInk,
          fontWeight: FontWeight.w800,
          fontVariations: [FontVariation('wght', 800)],
        ),
      ),
      const SizedBox(height: 24),
    ];

    if (!doc.phase2Unlocked) {
      // Server trả context rỗng khi Phase 2 còn khoá: chỉ nhắc, không nút.
      children.add(
        const Text(
          'Đọc xong Phase 1 để mở Thực chiến',
          key: Key('sd-context-locked'),
          style: TextStyle(
            fontFamily: kSerifFamily,
            fontSize: kBodySize,
            height: 1.7,
            color: kPaperMuted,
          ),
        ),
      );
    } else {
      String? prevTitle;
      for (var i = 0; i < doc.context.length; i++) {
        final c = doc.context[i];
        if (i > 0) children.add(const SizedBox(height: 30));
        children.add(
          KeyedSubtree(
            key: Key('sd-context-card-${c.id}'),
            child: SdBlockView(card: c, showTitle: c.title != prevTitle),
          ),
        );
        prevTitle = c.title;
      }
      if (start != null) {
        children
          ..add(const SizedBox(height: 40))
          ..add(
            SdPaperButton(
              key: const Key('sd-context-start'),
              label: 'Bắt đầu ${start.name}',
              onPressed: () => context.push(
                '/design/${Uri.encodeComponent(doc.id)}/tasks/${Uri.encodeComponent(start.id)}',
              ),
            ),
          );
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
