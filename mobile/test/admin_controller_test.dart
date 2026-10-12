import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/data/admin_repository.dart';
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/data/content_repository.dart';
import 'package:smart_coding_study/features/admin/admin_controller.dart';

import 'support/admin_fixture.dart' show sampleChange, samplePending;

/// Response JSON utf-8 (http.Response mặc định latin1 sẽ ném với tiếng Việt).
http.Response jsonResponse(String body, int status) => http.Response(
  body,
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> sampleContent() => {
  'version': 'x',
  'themes': [
    {
      'id': 't1',
      'name': 'Theme 1',
      'description': 'd',
      'tags': <String>[],
      'diagram': {'classes': <dynamic>[]},
      'topics': [
        {
          'id': 'm1',
          'name': 'Module 1',
          'description': 'md',
          'files': [
            {
              'id': 'f1',
              'name': 'a.py',
              'exercise_ids': ['e1', 'e2'],
            },
          ],
          'modules': <dynamic>[],
        },
      ],
    },
  ],
  'exercises': {
    'e1': {'id': 'e1', 'title': 'One'},
    'e2': {'id': 'e2', 'title': 'Two'},
  },
};

class Server {
  Server({this.putStatus = 200, this.putBody, this.validateBody});

  /// Mục chờ duyệt server trả (GET content.pending và GET changes).
  List<Map<String, dynamic>> changes = [];
  int decideStatus = 200;
  Map<String, dynamic>? decideBody;
  int changesStatus = 200;
  Completer<void>? putGate;
  Completer<void>? getGate;
  Map<String, dynamic>? Function()? content;
  int getStatus = 200;
  int putStatus;

  /// Nếu đặt: PUT có base_version khác giá trị này → 409 version_conflict.
  String? putExpectBase;
  Map<String, dynamic>? putBody;
  Map<String, dynamic>? validateBody;
  final requests = <http.Request>[];

  http.Client get client => MockClient((r) async {
    requests.add(r);
    final path = r.url.path;
    if (r.method == 'GET' && path == '/api/admin/content') {
      await getGate?.future;
      if (getStatus != 200) return jsonResponse('{}', getStatus);
      return jsonResponse(
        jsonEncode({
          'version': 'v1',
          'content': content?.call() ?? sampleContent(),
          'pending': [
            for (final c in changes)
              samplePending(
                id: c['id'] as int,
                kind: c['kind'] as String,
                itemId: c['item_id'] as String,
                action: c['action'] as String,
              ),
          ],
        }),
        200,
      );
    }
    if (r.method == 'GET' && path == '/api/admin/changes') {
      return jsonResponse(jsonEncode({'changes': changes}), changesStatus);
    }
    final decide = RegExp(
      r'^/api/admin/changes/(\d+)/(approve|reject)$',
    ).firstMatch(path);
    if (r.method == 'POST' && decide != null) {
      final id = int.parse(decide.group(1)!);
      if (decideStatus == 200) {
        changes.removeWhere((c) => c['id'] == id);
      }
      return jsonResponse(
        jsonEncode(
          decideBody ??
              {
                'id': id,
                'status': decide.group(2) == 'approve'
                    ? 'approved'
                    : 'rejected',
                'version': 'v3',
              },
        ),
        decideStatus,
      );
    }
    if (r.method == 'POST' && path == '/api/admin/validate') {
      return jsonResponse(
        jsonEncode(validateBody ?? {'ok': true, 'errors': <String>[]}),
        200,
      );
    }
    if (r.method == 'PUT' && path == '/api/admin/content') {
      await putGate?.future;
      if (putExpectBase != null &&
          (jsonDecode(r.body) as Map)['base_version'] != putExpectBase) {
        return jsonResponse('{"detail":"version_conflict"}', 409);
      }
      return jsonResponse(
        jsonEncode(putBody ?? {'version': 'v2', 'pending': 1}),
        putStatus,
      );
    }
    return http.Response('', 404);
  });
}

Future<ProviderContainer> boot(Server server) async {
  final c = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(
        AdminRepository(server.client, baseUrl: Uri.parse('http://x')),
      ),
    ],
  );
  addTearDown(c.dispose);
  c.listen(adminProvider, (_, _) {});
  await c.read(adminProvider.notifier).load();
  return c;
}

void main() {
  test('load: nạp doc + version, chưa dirty', () async {
    final c = await boot(Server());
    final s = c.read(adminProvider);
    expect(s.status, AdminStatus.ready);
    expect(s.version, 'v1');
    expect(s.dirty, isFalse);
    expect(s.themes.single['id'], 't1');
  });

  test('load 403 → failed/forbidden', () async {
    final c = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(
          AdminRepository(
            MockClient((_) async => http.Response('', 403)),
            baseUrl: Uri.parse('http://x'),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(adminProvider, (_, _) {});
    await c.read(adminProvider.notifier).load();
    expect(c.read(adminProvider).status, AdminStatus.failed);
    expect(c.read(adminProvider).failure, AdminErrorKind.forbidden);
  });

  test(
    'updateNode đổi tên/mô tả theme, module, file; file bỏ qua mô tả',
    () async {
      final c = await boot(Server());
      final ctl = c.read(adminProvider.notifier);
      ctl.updateNode('t1', name: 'T', description: 'TD');
      ctl.updateNode('m1', name: 'M', description: 'MD');
      ctl.updateNode('f1', name: 'b.py', description: 'ignored');
      final s = c.read(adminProvider);
      expect(s.dirty, isTrue);
      final t = s.themes.single;
      expect(t['name'], 'T');
      expect(t['description'], 'TD');
      final m = (t['topics'] as List).single as Map;
      expect(m['name'], 'M');
      expect(m['description'], 'MD');
      final f = (m['files'] as List).single as Map;
      expect(f['name'], 'b.py');
      expect(f.containsKey('description'), isFalse);
      expect(ctl.updateNode('nope', name: 'x'), isFalse);
    },
  );

  test(
    'addModule dưới theme → topics; dưới module → modules; id duy nhất',
    () async {
      final c = await boot(Server());
      final ctl = c.read(adminProvider.notifier);
      final a = ctl.addModule('t1', 'Sub A');
      final b = ctl.addModule('m1', 'Deep');
      final a2 = ctl.addModule('t1', 'Sub A');
      expect(a, 't1-sub-a');
      expect(a2, 't1-sub-a-2');
      expect(b, 'm1-deep');
      final t = c.read(adminProvider).themes.single;
      expect((t['topics'] as List).length, 3);
      final m1 = (t['topics'] as List).first as Map;
      expect((m1['modules'] as List).single['id'], 'm1-deep');
      expect(ctl.addModule('f1', 'x'), isNull); // file không chứa module
    },
  );

  test('addFile + addExercise tạo scaffold nháp', () async {
    final c = await boot(Server());
    final ctl = c.read(adminProvider.notifier);
    final fid = ctl.addFile('m1', 'b.py');
    expect(fid, 'm1-b-py');
    final eid = ctl.addExercise(fid!, 'Làm gì đó');
    expect(eid, 'lam-gi-do');
    final s = c.read(adminProvider);
    final m = (s.themes.single['topics'] as List).single as Map;
    final file = (m['files'] as List).last as Map;
    expect(file['exercise_ids'], [eid]);
    final ex = s.exercises[eid] as Map;
    expect(ex['title'], 'Làm gì đó');
    expect((ex['blocks'] as List).length, 1);
    expect(ex['template'], contains('# TODO A'));
    expect((ex['judge'] as Map)['cases'], isEmpty);
    expect(ctl.addExercise('m1', 'x'), isNull); // m1 không phải file
  });

  test('deleteExercise gỡ khỏi file và map exercises', () async {
    final c = await boot(Server());
    final ctl = c.read(adminProvider.notifier);
    expect(ctl.deleteExercise('e1'), isTrue);
    final s = c.read(adminProvider);
    expect(s.exercises.keys, ['e2']);
    final m = (s.themes.single['topics'] as List).single as Map;
    expect(((m['files'] as List).single as Map)['exercise_ids'], ['e2']);
    expect(ctl.deleteExercise('e1'), isFalse);
  });

  test(
    'replaceExercise: đổi nội dung; đổi id cập nhật tham chiếu; trùng id bị từ chối',
    () async {
      final c = await boot(Server());
      final ctl = c.read(adminProvider.notifier);
      expect(ctl.replaceExercise('e1', {'id': 'e1', 'title': 'Mới'}), isTrue);
      expect((c.read(adminProvider).exercises['e1'] as Map)['title'], 'Mới');

      expect(ctl.replaceExercise('e1', {'id': 'e3', 'title': 'R'}), isTrue);
      var s = c.read(adminProvider);
      expect(s.exercises.containsKey('e1'), isFalse);
      expect(s.exercises.containsKey('e3'), isTrue);
      final m = (s.themes.single['topics'] as List).single as Map;
      expect(((m['files'] as List).single as Map)['exercise_ids'], [
        'e3',
        'e2',
      ]);

      expect(ctl.replaceExercise('e3', {'id': 'e2', 'title': 'dup'}), isFalse);
      expect(ctl.replaceExercise('e3', {'title': 'noid'}), isFalse);
    },
  );

  test('replaceDiagram thay diagram của theme', () async {
    final c = await boot(Server());
    final ctl = c.read(adminProvider.notifier);
    expect(
      ctl.replaceDiagram('t1', {
        'classes': [
          {'name': 'A'},
        ],
      }),
      isTrue,
    );
    expect(
      (c.read(adminProvider).themes.single['diagram'] as Map)['classes'],
      hasLength(1),
    );
    expect(ctl.replaceDiagram('m1', {}), isFalse); // không phải theme
  });

  test('validate: lỗi được lưu, ok → notice; không đổi dirty', () async {
    final server = Server(
      validateBody: {
        'ok': false,
        'errors': ['e1: thiếu judge', 'e2: thiếu case'],
      },
    );
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    await ctl.validate();
    expect(c.read(adminProvider).errors, ['e1: thiếu judge', 'e2: thiếu case']);
    final sent = jsonDecode(server.requests.last.body) as Map;
    expect((sent['content'] as Map)['themes'], isNotEmpty);

    server.validateBody = {'ok': true, 'errors': <String>[]};
    await ctl.validate();
    expect(c.read(adminProvider).errors, isEmpty);
    expect(c.read(adminProvider).notice, isNotNull);
  });

  test('save gửi base_version; thành công → version mới, hết dirty', () async {
    final server = Server()..changes = [sampleChange()];
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.save();
    final put = server.requests.lastWhere((r) => r.method == 'PUT');
    expect(put.method, 'PUT');
    final body = jsonDecode(put.body) as Map;
    expect(body['base_version'], 'v1');
    expect(((body['content'] as Map)['themes'] as List).first['name'], 'Đổi');
    final s = c.read(adminProvider);
    expect(s.version, 'v2');
    expect(s.dirty, isFalse);
    expect(s.notice, 'Đã gửi duyệt 1 mục');
    expect(s.pendingCount, 1);
    expect(s.isPending('project', 't1'), isTrue);
  });

  test('load đọc pending từ /content', () async {
    final c = await boot(Server()..changes = [sampleChange(id: 7)]);
    final s = c.read(adminProvider);
    expect(s.pending.single.id, 7);
    expect(s.pendingCount, 1);
    expect(s.isPending('project', 't1'), isTrue);
    expect(s.isPending('module', 't1'), isFalse);
  });

  test('load không có field pending (server cũ) → rỗng', () async {
    final c = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(
          AdminRepository(
            MockClient(
              (_) async => jsonResponse(
                jsonEncode({'version': 'v1', 'content': sampleContent()}),
                200,
              ),
            ),
            baseUrl: Uri.parse('http://x'),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(adminProvider, (_, _) {});
    await c.read(adminProvider.notifier).load();
    expect(c.read(adminProvider).pending, isEmpty);
    expect(c.read(adminProvider).pendingCount, 0);
  });

  test('save thành công KHÔNG đụng contentProvider của học viên', () async {
    var refreshed = 0;
    final server = Server();
    final c = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(
          AdminRepository(server.client, baseUrl: Uri.parse('http://x')),
        ),
        contentProvider.overrideWith(() => _CountingContent(() => refreshed++)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(adminProvider, (_, _) {});
    c.listen(contentProvider, (_, _) {});
    final ctl = c.read(adminProvider.notifier);
    await ctl.load();
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.save();
    expect(refreshed, 0);
  });

  test('refreshPending lỗi mạng → giữ pendingCount từ lần gửi', () async {
    final server = Server()..changesStatus = 500;
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.save();
    final s = c.read(adminProvider);
    expect(s.pendingCount, 1);
    expect(s.pending, isEmpty);
    expect(s.failure, isNull);
  });

  test(
    'approve: thành công → reload nháp + pending, nạp lại /content',
    () async {
      var refreshed = 0;
      final server = Server()
        ..changes = [
          sampleChange(id: 1),
          sampleChange(id: 2, itemId: 'm1', kind: 'module'),
        ];
      final c = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            AdminRepository(server.client, baseUrl: Uri.parse('http://x')),
          ),
          contentProvider.overrideWith(
            () => _CountingContent(() => refreshed++),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(adminProvider, (_, _) {});
      c.listen(contentProvider, (_, _) {});
      final ctl = c.read(adminProvider.notifier);
      await ctl.load();
      expect(c.read(adminProvider).pendingCount, 2);

      final err = await ctl.approve(1);
      expect(err, isNull);
      final post = server.requests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '/api/admin/changes/1/approve');
      final s = c.read(adminProvider);
      expect(s.pending.map((p) => p.id), [2]);
      expect(s.pendingCount, 1);
      expect(s.busy, isFalse);
      expect(refreshed, 1);
    },
  );

  test('reject: thành công → reload, KHÔNG nạp lại /content', () async {
    var refreshed = 0;
    final server = Server()..changes = [sampleChange(id: 1)];
    final c = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(
          AdminRepository(server.client, baseUrl: Uri.parse('http://x')),
        ),
        contentProvider.overrideWith(() => _CountingContent(() => refreshed++)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(adminProvider, (_, _) {});
    c.listen(contentProvider, (_, _) {});
    final ctl = c.read(adminProvider.notifier);
    await ctl.load();
    expect(await ctl.reject(1), isNull);
    expect(
      server.requests.lastWhere((r) => r.method == 'POST').url.path,
      '/api/admin/changes/1/reject',
    );
    expect(c.read(adminProvider).pending, isEmpty);
    expect(refreshed, 0);
  });

  test('approve khi đang có sửa chưa gửi → không tải đè doc', () async {
    final server = Server()..changes = [sampleChange(id: 1)];
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đang sửa');
    expect(await ctl.approve(1), isNull);
    final s = c.read(adminProvider);
    expect(s.dirty, isTrue);
    expect(s.themes.single['name'], 'Đang sửa');
    expect(s.pending, isEmpty);
  });

  test('dirty → approve → save() gửi base_version mới, không 409', () async {
    final server = Server()
      ..changes = [sampleChange(id: 1)]
      ..putExpectBase = 'v3';
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đang sửa');
    expect(await ctl.approve(1), isNull);
    var s = c.read(adminProvider);
    expect(s.version, 'v3');
    expect(s.dirty, isTrue);
    expect(s.themes.single['name'], 'Đang sửa');
    await ctl.save();
    s = c.read(adminProvider);
    expect(s.conflict, isFalse);
    expect(s.dirty, isFalse);
    expect(s.version, 'v2');
  });

  test(
    'dirty → reject → version mới + notice nói rõ, save không 409',
    () async {
      final server = Server()
        ..changes = [sampleChange(id: 1)]
        ..putExpectBase = 'v3';
      final c = await boot(server);
      final ctl = c.read(adminProvider.notifier);
      ctl.updateNode('t1', name: 'Đang sửa');
      expect(await ctl.reject(1), isNull);
      var s = c.read(adminProvider);
      expect(s.version, 'v3');
      expect(s.dirty, isTrue);
      expect(s.notice, contains('đề xuất lại'));
      await ctl.save();
      s = c.read(adminProvider);
      expect(s.conflict, isFalse);
      expect(s.dirty, isFalse);
    },
  );

  test('không dirty → approve: tải lại, version theo server', () async {
    final server = Server()..changes = [sampleChange(id: 1)];
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    expect(await ctl.approve(1), isNull);
    final s = c.read(adminProvider);
    expect(s.dirty, isFalse);
    expect(s.version, 'v1'); // load() lấy version GET
  });

  test('404 trơn {"detail":"Not Found"} vẫn là network', () async {
    final server = Server()
      ..decideStatus = 404
      ..decideBody = {'detail': 'Not Found'};
    final c = await boot(server);
    final err = await c.read(adminProvider.notifier).approve(1);
    expect(err!.kind, AdminErrorKind.network);
  });

  test(
    'approve 409 item_conflict → trả lỗi có message, state giữ nguyên',
    () async {
      final server = Server()
        ..changes = [sampleChange(id: 1)]
        ..decideStatus = 409
        ..decideBody = {
          'detail': 'item_conflict',
          'message': 'Mục đã bị đổi bởi thay đổi khác',
          'errors': ['xung đột t1'],
        };
      final c = await boot(server);
      final ctl = c.read(adminProvider.notifier);
      final err = await ctl.approve(1);
      expect(err, isNotNull);
      expect(err!.kind, AdminErrorKind.conflict);
      expect(err.detail, 'item_conflict');
      expect(err.message, 'Mục đã bị đổi bởi thay đổi khác');
      expect(err.errors, ['xung đột t1']);
      final s = c.read(adminProvider);
      expect(s.busy, isFalse);
      expect(
        s.conflict,
        isFalse,
      ); // không nhầm với xung đột version khi gửi duyệt
      expect(s.pending, hasLength(1));
    },
  );

  test('approve 422 dependency_missing / 404 change_not_found', () async {
    final server = Server()
      ..decideStatus = 422
      ..decideBody = {
        'detail': 'dependency_missing',
        'message': 'Thiếu module cha',
        'errors': ['module m9'],
      };
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    var err = await ctl.approve(1);
    expect(err!.kind, AdminErrorKind.invalid);
    expect(err.detail, 'dependency_missing');
    expect(err.message, 'Thiếu module cha');
    expect(err.errors, ['module m9']);

    server
      ..decideStatus = 404
      ..decideBody = {'detail': 'change_not_found', 'message': 'Mục không còn'};
    err = await ctl.reject(1);
    expect(err!.kind, AdminErrorKind.server);
    expect(err.detail, 'change_not_found');
    expect(err.message, 'Mục không còn');

    server
      ..decideStatus = 403
      ..decideBody = {};
    err = await ctl.approve(1);
    expect(err!.kind, AdminErrorKind.forbidden);
  });

  test('changes() trả ContentChange đủ before/after/author', () async {
    final server = Server()
      ..changes = [
        sampleChange(id: 1),
        sampleChange(id: 2, action: 'create', itemId: 'p2'),
        sampleChange(id: 3, action: 'delete', itemId: 'p3'),
      ];
    final c = await boot(server);
    final list = await c.read(adminProvider.notifier).changes();
    expect(list, hasLength(3));
    expect(list[0].author, 'admin@x');
    expect(list[0].before!['fields'], isNotNull);
    expect(list[0].after!['fields'], {'id': 't1', 'name': 'Mới'});
    expect(list[1].before, isNull);
    expect(list[2].after, isNull);
    expect(list[0].createdAt, isNotNull);
  });

  test('save 409 → conflict, giữ nguyên sửa chưa lưu', () async {
    final c = await boot(
      Server(putStatus: 409, putBody: {'detail': 'version_conflict'}),
    );
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.save();
    final s = c.read(adminProvider);
    expect(s.conflict, isTrue);
    expect(s.dirty, isTrue);
    expect(s.version, 'v1');
  });

  test('save 422 → errors, vẫn dirty', () async {
    final c = await boot(
      Server(
        putStatus: 422,
        putBody: {
          'errors': ['sai A', 'sai B'],
        },
      ),
    );
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.save();
    final s = c.read(adminProvider);
    expect(s.errors, ['sai A', 'sai B']);
    expect(s.dirty, isTrue);
    expect(s.conflict, isFalse);
  });

  test('discardChanges tải lại bản server', () async {
    final c = await boot(Server());
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.discardChanges();
    final s = c.read(adminProvider);
    expect(s.dirty, isFalse);
    expect(s.themes.single['name'], 'Theme 1');
  });

  test('mạng lỗi khi save → failure network, vẫn dirty', () async {
    final c = ProviderContainer(
      overrides: [
        adminRepositoryProvider.overrideWithValue(
          AdminRepository(
            MockClient((r) async {
              if (r.method == 'GET') {
                return jsonResponse(
                  jsonEncode({'version': 'v1', 'content': sampleContent()}),
                  200,
                );
              }
              throw http.ClientException('down');
            }),
            baseUrl: Uri.parse('http://x'),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(adminProvider, (_, _) {});
    final ctl = c.read(adminProvider.notifier);
    await ctl.load();
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.save();
    expect(c.read(adminProvider).failure, AdminErrorKind.network);
    expect(c.read(adminProvider).dirty, isTrue);
  });

  test('sửa trong lúc đang lưu → vẫn dirty, nhận version mới', () async {
    final server = Server()..putGate = Completer<void>();
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'A');
    final saving = ctl.save();
    ctl.updateNode('t1', name: 'B');
    server.putGate!.complete();
    await saving;
    final s = c.read(adminProvider);
    expect(s.dirty, isTrue);
    expect(s.version, 'v2');
    expect(s.notice, contains('còn thay đổi mới'));
    expect(s.notice, contains('Đã gửi duyệt'));
    expect(s.themes.single['name'], 'B');
  });

  test('validate: doc đổi trong lúc chờ → không hiện kết quả cũ', () async {
    final c = await boot(
      Server(
        validateBody: {
          'ok': false,
          'errors': ['cũ'],
        },
      ),
    );
    final ctl = c.read(adminProvider.notifier);
    final v = ctl.validate();
    ctl.updateNode('t1', name: 'B');
    await v;
    expect(c.read(adminProvider).errors, isEmpty);
  });

  test('addExercise tránh đụng block id e1-a', () async {
    final server = Server()
      ..content = () {
        final j = sampleContent();
        j['exercises'] = <String, dynamic>{
          ...(j['exercises'] as Map<String, dynamic>),
          'e1': {
            'id': 'e1',
            'title': 'One',
            'blocks': [
              {'id': 'e1-a'},
            ],
          },
        };
        return j;
      };
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    final id = ctl.addExercise('f1', 'E1 A');
    expect(id, isNot('e1-a'));
    final ex = c.read(adminProvider).exercises[id] as Map;
    expect((ex['blocks'] as List).single['id'], isNot('e1-a'));
    // file tên "a" dưới module m1 → m1-a; thêm module id trùng prefix block
    expect(ctl.addFile('m1', 'a'), 'm1-a');
  });

  test('addFile/addModule tránh đụng block id', () async {
    final server = Server()
      ..content = () {
        final j = sampleContent();
        j['exercises'] = <String, dynamic>{
          ...(j['exercises'] as Map<String, dynamic>),
          'e1': {
            'id': 'e1',
            'title': 'One',
            'blocks': [
              {'id': 'm1-a'},
            ],
          },
        };
        return j;
      };
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    expect(ctl.addFile('m1', 'a'), 'm1-a-2');
  });

  test('replaceExercise từ chối id/block id đụng node khác', () async {
    final server = Server()
      ..content = () {
        final j = sampleContent();
        j['exercises'] = <String, dynamic>{
          ...(j['exercises'] as Map<String, dynamic>),
          'e2': {
            'id': 'e2',
            'title': 'Two',
            'blocks': [
              {'id': 'e2-a'},
            ],
          },
        };
        return j;
      };
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    expect(
      ctl.replaceExercise('e1', {
        'id': 'e1',
        'blocks': [
          {'id': 'e2-a'},
        ],
      }),
      isFalse,
    );
    expect(ctl.replaceExercise('e1', {'id': 'f1'}), isFalse);
    expect(
      ctl.replaceExercise('e1', {
        'id': 'e1',
        'blocks': [
          {'id': 'e1-a'},
        ],
      }),
      isTrue,
    );
  });

  test('addTheme: diagram/topics rỗng, dirty, id không đụng id cũ', () async {
    final c = await boot(Server());
    final ctl = c.read(adminProvider.notifier);
    final id = ctl.addTheme('Theme 1');
    expect(id, 'theme-1');
    // Tên trùng slug của theme/topic đã có → thêm hậu tố, không đè id cũ.
    expect(ctl.addTheme('T1'), 't1-2');
    final s = c.read(adminProvider);
    expect(s.dirty, isTrue);
    expect(s.themes.length, 3);
    final t = s.themes[1];
    expect(t['id'], id);
    expect(t['name'], 'Theme 1');
    expect(t['topics'], isEmpty);
    expect(t['diagram'], {'classes': <dynamic>[], 'relations': <dynamic>[]});
    expect(ctl.addTheme('   '), isNull);
  });

  test('addExercise: functionName/className tuỳ chọn', () async {
    final c = await boot(Server());
    final ctl = c.read(adminProvider.notifier);
    final id = ctl.addExercise(
      'f1',
      'Seats',
      functionName: ' seats_left ',
      className: 'Flight',
    );
    final ex = c.read(adminProvider).exercises[id] as Map;
    expect(
      ex['template'],
      'class Flight:\n    def seats_left(self):\n        # TODO A',
    );
    expect(ex['function_name'], 'seats_left');
    expect(ex['class_name'], 'Flight');
    expect((ex['blocks'] as List).single['indent_level'], 2);

    final id2 = ctl.addExercise(
      'f1',
      'Top',
      functionName: 'seats_left',
      className: null,
    );
    final ex2 = c.read(adminProvider).exercises[id2] as Map;
    expect(ex2['template'], 'def seats_left():\n    # TODO A');
    expect(ex2['class_name'], isNull);
    expect((ex2['blocks'] as List).single['indent_level'], 1);

    final id3 = ctl.addExercise('f1', 'Empty', functionName: '  ');
    final ex3 = c.read(adminProvider).exercises[id3] as Map;
    expect(ex3['function_name'], 'run');
    expect(
      ex3['template'],
      'class Draft:\n    def run(self):\n        # TODO A',
    );
  });

  test('422 không có errors → lỗi dự phòng', () async {
    final c = await boot(Server(putStatus: 422, putBody: {'detail': 'x'}));
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.save();
    expect(c.read(adminProvider).errors, isNotEmpty);
  });

  test('413 và 5xx → kind server kèm thông điệp', () async {
    final c = await boot(Server(putStatus: 413, putBody: {}));
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đổi');
    await ctl.save();
    var s = c.read(adminProvider);
    expect(s.failure, AdminErrorKind.server);
    expect(s.failureMessage, contains('4MB'));
    expect(s.dirty, isTrue);

    final c2 = await boot(Server(putStatus: 500, putBody: {}));
    final ctl2 = c2.read(adminProvider.notifier);
    ctl2.updateNode('t1', name: 'Đổi');
    await ctl2.save();
    s = c2.read(adminProvider);
    expect(s.failure, AdminErrorKind.server);
    expect(s.failureMessage, 'Lỗi máy chủ');
  });

  test('reload lỗi sau khi sửa → giữ doc và dirty, báo failure', () async {
    final server = Server();
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'Đổi');
    server.getStatus = 500;
    await ctl.load();
    final s = c.read(adminProvider);
    expect(s.status, AdminStatus.ready);
    expect(s.dirty, isTrue);
    expect(s.themes.single['name'], 'Đổi');
    expect(s.failure, AdminErrorKind.server);
    expect(s.busy, isFalse);
  });

  test('sửa sau 409 vẫn giữ conflict; load bị chặn khi đang lưu', () async {
    final server = Server(putStatus: 409, putBody: {})..putGate = Completer();
    final c = await boot(server);
    final ctl = c.read(adminProvider.notifier);
    ctl.updateNode('t1', name: 'A');
    final saving = ctl.save();
    await ctl.load(); // busy → bỏ qua
    expect(server.requests.where((r) => r.method == 'GET').length, 1);
    server.putGate!.complete();
    await saving;
    expect(c.read(adminProvider).conflict, isTrue);
    ctl.updateNode('t1', name: 'B');
    expect(c.read(adminProvider).conflict, isTrue);
  });
}

class _CountingContent extends ContentController {
  _CountingContent(this.onRefresh);
  final void Function() onRefresh;

  @override
  Future<ContentLoad> build() => Completer<ContentLoad>().future;

  @override
  Future<void> refresh() async => onRefresh();
}
