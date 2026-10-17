/// Màn ĐỌC toàn màn hình của một tài liệu System Design: cuộn liền mạch trên
/// tờ giấy trắng, thẻ nào được lướt qua thì tự đánh dấu đã đọc.
///
/// INV-04: khoá/xong chỉ do SERVER quyết. Màn này chỉ gửi PUT cho section mà
/// trạng thái mở khoá là true; mở khoá cục bộ lấy từ `SdSection.unlocked`
/// ban đầu và chỉ được nới thêm bằng `nextSectionId` của một PUT trả
/// `done=true`. Không tự tính "done".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/sd_repository.dart';
import '../../domain/sd_models.dart';
import '../../shared/widgets.dart';
import 'block_renderer.dart';
import 'card_snap_physics.dart';
import 'reader_menu.dart';

/// Nền thanh trên (hằng riêng của màn này, không theo theme).
const Color _kBarColor = Color(0xFF0B1220);
const Color _kProgressGreen = Color(0xFF58CC02);

/// Gom nhiều lần lướt thành một PUT cho mỗi section.
const Duration kSdProgressDebounce = Duration(milliseconds: 800);

/// Lỗi tạm thời (5xx/mạng): chờ 2s, 4s, 8s... tối đa 30s rồi mới gửi lại.
const Duration kSdBackoffBase = Duration(seconds: 2);
const Duration kSdBackoffMax = Duration(seconds: 30);

/// Quá số lần lỗi liên tiếp này thì dừng gửi section đó đến khi mở lại màn.
const int kSdMaxFailures = 5;

class SdReaderScreen extends ConsumerStatefulWidget {
  const SdReaderScreen({
    super.key,
    required this.docId,
    this.sectionId,
    this.preview = false,
  });

  final String docId;

  /// Section cần mở tới; null → section mở khoá đầu tiên chưa xong.
  final String? sectionId;

  /// Chế độ xem trước: lướt toàn bộ tài liệu, KHÔNG đánh dấu đã đọc và KHÔNG
  /// gửi tiến độ nào lên server.
  final bool preview;

  @override
  ConsumerState<SdReaderScreen> createState() => _SdReaderScreenState();
}

class _SdReaderScreenState extends ConsumerState<SdReaderScreen> {
  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(sdDocProvider(widget.docId));
    return Scaffold(
      key: const Key('sd-reader'),
      backgroundColor: _kBarColor,
      body: doc.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _kProgressGreen),
        ),
        error: (e, _) => _ReaderError(
          error: e,
          onRetry: () => ref.invalidate(sdDocProvider(widget.docId)),
        ),
        data: (d) => _ReaderBody(
          doc: d,
          sectionId: widget.sectionId,
          preview: widget.preview,
        ),
      ),
    );
  }
}

class _ReaderError extends StatelessWidget {
  const _ReaderError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is SdApiException
        ? 'Không tải được (mã ${(error as SdApiException).statusCode})'
        : 'Không tải được. Kiểm tra kết nối rồi thử lại.';
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                msg,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpace.s4),
              GhostButton(
                key: const Key('sd-retry'),
                label: 'Thử lại',
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Một thẻ trong danh sách phẳng của tài liệu.
class _Flat {
  _Flat(this.section, this.card, this.index) : key = GlobalKey();
  final SdSection section;
  final SdCard card;
  final int index;
  final GlobalKey key;
}

class _ReaderBody extends ConsumerStatefulWidget {
  const _ReaderBody({
    required this.doc,
    this.sectionId,
    this.preview = false,
  });
  final SdDoc doc;
  final String? sectionId;
  final bool preview;

  @override
  ConsumerState<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends ConsumerState<_ReaderBody> {
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _flat = <_Flat>[];
  final _headerKeys = <String, GlobalKey>{};

  // Trạng thái theo section.
  final _read = <String, Set<String>>{};
  final _unlocked = <String, bool>{};
  final _dirty = <String>{}; // có thẻ đọc chưa gửi
  final _inflight = <String>{};
  final _blocked = <String>{}; // server trả 409: dừng gửi
  final _doneNotified = <String>{};
  final _timers = <String, Timer>{};
  final _fails = <String, int>{}; // số lần PUT lỗi liên tiếp theo section
  final _backoff = <String>{}; // đang chờ backoff: cuộn không được lên lịch

  // Repo + container lấy một lần: dispose không được dùng `ref`, còn
  // container thì vẫn gọi được sau khi widget đã unmount.
  late final SdRepository _repo;
  late final ProviderContainer _container;

  /// Thẻ trước chỉ số này không được đánh dấu bằng cú nhảy mở màn.
  int _startIndex = 0;

  /// > 0 khi menu đang cuộn tới một section: `_evaluate` không đánh dấu thẻ nào
  /// (thẻ chạy ngang qua trong lúc cuộn không phải thẻ người đọc đã xem).
  int _menuJumps = 0;

  final _readCount = ValueNotifier<int>(0);
  late final ValueNotifier<String> _currentTitle;

  /// Id section đang ở đầu viewport (menu tô sáng dòng này).
  late final ValueNotifier<String> _currentSectionId;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(sdRepositoryProvider);
    _container = ProviderScope.containerOf(context, listen: false);
    var i = 0;
    for (final s in widget.doc.sections) {
      final ids = {for (final c in s.cards) c.id};
      _read[s.id] = s.read.intersection(ids);
      _unlocked[s.id] = s.unlocked;
      if (s.done) _doneNotified.add(s.id);
      _headerKeys[s.id] = GlobalKey();
      for (final c in s.cards) {
        _flat.add(_Flat(s, c, i++));
      }
    }
    _recount();
    _currentTitle = ValueNotifier(
      widget.doc.sections.isEmpty ? '' : widget.doc.sections.first.title,
    );
    _currentSectionId = ValueNotifier(
      widget.doc.sections.isEmpty ? '' : widget.doc.sections.first.id,
    );
    _scroll.addListener(_evaluate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialPosition());
  }

  @override
  void dispose() {
    _scroll.removeListener(_evaluate);
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    // Gửi nốt phần đang chờ (kể cả khi chưa hết debounce). Preview: không gửi.
    for (final sid in widget.preview ? const <String>[] : _dirty) {
      if (_blocked.contains(sid) || _unlocked[sid] != true) continue;
      unawaited(
        _repo
            .putProgress(widget.doc.id, sid, _readList(sid))
            .then<void>((_) => _invalidateProgress(), onError: (Object _) {}),
      );
    }
    _scroll.dispose();
    _readCount.dispose();
    _currentTitle.dispose();
    _currentSectionId.dispose();
    super.dispose();
  }

  /// PUT xong mà màn đã đóng: lộ trình có thể đã GET trước PUT này (back nhanh
  /// hơn animation) → làm mới tiến độ. Khi còn mounted thì KHÔNG làm: màn đọc
  /// đang theo dõi sdDocProvider, invalidate sẽ dựng lại màn và mất vị trí cuộn.
  void _invalidateProgress() {
    _container.invalidate(sdDocProvider(widget.doc.id));
    _container.invalidate(sdDocsProvider);
  }

  List<String> _readList(String sid) {
    final s = widget.doc.sections.firstWhere((s) => s.id == sid);
    return [
      for (final c in s.cards)
        if (_read[sid]!.contains(c.id)) c.id,
    ];
  }

  void _recount() {
    var n = 0;
    for (final s in _read.values) {
      n += s.length;
    }
    _readCount.value = n;
  }

  int get _total => _flat.length;

  // ── Vị trí mở màn ──

  SdSection? _targetSection() {
    final secs = widget.doc.sections;
    if (widget.sectionId != null) {
      for (final s in secs) {
        if (s.id == widget.sectionId) return s;
      }
      return null;
    }
    for (final s in secs) {
      if (_unlocked[s.id] == true && !s.done) return s;
    }
    return null;
  }

  void _initialPosition() {
    if (!mounted) return;
    final s = _targetSection();
    if (s != null && s.cards.isNotEmpty) {
      final read = _read[s.id]!;
      final firstUnread = s.cards
          .where((c) => !read.contains(c.id))
          .firstOrNull;
      // Có card đã đọc → tới card chưa đọc đầu tiên; chưa đọc gì → đầu section.
      final target = read.isNotEmpty && firstUnread != null
          ? firstUnread
          : null;
      final ctx = target != null
          ? _flat
                .firstWhere(
                  (f) => f.card.id == target.id && f.section.id == s.id,
                )
                .key
                .currentContext
          : _headerKeys[s.id]?.currentContext;
      // Đặt TRƯỚC khi nhảy: cú nhảy kích hoạt listener `_evaluate` ngay, lúc đó
      // thẻ phía trên điểm mở màn không được bị đánh dấu.
      _startIndex = _flat
          .firstWhere(
            (f) =>
                f.section.id == s.id &&
                (target == null || f.card.id == target.id),
          )
          .index;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0, duration: Duration.zero);
      }
    }
    _evaluate();
  }

  // ── Bảng mốc cuộn (dùng chung cho vuốt snap và menu nhảy section: INV-04) ──

  /// Mốc của mọi card theo thứ tự tài liệu: offset cuộn để đỉnh card chạm đỉnh
  /// viewport. Card đầu section lấy đỉnh tiêu đề section (hiện cả tiêu đề), card
  /// đầu tài liệu lấy 0. Đo lại từ layout thật mỗi lần gọi (O(số card), không
  /// dựng widget). Rỗng khi chưa có layout. `sectionStart` = mốc đầu section:
  /// menu hamburger lọc theo cờ này để nhảy tới section.
  List<({double offset, String sectionId, bool sectionStart})> _anchors() {
    final vp = _viewportKey.currentContext?.findRenderObject();
    if (vp is! RenderBox ||
        !vp.attached ||
        !vp.hasSize ||
        !_scroll.hasClients) {
      return const [];
    }
    final vTop = vp.localToGlobal(Offset.zero).dy;
    final base = _scroll.offset;
    final out = <({double offset, String sectionId, bool sectionStart})>[];
    String? lastSection;
    for (final f in _flat) {
      final start = f.section.id != lastSection;
      lastSection = f.section.id;
      final ctx = (start ? _headerKeys[f.section.id] : f.key)?.currentContext;
      final box = ctx?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = base + box.localToGlobal(Offset.zero).dy - vTop;
      out.add((
        offset: out.isEmpty ? 0.0 : top,
        sectionId: f.section.id,
        sectionStart: start,
      ));
    }
    return out;
  }

  /// Hàm ổn định (tearoff) để physics không bị coi là đổi sau mỗi lần build.
  List<double> _snapOffsets() => [for (final a in _anchors()) a.offset];

  late final _snapPhysics = SdCardSnapPhysics(anchors: _snapOffsets);

  // ── Đo hình học: thẻ nào đã được lướt qua ──

  void _evaluate() {
    if (!mounted) return;
    final vp = _viewportKey.currentContext?.findRenderObject();
    if (vp is! RenderBox || !vp.attached || !vp.hasSize) return;
    final vTop = vp.localToGlobal(Offset.zero).dy;
    final vBottom = vTop + vp.size.height;

    final touched = <String>{};
    for (final f in _flat) {
      if (_menuJumps > 0 || widget.preview) break; // menu/preview: không đánh dấu
      final sid = f.section.id;
      if (_unlocked[sid] != true || _read[sid]!.contains(f.card.id)) continue;
      final box = f.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      // Mép dưới thẻ đã đi qua mép dưới vùng nhìn thấy. Thẻ phía trên điểm mở
      // màn chỉ tính khi chính người dùng cuộn ngược lên tới (còn thấy được).
      if (bottom <= vBottom + 0.5 &&
          (f.index >= _startIndex || bottom >= vTop)) {
        _read[sid]!.add(f.card.id);
        touched.add(sid);
      }
    }
    if (touched.isNotEmpty) {
      _recount();
      for (final sid in touched) {
        _dirty.add(sid);
        _schedule(sid, restart: true);
      }
    }
    // Lần gửi trước lỗi mạng: thử lại ở lần cuộn tiếp theo.
    for (final sid in _dirty.toList()) {
      if (!_timers.containsKey(sid)) _schedule(sid);
    }

    // Section đang đọc = section có tiêu đề đã chạm mép trên viewport.
    var current = widget.doc.sections.isEmpty
        ? null
        : widget.doc.sections.first;
    for (final s in widget.doc.sections) {
      final h = _headerKeys[s.id]?.currentContext?.findRenderObject();
      if (h is RenderBox && h.attached && h.hasSize) {
        if (h.localToGlobal(Offset.zero).dy <= vTop + 24) current = s;
      }
    }
    _currentTitle.value = current?.title ?? '';
    _currentSectionId.value = current?.id ?? '';
  }

  // ── Menu mục lục ──

  void _openMenu() {
    final items = <SdMenuItem>[];
    var chapterNo = 0;
    int? lastChapter;
    for (final s in widget.doc.sections) {
      if (s.chapterPosition != lastChapter) chapterNo++;
      lastChapter = s.chapterPosition;
      items.add(
        SdMenuItem(
          id: s.id,
          title: s.title,
          chapterIndex: chapterNo,
          chapterName: s.chapter,
          readCount: _read[s.id]?.length ?? 0,
          total: s.cards.length,
          // INV-01: khoá/xong chỉ theo server (unlocked ban đầu + nextSectionId,
          // done ban đầu + kết quả PUT), không đếm card cục bộ.
          state: _unlocked[s.id] != true
              ? SdMenuState.locked
              : _doneNotified.contains(s.id)
              ? SdMenuState.done
              : SdMenuState.open,
          current: s.id == _currentSectionId.value,
        ),
      );
    }
    unawaited(
      showSdReaderMenu(
        context,
        items: items,
        onSelect: (sid) => unawaited(_scrollToSection(sid)),
        onLockedTap: (_) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Hoàn thành section trước để mở khoá'),
              ),
            );
        },
      ),
    );
  }

  /// Cuộn tới đầu section [sid] theo bảng mốc chung với snap (INV-04). Không
  /// nhảy section khoá (INV-01), phòng khi gọi lạc đường.
  Future<void> _scrollToSection(String sid) async {
    if (!mounted || _unlocked[sid] != true || !_scroll.hasClients) return;
    final target = _anchors()
        .where((a) => a.sectionStart && a.sectionId == sid)
        .firstOrNull;
    if (target == null) return;
    final dest = target.offset.clamp(0.0, _scroll.position.maxScrollExtent);
    // INV-02: trong lúc cuộn không đánh dấu thẻ nào; xong thì thẻ phía trên
    // đích chỉ tính khi còn thấy được (cùng cơ chế `_startIndex` lúc mở màn).
    _menuJumps++;
    try {
      await _scroll.animateTo(
        dest,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } finally {
      _menuJumps--;
      if (mounted) {
        if (_menuJumps == 0) {
          _startIndex = _flat.firstWhere((f) => f.section.id == sid).index;
          _evaluate();
        }
      }
    }
  }

  void _schedule(String sid, {bool restart = false}) {
    if (widget.preview) return;
    if (_blocked.contains(sid) || _unlocked[sid] != true) return;
    if (_backoff.contains(sid)) return; // timer backoff tự gửi lại
    if (_inflight.contains(sid) && !restart) return;
    if (!restart && _timers.containsKey(sid)) return;
    _timers[sid]?.cancel();
    _timers[sid] = Timer(kSdProgressDebounce, () {
      _timers.remove(sid);
      unawaited(_send(sid));
    });
  }

  Future<void> _send(String sid) async {
    if (widget.preview ||
        !mounted ||
        _inflight.contains(sid) ||
        _blocked.contains(sid) ||
        _unlocked[sid] != true ||
        !_dirty.contains(sid)) {
      return;
    }
    _inflight.add(sid);
    _dirty.remove(sid);
    SdProgressResult? res;
    var failed = false;
    int? failStatus;
    try {
      res = await _repo.putProgress(widget.doc.id, sid, _readList(sid));
    } on SdApiException catch (e) {
      failed = true;
      failStatus = e.statusCode;
    } catch (_) {
      failed = true; // lỗi mạng/định dạng: coi như tạm thời
    } finally {
      _inflight.remove(sid);
    }
    if (!mounted) {
      // Màn đã đóng trong lúc chờ phản hồi: lộ trình cần tải lại tiến độ.
      if (res != null) _invalidateProgress();
      return;
    }

    if (failed) {
      if (failStatus == 409) {
        _blocked.add(sid); // section_locked: dừng, không báo lỗi
      } else if (failStatus != null && failStatus >= 400 && failStatus < 500) {
        _blocked.add(sid); // lỗi phía client: gửi lại cũng vô ích
      } else {
        _dirty.add(sid); // giữ phần chưa gửi
        final n = (_fails[sid] ?? 0) + 1;
        _fails[sid] = n;
        if (n >= kSdMaxFailures) {
          _blocked.add(sid);
        } else {
          // Backoff luỹ thừa; trong lúc chờ, cuộn không lên lịch thêm PUT.
          final ms = (kSdBackoffBase.inMilliseconds * (1 << (n - 1))).clamp(
            0,
            kSdBackoffMax.inMilliseconds,
          );
          _backoff.add(sid);
          _timers[sid]?.cancel();
          _timers[sid] = Timer(Duration(milliseconds: ms), () {
            _timers.remove(sid);
            _backoff.remove(sid);
            unawaited(_send(sid));
          });
        }
      }
      return;
    }

    if (res != null) {
      _fails.remove(sid);
      final r = res;
      // Server lấy hợp: nhận lại các thẻ nó đã biết.
      final s = widget.doc.sections.firstWhere((s) => s.id == sid);
      final ids = {for (final c in s.cards) c.id};
      _read[sid]!.addAll(r.read.intersection(ids));
      _recount();
      if (r.done) {
        final next = r.nextSectionId;
        if (next != null && _unlocked.containsKey(next)) {
          _unlocked[next] = true;
          _blocked.remove(next);
        }
        if (_doneNotified.add(sid)) _announceDone(s, next);
      }
      // Thẻ đọc thêm trong lúc chờ phản hồi → gửi tiếp.
      if (_dirty.contains(sid)) _schedule(sid, restart: true);
      // Section mới mở khoá: tính lại các thẻ đã lướt qua.
      _evaluate();
    }
  }

  void _announceDone(SdSection done, String? nextId) {
    final next = widget.doc.sections.where((s) => s.id == nextId).firstOrNull;
    final msg =
        'Xong: ${done.title}${next != null ? ' · tiếp: ${next.title}' : ''}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Giao diện ──

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _TopBar(
            readCount: _readCount,
            total: _total,
            title: _currentTitle,
            onBack: () => Navigator.of(context).maybePop(),
            onMenu: _openMenu,
          ),
          if (widget.preview)
            Container(
              key: const Key('sd-preview-banner'),
              width: double.infinity,
              color: const Color(0xFFB45309),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Text(
                'Xem trước — không tính tiến độ',
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: Colors.white),
              ),
            ),
          Expanded(
            child: Container(
              key: const Key('sd-reader-paper'),
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: kPaperColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                key: _viewportKey,
                controller: _scroll,
                physics: _snapPhysics,
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 56),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: _content(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final secs = widget.doc.sections;
    final children = <Widget>[];
    var chapterNo = 0;
    int? lastChapter;
    var flatIdx = 0;
    for (var si = 0; si < secs.length; si++) {
      final s = secs[si];
      final firstOfChapter = s.chapterPosition != lastChapter;
      if (firstOfChapter) chapterNo++;
      lastChapter = s.chapterPosition;
      if (si > 0) {
        children
          ..add(const SizedBox(height: 40))
          ..add(const Divider(height: 1, thickness: 1, color: kPaperLine))
          ..add(const SizedBox(height: 40));
      }
      final kicker = firstOfChapter
          ? 'CHAPTER $chapterNo · ${s.chapter}'
          : s.chapter;
      children.add(
        Column(
          key: _headerKeys[s.id],
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kicker.toUpperCase(),
              style: const TextStyle(
                fontFamily: kSansFamily,
                fontSize: 12,
                letterSpacing: 1,
                color: kPaperMuted,
                fontWeight: FontWeight.w700,
                fontVariations: [FontVariation('wght', 700)],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.title,
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
          ],
        ),
      );
      String? prevTitle;
      for (var ci = 0; ci < s.cards.length; ci++) {
        final f = _flat[flatIdx++];
        if (ci > 0) children.add(const SizedBox(height: 30));
        children.add(
          KeyedSubtree(
            key: Key('sd-card-${s.id}-${f.card.id}'),
            child: Container(
              key: f.key,
              child: SdBlockView(
                card: f.card,
                showTitle: f.card.title != prevTitle,
              ),
            ),
          ),
        );
        prevTitle = f.card.title;
      }
    }
    children
      ..add(const SizedBox(height: 48))
      ..add(
        const Center(
          child: Text(
            'Hết tài liệu',
            style: TextStyle(
              fontFamily: kSansFamily,
              fontSize: 14,
              color: kPaperMuted,
              fontWeight: FontWeight.w700,
              fontVariations: [FontVariation('wght', 700)],
            ),
          ),
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.readCount,
    required this.total,
    required this.title,
    required this.onBack,
    required this.onMenu,
  });

  final ValueNotifier<int> readCount;
  final int total;
  final ValueNotifier<String> title;
  final VoidCallback onBack;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            key: const Key('sd-reader-back'),
            tooltip: 'Quay lại',
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: onBack,
          ),
          IconButton(
            key: const Key('sd-reader-menu'),
            tooltip: 'Mục lục',
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: onMenu,
          ),
          Expanded(
            flex: 3,
            child: ValueListenableBuilder<int>(
              valueListenable: readCount,
              builder: (_, n, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  key: const Key('sd-reader-progress'),
                  minHeight: 6,
                  value: total == 0 ? 0 : n / total,
                  color: _kProgressGreen,
                  backgroundColor: const Color(0xFF263145),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ValueListenableBuilder<String>(
                valueListenable: title,
                builder: (_, t, _) => Text(
                  t,
                  key: const Key('sd-reader-section'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppText.caption.copyWith(color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
