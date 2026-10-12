/// Bổ sung cho vuốt snap từng card: các biên của `snapTarget` (kẹp extent,
/// sai số mốc, chiều lùi), physics trên iOS (kéo quá biên) và mốc đầu section
/// phải là TIÊU ĐỀ section chứ không phải card đầu.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/sd_repository.dart';
import 'package:smart_coding_study/features/system_design/card_snap_physics.dart';
import 'package:smart_coding_study/features/system_design/reader_screen.dart';

// ── Harness riêng (copy gọn từ sd_reader_test.dart) ──

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _card(String id, int lines) => {
  'id': id,
  'kind': 'text',
  'title': 'Tiêu đề $id',
  'body': List.generate(lines, (i) => 'Dòng $id-$i').join('\n'),
};

Map<String, dynamic> _section(
  String id,
  int pos,
  List<Map<String, dynamic>> cards, {
  String chapter = 'Cơ bản',
  int chapterPos = 1,
}) => {
  'id': id,
  'position': pos,
  'chapter': chapter,
  'chapter_position': chapterPos,
  'title': 'Section $id',
  'cards': cards,
  'read': <String>[],
  'done': false,
  'unlocked': true,
};

Map<String, dynamic> _doc(List<Map<String, dynamic>> sections) => {
  'id': 'doc1',
  'title': 'Tài liệu',
  'phase2_unlocked': false,
  'context': <Object>[],
  'tasks': <Object>[],
  'sections': sections,
};

/// [n] card ngắn trong một section.
Map<String, dynamic> _oneSection(int n) => _doc([
  _section('s1', 1, [for (var i = 0; i < n; i++) _card('c$i', 5)]),
]);

Future<void> _open(WidgetTester tester, Map<String, dynamic> doc) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = SdRepository(
    MockClient((r) async {
      if (r.method == 'GET') return _json(doc);
      return _json({
        'section_id': 'x',
        'read': <String>[],
        'done': false,
        'next_section_id': null,
        'phase2_unlocked': false,
      });
    }),
    baseUrl: Uri.parse('http://t'),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sdRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: const SdReaderScreen(docId: 'doc1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

final _paper = find.byKey(const Key('sd-reader-paper'));

ScrollPosition _pos(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _paper, matching: find.byType(Scrollable)).first,
    )
    .position;

double _relTop(WidgetTester tester, Finder f) =>
    tester.getTopLeft(f).dy - tester.getTopLeft(_paper).dy;

Finder _card1(String sec, String id) => find.byKey(Key('sd-card-$sec-$id'));

Future<void> _flingFwd(WidgetTester tester) async {
  await tester.fling(_paper, const Offset(0, -150), 2500);
  await tester.pumpAndSettle();
}

double _target(
  double pixels,
  double v,
  List<double> anchors, {
  double viewport = 800,
  double max = 2000,
}) => SdCardSnapPhysics.snapTarget(
  pixels: pixels,
  velocity: v,
  viewport: viewport,
  minExtent: 0,
  maxExtent: max,
  anchors: anchors,
);

void main() {
  group('snapTarget: biên', () {
    test('(1) mốc quá maxScrollExtent → kẹp đúng ở max, không vượt', () {
      // Card cuối ngắn: mốc 1035 nhưng nội dung chỉ cuộn tới 848.
      expect(_target(500, 1000, [0, 400, 1035], max: 848), 848);
      expect(_target(848, 1000, [0, 400, 1035], max: 848), 848);
      // Chiều lùi: mốc âm (không xảy ra thật) vẫn kẹp ở min.
      expect(_target(100, -1000, [-50], max: 848), 0);
    });

    test('(2) lệch mốc dưới 1px vẫn sang mốc KẾ, không đứng yên', () {
      const a = [0.0, 400.0, 800.0];
      expect(_target(400 - 0.6, 1000, a), 800);
      expect(_target(400 + 0.4, 1000, a), 800);
      expect(_target(400 + 0.6, -1000, a), 0);
      expect(_target(400 - 0.4, -1000, a), 0);
    });

    test('(3) lùi với mốc xa hơn 0,9 viewport → kẹp ở 0,9 viewport', () {
      // Mốc trước ở 300, đang ở 1500: cách 1200 > 720 (0,9 × 800).
      expect(_target(1500, -1000, [0, 300]), 780);
      // Tiến đối xứng.
      expect(_target(100, 1000, [0, 1500]), 820);
    });
  });

  group('iOS (physics cha là bouncing)', () {
    test(
      '(4a) ngoài biên + vận tốc lớn → physics cha kéo về biên, không snap',
      () {
        final physics = SdCardSnapPhysics(
          parent: const BouncingScrollPhysics(),
          anchors: () => const [0, 300, 600],
        );
        final m = FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 700,
          pixels: 760, // quá biên cuối
          viewportDimension: 800,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1,
        );
        final sim = physics.createBallisticSimulation(m, -1000)!;
        // Về đúng biên 700; nếu snap chen vào sẽ dừng ở mốc 600.
        expect(sim.x(10), closeTo(700, 0.5));
      },
    );

    testWidgets(
      '(4) kéo quá biên cuối rồi vuốt ngược → về biên, không vào mốc',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await _open(tester, _oneSection(12));
          final p = _pos(tester);
          p.jumpTo(p.maxScrollExtent);
          await tester.pump();
          // Kéo quá biên cuối, rồi hất nhanh ngược lại khi còn ngoài biên.
          final g = await tester.startGesture(tester.getCenter(_paper));
          for (var i = 0; i < 6; i++) {
            await g.moveBy(const Offset(0, -30));
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(p.pixels, greaterThan(p.maxScrollExtent));
          for (var i = 0; i < 3; i++) {
            await g.moveBy(const Offset(0, 12));
            await tester.pump(const Duration(milliseconds: 8));
          }
          expect(p.pixels, greaterThan(p.maxScrollExtent)); // vẫn ngoài biên
          await g.up();
          await tester.pumpAndSettle();
          // Physics cha kéo về biên; snap không được chen vào lùi về mốc trước.
          expect(p.pixels, p.maxScrollExtent);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );

    testWidgets('(4b) fling tiến liên tiếp dừng ở các mốc, không kẹt', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _open(tester, _oneSection(20));
        for (final id in ['c1', 'c2', 'c3', 'c4']) {
          await _flingFwd(tester);
          expect(
            _relTop(tester, _card1('s1', id)),
            closeTo(0, 1.5),
            reason: 'dừng ở $id',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  testWidgets('(5) fling dừng ở đỉnh TIÊU ĐỀ section 2, không ở card đầu', (
    tester,
  ) async {
    await _open(
      tester,
      _doc([
        _section('s1', 1, [for (var i = 0; i < 6; i++) _card('a$i', 5)]),
        _section(
          's2',
          2,
          [for (var i = 0; i < 6; i++) _card('b$i', 5)],
          chapter: 'Nâng cao',
          chapterPos: 2,
        ),
      ]),
    );
    final kicker = find.descendant(
      of: _paper,
      matching: find.text('CHAPTER 2 · NÂNG CAO'),
    );
    var onHeader = false;
    for (var i = 0; i < 12 && !onHeader; i++) {
      await _flingFwd(tester);
      // Không bao giờ dừng với card đầu s2 ở đỉnh (tiêu đề bị cuộn mất).
      expect(
        _relTop(tester, _card1('s2', 'b0')).abs(),
        greaterThan(1.5),
        reason: 'dừng ở card b0 thay vì tiêu đề section',
      );
      onHeader =
          kicker.evaluate().isNotEmpty && _relTop(tester, kicker).abs() < 1.5;
    }
    expect(onHeader, isTrue, reason: 'phải có lần dừng sát tiêu đề section 2');
  });
}
