import 'package:http/http.dart' as http;

/// Fixture riêng cho test trình soạn bài (không phụ thuộc admin_controller_test).
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

/// Một mục trong GET /api/admin/changes (project đổi tên).
Map<String, dynamic> sampleChange({
  int id = 1,
  String kind = 'project',
  String itemId = 't1',
  String action = 'update',
}) => {
  'id': id,
  'kind': kind,
  'item_id': itemId,
  'action': action,
  'before': action == 'create'
      ? null
      : {
          'fields': {'id': itemId, 'name': 'Cũ'},
          'prev': <String>[],
        },
  'after': action == 'delete'
      ? null
      : {
          'fields': {'id': itemId, 'name': 'Mới'},
          'prev': <String>[],
        },
  'status': 'pending',
  'author': 'admin@x',
  'created_at': '2026-10-11T00:00:00Z',
  'updated_at': '2026-10-11T00:00:00Z',
};

/// Tóm tắt trong `pending` của GET /api/admin/content.
Map<String, dynamic> samplePending({
  int id = 1,
  String kind = 'project',
  String itemId = 't1',
  String action = 'update',
}) => {'id': id, 'kind': kind, 'item_id': itemId, 'action': action};
