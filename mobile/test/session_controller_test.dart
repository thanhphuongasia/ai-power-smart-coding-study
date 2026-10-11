// fake_async là dependency transitive (qua flutter_test) — dùng trực tiếp
// để giả lập Timer/clock trong test, không sleep thật. pubspec.yaml không
// thuộc phạm vi sửa của task này (xem T-04.md Forbidden).
// ignore_for_file: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_coding_study/data/seed.dart';
import 'package:smart_coding_study/features/exercise/session_controller.dart';
import 'package:smart_coding_study/features/exercise/session_providers.dart';
import 'package:smart_coding_study/features/stats/activity.dart';

/// Chạy [body] trong một [ProviderContainer] mà [clockProvider] đọc thời
/// gian từ [FakeAsync] — cho phép test Timer.periodic bằng `async.elapse`
/// thay vì chờ thời gian thật.
///
/// `sessionProvider` là `autoDispose`: giống widget thật phải `ref.watch`
/// nó để giữ sống, [body] nhận `listen(exerciseId)` để giả lập việc đó —
/// đóng subscription trả về (`.close()`) để giả lập rời màn hình.
void _withFakeSession(
  void Function(
    FakeAsync async,
    ProviderContainer container,
    ProviderSubscription<SessionState> Function(String exerciseId) listen,
  )
  body,
) {
  fakeAsync((async) {
    final fakeClock = async.getClock(DateTime(2024, 1, 1));
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(fakeClock.now)],
    );
    addTearDown(container.dispose);
    ProviderSubscription<SessionState> listen(String exerciseId) {
      return container.listen(sessionProvider(exerciseId), (_, _) {});
    }

    body(async, container, listen);
    async.flushTimers();
  });
}

void main() {
  group('ProgressController', () {
    test('khởi tạo từ seedPassedExercises + seedDrafts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final progress = container.read(progressProvider);

      expect(progress['clean-text']!.passed, isTrue);
      expect(
        progress['clean-text']!.completedBlocks,
        exerciseById('clean-text').blocks.length,
      );
      expect(progress['split-chunks']!.passed, isFalse);
      expect(progress['split-chunks']!.completedBlocks, 0);
      expect(
        progress['split-chunks']!.drafts['A'],
        'for i in range(0, len(text), size):',
      );
      expect(progress['overlap-chunks'], isNull);
    });

    test('markPassed ⇒ passed và completedBlocks == số ô của bài', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(progressProvider.notifier).markPassed('split-chunks');

      final p = container.read(progressProvider)['split-chunks']!;
      expect(p.passed, isTrue);
      expect(p.completedBlocks, exerciseById('split-chunks').blocks.length);
      expect(p.drafts['A'], isNotNull, reason: 'draft không bị mất');
    });

    test('markPassed bài chưa có entry vẫn đúng', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(progressProvider.notifier).markPassed('overlap-chunks');

      final p = container.read(progressProvider)['overlap-chunks']!;
      expect(p.passed, isTrue);
      expect(p.completedBlocks, exerciseById('overlap-chunks').blocks.length);
    });

    test('markPassed ghi activity đúng một lần (idempotent)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final before = container.read(activityProvider);
      final notifier = container.read(progressProvider.notifier);

      notifier.markPassed('split-chunks');
      final afterFirst = container.read(activityProvider);
      notifier.markPassed('split-chunks');
      final afterSecond = container.read(activityProvider);

      expect(afterFirst, isNot(equals(before)));
      expect(afterSecond, equals(afterFirst));
    });

    test('markBlockPassed (deprecated): chỉ block cuối mới pass cả bài', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(progressProvider.notifier);

      // ignore: deprecated_member_use_from_same_package
      notifier.markBlockPassed('split-chunks', 0);
      expect(container.read(progressProvider)['split-chunks']!.passed, isFalse);

      // ignore: deprecated_member_use_from_same_package
      notifier.markBlockPassed('split-chunks', 2);
      expect(container.read(progressProvider)['split-chunks']!.passed, isTrue);
    });

    test('useHint tối đa 3 mỗi ô (key = nhãn)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(progressProvider.notifier);

      expect(notifier.useHint('split-chunks', 'B'), 1);
      expect(notifier.useHint('split-chunks', 'B'), 2);
      expect(notifier.useHint('split-chunks', 'B'), 3);
      expect(
        notifier.useHint('split-chunks', 'B'),
        3,
        reason: 'gọi lần thứ 4 vẫn dừng ở 3',
      );

      final progress = container.read(progressProvider)['split-chunks']!;
      expect(progress.hintsUsed['B'], 3);
    });

    test('viewSolution ghi nhận nhãn ô, gọi lại không đổi', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(progressProvider.notifier);

      notifier.viewSolution('split-chunks', 'B');
      notifier.viewSolution('split-chunks', 'B');

      expect(container.read(progressProvider)['split-chunks']!.solutionViewed, {
        'B',
      });
    });

    test('draft, hint, lời giải sống qua việc sessionProvider bị huỷ', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(sessionProvider('split-chunks'));

      final progressNotifier = container.read(progressProvider.notifier);
      progressNotifier.saveDraft('split-chunks', 'B', 'chunks.append(x)');
      progressNotifier.useHint('split-chunks', 'B');
      progressNotifier.viewSolution('split-chunks', 'C');

      // Rời màn hình: sessionProvider (autoDispose) bị huỷ.
      container.invalidate(sessionProvider('split-chunks'));

      final progress = container.read(progressProvider)['split-chunks']!;
      expect(progress.drafts['B'], 'chunks.append(x)');
      expect(progress.hintsUsed['B'], 1);
      expect(progress.solutionViewed, {'C'});
    });
  });

  group('inProgressExerciseProvider / exerciseUnlockedProvider', () {
    test('seed: split-chunks đang làm dở (INV-09)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(inProgressExerciseProvider)?.id, 'split-chunks');
    });

    test('hết dở khi passed, hoặc khi draft rỗng toàn bộ', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(progressProvider.notifier);

      notifier.saveDraft('split-chunks', 'A', '   ');
      expect(container.read(inProgressExerciseProvider), isNull);

      notifier.saveDraft('split-chunks', 'A', 'x');
      expect(container.read(inProgressExerciseProvider)?.id, 'split-chunks');

      notifier.markPassed('split-chunks');
      expect(container.read(inProgressExerciseProvider), isNull);
    });

    test('draft ở bài chưa mở vẫn không làm dở bài đã passed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(progressProvider.notifier);

      notifier.saveDraft('clean-text', 'A', 'x'); // clean-text đã passed
      notifier.saveDraft('split-chunks', 'A', '');
      expect(container.read(inProgressExerciseProvider), isNull);
    });

    test('overlap-chunks khoá tới khi split-chunks pass (INV-08)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(exerciseUnlockedProvider('overlap-chunks')),
        isFalse,
      );
      expect(container.read(exerciseUnlockedProvider('split-chunks')), isTrue);

      container.read(progressProvider.notifier).markPassed('split-chunks');

      expect(
        container.read(exerciseUnlockedProvider('overlap-chunks')),
        isTrue,
      );
    });
  });

  group('SessionController — timer/idle/timeout', () {
    test('start() đếm elapsed mỗi giây qua clockProvider', () {
      _withFakeSession((async, container, listen) {
        listen('split-chunks');
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );
        controller.start();

        async.elapse(const Duration(seconds: 5));

        final state = container.read(sessionProvider('split-chunks'));
        expect(state.elapsed, const Duration(seconds: 5));
        expect(state.phase, SessionPhase.active);
        expect(state.idleCountdownSeconds, 0);
      });
    });

    test('không hoạt động đủ idleThreshold → phase idle, đếm ngược 60→0', () {
      _withFakeSession((async, container, listen) {
        listen('split-chunks');
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );
        controller.start();

        // Ngay trước ngưỡng idle: vẫn active.
        async.elapse(idleThreshold - const Duration(seconds: 1));
        expect(
          container.read(sessionProvider('split-chunks')).phase,
          SessionPhase.active,
        );

        // Chạm ngưỡng idle.
        async.elapse(const Duration(seconds: 1));
        var state = container.read(sessionProvider('split-chunks'));
        expect(state.phase, SessionPhase.idle);
        expect(state.idleCountdownSeconds, 60);

        // Đếm ngược tiếp.
        async.elapse(const Duration(seconds: 30));
        state = container.read(sessionProvider('split-chunks'));
        expect(state.phase, SessionPhase.idle);
        expect(state.idleCountdownSeconds, 30);
      });
    });

    test('activity()/resume() đưa về active và reset mốc idle', () {
      _withFakeSession((async, container, listen) {
        listen('split-chunks');
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );
        controller.start();

        async.elapse(idleThreshold);
        expect(
          container.read(sessionProvider('split-chunks')).phase,
          SessionPhase.idle,
        );

        controller.resume();
        var state = container.read(sessionProvider('split-chunks'));
        expect(state.phase, SessionPhase.active);
        expect(state.idleCountdownSeconds, 0);

        // Sau resume, phải mất lại đủ idleThreshold mới idle lại — 1 phút
        // sau đó vẫn active.
        async.elapse(const Duration(minutes: 1));
        state = container.read(sessionProvider('split-chunks'));
        expect(state.phase, SessionPhase.active);

        controller.activity();
        async.elapse(const Duration(seconds: 1));
        state = container.read(sessionProvider('split-chunks'));
        expect(state.phase, SessionPhase.active);
      });
    });

    test('hết đếm ngược idle (60s) → timedOut', () {
      _withFakeSession((async, container, listen) {
        listen('split-chunks');
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );
        controller.start();

        async.elapse(idleThreshold + idleCountdown);

        final state = container.read(sessionProvider('split-chunks'));
        expect(state.phase, SessionPhase.timedOut);
      });
    });

    test('elapsed >= maxSessionDuration → timedOut dù vẫn active', () {
      _withFakeSession((async, container, listen) {
        listen('split-chunks');
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );
        controller.start();

        // Giữ active bằng cách gọi activity() trước khi chạm idleThreshold,
        // cho tới khi tổng thời gian chạm maxSessionDuration.
        var remaining = maxSessionDuration;
        const step = Duration(minutes: 1);
        while (remaining > step) {
          async.elapse(step);
          controller.activity();
          remaining -= step;
        }
        async.elapse(remaining);

        final state = container.read(sessionProvider('split-chunks'));
        expect(state.phase, SessionPhase.timedOut);
        expect(state.elapsed, maxSessionDuration);
      });
    });

    test('stop() huỷ timer, elapsed ngừng tăng', () {
      _withFakeSession((async, container, listen) {
        listen('split-chunks');
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );
        controller.start();

        async.elapse(const Duration(seconds: 3));
        controller.stop();
        expect(async.pendingTimers.length, 0);

        async.elapse(const Duration(seconds: 10));
        final state = container.read(sessionProvider('split-chunks'));
        expect(state.elapsed, const Duration(seconds: 3));
      });
    });

    test('rời màn hình (huỷ subscription) → autoDispose huỷ timer', () {
      _withFakeSession((async, container, listen) {
        final sub = listen('split-chunks');
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );
        controller.start();
        async.elapse(const Duration(seconds: 2));
        expect(async.pendingTimers.length, 1);

        // Rời màn hình: không còn ai watch sessionProvider nữa →
        // autoDispose gọi ref.onDispose → huỷ timer.
        sub.close();
        async.elapse(Duration.zero);

        expect(async.pendingTimers.length, 0);
      });
    });

    test(
      'start() idempotent: gọi lại khi timer đang chạy → elapsed không reset',
      () {
        _withFakeSession((async, container, listen) {
          listen('split-chunks');
          final controller = container.read(
            sessionProvider('split-chunks').notifier,
          );
          controller.start();

          // Đếm giờ được 30 giây.
          async.elapse(const Duration(seconds: 30));
          var state = container.read(sessionProvider('split-chunks'));
          expect(state.elapsed, const Duration(seconds: 30));
          expect(state.phase, SessionPhase.active);

          // Gọi start() lần thứ 2 — phải idempotent, elapsed vẫn ≥30s.
          controller.start();
          state = container.read(sessionProvider('split-chunks'));
          expect(
            state.elapsed,
            greaterThanOrEqualTo(const Duration(seconds: 30)),
          );
          expect(state.phase, SessionPhase.active);
          // Vẫn chỉ 1 timer, không tạo cái mới.
          expect(async.pendingTimers.length, 1);
        });
      },
    );

    test('start() sau timedOut → reset elapsed về 0, khởi động lại phiên', () {
      _withFakeSession((async, container, listen) {
        listen('split-chunks');
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );
        controller.start();

        // Đếm quá maxSessionDuration để trigger timedOut.
        async.elapse(maxSessionDuration);
        var state = container.read(sessionProvider('split-chunks'));
        expect(state.phase, SessionPhase.timedOut);

        // Gọi start() lúc timedOut → reset, khởi động lại.
        controller.start();
        state = container.read(sessionProvider('split-chunks'));
        expect(state.elapsed, const Duration(seconds: 0));
        expect(state.phase, SessionPhase.active);
        // Có timer chạy lại.
        expect(async.pendingTimers.length, 1);
      });
    });
  });

  group('SessionController.run (deprecated)', () {
    test('block cuối đúng → pass cả bài; block giữa đúng → chưa', () {
      _withFakeSession((async, container, listen) {
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );

        // ignore: deprecated_member_use_from_same_package
        final mid = controller.run(0, 'for i in range(0, len(text), size):');
        expect(mid.passed, isTrue);
        expect(
          container.read(progressProvider)['split-chunks']!.passed,
          isFalse,
        );

        // ignore: deprecated_member_use_from_same_package
        final last = controller.run(2, 'return chunks');
        expect(last.passed, isTrue);
        expect(
          container.read(progressProvider)['split-chunks']!.passed,
          isTrue,
        );
      });
    });

    test('sai → không đánh dấu passed', () {
      _withFakeSession((async, container, listen) {
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );

        // ignore: deprecated_member_use_from_same_package
        final result = controller.run(2, 'code sai hoàn toàn');

        expect(result.passed, isFalse);
        expect(
          container.read(progressProvider)['split-chunks']!.passed,
          isFalse,
        );
      });
    });
  });

  group('knownIdentifiersFor', () {
    final exercise = exerciseById('split-chunks');

    test('luôn có tên hàm, tham số và biến gán trong template', () {
      expect(
        knownIdentifiersFor(exercise, 0),
        containsAll(<String>['split_chunks', 'text', 'size', 'chunks']),
      );
      expect(knownIdentifiersFor(exercise, 0), isNot(contains('i')));
    });

    test('block 1 có thêm i (biến lặp ở ô A)', () {
      expect(
        knownIdentifiersFor(exercise, 1),
        containsAll(<String>['split_chunks', 'text', 'size', 'chunks', 'i']),
      );
    });
  });
}
