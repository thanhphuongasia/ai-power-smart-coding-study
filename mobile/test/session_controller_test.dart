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
    test('khởi tạo từ seedCompletedBlocks', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final progress = container.read(progressProvider);

      expect(progress['split-chunks']!.completedBlocks, 2);
      expect(progress['overlap-chunks']!.completedBlocks, 0);
    });

    test(
      'markBlockPassed chỉ tăng khi blockIndex đúng bằng block đang active',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(progressProvider.notifier);

        // split-chunks đang ở completedBlocks=2 → block active là index 2.
        notifier.markBlockPassed('split-chunks', 0);
        expect(
          container.read(progressProvider)['split-chunks']!.completedBlocks,
          2,
          reason: 'index sai (không phải block active) thì không tăng',
        );

        notifier.markBlockPassed('split-chunks', 2);
        expect(
          container.read(progressProvider)['split-chunks']!.completedBlocks,
          3,
        );
      },
    );

    test('blockStatusOf trả done/active/locked đúng theo completedBlocks', () {
      const progress = ExerciseProgress(
        completedBlocks: 2,
        drafts: {},
        hintsUsed: {},
      );

      expect(blockStatusOf(progress, 0), BlockStatus.done);
      expect(blockStatusOf(progress, 1), BlockStatus.done);
      expect(blockStatusOf(progress, 2), BlockStatus.active);
      expect(blockStatusOf(progress, 3), BlockStatus.locked);
      expect(blockStatusOf(progress, 4), BlockStatus.locked);
    });

    test('useHint tối đa 3 mỗi block', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(progressProvider.notifier);

      expect(notifier.useHint('split-chunks', 'split-chunks-b2'), 1);
      expect(notifier.useHint('split-chunks', 'split-chunks-b2'), 2);
      expect(notifier.useHint('split-chunks', 'split-chunks-b2'), 3);
      expect(
        notifier.useHint('split-chunks', 'split-chunks-b2'),
        3,
        reason: 'gọi lần thứ 4 vẫn dừng ở 3',
      );

      final progress = container.read(progressProvider)['split-chunks']!;
      expect(progress.hintsUsed['split-chunks-b2'], 3);
    });

    test(
      'draft và hint sống qua việc sessionProvider (autoDispose) bị huỷ',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Đọc sessionProvider để dựng SessionController (giống lúc mở màn
        // làm bài).
        container.read(sessionProvider('split-chunks'));

        final progressNotifier = container.read(progressProvider.notifier);
        progressNotifier.saveDraft(
          'split-chunks',
          'split-chunks-b2',
          'for i in range(0, len(text), size)',
        );
        progressNotifier.useHint('split-chunks', 'split-chunks-b2');

        // Rời màn hình: sessionProvider (autoDispose) bị huỷ.
        container.invalidate(sessionProvider('split-chunks'));

        final progress = container.read(progressProvider)['split-chunks']!;
        expect(
          progress.drafts['split-chunks-b2'],
          'for i in range(0, len(text), size)',
        );
        expect(progress.hintsUsed['split-chunks-b2'], 1);
      },
    );
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
          expect(state.elapsed, greaterThanOrEqualTo(const Duration(seconds: 30)));
          expect(state.phase, SessionPhase.active);
          // Vẫn chỉ 1 timer, không tạo cái mới.
          expect(async.pendingTimers.length, 1);
        });
      },
    );

    test(
      'start() sau timedOut → reset elapsed về 0, khởi động lại phiên',
      () {
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
      },
    );
  });

  group('SessionController.run', () {
    test('pass → markBlockPassed và trả RunResult của runBlock', () {
      _withFakeSession((async, container, listen) {
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );

        // split-chunks đang ở completedBlocks=2 → block active là b2:
        // 'for i in range(0, len(text), size):'.
        final result = controller.run(
          2,
          'for i in range(0, len(text), size):',
        );

        expect(result.passed, isTrue);
        expect(
          container.read(progressProvider)['split-chunks']!.completedBlocks,
          3,
        );
      });
    });

    test('sai → không markBlockPassed', () {
      _withFakeSession((async, container, listen) {
        final controller = container.read(
          sessionProvider('split-chunks').notifier,
        );

        final result = controller.run(2, 'code sai hoàn toàn');

        expect(result.passed, isFalse);
        expect(
          container.read(progressProvider)['split-chunks']!.completedBlocks,
          2,
        );
      });
    });
  });

  group('knownIdentifiersFor', () {
    final exercise = exerciseById('split-chunks');

    test('block 0 chỉ có params', () {
      expect(
        knownIdentifiersFor(exercise, 0),
        containsAll(<String>['text', 'size']),
      );
      expect(knownIdentifiersFor(exercise, 0), isNot(contains('chunks')));
    });

    test('block 2 có thêm chunks (gán ở block 1)', () {
      final identifiers = knownIdentifiersFor(exercise, 2);
      expect(identifiers, containsAll(<String>['text', 'size', 'chunks']));
      expect(identifiers, isNot(contains('i')));
    });

    test('block 3 có thêm i (biến lặp ở block 2)', () {
      final identifiers = knownIdentifiersFor(exercise, 3);
      expect(
        identifiers,
        containsAll(<String>['text', 'size', 'chunks', 'i']),
      );
    });
  });
}
