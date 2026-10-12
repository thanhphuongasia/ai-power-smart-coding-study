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
    expect(find.bySemanticsLabel('Ước lượng tải, đang học'), findsOneWidget);
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
}
