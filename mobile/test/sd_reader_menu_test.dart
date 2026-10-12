/// Menu mục lục (hamburger) của màn đọc System Design: trạng thái xong/khoá chỉ
/// theo server (INV-01), nhảy section dùng chung bảng mốc với snap (INV-04),
/// nhảy không đánh dấu thẻ chưa hiện (INV-02).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_coding_study/app/theme.dart';
import 'package:smart_coding_study/data/sd_repository.dart';
import 'package:smart_coding_study/features/system_design/reader_screen.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _lines(String tag, int n) =>
    List.generate(n, (i) => 'Dòng $tag-$i').join('\n');

Map<String, dynamic> _card(String id, int lines) => {
  'id': id,
  'kind': 'text',
  'title': 'Tiêu đề $id',
  'body': _lines(id, lines),
};

Map<String, dynamic> _section(
  String id,
  int pos, {
  required String chapter,
  required int chapterPos,
  bool unlocked = true,
  bool done = false,
  int lines = 5,
  int cards = 3,
  List<String>? read,
}) => {
  'id': id,
  'position': pos,
  'chapter': chapter,
  'chapter_position': chapterPos,
  'title': 'Section $id',
  'cards': [for (var i = 1; i <= cards; i++) _card('c$i', lines)],
  'read':
      read ?? (done ? [for (var i = 1; i <= cards; i++) 'c$i'] : <String>[]),
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

/// 3 chapter / 8 section. s1, s2 xong; s3 (đang đọc, thẻ cao), s4 mở nhưng
/// chưa xong; s5..s8 khoá.
Map<String, dynamic> _menuDoc({int s3Lines = 14}) => _doc([
  _section('s1', 1, chapter: 'Basics', chapterPos: 1, done: true),
  _section('s2', 2, chapter: 'Basics', chapterPos: 1, done: true),
  _section('s3', 3, chapter: 'Scale', chapterPos: 2, lines: s3Lines),
  _section('s4', 4, chapter: 'Scale', chapterPos: 2),
  _section('s5', 5, chapter: 'Deep', chapterPos: 3, unlocked: false),
  _section('s6', 6, chapter: 'Deep', chapterPos: 3, unlocked: false),
  _section('s7', 7, chapter: 'Deep', chapterPos: 3, unlocked: false),
  _section('s8', 8, chapter: 'Deep', chapterPos: 3, unlocked: false),
]);

typedef _Put = ({String section, List<String> cards});

class _Server {
  _Server(this.doc);
  final Map<String, dynamic> doc;
  final puts = <_Put>[];
  bool done = false; // PUT trả done=true
  String? next;

  Future<http.Response> handle(http.Request r) async {
    if (r.method == 'GET') return _json(doc);
    final m = RegExp(r'/sections/([^/]+)/progress').firstMatch(r.url.path)!;
    final cards = ((jsonDecode(r.body) as Map)['read_cards'] as List)
        .cast<String>();
    puts.add((section: m.group(1)!, cards: cards));
    return _json({
      'section_id': m.group(1)!,
      'read': cards,
      'done': done,
      'next_section_id': done ? next : null,
      'phase2_unlocked': false,
    });
  }

  List<String> putCards(String sec) => [
    for (final p in puts)
      if (p.section == sec) ...p.cards,
  ];
}

Future<void> _open(
  WidgetTester tester,
  _Server server, {
  String? sectionId,
  double w = 400,
  double h = 700,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final repo = SdRepository(
    MockClient(server.handle),
    baseUrl: Uri.parse('http://t'),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sdRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildAppTheme(brightness: Brightness.light),
        home: SdReaderScreen(docId: 'doc1', sectionId: sectionId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

final _paper = find.byKey(const Key('sd-reader-paper'));
final _sheet = find.byKey(const Key('sd-reader-menu-sheet'));
final _menuBtn = find.byKey(const Key('sd-reader-menu'));

Finder _row(String sid) => find.byKey(Key('sd-menu-section-$sid'));

Finder _in(Finder row, IconData icon) =>
    find.descendant(of: row, matching: find.byIcon(icon));

ScrollPosition _pos(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _paper, matching: find.byType(Scrollable)).first,
    )
    .position;

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_menuBtn);
  await tester.pumpAndSettle();
}

/// Cuộn danh sách trong sheet để dòng [sid] hiện ra (sheet tự cuộn tới dòng
/// đang đọc nên các dòng khác có thể chưa được dựng).
Future<void> _showRow(WidgetTester tester, String sid) async {
  final list = find
      .descendant(of: _sheet, matching: find.byType(Scrollable))
      .first;
  await tester.drag(list, const Offset(0, 5000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(_row(sid), 100, scrollable: list);
  await tester.pumpAndSettle();
}

Future<void> _debounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump();
}

/// Đỉnh dòng kicker (dòng trên cùng) của header section so với đỉnh tờ giấy.
double _kickerTop(WidgetTester tester, String text) =>
    tester
        .getTopLeft(
          find.descendant(of: _paper, matching: find.text(text)).first,
        )
        .dy -
    tester.getTopLeft(_paper).dy;

/// Cuộn từng bước nhỏ tới cuối để mọi thẻ đều đi qua mép dưới viewport.
Future<void> _scrollAll(WidgetTester tester) async {
  final p = _pos(tester);
  while (p.pixels < p.maxScrollExtent) {
    p.jumpTo((p.pixels + 120).clamp(0, p.maxScrollExtent));
    await tester.pump();
  }
}

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('sd-reader-section'))).data!;

void main() {
  testWidgets(
    '(a) nút menu cạnh nút quay lại; sheet đủ chapter/section/trạng thái',
    (tester) async {
      await _open(tester, _Server(_menuDoc()), h: 1400);
      expect(find.byKey(const Key('sd-reader-back')), findsOneWidget);
      expect(_menuBtn, findsOneWidget);
      // Thứ tự: quay lại, menu, thanh tiến độ.
      final back = tester.getCenter(find.byKey(const Key('sd-reader-back'))).dx;
      final menu = tester.getCenter(_menuBtn).dx;
      final bar = tester
          .getCenter(find.byKey(const Key('sd-reader-progress')))
          .dx;
      expect(back < menu && menu < bar, isTrue);

      await _openMenu(tester);
      expect(_sheet, findsOneWidget);
      // Sheet tự cuộn tới s3; kéo về đầu để thấy đủ chapter.
      await tester.drag(
        find.descendant(of: _sheet, matching: find.byType(Scrollable)).first,
        const Offset(0, 1000),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _sheet, matching: find.text('Mục lục')),
        findsOne,
      );
      for (final c in [
        'CHAPTER 1 · BASICS',
        'CHAPTER 2 · SCALE',
        'CHAPTER 3 · DEEP',
      ]) {
        expect(
          find.descendant(of: _sheet, matching: find.text(c)),
          findsOneWidget,
        );
      }
      for (var i = 1; i <= 8; i++) {
        expect(_row('s$i'), findsOneWidget, reason: 's$i');
      }
      // Xong: s1, s2. Khoá: s5..s8. s3 đang đọc, s4 mở chưa xong.
      for (final s in ['s1', 's2']) {
        expect(_in(_row(s), Icons.check_circle), findsOneWidget, reason: s);
      }
      for (final s in ['s5', 's6', 's7', 's8']) {
        expect(_in(_row(s), Icons.lock), findsOneWidget, reason: s);
      }
      for (final s in ['s3', 's4']) {
        expect(_in(_row(s), Icons.check_circle), findsNothing, reason: s);
        expect(_in(_row(s), Icons.lock), findsNothing, reason: s);
      }
      expect(_in(_row('s4'), Icons.circle_outlined), findsOneWidget);
      // s3 là dòng đang đọc (chấm xanh, không phải vòng rỗng).
      expect(_in(_row('s3'), Icons.circle_outlined), findsNothing);
      expect(
        find.descendant(of: _row('s1'), matching: find.text('3/3 card')),
        findsOneWidget,
      );
      // Nút đóng.
      await tester.tap(find.byKey(const Key('sd-menu-close')));
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
    },
  );

  testWidgets(
    '(b) chạm section mở: đóng sheet, đỉnh section chạm đỉnh viewport',
    (tester) async {
      final server = _Server(_menuDoc());
      await _open(tester, server);
      expect(_title(tester), 'Section s3');

      // Lùi về s2 (kicker 'BASICS' không có tiền tố CHAPTER).
      await _openMenu(tester);
      await _showRow(tester, 's2');
      await tester.tap(_row('s2'));
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(_kickerTop(tester, 'BASICS'), closeTo(0, 1.5));
      expect(_title(tester), 'Section s2');

      // Tiến tới s4 (kicker 'SCALE' của s4; s3 là 'CHAPTER 2 · SCALE').
      await _openMenu(tester);
      await _showRow(tester, 's4');
      await tester.tap(_row('s4'));
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(_kickerTop(tester, 'SCALE'), closeTo(0, 1.5));
      expect(_title(tester), 'Section s4');
    },
  );

  testWidgets('(c) chạm section KHOÁ: SnackBar, không nhảy, không PUT', (
    tester,
  ) async {
    final server = _Server(_menuDoc());
    await _open(tester, server);
    await _debounce(tester);
    final before = _pos(tester).pixels;
    final putsBefore = server.puts.length;

    await _openMenu(tester);
    await _showRow(tester, 's5');
    await tester.tap(_row('s5'));
    await tester.pumpAndSettle();
    // SnackBar hiện TRONG sheet (không bị lớp phủ che mất).
    expect(
      find.descendant(
        of: _sheet,
        matching: find.text('Hoàn thành section trước để mở khoá'),
      ),
      findsOneWidget,
    );
    expect(_sheet, findsOneWidget, reason: 'sheet giữ mở');
    expect(_pos(tester).pixels, before);

    await tester.tap(find.byKey(const Key('sd-menu-close')));
    await tester.pumpAndSettle();
    await _debounce(tester);
    expect(_pos(tester).pixels, before);
    expect(server.puts.length, putsBefore);
    expect(server.putCards('s5'), isEmpty);
    expect(_title(tester), 'Section s3');
  });

  testWidgets('(d1) "xong" chỉ theo server: đọc đủ card cục bộ mà server chưa '
      'báo done → không có ✓', (tester) async {
    final server = _Server(_menuDoc(s3Lines: 5)); // done=false mặc định
    await _open(tester, server);
    await _scrollAll(tester); // đọc đủ 3/3 card cục bộ
    await _debounce(tester);
    expect(server.putCards('s3').toSet(), {'c1', 'c2', 'c3'});

    await _openMenu(tester);
    expect(
      find.descendant(of: _row('s3'), matching: find.text('3/3 card')),
      findsOneWidget,
    );
    expect(_in(_row('s3'), Icons.check_circle), findsNothing);
    expect(_in(_row('s4'), Icons.lock), findsNothing);
  });

  testWidgets('(d2) sau khi PUT trả done → mở lại sheet thấy ✓', (
    tester,
  ) async {
    final server = _Server(_menuDoc(s3Lines: 5))
      ..done = true
      ..next = 's4';
    await _open(tester, server);
    await _scrollAll(tester);
    await _debounce(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.putCards('s3').toSet(), containsAll({'c1', 'c2', 'c3'}));
    await tester.pumpAndSettle(); // đóng SnackBar "Xong: ..."
    await _openMenu(tester);
    expect(_in(_row('s3'), Icons.check_circle), findsOneWidget);
  });

  testWidgets('(e) nhảy xa từ menu: thẻ trên đường nhảy KHÔNG bị đánh dấu; '
      'vuốt một lần sang đúng card kế', (tester) async {
    final server = _Server(_menuDoc());
    await _open(tester, server);
    await _debounce(tester);
    // Tiền đề: lúc mở màn mới chỉ thấy c1 của s3 (thẻ cao), c2/c3 chưa hiện.
    expect(server.putCards('s3'), isNot(contains('c2')));
    expect(server.putCards('s3'), isNot(contains('c3')));

    await _openMenu(tester);
    await _showRow(tester, 's4');
    await tester.tap(_row('s4'));
    await tester.pumpAndSettle();
    await _debounce(tester);
    expect(server.putCards('s3'), isNot(contains('c2')));
    expect(server.putCards('s3'), isNot(contains('c3')));
    expect(_kickerTop(tester, 'SCALE'), closeTo(0, 1.5));

    // Vuốt một lần: card kế của vị trí mới = c2 của s4 (c1 nằm ngay đầu section).
    Finder card(String id) => find.byKey(Key('sd-card-s4-$id'));
    double top(String id) =>
        tester.getTopLeft(card(id)).dy - tester.getTopLeft(_paper).dy;
    await tester.fling(_paper, const Offset(0, -150), 2500);
    await tester.pumpAndSettle();
    expect(top('c2'), closeTo(0, 1.5));
    await _debounce(tester);
    expect(server.putCards('s3'), isNot(contains('c2')));
    expect(server.putCards('s3'), isNot(contains('c3')));
    // Nhảy lùi về s2 rồi vuốt: không làm lộ thẻ s3 bị bỏ qua.
    await _openMenu(tester);
    await _showRow(tester, 's2');
    await tester.tap(_row('s2'));
    await tester.pumpAndSettle();
    await _debounce(tester);
    expect(server.putCards('s3'), isNot(contains('c2')));
    expect(server.putCards('s3'), isNot(contains('c3')));
  });

  testWidgets(
    '(f) 200 section: mở nhanh, tự cuộn tới dòng đang đọc, cuộn được',
    (tester) async {
      final secs = [
        for (var i = 1; i <= 200; i++)
          _section(
            's$i',
            i,
            chapter: 'Ch ${(i - 1) ~/ 10 + 1}',
            chapterPos: (i - 1) ~/ 10 + 1,
            unlocked: i <= 130,
            done: i < 120,
            cards: 1,
            lines: 2,
          ),
      ];
      await _open(tester, _Server(_doc(secs)), sectionId: 's120');
      await _openMenu(tester);
      expect(_sheet, findsOneWidget);
      // Lazy: chỉ dựng một phần nhỏ trong 200 dòng.
      final built = find.descendant(of: _sheet, matching: find.byType(InkWell));
      expect(built.evaluate().length, lessThan(40));
      // Tự cuộn tới dòng đang đọc (s120) nằm trong sheet.
      expect(_row('s120'), findsOneWidget);
      final sheetRect = tester.getRect(_sheet);
      expect(sheetRect.contains(tester.getCenter(_row('s120'))), isTrue);
      expect(_row('s1'), findsNothing);
      // Cuộn tiếp tới section khoá cuối cùng.
      await tester.scrollUntilVisible(
        _row('s200'),
        600,
        scrollable: find
            .descendant(of: _sheet, matching: find.byType(Scrollable))
            .first,
      );
      expect(_in(_row('s200'), Icons.lock), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final c in [(320.0, 1.0), (390.0, 1.5), (320.0, 1.5), (800.0, 1.0)]) {
    testWidgets('(g) không overflow ở ${c.$1.toInt()}px, chữ x${c.$2}', (
      tester,
    ) async {
      await _open(
        tester,
        _Server(_menuDoc()),
        w: c.$1,
        h: 800,
        textScale: c.$2,
      );
      expect(tester.takeException(), isNull);
      await _openMenu(tester);
      expect(_sheet, findsOneWidget);
      expect(_row('s3'), findsOneWidget);
      await _showRow(tester, 's5');
      await tester.tap(_row('s5')); // khoá → SnackBar trên sheet
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('(h) semantics: nhãn trạng thái, button, đích chạm >= 48dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester, _Server(_menuDoc()), h: 1400);
    await _openMenu(tester);
    for (final e in {
      's1': 'đã xong',
      's3': 'đang đọc',
      's4': 'chưa xong',
      's5': 'chưa mở',
    }.entries) {
      final label = 'Section ${e.key}, ${e.value}';
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(isButton: true, hasTapAction: true),
        reason: label,
      );
    }
    for (var i = 1; i <= 8; i++) {
      final size = tester.getSize(_row('s$i'));
      expect(size.height, greaterThanOrEqualTo(48), reason: 's$i');
      expect(size.width, greaterThanOrEqualTo(48), reason: 's$i');
    }
    final mb = tester.getSize(_menuBtn);
    expect(mb.shortestSide, greaterThanOrEqualTo(48));
    handle.dispose();
  });
}
