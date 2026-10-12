/// Trạng thái soạn nội dung: giữ nguyên JSON của content.json, mỗi thao tác
/// sửa một bản sao mới (state bất biến) rồi đánh dấu "chưa lưu". Gửi duyệt
/// đưa thay đổi vào hàng chờ; chỉ khi duyệt thì nội dung học viên mới đổi.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/admin_repository.dart';
import '../../data/content_providers.dart';

enum AdminStatus { loading, ready, failed }

typedef Json = Map<String, dynamic>;

class AdminState {
  const AdminState({
    this.status = AdminStatus.loading,
    this.doc,
    this.version,
    this.dirty = false,
    this.errors = const [],
    this.failure,
    this.failureMessage,
    this.conflict = false,
    this.busy = false,
    this.notice,
    this.pending = const [],
    this.pendingCount = 0,
  });

  final AdminStatus status;
  final Json? doc;
  final String? version;
  final bool dirty;

  /// Lỗi nội dung từ validate/save (422).
  final List<String> errors;

  /// Lỗi không phải nội dung: forbidden / network. null = không lỗi.
  final AdminErrorKind? failure;

  /// Thông điệp riêng của [failure] (với AdminErrorKind.server).
  final String? failureMessage;

  /// Server báo content đã đổi từ lúc tải (409).
  final bool conflict;
  final bool busy;

  /// Thông báo thành công ngắn ("Hợp lệ", "Đã gửi duyệt N mục").
  final String? notice;

  /// Các mục đang chờ duyệt (tóm tắt).
  final List<PendingItem> pending;

  /// Số mục chờ. Bằng pending.length, trừ khoảnh khắc ngay sau gửi duyệt khi
  /// danh sách chưa kịp tải lại.
  final int pendingCount;

  /// Mục [itemId] loại [kind] (project|module|file|exercise) có đang chờ duyệt.
  bool isPending(String kind, String itemId) =>
      pending.any((p) => p.kind == kind && p.itemId == itemId);

  List<Json> get themes => [
    if (doc?['themes'] is List)
      for (final t in doc!['themes'] as List) t as Json,
  ];

  Json get exercises => (doc?['exercises'] as Json?) ?? const {};

  AdminState copyWith({
    AdminStatus? status,
    Json? doc,
    String? version,
    bool? dirty,
    List<String>? errors,
    AdminErrorKind? failure,
    String? failureMessage,
    bool clearFailure = false,
    bool? conflict,
    bool? busy,
    String? notice,
    bool clearNotice = false,
    List<PendingItem>? pending,
    int? pendingCount,
  }) => AdminState(
    status: status ?? this.status,
    doc: doc ?? this.doc,
    version: version ?? this.version,
    dirty: dirty ?? this.dirty,
    errors: errors ?? this.errors,
    failure: clearFailure ? null : (failure ?? this.failure),
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
    conflict: conflict ?? this.conflict,
    busy: busy ?? this.busy,
    notice: clearNotice ? null : (notice ?? this.notice),
    pending: pending ?? this.pending,
    pendingCount: pendingCount ?? this.pendingCount,
  );
}

Json _clone(Json j) => jsonDecode(jsonEncode(j)) as Json;

/// Duyệt mọi module/file/theme để tìm node theo id.
Json? _findNode(Json doc, String id) {
  Json? walkModule(Json m) {
    if (m['id'] == id) return m;
    for (final f in (m['files'] as List? ?? const [])) {
      if ((f as Json)['id'] == id) return f;
    }
    for (final sub in (m['modules'] as List? ?? const [])) {
      final hit = walkModule(sub as Json);
      if (hit != null) return hit;
    }
    return null;
  }

  for (final t in (doc['themes'] as List? ?? const [])) {
    t as Json;
    if (t['id'] == id) return t;
    for (final topic in (t['topics'] as List? ?? const [])) {
      final hit = walkModule(topic as Json);
      if (hit != null) return hit;
    }
  }
  return null;
}

void _collectIds(Json doc, Set<String> out) {
  void walk(Json m) {
    out.add(m['id'] as String);
    for (final f in (m['files'] as List? ?? const [])) {
      out.add((f as Json)['id'] as String);
    }
    for (final s in (m['modules'] as List? ?? const [])) {
      walk(s as Json);
    }
  }

  for (final t in (doc['themes'] as List? ?? const [])) {
    out.add((t as Json)['id'] as String);
    for (final topic in (t['topics'] as List? ?? const [])) {
      walk(topic as Json);
    }
  }
  final exercises = (doc['exercises'] as Json?) ?? const {};
  out.addAll(exercises.keys);
  // Server dùng chung MỘT namespace id cho theme/topic/file/bài/block.
  for (final ex in exercises.values) {
    out.addAll(_blockIds(ex));
  }
}

List<String> _blockIds(Object? exercise) => [
  if (exercise is Map && exercise['blocks'] is List)
    for (final b in exercise['blocks'] as List)
      if (b is Map && b['id'] is String) b['id'] as String,
];

const _from =
    'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to =
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Bỏ dấu tiếng Việt rồi biến mọi thứ không phải a-z0-9 thành '-'.
String _slug(String text) {
  final folded = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    final i = _from.indexOf(ch);
    folded.write(i >= 0 ? _to[i] : ch);
  }
  final s = folded
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'new' : s;
}

String _uniqueId(Json doc, String base) {
  final taken = <String>{};
  _collectIds(doc, taken);
  if (!taken.contains(base)) return base;
  var n = 2;
  while (taken.contains('$base-$n')) {
    n++;
  }
  return '$base-$n';
}

/// Bài tập nháp tối thiểu: validate() sẽ báo thiếu judge/case để admin bổ sung.
/// [className] null/rỗng → hàm top-level (không có class).
Json exerciseScaffold(
  String id,
  String title, {
  String functionName = 'run',
  String? className = 'Draft',
}) {
  final fn = functionName.trim().isEmpty ? 'run' : functionName.trim();
  final cls = className?.trim().isEmpty ?? true ? null : className!.trim();
  final template = cls == null
      ? 'def $fn():\n    # TODO A'
      : 'class $cls:\n    def $fn(self):\n        # TODO A';
  return {
    'id': id,
    'title': title,
    'class_name': cls,
    'function_name': fn,
    'params': <String>[],
    'template': template,
    'challenge': {
      'statement': '',
      'motivation': '',
      'small': {'caption': '', 'input': '', 'output': '', 'note': null},
      'project': {'caption': '', 'input': '', 'output': '', 'note': null},
    },
    'blocks': [
      {
        'id': '$id-a',
        'label': 'A',
        'title': '',
        'prompt': '',
        'indent_level': cls == null ? 1 : 2,
        'accepted_answers': <String>[],
        'expected_output': '',
        'explanation': '',
        'hints': <String>[],
        'vocab': <String>[],
      },
    ],
    'judge': {'solution': '', 'cases': <Json>[]},
  };
}

class AdminController extends Notifier<AdminState> {
  @override
  AdminState build() {
    Future.microtask(load);
    return const AdminState();
  }

  AdminRepository get _repo => ref.read(adminRepositoryProvider);

  Future<void>? _inflight;

  /// Tải (lại) từ server, bỏ mọi sửa chưa lưu. Gọi khi đang tải thì dùng lại
  /// lần tải đó.
  Future<void> load() {
    final running = _inflight;
    if (running != null) return running;
    if (state.busy) return Future.value(); // đang lưu/kiểm tra: không tải đè
    return _inflight = _load().whenComplete(() => _inflight = null);
  }

  Future<void> _load() async {
    final hasDoc = state.doc != null;
    // Đã có doc: giữ nguyên cây + dirty, chỉ khoá nút bằng busy.
    state = hasDoc
        ? state.copyWith(busy: true, clearNotice: true, clearFailure: true)
        : const AdminState();
    try {
      final d = await _repo.load();
      state = AdminState(
        status: AdminStatus.ready,
        doc: d.content,
        version: d.version,
        pending: d.pending,
        pendingCount: d.pending.length,
      );
    } on AdminError catch (e) {
      state = hasDoc
          ? state.copyWith(
              busy: false,
              failure: e.kind,
              failureMessage: e.message,
            )
          : AdminState(
              status: AdminStatus.failed,
              failure: e.kind,
              failureMessage: e.message,
            );
    }
  }

  /// Bỏ mọi sửa chưa lưu: tải lại bản trên server.
  Future<void> discardChanges() => load();

  // ---- thao tác sửa -------------------------------------------------------

  /// Áp [edit] lên bản sao của doc. Trả false nếu [edit] trả false (không đổi).
  bool _mutate(bool Function(Json doc) edit) {
    final current = state.doc;
    if (current == null) return false;
    final copy = _clone(current);
    if (!edit(copy)) return false;
    state = state.copyWith(doc: copy, dirty: true, clearNotice: true);
    return true;
  }

  /// Đổi tên/mô tả của theme, module hoặc file (file không có description).
  bool updateNode(String id, {String? name, String? description}) =>
      _mutate((doc) {
        final node = _findNode(doc, id);
        if (node == null) return false;
        if (name != null && name.trim().isEmpty) return false;
        if (name != null) node['name'] = name;
        if (description != null && !_isFile(node)) {
          node['description'] = description;
        }
        return true;
      });

  static bool _isFile(Json node) => node.containsKey('exercise_ids');

  /// Thêm module dưới theme (vào `topics`) hoặc dưới module (vào `modules`).
  /// Trả id mới, null nếu [parentId] không tồn tại.
  String? addModule(String parentId, String name, {String description = ''}) {
    String? newId;
    _mutate((doc) {
      final parent = _findNode(doc, parentId);
      if (parent == null || _isFile(parent)) return false;
      newId = _uniqueId(doc, '$parentId-${_slug(name)}');
      final module = {
        'id': newId,
        'name': name,
        'description': description,
        'files': <Json>[],
        'modules': <Json>[],
      };
      final key = parent.containsKey('topics') ? 'topics' : 'modules';
      (parent.putIfAbsent(key, () => <Json>[]) as List).add(module);
      return true;
    });
    return newId;
  }

  String? addFile(String moduleId, String name) {
    String? newId;
    _mutate((doc) {
      final module = _findNode(doc, moduleId);
      if (module == null || !module.containsKey('files')) return false;
      newId = _uniqueId(doc, '$moduleId-${_slug(name)}');
      (module['files'] as List).add({
        'id': newId,
        'name': name,
        'exercise_ids': <String>[],
      });
      return true;
    });
    return newId;
  }

  /// Thêm theme mới vào cuối `themes`. Trả id mới, null nếu [name] rỗng.
  String? addTheme(String name, {String description = ''}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    String? newId;
    _mutate((doc) {
      newId = _uniqueId(doc, _slug(trimmed));
      (doc.putIfAbsent('themes', () => <Json>[]) as List).add({
        'id': newId,
        'name': trimmed,
        'description': description,
        'tags': <String>[],
        'diagram': {'classes': <Json>[], 'relations': <Json>[]},
        'topics': <Json>[],
      });
      return true;
    });
    return newId;
  }

  /// Thêm bài nháp vào file. Trả id mới, null nếu file không tồn tại.
  /// [className] null/rỗng → hàm top-level, không có class.
  String? addExercise(
    String fileId,
    String title, {
    String functionName = 'run',
    String? className = 'Draft',
  }) {
    String? newId;
    _mutate((doc) {
      final file = _findNode(doc, fileId);
      if (file == null || !_isFile(file)) return false;
      final taken = <String>{};
      _collectIds(doc, taken);
      final base = _slug(title);
      var candidate = base;
      var n = 2;
      // Cả id bài lẫn id block scaffold ('$id-a') phải còn trống.
      while (taken.contains(candidate) || taken.contains('$candidate-a')) {
        candidate = '$base-$n';
        n++;
      }
      newId = candidate;
      (file['exercise_ids'] as List).add(newId);
      (doc.putIfAbsent('exercises', () => <String, dynamic>{})
          as Json)[newId!] = exerciseScaffold(
        newId!,
        title,
        functionName: functionName,
        className: className,
      );
      return true;
    });
    return newId;
  }

  /// Xoá bài khỏi mọi file và khỏi map `exercises`.
  bool deleteExercise(String id) => _mutate((doc) {
    final exercises = doc['exercises'] as Json?;
    if (exercises == null || !exercises.containsKey(id)) return false;
    exercises.remove(id);
    void walk(Json m) {
      for (final f in (m['files'] as List? ?? const [])) {
        ((f as Json)['exercise_ids'] as List).remove(id);
      }
      for (final s in (m['modules'] as List? ?? const [])) {
        walk(s as Json);
      }
    }

    for (final t in (doc['themes'] as List? ?? const [])) {
      for (final topic in ((t as Json)['topics'] as List? ?? const [])) {
        walk(topic as Json);
      }
    }
    return true;
  });

  /// Thay JSON của một bài. Nếu `id` trong JSON đổi, cập nhật luôn tham chiếu
  /// trong các file; id mới trùng bài khác thì từ chối (false).
  bool replaceExercise(String id, Json exercise) => _mutate((doc) {
    final exercises = doc['exercises'] as Json?;
    if (exercises == null || !exercises.containsKey(id)) return false;
    final newId = exercise['id'];
    if (newId is! String || newId.isEmpty) return false;
    // Id của mọi node KHÁC bài đang sửa (một namespace chung với block id).
    final others = <String>{};
    _collectIds({
      ...doc,
      'exercises': {...exercises}..remove(id),
    }, others);
    final mine = [newId, ..._blockIds(exercise)];
    if (mine.toSet().length != mine.length) return false;
    if (mine.any(others.contains)) return false;
    if (newId != id) {
      void walk(Json m) {
        for (final f in (m['files'] as List? ?? const [])) {
          final ids = (f as Json)['exercise_ids'] as List;
          for (var i = 0; i < ids.length; i++) {
            if (ids[i] == id) ids[i] = newId;
          }
        }
        for (final s in (m['modules'] as List? ?? const [])) {
          walk(s as Json);
        }
      }

      for (final t in (doc['themes'] as List? ?? const [])) {
        for (final topic in ((t as Json)['topics'] as List? ?? const [])) {
          walk(topic as Json);
        }
      }
      exercises.remove(id);
    }
    exercises[newId] = _clone(exercise);
    return true;
  });

  bool replaceDiagram(String themeId, Json diagram) => _mutate((doc) {
    final theme = _findNode(doc, themeId);
    if (theme == null || !theme.containsKey('topics')) return false;
    theme['diagram'] = _clone(diagram);
    return true;
  });

  // ---- đọc ----------------------------------------------------------------

  Json? exerciseJson(String id) {
    final e = state.exercises[id];
    return e is Json ? e : null;
  }

  // ---- gọi server ---------------------------------------------------------

  Future<void> validate() async {
    final doc = state.doc;
    if (doc == null || state.busy) return;
    state = state.copyWith(busy: true, clearNotice: true, clearFailure: true);
    try {
      final r = await _repo.validate(doc);
      if (!identical(state.doc, doc)) {
        state = state.copyWith(
          busy: false,
          notice: 'Nội dung đã đổi trong lúc kiểm tra, hãy kiểm tra lại',
        );
        return;
      }
      state = state.copyWith(
        busy: false,
        errors: r.errors,
        notice: r.ok ? 'Nội dung hợp lệ' : null,
      );
    } on AdminError catch (e) {
      state = state.copyWith(
        busy: false,
        failure: e.kind,
        failureMessage: e.message,
      );
    }
  }

  /// Gửi duyệt: đưa thay đổi vào hàng chờ. Nội dung học viên KHÔNG đổi ở bước
  /// này nên không nạp lại contentProvider.
  Future<void> save() async {
    final doc = state.doc;
    final base = state.version;
    if (doc == null || base == null || state.busy) return;
    state = state.copyWith(busy: true, clearNotice: true, clearFailure: true);
    try {
      final r = await _repo.save(base, doc);
      // Người dùng sửa tiếp trong lúc chờ: bản mới chưa được gửi.
      final stale = !identical(state.doc, doc);
      final sent = 'Đã gửi duyệt ${r.pending} mục';
      state = state.copyWith(
        busy: false,
        version: r.version,
        dirty: stale,
        errors: const [],
        conflict: false,
        pendingCount: r.pending,
        notice: stale ? '$sent, còn thay đổi mới chưa gửi' : sent,
      );
      await refreshPending();
    } on AdminError catch (e) {
      switch (e.kind) {
        case AdminErrorKind.conflict:
          state = state.copyWith(busy: false, conflict: true);
        case AdminErrorKind.invalid:
          state = state.copyWith(busy: false, errors: e.errors);
        case AdminErrorKind.forbidden ||
            AdminErrorKind.network ||
            AdminErrorKind.server:
          state = state.copyWith(
            busy: false,
            failure: e.kind,
            failureMessage: e.message,
          );
      }
    }
  }

  /// Tải lại danh sách mục chờ (không đụng doc/dirty). Lỗi mạng bị nuốt:
  /// giữ danh sách cũ, [AdminState.pendingCount] vẫn đúng từ lần gửi/tải trước.
  Future<void> refreshPending() async {
    try {
      final list = await _repo.changes();
      state = state.copyWith(
        pending: [
          for (final c in list)
            PendingItem(
              id: c.id,
              kind: c.kind,
              itemId: c.itemId,
              action: c.action,
            ),
        ],
        pendingCount: list.length,
      );
    } on AdminError {
      // giữ nguyên
    }
  }

  /// Danh sách đầy đủ cho màn Duyệt. Lỗi ném ra để màn tự hiển thị.
  Future<List<ContentChange>> changes() => _repo.changes();

  /// Duyệt một mục. Trả null nếu thành công, ngược lại trả lỗi (có
  /// `detail`/`message` của server) để màn Duyệt hiển thị.
  Future<AdminError?> approve(int id) => _decide(id, approve: true);

  /// Từ chối một mục (bỏ khỏi hàng chờ, live không đổi).
  Future<AdminError?> reject(int id) => _decide(id, approve: false);

  ChangeResult? _lastDecision;

  /// Kết quả của lần duyệt/bỏ thành công gần nhất (có `also`), null nếu chưa
  /// có hoặc lần gần nhất lỗi.
  ChangeResult? get lastDecision => _lastDecision;

  Future<AdminError?> _decide(int id, {required bool approve}) async {
    _lastDecision = null;
    if (state.busy) {
      return const AdminError(
        AdminErrorKind.server,
        [],
        'Đang xử lý, thử lại sau',
      );
    }
    state = state.copyWith(busy: true, clearNotice: true, clearFailure: true);
    final ChangeResult result;
    try {
      result = approve ? await _repo.approve(id) : await _repo.reject(id);
    } on AdminError catch (e) {
      state = state.copyWith(busy: false);
      return e;
    }
    state = state.copyWith(busy: false);
    // Bản nháp trên server đã đổi (hash mới = result.version). Có sửa chưa gửi
    // thì KHÔNG tải đè (mất việc): giữ doc, chỉ nhận version mới để lần gửi
    // sau không bị 409.
    if (state.dirty) {
      state = state.copyWith(
        version: result.version,
        notice: approve
            ? null
            : 'Đã bỏ mục này. Bạn đang có sửa chưa gửi — nếu gửi, '
                  'mục này sẽ được đề xuất lại.',
      );
      await refreshPending();
    } else {
      await load();
    }
    // Duyệt làm live đổi → học viên (Home/bài) thấy ngay.
    if (approve && ref.exists(contentProvider)) {
      unawaited(ref.read(contentProvider.notifier).refresh());
    }
    _lastDecision = result;
    return null;
  }
}

final adminProvider = NotifierProvider<AdminController, AdminState>(
  AdminController.new,
);
