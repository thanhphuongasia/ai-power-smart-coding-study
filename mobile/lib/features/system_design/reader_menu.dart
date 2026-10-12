/// Menu mục lục (hamburger) của màn đọc System Design: bottom sheet trắng liệt
/// kê chapter/section kèm trạng thái xong / đang đọc / khoá.
///
/// INV-01: file này chỉ VẼ. Trạng thái (khoá, xong) do màn đọc truyền vào từ dữ
/// liệu server; menu không tự suy từ số card đã đọc. Không phụ thuộc Riverpod
/// hay router: dữ liệu vào bằng tham số, hành động ra bằng callback.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'block_renderer.dart';

/// Trạng thái server của một section (ô "đang đọc" tách riêng: xem [SdMenuItem.current]).
enum SdMenuState { done, open, locked }

const Color _kDoneGreen = Color(0xFF3FA300);
const Color _kReadingBlue = Color(0xFF1C7ED6);
const Color _kReadingTint = Color(0xFFEAF3FC);

/// Hệ số dòng dùng để tính chiều cao dòng cố định (Nunito cao hơn 1,36 một chút).
const double _kLineFactor = 1.5;

/// Một section trong menu.
class SdMenuItem {
  const SdMenuItem({
    required this.id,
    required this.title,
    required this.chapterIndex,
    required this.chapterName,
    required this.readCount,
    required this.total,
    required this.state,
    this.current = false,
  });

  final String id;
  final String title;

  /// Số thứ tự chapter hiển thị (1, 2, ...).
  final int chapterIndex;
  final String chapterName;

  /// Số card đã đọc cục bộ / tổng card: chỉ là thông tin phụ.
  final int readCount;
  final int total;
  final SdMenuState state;

  /// Section đang ở đầu viewport.
  final bool current;
}

String _semanticLabel(SdMenuItem it) {
  final s = it.state == SdMenuState.locked
      ? 'chưa mở'
      : it.state == SdMenuState.done
      ? 'đã xong'
      : it.current
      ? 'đang đọc'
      : 'chưa xong';
  return '${it.title}, $s';
}

/// Mở menu. Chạm section mở khoá → đóng sheet rồi gọi [onSelect]; chạm section
/// khoá → gọi [onLockedTap], sheet giữ nguyên.
Future<void> showSdReaderMenu(
  BuildContext context, {
  required List<SdMenuItem> items,
  required ValueChanged<String> onSelect,
  required ValueChanged<String> onLockedTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kPaperColor,
    showDragHandle: false,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height * 0.85;
      return SizedBox(
        height: height,
        // Scaffold riêng để SnackBar "khoá" hiện TRÊN sheet (Scaffold của màn
        // đọc nằm dưới lớp phủ, người dùng sẽ không thấy).
        child: Scaffold(
          key: const Key('sd-reader-menu-sheet'),
          backgroundColor: Colors.transparent,
          body: _MenuSheet(
            items: items,
            onSelect: (id) {
              Navigator.of(sheetContext).pop();
              onSelect(id);
            },
            onLockedTap: onLockedTap,
          ),
        ),
      );
    },
  );
}

/// Một dòng trong danh sách: tiêu đề chapter hoặc một section.
class _Row {
  const _Row.header(this.chapterIndex, this.chapterName) : item = null;
  const _Row.section(this.item) : chapterIndex = 0, chapterName = '';
  final int chapterIndex;
  final String chapterName;
  final SdMenuItem? item;
}

class _MenuSheet extends StatefulWidget {
  const _MenuSheet({
    required this.items,
    required this.onSelect,
    required this.onLockedTap,
  });

  final List<SdMenuItem> items;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onLockedTap;

  @override
  State<_MenuSheet> createState() => _MenuSheetState();
}

class _MenuSheetState extends State<_MenuSheet> {
  final _rows = <_Row>[];
  ScrollController? _controller;

  @override
  void initState() {
    super.initState();
    int? lastChapter;
    for (final it in widget.items) {
      if (it.chapterIndex != lastChapter) {
        _rows.add(_Row.header(it.chapterIndex, it.chapterName));
        lastChapter = it.chapterIndex;
      }
      _rows.add(_Row.section(it));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Mọi dòng có chiều cao CỐ ĐỊNH (theo cỡ chữ): cuộn sẵn tới dòng đang đọc
  // chính xác mà không cần dựng 200 dòng, và danh sách vẫn lazy.
  double _extentOf(_Row r, TextScaler scaler) => r.item == null
      ? scaler.scale(12) * _kLineFactor + 24
      : scaler.scale(16) * _kLineFactor * 2 +
            scaler.scale(12) * _kLineFactor +
            18;

  double _offsetOfCurrent(TextScaler scaler) {
    var y = 0.0;
    for (final r in _rows) {
      if (r.item?.current ?? false) break;
      y += _extentOf(r, scaler);
    }
    return (y - 80).clamp(0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    _controller ??= ScrollController(
      initialScrollOffset: _offsetOfCurrent(scaler),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Mục lục',
                  style: const TextStyle(
                    fontFamily: kSansFamily,
                    fontSize: 20,
                    color: kPaperInk,
                    fontWeight: FontWeight.w800,
                    fontVariations: [FontVariation('wght', 800)],
                  ),
                ),
              ),
              IconButton(
                key: const Key('sd-menu-close'),
                tooltip: 'Đóng',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.close, color: kPaperInk),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: kPaperLine),
        Expanded(
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: _rows.length,
            itemExtentBuilder: (i, _) => _extentOf(_rows[i], scaler),
            itemBuilder: (context, i) {
              final r = _rows[i];
              final it = r.item;
              if (it == null) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
                  child: Text(
                    'CHAPTER ${r.chapterIndex} · ${r.chapterName}'
                        .toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: kSansFamily,
                      fontSize: 12,
                      letterSpacing: 1,
                      color: kPaperMuted,
                      fontWeight: FontWeight.w700,
                      fontVariations: [FontVariation('wght', 700)],
                    ),
                  ),
                );
              }
              return _SectionRow(
                item: it,
                onTap: () => it.state == SdMenuState.locked
                    ? widget.onLockedTap(it.id)
                    : widget.onSelect(it.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.item, required this.onTap});

  final SdMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locked = item.state == SdMenuState.locked;
    final Widget icon;
    if (locked) {
      icon = const Icon(Icons.lock, size: 20, color: kPaperMuted);
    } else if (item.state == SdMenuState.done) {
      icon = const Icon(Icons.check_circle, size: 22, color: _kDoneGreen);
    } else if (item.current) {
      icon = Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: _kReadingBlue,
          shape: BoxShape.circle,
        ),
      );
    } else {
      icon = const Icon(Icons.circle_outlined, size: 20, color: kPaperMuted);
    }
    final ink = locked ? kPaperMuted : kPaperInk;
    return Semantics(
      button: true,
      label: _semanticLabel(item),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: item.current ? _kReadingTint : Colors.transparent,
        child: InkWell(
          key: Key('sd-menu-section-${item.id}'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Align(alignment: Alignment.centerLeft, child: icon),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: kSansFamily,
                            fontSize: 16,
                            color: ink,
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.readCount}/${item.total} card',
                          style: const TextStyle(
                            fontFamily: kSansFamily,
                            fontSize: 12,
                            color: kPaperMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
