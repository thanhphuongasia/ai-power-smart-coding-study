/// SdRepository: parse, body gửi đi, ánh xạ lỗi HTTP, và bất biến "client không
/// giữ dữ liệu chấm" (rubric/keywords).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/sd_repository.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Repo + danh sách request đã nhận; [reply] quyết định response.
(SdRepository, List<http.Request>) _repo(
  http.Response Function(http.Request) reply,
) {
  final seen = <http.Request>[];
  final client = MockClient((req) async {
    seen.add(req);
    return reply(req);
  });
  return (SdRepository(client, baseUrl: Uri.parse('http://t')), seen);
}

Map<String, dynamic> _card(String id, {String? lang}) => {
  'id': id,
  'kind': 'text',
  'title': 'Thẻ $id',
  'body': 'Nội dung $id',
  'lang': ?lang,
};

Map<String, dynamic> _docJson() => {
  'id': 'url-shortener',
  'title': 'URL Shortener',
  'phase2_unlocked': false,
  'context': <Object>[],
  'rubric': ['không được lộ'],
  'sections': [
    {
      'id': 's1',
      'position': 1,
      'chapter': 'Cơ bản',
      'chapter_position': 1,
      'title': 'Yêu cầu',
      'cards': [_card('c1'), _card('c2', lang: 'sql')],
      'read': ['c1'],
      'done': false,
      'unlocked': true,
      'keywords': ['hash'],
    },
    {
      'id': 's2',
      'position': 2,
      'chapter': 'Cơ bản',
      'chapter_position': 2,
      'title': 'Lưu trữ',
      'cards': [_card('c3')],
      'read': <String>[],
      'done': false,
      'unlocked': false,
    },
  ],
  'tasks': [
    {
      'id': 't1',
      'position': 1,
      'name': 'Thiết kế khoá',
      'unlocked': false,
      'done': false,
      'attempts': 0,
      'prompt': null,
      'hints': <String>[],
      'ref_section_id': null,
      'rubric': [
        {
          'keywords': ['x'],
        },
      ],
    },
  ],
};

Map<String, dynamic> _attemptJson({int n = 1}) => {
  'id': 10 + n,
  'n': n,
  'answer': 'dùng base62',
  'created_at': '2026-10-12T09:00:00Z',
  'source': 'auto',
  'score': 0.5,
  'items': [
    {'text': 'Nêu hash', 'ok': true, 'note': 'ok'},
    {'text': 'Nêu cache', 'ok': false, 'note': 'thiếu'},
  ],
  'feedback': null,
  'reviewed_at': null,
  'keywords': ['hash'],
};

void main() {
  test('listDocs parse đúng và gọi GET /api/sd/docs', () async {
    final (repo, seen) = _repo(
      (_) => _json({
        'items': [
          {
            'id': 'd1',
            'title': 'Tiêu đề Việt',
            'sections': 4,
            'sections_done': 1,
            'cards': 12,
            'cards_read': 5,
            'phase2_unlocked': false,
            'tasks': 3,
            'tasks_done': 0,
          },
        ],
      }),
    );
    final docs = await repo.listDocs();
    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/api/sd/docs');
    expect(docs, hasLength(1));
    expect(docs.single.id, 'd1');
    expect(docs.single.title, 'Tiêu đề Việt');
    expect(docs.single.sectionsDone, 1);
    expect(docs.single.cardsRead, 5);
    expect(docs.single.phase2Unlocked, isFalse);
    expect(docs.single.tasks, 3);
  });

  test(
    'getDoc parse section/task; task khoá prompt null, context rỗng',
    () async {
      final (repo, seen) = _repo((_) => _json(_docJson()));
      final doc = await repo.getDoc('url-shortener');
      expect(seen.single.url.path, '/api/sd/docs/url-shortener');
      expect(doc.title, 'URL Shortener');
      expect(doc.phase2Unlocked, isFalse);
      expect(doc.context, isEmpty);

      final s1 = doc.sections[0];
      expect(s1.unlocked, isTrue);
      expect(s1.done, isFalse);
      expect(s1.read, {'c1'});
      expect(s1.cards, hasLength(2));
      expect(s1.cards[0].lang, isNull);
      expect(s1.cards[1].lang, 'sql');
      expect(s1.chapterPosition, 1);
      expect(doc.sections[1].unlocked, isFalse);
      expect(doc.sections[1].read, isEmpty);

      final t = doc.tasks.single;
      expect(t.unlocked, isFalse);
      expect(t.prompt, isNull);
      expect(t.hints, isEmpty);
      expect(t.refSectionId, isNull);
    },
  );

  test('getDoc: id có ký tự đặc biệt được encode trong path', () async {
    final (repo, seen) = _repo((_) => _json(_docJson()));
    await repo.getDoc('a b/c');
    expect(seen.single.url.path, '/api/sd/docs/a%20b%2Fc');
  });

  test('putProgress gửi {"read_cards":[...]} và parse kết quả', () async {
    final (repo, seen) = _repo(
      (_) => _json({
        'section_id': 's1',
        'read': ['c1', 'c2'],
        'done': true,
        'next_section_id': 's2',
        'phase2_unlocked': false,
      }),
    );
    final r = await repo.putProgress('d1', 's1', ['c1', 'c2']);
    final req = seen.single;
    expect(req.method, 'PUT');
    expect(req.url.path, '/api/sd/docs/d1/sections/s1/progress');
    expect(jsonDecode(req.body), {
      'read_cards': ['c1', 'c2'],
    });
    expect(req.headers['content-type'], contains('application/json'));
    expect(r.sectionId, 's1');
    expect(r.read, {'c1', 'c2'});
    expect(r.done, isTrue);
    expect(r.nextSectionId, 's2');
    expect(r.phase2Unlocked, isFalse);
  });

  test('putProgress: next_section_id null được chấp nhận', () async {
    final (repo, _) = _repo(
      (_) => _json({
        'section_id': 's9',
        'read': <String>[],
        'done': false,
        'next_section_id': null,
        'phase2_unlocked': true,
      }),
    );
    final r = await repo.putProgress('d1', 's9', []);
    expect(r.nextSectionId, isNull);
    expect(r.phase2Unlocked, isTrue);
  });

  test('409 section_locked → SdApiException(409, section_locked)', () async {
    final (repo, _) = _repo((_) => _json({'detail': 'section_locked'}, 409));
    await expectLater(
      repo.putProgress('d1', 's2', ['c3']),
      throwsA(
        isA<SdApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.detail, 'detail', 'section_locked'),
      ),
    );
  });

  test('401 không có body JSON → SdApiException(401, null)', () async {
    final (repo, _) = _repo((_) => http.Response('Unauthorized', 401));
    await expectLater(
      repo.listDocs(),
      throwsA(
        isA<SdApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.detail, 'detail', isNull),
      ),
    );
  });

  test('submitAttempt gửi {"answer":...}, đọc root["attempt"]', () async {
    final (repo, seen) = _repo((_) => _json({'attempt': _attemptJson()}, 201));
    final a = await repo.submitAttempt('d1', 't1', 'dùng base62');
    final req = seen.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/api/sd/docs/d1/tasks/t1/attempts');
    expect(jsonDecode(req.body), {'answer': 'dùng base62'});
    expect(a.n, 1);
    expect(a.source, 'auto');
    expect(a.score, 0.5);
    expect(a.items, hasLength(2));
    expect(a.items[1].ok, isFalse);
    expect(a.items[1].note, 'thiếu');
    expect(a.feedback, isNull);
    expect(a.reviewedAt, isNull);
  });

  test('submitAttempt: 200 (không phải 201) coi là lỗi', () async {
    final (repo, _) = _repo((_) => _json({'attempt': _attemptJson()}));
    await expectLater(
      repo.submitAttempt('d1', 't1', 'x'),
      throwsA(isA<SdApiException>()),
    );
  });

  test('submitAttempt 429 attempt_limit và 409 task_locked', () async {
    final (r429, _) = _repo((_) => _json({'detail': 'attempt_limit'}, 429));
    await expectLater(
      r429.submitAttempt('d1', 't1', 'x'),
      throwsA(
        isA<SdApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.detail, 'detail', 'attempt_limit'),
      ),
    );
    final (r409, _) = _repo((_) => _json({'detail': 'task_locked'}, 409));
    await expectLater(
      r409.submitAttempt('d1', 't1', 'x'),
      throwsA(
        isA<SdApiException>().having((e) => e.detail, 'detail', 'task_locked'),
      ),
    );
  });

  test('422 với detail dạng list không nổ: detail = null', () async {
    final (repo, _) = _repo(
      (_) => _json({
        'detail': [
          {
            'loc': ['body', 'answer'],
            'msg': 'quá ngắn',
          },
        ],
      }, 422),
    );
    await expectLater(
      repo.submitAttempt('d1', 't1', ''),
      throwsA(
        isA<SdApiException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.detail, 'detail', isNull),
      ),
    );
  });

  test('listAttempts gửi ?limit= (mặc định 20) và giữ thứ tự server', () async {
    final (repo, seen) = _repo(
      (_) => _json({
        'items': [_attemptJson(n: 2), _attemptJson()],
      }),
    );
    final list = await repo.listAttempts('d1', 't1');
    expect(seen.single.url.path, '/api/sd/docs/d1/tasks/t1/attempts');
    expect(seen.single.url.queryParameters, {'limit': '20'});
    expect(list.map((a) => a.n), [2, 1]);

    await repo.listAttempts('d1', 't1', limit: 5);
    expect(seen.last.url.queryParameters, {'limit': '5'});
  });

  test('body không phải JSON object → FormatException', () async {
    final (repo, _) = _repo((_) => _json([1, 2]));
    await expectLater(repo.listDocs(), throwsFormatException);
  });

  test('thiếu field bắt buộc → FormatException nêu tên field', () async {
    final doc = _docJson();
    (doc['sections'] as List)[0].remove('unlocked');
    final (repo, _) = _repo((_) => _json(doc));
    await expectLater(
      repo.getDoc('d1'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('unlocked'),
        ),
      ),
    );
  });

  test('sai kiểu field → FormatException nêu tên field', () async {
    final (repo, _) = _repo(
      (_) => _json({
        'attempt': {..._attemptJson(), 'score': 'cao'},
      }, 201),
    );
    await expectLater(
      repo.submitAttempt('d1', 't1', 'x'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('score'),
        ),
      ),
    );
  });

  test('bất biến: JSON có rubric/keywords thì model không giữ chúng', () async {
    final (repo, _) = _repo((req) {
      if (req.method == 'POST') {
        return _json({'attempt': _attemptJson()}, 201);
      }
      return _json(_docJson());
    });
    final doc = await repo.getDoc('d1');
    final attempt = await repo.submitAttempt('d1', 't1', 'x');
    // Truy cập động: model không được có getter rubric/keywords.
    final dynamic d = doc;
    final dynamic s = doc.sections.first;
    final dynamic t = doc.tasks.first;
    final dynamic a = attempt;
    for (final obj in [d, s, t, a]) {
      for (final name in ['rubric', 'keywords']) {
        expect(
          () {
            switch (name) {
              case 'rubric':
                return obj.rubric;
              default:
                return obj.keywords;
            }
          },
          throwsNoSuchMethodError,
          reason: '${obj.runtimeType}.$name',
        );
      }
    }
    // Và nội dung hợp lệ vẫn parse bình thường.
    expect(doc.tasks.single.name, 'Thiết kế khoá');
    expect(attempt.items, hasLength(2));
  });
}
