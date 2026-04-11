import '../models/app_sync_models.dart';
import '../services/app_api_service.dart';
import '../storage/local_app_store.dart';

abstract class SyncRepository {
  Future<List<PendingSyncEvent>> readPendingEvents();

  Future<void> enqueueEvent(PendingSyncEvent event);

  Future<bool> flushPendingEvents({
    required LearnerProfile learnerProfile,
  });
}

class AppApiSyncRepository implements SyncRepository {
  AppApiSyncRepository({
    required LocalAppStore localAppStore,
    required AppApiService appApiService,
  })  : _localAppStore = localAppStore,
        _appApiService = appApiService;

  final LocalAppStore _localAppStore;
  final AppApiService _appApiService;

  @override
  Future<List<PendingSyncEvent>> readPendingEvents() async {
    final document = await _localAppStore.read();
    return document.pendingEvents;
  }

  @override
  Future<void> enqueueEvent(PendingSyncEvent event) async {
    final document = await _localAppStore.read();
    await _localAppStore.write(
      document.copyWith(
        pendingEvents: <PendingSyncEvent>[
          ...document.pendingEvents,
          event,
        ],
      ),
    );
  }

  @override
  Future<bool> flushPendingEvents({
    required LearnerProfile learnerProfile,
  }) async {
    if (!_appApiService.isConfigured || learnerProfile.isOfflineOnly) {
      return false;
    }

    final document = await _localAppStore.read();
    if (document.pendingEvents.isEmpty) {
      return false;
    }

    final result = await _appApiService.flushEvents(
      learnerProfile: learnerProfile,
      events: document.pendingEvents,
    );
    final accepted = result.acceptedClientEventIds.toSet();

    await _localAppStore.write(
      document.copyWith(
        learnerProfile: learnerProfile.copyWith(syncCursor: result.nextCursor),
        pendingEvents: document.pendingEvents
            .where((event) => !accepted.contains(event.clientEventId))
            .toList(growable: false),
        lastSyncedAt: DateTime.now(),
      ),
    );
    return accepted.isNotEmpty;
  }
}

class MemorySyncRepository implements SyncRepository {
  MemorySyncRepository({
    List<PendingSyncEvent> pendingEvents = const <PendingSyncEvent>[],
  }) : _pendingEvents = List<PendingSyncEvent>.from(pendingEvents);

  List<PendingSyncEvent> _pendingEvents;

  @override
  Future<List<PendingSyncEvent>> readPendingEvents() async => _pendingEvents;

  @override
  Future<void> enqueueEvent(PendingSyncEvent event) async {
    _pendingEvents = <PendingSyncEvent>[
      ..._pendingEvents,
      event,
    ];
  }

  @override
  Future<bool> flushPendingEvents({
    required LearnerProfile learnerProfile,
  }) async {
    _pendingEvents = const <PendingSyncEvent>[];
    return true;
  }
}
