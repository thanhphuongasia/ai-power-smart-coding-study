import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/features/exercise/completion_engine.dart';

const _known = ['text', 'size', 'chunks'];
const _vocab = ['range', 'len', 'append'];

List<String> labels(String before, {List<String> known = _known, List<String> vocab = _vocab, int limit = 8}) =>
    suggest(textBeforeCursor: before, knownIdentifiers: known, vocab: vocab, limit: limit)
        .map((s) => s.label)
        .toList();

Suggestion first(String before) =>
    suggest(textBeforeCursor: before, knownIdentifiers: _known, vocab: _vocab).first;

void main() {
  group('prefix', () {
    test('matches known identifier from partial word', () {
      expect(labels('    chu'), ['chunks']);
      expect(first('    chu').kind, SuggestionKind.known);
    });

    test('is case-insensitive', () {
      expect(labels('CHU'), ['chunks']);
      expect(labels('tr', known: const []), ['True']);
    });

    test('ranks known > vocab > keyword', () {
      final got = suggest(
        textBeforeCursor: 'r',
        knownIdentifiers: const ['result'],
        vocab: const ['range'],
      );
      expect(got.map((s) => s.label), ['result', 'range', 'return']);
      expect(got.map((s) => s.kind),
          [SuggestionKind.known, SuggestionKind.vocab, SuggestionKind.keyword]);
    });

    test('within a group: exact case first, then shorter', () {
      expect(
        labels('s', known: const ['Size', 'sizes', 'size'], vocab: const []),
        ['size', 'sizes', 'Size'],
      );
    });

    test('keeps original order on full ties', () {
      expect(labels('a', known: const ['ab', 'aa', 'ac'], vocab: const [])
          .take(3), ['ab', 'aa', 'ac']);
    });

    test('drops exact match of the word being typed', () {
      expect(labels('text'), isNot(contains('text')));
      expect(labels('size', known: const ['size', 'sizes']), ['sizes']);
    });

    test('dedupes across groups, highest group wins', () {
      final got = suggest(
          textBeforeCursor: 'ra', knownIdentifiers: const [], vocab: const ['range']);
      expect(got, [
        const Suggestion(label: 'range', insertText: 'range(', kind: SuggestionKind.vocab),
      ]);
    });

    test('respects limit', () {
      final many = List.generate(20, (i) => 'v$i');
      expect(labels('v', known: many, limit: 5), hasLength(5));
      expect(labels('v', known: many, limit: 0), isEmpty);
    });

    test('uses only the word right before the cursor', () {
      expect(labels('for i in range(0, len(te'), ['text']);
      expect(labels('    chunks.app'), ['append']);
    });

    test('no match → empty', () {
      expect(labels('zzz'), isEmpty);
      expect(labels('range(0'), isEmpty);
    });
  });

  group('insertText', () {
    test('callables open a paren', () {
      expect(first('ran').insertText, 'range(');
      expect(first('le').insertText, 'len(');
      expect(first('pri').insertText, 'print(');
      expect(first('chunks.ap').insertText, 'append(');
    });

    test('statement keywords add a space, identifiers stay bare', () {
      expect(first('fo').insertText, 'for ');
      expect(first('ret').insertText, 'return ');
      expect(first('chu').insertText, 'chunks');
      expect(first('Tr').insertText, 'True');
    });
  });

  group('context (no word typed yet)', () {
    test('after "for " → i then known', () {
      expect(labels('    for '), ['i', 'text', 'size', 'chunks']);
    });

    test('after "for i " → in', () {
      expect(labels('for i '), ['in']);
    });

    test('after "in " → range( then known', () {
      final got = suggest(
          textBeforeCursor: 'for i in ', knownIdentifiers: _known, vocab: _vocab);
      expect(got.first.insertText, 'range(');
      expect(got.map((s) => s.label), ['range', 'text', 'size', 'chunks']);
    });

    test('blank line start → known + for, return, if', () {
      expect(labels(''), ['text', 'size', 'chunks', 'for', 'return', 'if']);
      expect(labels('def f():\n    '), ['text', 'size', 'chunks', 'for', 'return', 'if']);
    });

    test('inside call args → known then vocab', () {
      expect(labels('range(0, '), ['text', 'size', 'chunks', 'range', 'len', 'append']);
    });

    test('after a dot → block vocab (methods)', () {
      expect(labels('chunks.'), ['range', 'len', 'append']);
    });

    test('word "for" inside identifier is not the for-context', () {
      expect(labels('before '), ['text', 'size', 'chunks', 'range', 'len', 'append']);
    });

    test('inside an open string or comment → nothing', () {
      expect(labels('print("te'), isEmpty);
      expect(labels('x = 1  # te'), isEmpty);
      expect(labels('print("a", te'), ['text']);
    });

    test('empty known + vocab still offers keywords on blank line', () {
      expect(labels('', known: const [], vocab: const []), ['for', 'return', 'if']);
    });
  });
}
