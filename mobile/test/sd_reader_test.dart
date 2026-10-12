/// Màn đọc System Design: render thẻ, tờ giấy trắng, tự đánh dấu đã đọc khi
/// lướt (debounce), khoá do server quyết (INV-04), lỗi PUT, vị trí mở màn.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/sd_repository.dart';
import 'package:smart_coding_study/features/system_design/block_renderer.dart';
import 'package:smart_coding_study/features/system_design/reader_screen.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Thân dài [n] dòng để mỗi thẻ cao hơn một phần màn hình.
String _lines(String tag, int n) =>
    List.generate(n, (i) => 'Dòng $tag-$i').join('\n');

Map<String, dynamic> _card(
  String id, {
  String kind = 'text',
  String? title,
  String? body,
  String? lang,
}) => {
  'id': id,
  'kind': kind,
  'title': title ?? 'Tiêu đề $id',
  'body': body ?? _lines(id, 9),
  'lang': ?lang,
};

Map<String, dynamic> _section(
  String id,
  int pos,
  List<Map<String, dynamic>> cards, {
  bool unlocked = true,
  bool done = false,
  List<String> read = const [],
  String chapter = 'Cơ bản',
  int chapterPos = 1,
}) => {
  'id': id,
  'position': pos,
  'chapter': chapter,
  'chapter_position': chapterPos,
  'title': 'Section $id',
  'cards': cards,
  'read': read,
  'done': done,
  'unlocked': unlocked,
};

Map<String, dynamic> _doc(List<Map<String, dynamic>> sections) => {
  'id': 'doc1',
  'title': 'Tài liệu',
  'phase2_unlocked': false,
  'context': <Object>[],
  'tasks': <Object>[],
  'sections': sections,
};

/// Doc 2 section, mỗi section 3 thẻ cao.
Map<String, dynamic> _twoSections({
  bool s2Unlocked = true,
  bool s1Done = false,
  List<String> s1Read = const [],
  List<String> s2Read = const [],
}) => _doc([
  _section(
    's1',
    1,
    [_card('a1'), _card('a2'), _card('a3')],
    done: s1Done,
    read: s1Read,
  ),
  _section(
    's2',
    2,
    [_card('b1'), _card('b2'), _card('b3')],
    unlocked: s2Unlocked,
    read: s2Read,
    chapter: 'Nâng cao',
    chapterPos: 2,
  ),
]);

typedef _Put = ({String section, List<String> cards});

class _Server {
  _Server(this.doc);
  final Map<String, dynamic> doc;
  final puts = <_Put>[];
  Future<http.Response> Function(String section, List<String> cards, int n)?
  onPut;

  Future<http.Response> handle(http.Request r) async {
    if (r.method == 'GET') return _json(doc);
    final m = RegExp(r'/sections/([^/]+)/progress').firstMatch(r.url.path)!;
    final cards = ((jsonDecode(r.body) as Map)['read_cards'] as List)
        .cast<String>();
    puts.add((section: m.group(1)!, cards: cards));
    return (onPut ?? _ok)(m.group(1)!, cards, puts.length);
  }
}

Future<http.Response> _ok(String s, List<String> cards, int n) async => _json({
  'section_id': s,
  'read': cards,
  'done': false,
  'next_section_id': null,
  'phase2_unlocked': false,
});

Future<http.Response> _doneNext(String s, List<String> cards, int n) async =>
    _json({
      'section_id': s,
      'read': cards,
      'done': true,
      'next_section_id': s == 's1' ? 's2' : null,
      'phase2_unlocked': false,
    });

Widget _app(
  _Server server, {
  String? sectionId,
  Brightness brightness = Brightness.light,
  Widget? home,
}) {
  final repo = SdRepository(
    MockClient(server.handle),
    baseUrl: Uri.parse('http://t'),
  );
  return ProviderScope(
    overrides: [sdRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: buildAppTheme(brightness: brightness),
      home: home ?? SdReaderScreen(docId: 'doc1', sectionId: sectionId),
    ),
  );
}

Future<void> _size(WidgetTester tester, double w, [double h = 800]) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  String? sectionId,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    _app(server, sectionId: sectionId, brightness: brightness),
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

/// Cuộn tối thiểu để mép dưới của [card] chạm mép dưới tờ giấy.
Future<void> _reveal(WidgetTester tester, String card) async {
  final f = find.byKey(Key('sd-card-$card'));
  final delta = tester.getRect(f).bottom - tester.getRect(_paper).bottom;
  final p = _pos(tester);
  if (delta > 0) p.jumpTo((p.pixels + delta + 2).clamp(0, p.maxScrollExtent));
  await tester.pump();
}

double _progress(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(
      find.byKey(const Key('sd-reader-progress')),
    )
    .value!;

Future<void> _debounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump();
}

void main() {
  testWidgets('(a) render text/bảng/code/callout + tiêu đề section', (
    tester,
  ) async {
    await _size(tester, 400);
    final server = _Server(
      _doc([
        _section('s1', 1, [
          _card(
            't',
            title: 'Văn bản',
            body: 'Xin **chào** `mã` đây\n\n- một\n- hai',
          ),
          _card(
            'tb',
            kind: 'table',
            title: 'Bảng',
            body: 'Tên | Giá trị\n--- | ---\nAlpha | 42',
          ),
          _card(
            'c',
            kind: 'code',
            title: 'Mã',
            body: 'print(1)',
            lang: 'python',
          ),
          _card('d', kind: 'diagram', title: 'Sơ đồ A', body: 'A --> B'),
          _card('k', kind: 'callout', title: 'Lưu ý', body: 'Cẩn thận **nhé**'),
        ]),
        _section(
          's2',
          2,
          [_card('x', body: 'Nội dung hai')],
          chapter: 'Nâng cao',
          chapterPos: 2,
        ),
      ]),
    );
    await _open(tester, server);
    expect(find.byKey(const Key('sd-reader')), findsOneWidget);
    expect(find.text('Section s1'), findsNWidgets(2)); // thanh trên + tiêu đề
    expect(find.text('Section s2'), findsOneWidget);
    expect(find.text('CHAPTER 1 · CƠ BẢN'), findsOneWidget);
    expect(find.text('CHAPTER 2 · NÂNG CAO'), findsOneWidget);
    expect(
      find.textContaining('Xin chào mã đây', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('hai', findRichText: true), findsWidgets);
    expect(find.textContaining('Alpha', findRichText: true), findsOneWidget);
    expect(find.textContaining('42', findRichText: true), findsOneWidget);
    expect(find.text('print(1)'), findsOneWidget);
    expect(find.text('python'), findsOneWidget);
    expect(find.text('Sơ đồ'), findsOneWidget); // nhãn khối diagram
    expect(
      find.textContaining('Cẩn thận nhé', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Văn bản'), findsOneWidget);
    expect(find.byKey(const Key('sd-card-s1-tb')), findsOneWidget);
    expect(find.text('Hết tài liệu'), findsOneWidget);
  });

  testWidgets('tiêu đề card chỉ hiện khi khác card ngay trước', (tester) async {
    await _size(tester, 400);
    final server = _Server(
      _doc([
        _section('s1', 1, [
          _card('p', title: 'Giống nhau', body: 'một'),
          _card('q', title: 'Giống nhau', body: 'hai'),
          _card('r', title: 'Khác', body: 'ba'),
        ]),
      ]),
    );
    await _open(tester, server);
    expect(find.text('Giống nhau'), findsOneWidget);
    expect(find.text('Khác'), findsOneWidget);
  });

  testWidgets('(b) tờ giấy luôn trắng ở theme tối', (tester) async {
    await _size(tester, 400);
    await _open(tester, _Server(_twoSections()), brightness: Brightness.dark);
    final box = tester.widget<Container>(_paper);
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, const Color(0xFFFFFFFF));
    expect(
      (deco.borderRadius! as BorderRadius).topLeft,
      const Radius.circular(28),
    );
  });

  testWidgets('(c) cuộn hết section 1 → đúng 1 PUT đủ id, tiến độ tăng', (
    tester,
  ) async {
    await _size(tester, 400);
    final server = _Server(_twoSections());
    await _open(tester, server);
    final before = _progress(tester);
    expect(server.puts, isEmpty); // chưa hết debounce
    await _reveal(tester, 's1-a3');
    expect(_progress(tester), greaterThan(before));
    expect(server.puts, isEmpty);
    await _debounce(tester);
    expect(server.puts.length, 1);
    expect(server.puts.single.section, 's1');
    expect(server.puts.single.cards, ['a1', 'a2', 'a3']);
    expect(_progress(tester), closeTo(3 / 6, 1e-9));
  });

  testWidgets('(d) section khoá không sinh PUT dù cuộn tới', (tester) async {
    await _size(tester, 400);
    final server = _Server(_twoSections(s2Unlocked: false));
    await _open(tester, server);
    final p = _pos(tester);
    p.jumpTo(p.maxScrollExtent);
    await tester.pump();
    await _debounce(tester);
    await _debounce(tester);
    expect(server.puts.map((e) => e.section).toSet(), {'s1'});
    expect(_progress(tester), closeTo(3 / 6, 1e-9)); // thẻ khoá không tính
  });

  testWidgets('(d) PUT done + nextSectionId mở section 2 → cuộn tiếp có PUT', (
    tester,
  ) async {
    await _size(tester, 400);
    final server = _Server(_twoSections(s2Unlocked: false))..onPut = _doneNext;
    await _open(tester, server);
    await _reveal(tester, 's1-a3');
    await _debounce(tester);
    expect(server.puts.map((e) => e.section), ['s1']);
    // s2 vừa mở khoá (nhờ kết quả PUT): cuộn tiếp tới hết.
    await _reveal(tester, 's2-b3');
    await _debounce(tester);
    expect(server.puts.last.section, 's2');
    expect(server.puts.last.cards, ['b1', 'b2', 'b3']);
  });

  testWidgets('(e) 409 section_locked: không crash, không gửi lại', (
    tester,
  ) async {
    await _size(tester, 400);
    // Mỗi section bị 409 thì dừng riêng: s2 cũng mở nên cũng tối đa 1 lần.
    final server = _Server(_twoSections())
      ..onPut = (s, c, n) async => _json({'detail': 'section_locked'}, 409);
    await _open(tester, server);
    await _debounce(tester);
    expect(server.puts.length, 1);
    final p = _pos(tester);
    p.jumpTo(p.maxScrollExtent / 2);
    await tester.pump();
    await _debounce(tester);
    p.jumpTo(p.maxScrollExtent);
    await tester.pump();
    await _debounce(tester);
    await _debounce(tester);
    expect(server.puts.where((e) => e.section == 's1').length, 1);
    expect(server.puts.where((e) => e.section == 's2').length, lessThan(2));
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('(f) lỗi mạng giữ phần chưa gửi, gửi lại ở lần cuộn sau', (
    tester,
  ) async {
    await _size(tester, 400);
    final server = _Server(_twoSections())
      ..onPut = (s, c, n) async {
        if (n == 1) throw http.ClientException('mất mạng');
        return _ok(s, c, n);
      };
    await _open(tester, server);
    await _debounce(tester);
    expect(server.puts.length, 1);
    // Không cuộn → không tự thử lại liên tục.
    await _debounce(tester);
    expect(server.puts.length, 1);
    await _reveal(tester, 's1-a3');
    await _debounce(tester);
    expect(server.puts.length, 2);
    expect(server.puts[1].cards, containsAll(server.puts[0].cards));
    expect(server.puts[1].cards, ['a1', 'a2', 'a3']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('(g) mở với sectionId=s2: cuộn tới card chưa đọc đầu tiên', (
    tester,
  ) async {
    await _size(tester, 400);
    final server = _Server(
      _twoSections(s1Done: true, s1Read: ['a1', 'a2', 'a3'], s2Read: ['b1']),
    );
    await _open(tester, server, sectionId: 's2');
    expect(_pos(tester).pixels, greaterThan(0));
    final top = tester.getTopLeft(find.byKey(const Key('sd-card-s2-b2'))).dy;
    expect(top - tester.getTopLeft(_paper).dy, closeTo(0, 1.5));
    // Cú nhảy mở màn không làm section 1 bị gửi lại.
    await _debounce(tester);
    expect(server.puts.where((e) => e.section == 's1'), isEmpty);
  });

  testWidgets('(g) section chưa đọc gì → đầu section', (tester) async {
    await _size(tester, 400);
    final server = _Server(
      _twoSections(s1Done: true, s1Read: ['a1', 'a2', 'a3']),
    );
    await _open(tester, server, sectionId: 's2');
    final top = tester
        .getTopLeft(
          find.descendant(
            of: _paper,
            matching: find.text('CHAPTER 2 · NÂNG CAO'),
          ),
        )
        .dy; // kicker là dòng đầu của header section
    expect(top - tester.getTopLeft(_paper).dy, closeTo(0, 1.5));
  });

  testWidgets('(h) rời màn gửi nốt phần đang chờ', (tester) async {
    await _size(tester, 400);
    final server = _Server(_twoSections());
    await tester.pumpWidget(
      _app(
        server,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SdReaderScreen(docId: 'doc1'),
                ),
              ),
              child: const Text('vào đọc'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('vào đọc'));
    await tester.pumpAndSettle();
    await _reveal(tester, 's1-a3');
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.puts, isEmpty);
    await tester.tap(find.byKey(const Key('sd-reader-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sd-reader')), findsNothing);
    expect(server.puts.length, 1);
    expect(server.puts.single.cards, ['a1', 'a2', 'a3']);
    // Timer debounce đã huỷ: không gửi thêm.
    await tester.pump(const Duration(seconds: 2));
    expect(server.puts.length, 1);
  });

  testWidgets('(i) SnackBar "Xong: ..." chỉ hiện một lần', (tester) async {
    await _size(tester, 400);
    final server = _Server(_twoSections())..onPut = _doneNext;
    await _open(tester, server);
    await _debounce(tester); // PUT #1: thẻ đang thấy lúc mở
    expect(find.text('Xong: Section s1 · tiếp: Section s2'), findsOneWidget);
    await _reveal(tester, 's1-a3');
    await _debounce(tester); // PUT #2: cùng section, done lần nữa
    expect(server.puts.length, 2);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Xong: Section s1 · tiếp: Section s2'), findsOneWidget);
  });

  testWidgets('lỗi tải → thông điệp + Thử lại', (tester) async {
    await _size(tester, 400);
    var calls = 0;
    final repo = SdRepository(
      MockClient((r) async {
        calls++;
        return _json({'detail': 'x'}, 500);
      }),
      baseUrl: Uri.parse('http://t'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sdRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const SdReaderScreen(docId: 'doc1'),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Không tải được'), findsOneWidget);
    final before = calls;
    await tester.tap(find.byKey(const Key('sd-retry')));
    await tester.pump();
    await tester.pump();
    expect(calls, greaterThan(before));
  });

  test('(j) parseTable: không "|" đầu dòng, bỏ dòng phân cách', () {
    expect(parseTable('a | b\n--- | ---\n1 | 2'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
    expect(parseTable('| a | b |\n|:---|---:|\n| 1 | 2 |\n\n'), [
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('(j) parseInline: đậm, mã, dấu thiếu cặp', () {
    expect(parseInline('a **b** `c` d'), const [
      InlineSeg('a ', InlineStyle.plain),
      InlineSeg('b', InlineStyle.bold),
      InlineSeg(' ', InlineStyle.plain),
      InlineSeg('c', InlineStyle.code),
      InlineSeg(' d', InlineStyle.plain),
    ]);
    expect(parseInline('`**không đậm**`'), const [
      InlineSeg('**không đậm**', InlineStyle.code),
    ]);
    expect(parseInline('2 ** 3 và `x'), const [
      InlineSeg('2 ** 3 và `x', InlineStyle.plain),
    ]);
  });

  test('(j) parseBlocks: đoạn, gạch đầu dòng, đánh số', () {
    final b = parseBlocks('Mở đầu\ntiếp\n\n- x\n* y\n1. một\n2. hai');
    expect(b.map((e) => e.kind), [
      MdKind.paragraph,
      MdKind.bullets,
      MdKind.numbered,
    ]);
    expect(b[0].items, ['Mở đầu\ntiếp']);
    expect(b[1].items, ['x', 'y']);
    expect(b[2].items, ['một', 'hai']);
  });

  for (final w in [320.0, 800.0]) {
    testWidgets('(k) không overflow ở bề rộng ${w.toInt()}', (tester) async {
      await _size(tester, w);
      final server = _Server(
        _doc([
          _section('s1', 1, [
            _card(
              't',
              body: 'Từ rất dài ${'x' * 80} **đậm** `mã`\n\n1. một\n2. hai',
            ),
            _card(
              'tb',
              kind: 'table',
              body:
                  '| Cột một | Cột hai | Cột ba | Cột bốn |\n|---|---|---|---|\n'
                  '| ${'dài ' * 30} | b | c | d |',
            ),
            _card(
              'c',
              kind: 'code',
              lang: 'python',
              body: 'x = ${'1 + ' * 40}1',
            ),
            _card('k', kind: 'callout', body: 'Lưu ý ${'dài ' * 30}'),
          ]),
        ]),
      );
      await _open(tester, server);
      final p = _pos(tester);
      p.jumpTo(p.maxScrollExtent);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
