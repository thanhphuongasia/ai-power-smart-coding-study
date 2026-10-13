import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/features/system_design/duo_path.dart';

const _nodes = [
  DuoNode(id: 'a', label: 'Đề bài', state: DuoNodeState.done),
  DuoNode(
    id: 'b',
    label: 'Ước lượng tải',
    state: DuoNodeState.current,
    sublabel: '3/5 card',
  ),
  DuoNode(id: 'c', label: 'API', state: DuoNodeState.open),
  DuoNode(id: 'd', label: 'Kiến trúc', state: DuoNodeState.locked),
];

Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: buildAppTheme(brightness: brightness),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Future<void> _setWidth(WidgetTester tester, double w) async {
  tester.view.physicalSize = Size(w, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('bóng BẮT ĐẦU chỉ xuất hiện một lần khi có node current', (
    tester,
  ) async {
    await tester.pumpWidget(_host(DuoPath(nodes: _nodes, onTap: (_) {})));
    expect(find.text('BẮT ĐẦU'), findsOneWidget);
    expect(find.byKey(const Key('duo-start-bubble')), findsOneWidget);
  });

  testWidgets('không có node current thì không có bóng', (tester) async {
    final nodes = [_nodes[0], _nodes[2], _nodes[3]];
    await tester.pumpWidget(_host(DuoPath(nodes: nodes, onTap: (_) {})));
    expect(find.text('BẮT ĐẦU'), findsNothing);
    expect(find.byKey(const Key('duo-start-bubble')), findsNothing);
  });

  testWidgets('nhấn node gọi onTap đúng node, kể cả locked', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      _host(DuoPath(nodes: _nodes, onTap: (n) => tapped.add(n.id))),
    );
    await tester.tap(find.byKey(const Key('duo-node-c')));
    await tester.tap(find.byKey(const Key('duo-node-d')));
    expect(tapped, ['c', 'd']);
  });

  testWidgets('hiện label và sublabel', (tester) async {
    await tester.pumpWidget(_host(DuoPath(nodes: _nodes, onTap: (_) {})));
    expect(find.text('Đề bài'), findsOneWidget);
    expect(find.text('Ước lượng tải'), findsOneWidget);
    expect(find.text('3/5 card'), findsOneWidget);
  });

  testWidgets('banner hiện eyebrow (in hoa) và title', (tester) async {
    await tester.pumpWidget(
      _host(
        const DuoBanner(eyebrow: 'Chapter 1 · 2/3 section', title: 'Đề bài'),
      ),
    );
    expect(find.byKey(const Key('duo-banner')), findsOneWidget);
    expect(find.text('CHAPTER 1 · 2/3 SECTION'), findsOneWidget);
    expect(find.text('Đề bài'), findsOneWidget);
  });

  for (final b in Brightness.values) {
    for (final w in [360.0, 800.0]) {
      testWidgets('không overflow ở theme ${b.name}, rộng ${w.toInt()}', (
        tester,
      ) async {
        await _setWidth(tester, w);
        final many = [
          for (var i = 0; i < 9; i++)
            DuoNode(
              id: 'n$i',
              label: 'Một nhãn rất dài để thử cắt hai dòng số $i của lộ trình',
              state: i == 3 ? DuoNodeState.current : DuoNodeState.locked,
              sublabel: 'Dòng phụ khá dài cũng phải được cắt gọn $i',
            ),
        ];
        await tester.pumpWidget(
          _host(
            Column(
              children: [
                const DuoBanner(eyebrow: 'Chapter 1', title: 'Tiêu đề'),
                DuoPath(nodes: many, onTap: (_) {}),
              ],
            ),
            brightness: b,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('danh sách rỗng không lỗi', (tester) async {
    await tester.pumpWidget(_host(DuoPath(nodes: const [], onTap: (_) {})));
    expect(tester.takeException(), isNull);
    expect(find.text('BẮT ĐẦU'), findsNothing);
  });

  testWidgets('Semantics có chữ trạng thái và là button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(DuoPath(nodes: _nodes, onTap: (_) {})));
    expect(find.bySemanticsLabel('Đề bài, đã xong'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Ước lượng tải, 3/5 card, đang học'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('API, đã mở'), findsOneWidget);
    expect(find.bySemanticsLabel('Kiến trúc, chưa mở'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('API, đã mở')),
      matchesSemantics(
        label: 'API, đã mở',
        isButton: true,
        hasTapAction: true,
        hasEnabledState: false,
      ),
    );
    handle.dispose();
  });

  testWidgets('Semantics gồm cả sublabel (tiến độ)', (tester) async {
    final handle = tester.ensureSemantics();
    final nodes = [
      const DuoNode(
        id: 'r',
        label: 'Requirements',
        state: DuoNodeState.current,
        sublabel: '3/5 card',
      ),
    ];
    await tester.pumpWidget(_host(DuoPath(nodes: nodes, onTap: (_) {})));
    expect(
      find.bySemanticsLabel('Requirements, 3/5 card, đang học'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('hai node current: đúng MỘT bóng, ở node current đầu tiên', (
    tester,
  ) async {
    final nodes = [
      _nodes[0],
      const DuoNode(id: 'b', label: 'B', state: DuoNodeState.current),
      const DuoNode(id: 'c', label: 'C', state: DuoNodeState.current),
    ];
    await tester.pumpWidget(_host(DuoPath(nodes: nodes, onTap: (_) {})));
    expect(find.text('BẮT ĐẦU'), findsOneWidget);
    final bubble = tester.getCenter(find.byKey(const Key('duo-start-bubble')));
    final faceB = tester.getCenter(find.byKey(const Key('duo-face-b')));
    final faceC = tester.getCenter(find.byKey(const Key('duo-face-c')));
    expect(bubble.dx, closeTo(faceB.dx, 0.5));
    expect(bubble.dy, lessThan(faceB.dy)); // bóng nằm trên đĩa B
    expect(bubble.dy, lessThan(faceC.dy));
  });

  testWidgets('kích thước đĩa: >= 48 và không vượt bề rộng cột', (
    tester,
  ) async {
    await tester.pumpWidget(_host(DuoPath(nodes: _nodes, onTap: (_) {})));
    for (final n in _nodes) {
      final size = tester.getSize(find.byKey(Key('duo-face-${n.id}')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, lessThanOrEqualTo(160)); // _kNodeWidth
    }
    // Vùng chạm cũng >= 48.
    final hit = tester.getSize(find.byKey(const Key('duo-node-a')));
    expect(hit.width, greaterThanOrEqualTo(48));
    expect(hit.height, greaterThanOrEqualTo(48));
  });

  for (final b in Brightness.values) {
    testWidgets('màu đĩa theo trạng thái dùng token palette (${b.name})', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DuoPath(nodes: _nodes, onTap: (_) {}),
          brightness: b,
        ),
      );
      final p = tester.element(find.byKey(const Key('duo-face-a'))).palette;
      Color faceOf(String id) {
        final box = tester.widget<Container>(find.byKey(Key('duo-face-$id')));
        return (box.decoration as BoxDecoration).color!;
      }

      expect(faceOf('a'), p.success); // done
      expect(faceOf('b'), p.primary); // current
      expect(faceOf('c'), p.primary); // open
      expect(faceOf('d'), p.outline); // locked
      expect(faceOf('c'), isNot(faceOf('a'))); // open khác done
      expect(faceOf('d'), isNot(faceOf('c')));
    });
  }

  testWidgets('icon theo trạng thái: tick / play / sao / khoá', (tester) async {
    await tester.pumpWidget(_host(DuoPath(nodes: _nodes, onTap: (_) {})));
    Finder iconIn(String id, IconData icon) => find.descendant(
      of: find.byKey(Key('duo-face-$id')),
      matching: find.byIcon(icon),
    );
    expect(iconIn('a', Icons.check_rounded), findsOneWidget);
    expect(iconIn('b', Icons.play_arrow_rounded), findsOneWidget);
    expect(iconIn('c', Icons.star_rounded), findsOneWidget);
    expect(iconIn('d', Icons.lock_rounded), findsOneWidget);
    // Không lẫn icon giữa các trạng thái.
    expect(iconIn('a', Icons.lock_rounded), findsNothing);
    expect(iconIn('d', Icons.check_rounded), findsNothing);
    expect(iconIn('c', Icons.play_arrow_rounded), findsNothing);
  });

  testWidgets('quầng sáng chỉ có ở node current', (tester) async {
    await tester.pumpWidget(_host(DuoPath(nodes: _nodes, onTap: (_) {})));
    List<BoxShadow>? shadowOf(String id) {
      final box = tester.widget<Container>(find.byKey(Key('duo-face-$id')));
      return (box.decoration as BoxDecoration).boxShadow
          ?.cast<BoxShadow>()
          .toList();
    }

    expect(shadowOf('b'), isNotEmpty);
    for (final id in ['a', 'c', 'd']) {
      expect(shadowOf(id) ?? const [], isEmpty, reason: 'node $id');
    }
  });

  testWidgets('zigzag: toạ độ ngang đổi giữa các node, đối xứng quanh tâm', (
    tester,
  ) async {
    final nodes = [
      for (var i = 0; i < 8; i++)
        DuoNode(id: 'z$i', label: 'N$i', state: DuoNodeState.open),
    ];
    await tester.pumpWidget(_host(DuoPath(nodes: nodes, onTap: (_) {})));
    final dx = [
      for (final n in nodes)
        tester.getCenter(find.byKey(Key('duo-face-${n.id}'))).dx,
    ];
    final mid = dx[0]; // node 0 nằm đúng trục giữa
    final off = [for (final x in dx) x - mid];
    expect(off[1], isNot(closeTo(off[0], 0.5)));
    expect(off[2], isNot(closeTo(off[1], 0.5)));
    // Nửa sau là gương của nửa đầu quanh trục giữa.
    for (final i in [1, 2, 3]) {
      expect(off[i], closeTo(-off[i + 4], 0.5), reason: 'node $i');
    }
    // Có lệch cả hai phía.
    expect(off.any((v) => v < -1), isTrue);
    expect(off.any((v) => v > 1), isTrue);
  });

  testWidgets('không overflow ở rộng 320 và textScale 1.5', (tester) async {
    await _setWidth(tester, 320);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final many = [
      for (var i = 0; i < 8; i++)
        DuoNode(
          id: 'n$i',
          label: 'Một nhãn rất dài để thử cắt hai dòng số $i của lộ trình',
          state: i == 2 ? DuoNodeState.current : DuoNodeState.open,
          sublabel: 'Dòng phụ khá dài cũng phải được cắt gọn $i',
        ),
    ];
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const DuoBanner(eyebrow: 'Chapter 1', title: 'Tiêu đề'),
            DuoPath(nodes: many, onTap: (_) {}),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Đĩa không tràn ra ngoài màn hình ngang.
    for (final n in many) {
      final r = tester.getRect(find.byKey(Key('duo-face-${n.id}')));
      expect(r.left, greaterThanOrEqualTo(0), reason: n.id);
      expect(r.right, lessThanOrEqualTo(320), reason: n.id);
    }
  });

  testWidgets('thứ tự: node đầu nằm phía trên node sau', (tester) async {
    await tester.pumpWidget(_host(DuoPath(nodes: _nodes, onTap: (_) {})));
    final ys = [
      for (final n in _nodes)
        tester.getTopLeft(find.byKey(Key('duo-face-${n.id}'))).dy,
    ];
    for (var i = 0; i < ys.length - 1; i++) {
      expect(ys[i], lessThan(ys[i + 1]), reason: 'node $i trước node ${i + 1}');
    }
  });
}
