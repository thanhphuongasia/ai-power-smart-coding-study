import 'dart:math';

import '../models/app_sync_models.dart';
import '../models/learning_models.dart';
import '../services/app_api_service.dart';
import '../storage/local_app_store.dart';

abstract class LearnerRepository {
  Future<LearnerProfile> bootstrapLearner();

  Future<LearnerProfile?> readCachedLearnerProfile();

  Future<Map<String, SkillMasteryRecord>> readCachedSkillMemory();

  Future<List<ReviewTask>> readCachedReviewQueue();

  Future<DashboardStats?> readCachedDashboard();

  Future<Set<String>> readCachedCompletedExerciseIds();

  Future<String?> readCachedPreferredLanguageId();

  Future<void> savePreferredLanguageId(String? languageId);

  Future<void> saveDerivedState({
    required Map<String, SkillMasteryRecord> skillMemory,
    required List<ReviewTask> reviewQueue,
    required DashboardStats dashboardStats,
    required Set<String> completedExerciseIds,
  });

  Future<bool> refreshLearnerState();
}

class AppApiLearnerRepository implements LearnerRepository {
  AppApiLearnerRepository({
    required LocalAppStore localAppStore,
    required AppApiService appApiService,
    DeviceInfoSnapshot? deviceInfo,
  })  : _localAppStore = localAppStore,
        _appApiService = appApiService,
        _deviceInfo = deviceInfo ??
            const DeviceInfoSnapshot(
              platform: 'flutter',
              appVersion: '1.0.0',
              locale: 'en',
            );

  final LocalAppStore _localAppStore;
  final AppApiService _appApiService;
  final DeviceInfoSnapshot _deviceInfo;

  @override
  Future<LearnerProfile> bootstrapLearner() async {
    final document = await _localAppStore.read();
    final cached = document.learnerProfile;
    if (cached != null) {
      return cached;
    }

    final installId = document.installId ?? _generateInstallId();
    LearnerProfile learnerProfile;
    if (_appApiService.isConfigured) {
      try {
        learnerProfile = await _appApiService.bootstrapAnonymousLearner(
          installId: installId,
          deviceInfo: _deviceInfo,
        );
      } catch (_) {
        learnerProfile = LearnerProfile(
          installId: installId,
          learnerId: 'offline-$installId',
          accessToken: '',
          syncCursor: 0,
          isOfflineOnly: true,
        );
      }
    } else {
      learnerProfile = LearnerProfile(
        installId: installId,
        learnerId: 'offline-$installId',
        accessToken: '',
        syncCursor: 0,
        isOfflineOnly: true,
      );
    }

    await _localAppStore.write(
      document.copyWith(
        installId: installId,
        learnerProfile: learnerProfile,
      ),
    );
    return learnerProfile;
  }

  @override
  Future<LearnerProfile?> readCachedLearnerProfile() async {
    final document = await _localAppStore.read();
    return document.learnerProfile;
  }

  @override
  Future<Map<String, SkillMasteryRecord>> readCachedSkillMemory() async {
    final document = await _localAppStore.read();
    return document.skillMemory;
  }

  @override
  Future<List<ReviewTask>> readCachedReviewQueue() async {
    final document = await _localAppStore.read();
    return document.reviewQueue;
  }

  @override
  Future<DashboardStats?> readCachedDashboard() async {
    final document = await _localAppStore.read();
    return document.dashboardStats;
  }

  @override
  Future<Set<String>> readCachedCompletedExerciseIds() async {
    final document = await _localAppStore.read();
    return document.completedExerciseIds;
  }

  @override
  Future<String?> readCachedPreferredLanguageId() async {
    final document = await _localAppStore.read();
    return document.preferredLanguageId;
  }

  @override
  Future<void> savePreferredLanguageId(String? languageId) async {
    final document = await _localAppStore.read();
    await _localAppStore.write(
      document.copyWith(
        preferredLanguageId: languageId,
        clearPreferredLanguageId: languageId == null,
      ),
    );
  }

  @override
  Future<void> saveDerivedState({
    required Map<String, SkillMasteryRecord> skillMemory,
    required List<ReviewTask> reviewQueue,
    required DashboardStats dashboardStats,
    required Set<String> completedExerciseIds,
  }) async {
    final document = await _localAppStore.read();
    await _localAppStore.write(
      document.copyWith(
        skillMemory: skillMemory,
        reviewQueue: reviewQueue,
        dashboardStats: dashboardStats,
        completedExerciseIds: completedExerciseIds,
      ),
    );
  }

  @override
  Future<bool> refreshLearnerState() async {
    if (!_appApiService.isConfigured) {
      return false;
    }

    final document = await _localAppStore.read();
    final learnerProfile = document.learnerProfile;
    if (learnerProfile == null) {
      return false;
    }

    final remoteState =
        await _appApiService.fetchLearnerState(learnerProfile: learnerProfile);
    await _localAppStore.write(
      document.copyWith(
        learnerProfile:
            learnerProfile.copyWith(syncCursor: remoteState.nextCursor),
        skillMemory: remoteState.skillMemory,
        reviewQueue: remoteState.reviewQueue,
        dashboardStats: remoteState.dashboard,
        completedExerciseIds: remoteState.completedExerciseIds,
        lastSyncedAt: DateTime.now(),
      ),
    );
    return true;
  }

  String _generateInstallId() {
    final random = Random();
    final entropy = List.generate(
      4,
      (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
    return 'install-$entropy';
  }
}

class MemoryLearnerRepository implements LearnerRepository {
  MemoryLearnerRepository({
    required LearnerProfile learnerProfile,
    Map<String, SkillMasteryRecord> skillMemory =
        const <String, SkillMasteryRecord>{},
    List<ReviewTask> reviewQueue = const <ReviewTask>[],
    DashboardStats? dashboardStats,
    Set<String> completedExerciseIds = const <String>{},
    String? preferredLanguageId,
  })  : _learnerProfile = learnerProfile,
        _skillMemory = Map<String, SkillMasteryRecord>.from(skillMemory),
        _reviewQueue = List<ReviewTask>.from(reviewQueue),
        _dashboardStats = dashboardStats,
        _completedExerciseIds = Set<String>.from(completedExerciseIds),
        _preferredLanguageId = preferredLanguageId;

  final LearnerProfile _learnerProfile;
  Map<String, SkillMasteryRecord> _skillMemory;
  List<ReviewTask> _reviewQueue;
  DashboardStats? _dashboardStats;
  Set<String> _completedExerciseIds;
  String? _preferredLanguageId;

  @override
  Future<LearnerProfile> bootstrapLearner() async => _learnerProfile;

  @override
  Future<LearnerProfile?> readCachedLearnerProfile() async => _learnerProfile;

  @override
  Future<Map<String, SkillMasteryRecord>> readCachedSkillMemory() async =>
      _skillMemory;

  @override
  Future<List<ReviewTask>> readCachedReviewQueue() async => _reviewQueue;

  @override
  Future<DashboardStats?> readCachedDashboard() async => _dashboardStats;

  @override
  Future<Set<String>> readCachedCompletedExerciseIds() async =>
      _completedExerciseIds;

  @override
  Future<String?> readCachedPreferredLanguageId() async => _preferredLanguageId;

  @override
  Future<void> savePreferredLanguageId(String? languageId) async {
    _preferredLanguageId = languageId;
  }

  @override
  Future<void> saveDerivedState({
    required Map<String, SkillMasteryRecord> skillMemory,
    required List<ReviewTask> reviewQueue,
    required DashboardStats dashboardStats,
    required Set<String> completedExerciseIds,
  }) async {
    _skillMemory = Map<String, SkillMasteryRecord>.from(skillMemory);
    _reviewQueue = List<ReviewTask>.from(reviewQueue);
    _dashboardStats = dashboardStats;
    _completedExerciseIds = Set<String>.from(completedExerciseIds);
  }

  @override
  Future<bool> refreshLearnerState() async => false;
}
