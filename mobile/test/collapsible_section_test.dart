import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/features/admin/collapsible_section.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Center(child: SizedBox(width: 400, child: child)),
    ),
  );
}

void main() {
  testWidgets('CollapsibleSection mặc định mở thì thấy child', (tester) async {
    await tester.pumpWidget(_host(const CollapsibleSection(
      title: 'Cơ bản',
      summary: 'tóm tắt',
      child: Text('nội dung child'),
    )));

    expect(find.text('nội dung child'), findsOneWidget);
    expect(find.text('tóm tắt'), findsNothing);
  });

  testWidgets('CollapsibleSection: bấm tiêu đề thì đóng, hiện summary; bấm lại thì mở', (tester) async {
    await tester.pumpWidget(_host(const CollapsibleSection(
      title: 'Cơ bản',
      summary: 'tóm tắt',
      child: Text('nội dung child'),
    )));

    await tester.tap(find.text('Cơ bản'));
    await tester.pumpAndSettle();
    expect(find.text('nội dung child'), findsNothing);
    expect(find.text('tóm tắt'), findsOneWidget);

    await tester.tap(find.text('Cơ bản'));
    await tester.pumpAndSettle();
    expect(find.text('nội dung child'), findsOneWidget);
    expect(find.text('tóm tắt'), findsNothing);
  });

  testWidgets('CollapsibleSection: bấm mũi tên cũng đóng/mở', (tester) async {
    await tester.pumpWidget(_host(const CollapsibleSection(
      title: 'Cơ bản',
      child: Text('nội dung child'),
    )));

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text('nội dung child'), findsNothing);
  });

  testWidgets('CollapsibleSection initiallyOpen=false thì bắt đầu đóng', (tester) async {
    await tester.pumpWidget(_host(const CollapsibleSection(
      title: 'Judge',
      initiallyOpen: false,
      child: Text('nội dung child'),
    )));

    expect(find.text('nội dung child'), findsNothing);
  });

  testWidgets('CollapsibleSection giữ trạng thái đóng qua rebuild của cha', (tester) async {
    await tester.pumpWidget(_host(const _ParentRebuild()));

    await tester.tap(find.text('Cơ bản'));
    await tester.pumpAndSettle();
    expect(find.text('nội dung child'), findsNothing);

    await tester.tap(find.text('đổi nhãn cha'));
    await tester.pumpAndSettle();
    expect(find.text('đã đổi 1 lần'), findsOneWidget);
    expect(find.text('nội dung child'), findsNothing);
  });

  testWidgets('CollapsibleCard mặc định mở, bấm header thì đóng và mở lại', (tester) async {
    await tester.pumpWidget(_host(const CollapsibleCard(
      badge: Text('A'),
      title: 'Gán origin',
      subtitle: 'flight-init-a',
      actions: [Text('Xoá')],
      child: Text('nội dung ô A'),
    )));

    expect(find.text('A'), findsOneWidget);
    expect(find.text('flight-init-a'), findsOneWidget);
    expect(find.text('Xoá'), findsOneWidget);
    expect(find.text('nội dung ô A'), findsOneWidget);

    await tester.tap(find.text('Gán origin'));
    await tester.pumpAndSettle();
    expect(find.text('nội dung ô A'), findsNothing);

    await tester.tap(find.text('Gán origin'));
    await tester.pumpAndSettle();
    expect(find.text('nội dung ô A'), findsOneWidget);
  });

  testWidgets('CollapsibleCard initiallyOpen=false thì bắt đầu đóng', (tester) async {
    await tester.pumpWidget(_host(const CollapsibleCard(
      badge: Text('B'),
      title: 'Gán dest',
      initiallyOpen: false,
      child: Text('nội dung ô B'),
    )));

    expect(find.text('nội dung ô B'), findsNothing);
  });
}

class _ParentRebuild extends StatefulWidget {
  const _ParentRebuild();

  @override
  State<_ParentRebuild> createState() => _ParentRebuildState();
}

class _ParentRebuildState extends State<_ParentRebuild> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () => setState(() => _count++),
          child: const Text('đổi nhãn cha'),
        ),
        Text(_count == 0 ? 'chưa đổi' : 'đã đổi $_count lần'),
        const CollapsibleSection(
          title: 'Cơ bản',
          child: Text('nội dung child'),
        ),
      ],
    );
  }
}
