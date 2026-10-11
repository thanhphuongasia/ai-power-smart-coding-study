import 'package:flutter_test/flutter_test.dart';
import 'support/content_fixture.dart';
import 'package:smart_coding_study/domain/merge.dart';
import 'package:smart_coding_study/domain/models.dart';
import 'package:smart_coding_study/features/exercise/session_controller.dart';

const _splitSolution =
    'def split_chunks(text, size):\n'
    '    chunks = []\n'
    '    for i in range(0, len(text), size):\n'
    '        chunks.append(text[i:i + size])\n'
    '    return chunks';

Map<String, String> _cells(Exercise e) => {
  for (final b in e.blocks) b.label: b.acceptedAnswers.first,
};

Block _block(String label, int indent) => Block(
  id: 'x-$label',
  title: '',
  prompt: '',
  indentLevel: indent,
  acceptedAnswers: const [''],
  expectedOutput: '',
  hints: const ['', '', ''],
  vocab: const ['x'],
  label: label,
);

void main() {
  final split = testContent.exerciseById('split-chunks');

  test('ghép lời giải split-chunks ra đúng chuỗi tham chiếu', () {
    expect(mergeCells(split, _cells(split)).code, _splitSolution);
  });

  test('ô 2 dòng giữ thụt tương đối, lineOrigin đúng từng dòng', () {
    final e = Exercise(
      id: 't',
      title: 't',
      functionName: 'f',
      params: const [],
      blocks: [_block('A', 1)],
      template: 'def f(x):\n    # TODO A\n    return 1',
    );
    final m = mergeCells(e, {'A': 'if x:\n    y = 1'});
    expect(m.code, 'def f(x):\n    if x:\n        y = 1\n    return 1');
    expect(m.lineOrigin, [null, 'A', 'A', null]);
    expect(m.lineOrigin.length, m.code.split('\n').length);
  });

  test('ô có tab, dòng trống đầu/cuối và thụt thừa được chuẩn hoá', () {
    final e = Exercise(
      id: 't',
      title: 't',
      functionName: 'f',
      params: const [],
      blocks: [_block('A', 1)],
      template: 'def f(x):\n    # TODO A',
    );
    final m = mergeCells(e, {'A': '\n\n  \tif x:\n  \t\ty = 1\n\n'});
    expect(m.code, 'def f(x):\n    if x:\n        y = 1');
    expect(m.lineOrigin, [null, 'A', 'A']);
    expect(m.code.endsWith('\n'), isFalse);
  });

  test('thiếu ô → ArgumentError', () {
    expect(() => mergeCells(split, {'A': 'x', 'B': 'y'}), throwsArgumentError);
  });

  test('lineOrigin của split-chunks: khoá, khoá, A, B, C', () {
    final m = mergeCells(split, _cells(split));
    expect(m.lineOrigin, [null, null, 'A', 'B', 'C']);
  });

  test('templateSegments split-chunks = Locked(2 dòng), A, B, C', () {
    final segs = templateSegments(split);
    expect(segs.length, 4);
    expect((segs[0] as LockedSegment).code.split('\n').length, 2);
    expect(segs.skip(1).map((s) => (s as TodoSegment).block.label).toList(), [
      'A',
      'B',
      'C',
    ]);
  });

  Block blk(String label, String answer) => Block(
    id: 'x-$label',
    title: '',
    prompt: '',
    indentLevel: 1,
    acceptedAnswers: [answer],
    expectedOutput: '',
    hints: const ['', '', ''],
    vocab: const ['x'],
    label: label,
  );

  Exercise ex(String template, List<Block> blocks, {String? cls}) => Exercise(
    id: 't',
    title: 't',
    functionName: 'search',
    className: cls,
    params: const ['origin', 'dest'],
    blocks: blocks,
    template: template,
  );

  test('cellLocation split-chunks: A,C trong hàm; B qua đáp án ô A', () {
    expect(cellLocation(split, 'A'), 'trong hàm');
    expect(cellLocation(split, 'B'), 'trong vòng for');
    expect(cellLocation(split, 'C'), 'trong hàm');
    expect(cellLocation(split, 'Z'), '');
  });

  const methodTemplate =
      'class FlightService:\n'
      '    def __init__(self):\n'
      '        self.flights = []\n'
      '\n'
      '    def search(self, origin, dest):\n'
      '        result = []\n'
      '        # TODO A\n'
      '            # TODO B\n'
      '        return result';
  final method = ex(methodTemplate, [
    blk('A', 'for f in self.flights:'),
    blk('B', 'result.append(f)'),
  ], cls: 'FlightService');

  test('cellLocation method: A trong method, B theo đáp án A', () {
    expect(cellLocation(method, 'A'), 'trong method');
    expect(cellLocation(method, 'B'), 'trong vòng for');
  });

  test('cellLocation: cha if, class level, hàm tự do', () {
    final e = ex(
      'class C:\n    # TODO A\n    def f(self):\n        if x:\n'
      '            # TODO B',
      [blk('A', 'x = 1'), blk('B', 'pass')],
      cls: 'C',
    );
    expect(cellLocation(e, 'A'), 'trong class');
    expect(cellLocation(e, 'B'), 'trong if');
    expect(cellLocation(ex('# TODO A', [blk('A', 'x')]), 'A'), '');
  });

  test('knownIdentifiersFor method có self, tên class, thuộc tính', () {
    final ids = knownIdentifiersFor(method, 0);
    expect(ids, containsAll(['self', 'FlightService', 'flights', 'search']));
    final free = knownIdentifiersFor(split, 0);
    expect(free.contains('self'), isFalse);
  });
}
