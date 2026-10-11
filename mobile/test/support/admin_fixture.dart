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
