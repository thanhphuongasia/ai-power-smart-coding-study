import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/domain/class_scope.dart';

import 'support/content_fixture.dart';

void main() {
  ClassScope? scopeOf(String id) => classScope(testContent.exerciseById(id));

  test('flight-init gom mọi self.<attr>', () {
    final s = scopeOf('flight-init')!;
    expect(s.className, 'Flight');
    expect(s.method, '__init__');
    expect(s.attributes, {
      'code',
      'origin',
      'dest',
      'capacity',
      'booked',
      'status',
    });
  });

  test('flight-seats-left', () {
    expect(scopeOf('flight-seats-left')!.attributes, {'capacity', 'booked'});
  });

  test(
    'flight-is-full: self.seats_left() là lời gọi, không phải attribute',
    () {
      final s = scopeOf('flight-is-full')!;
      expect(s.attributes, isNot(contains('seats_left')));
    },
  );

  test('flight-service-search dùng flights', () {
    expect(scopeOf('flight-service-search')!.attributes, contains('flights'));
  });

  test('hàm tự do → null', () {
    expect(scopeOf('split-chunks'), isNull);
  });
}
