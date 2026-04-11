import 'app_sync_models.dart';
import 'learning_models.dart';
import 'learning_serialization.dart';

class AppCacheDocument {
  const AppCacheDocument({
    required this.installId,
    required this.contentManifest,
    required this.tracks,
    required this.skillNodes,
    required this.learnerProfile,
    required this.skillMemory,
    required this.reviewQueue,
    required this.dashboardStats,
    required this.completedMilestoneIds,
    required this.pendingEvents,
    required this.lastSyncedAt,
  });

  const AppCacheDocument.empty()
      : installId = null,
        contentManifest = null,
        tracks = const <LearningTrack>[],
        skillNodes = const <SkillNode>[],
        learnerProfile = null,
        skillMemory = const <String, SkillMasteryRecord>{},
        reviewQueue = const <ReviewTask>[],
        dashboardStats = null,
        completedMilestoneIds = const <String>{},
        pendingEvents = const <PendingSyncEvent>[],
        lastSyncedAt = null;

  final String? installId;
  final ContentManifest? contentManifest;
  final List<LearningTrack> tracks;
  final List<SkillNode> skillNodes;
  final LearnerProfile? learnerProfile;
  final Map<String, SkillMasteryRecord> skillMemory;
  final List<ReviewTask> reviewQueue;
  final DashboardStats? dashboardStats;
  final Set<String> completedMilestoneIds;
  final List<PendingSyncEvent> pendingEvents;
  final DateTime? lastSyncedAt;

  AppCacheDocument copyWith({
    String? installId,
    ContentManifest? contentManifest,
    bool clearContentManifest = false,
    List<LearningTrack>? tracks,
    List<SkillNode>? skillNodes,
    LearnerProfile? learnerProfile,
    bool clearLearnerProfile = false,
    Map<String, SkillMasteryRecord>? skillMemory,
    List<ReviewTask>? reviewQueue,
    DashboardStats? dashboardStats,
    bool clearDashboardStats = false,
    Set<String>? completedMilestoneIds,
    List<PendingSyncEvent>? pendingEvents,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return AppCacheDocument(
      installId: installId ?? this.installId,
      contentManifest: clearContentManifest
          ? null
          : (contentManifest ?? this.contentManifest),
      tracks: tracks ?? this.tracks,
      skillNodes: skillNodes ?? this.skillNodes,
      learnerProfile: clearLearnerProfile
          ? null
          : (learnerProfile ?? this.learnerProfile),
      skillMemory: skillMemory ?? this.skillMemory,
      reviewQueue: reviewQueue ?? this.reviewQueue,
      dashboardStats: clearDashboardStats
          ? null
          : (dashboardStats ?? this.dashboardStats),
      completedMilestoneIds:
          completedMilestoneIds ?? this.completedMilestoneIds,
      pendingEvents: pendingEvents ?? this.pendingEvents,
      lastSyncedAt:
          clearLastSyncedAt ? null : (lastSyncedAt ?? this.lastSyncedAt),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'installId': installId,
      'contentManifest': contentManifest == null
          ? null
          : <String, Object?>{
              'contentVersion': contentManifest!.contentVersion,
              'publishedAt': contentManifest!.publishedAt.toIso8601String(),
              'checksum': contentManifest!.checksum,
            },
      'tracks': tracks.map(learningTrackToJson).toList(growable: false),
      'skillNodes': skillNodes.map(skillNodeToJson).toList(growable: false),
      'learnerProfile': learnerProfile == null
          ? null
          : <String, Object?>{
              'installId': learnerProfile!.installId,
              'learnerId': learnerProfile!.learnerId,
              'accessToken': learnerProfile!.accessToken,
              'syncCursor': learnerProfile!.syncCursor,
              'isOfflineOnly': learnerProfile!.isOfflineOnly,
            },
      'skillMemory': <String, Object?>{
        for (final entry in skillMemory.entries)
          entry.key: skillMasteryRecordToJson(entry.value),
      },
      'reviewQueue':
          reviewQueue.map(reviewTaskToJson).toList(growable: false),
      'dashboardStats':
          dashboardStats == null ? null : dashboardStatsToJson(dashboardStats!),
      'completedMilestoneIds': completedMilestoneIds.toList(growable: false),
      'pendingEvents': pendingEvents
          .map((event) => <String, Object?>{
                'clientEventId': event.clientEventId,
                'type': event.type.name,
                'occurredAt': event.occurredAt.toIso8601String(),
                'payload': event.payload,
              })
          .toList(growable: false),
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }

  static AppCacheDocument fromJson(Map<String, dynamic> json) {
    final rawSkillMemory = json['skillMemory'];
    final skillMemory = <String, SkillMasteryRecord>{};
    if (rawSkillMemory is Map) {
      for (final entry in rawSkillMemory.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          skillMemory[entry.key.toString()] = skillMasteryRecordFromJson(value);
        } else if (value is Map) {
          skillMemory[entry.key.toString()] =
              skillMasteryRecordFromJson(value.cast<String, dynamic>());
        }
      }
    }

    final rawManifest = json['contentManifest'];
    final rawLearnerProfile = json['learnerProfile'];
    final rawPendingEvents = json['pendingEvents'];

    return AppCacheDocument(
      installId: json['installId'] as String?,
      contentManifest: rawManifest is Map
          ? ContentManifest(
              contentVersion: rawManifest['contentVersion'] as String? ?? '',
              publishedAt: DateTime.tryParse(
                    rawManifest['publishedAt'] as String? ?? '',
                  ) ??
                  DateTime.fromMillisecondsSinceEpoch(0),
              checksum: rawManifest['checksum'] as String? ?? '',
            )
          : null,
      tracks: (json['tracks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => learningTrackFromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      skillNodes: (json['skillNodes'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => skillNodeFromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      learnerProfile: rawLearnerProfile is Map
          ? LearnerProfile(
              installId: rawLearnerProfile['installId'] as String? ?? '',
              learnerId: rawLearnerProfile['learnerId'] as String? ?? '',
              accessToken: rawLearnerProfile['accessToken'] as String? ?? '',
              syncCursor: rawLearnerProfile['syncCursor'] as int? ?? 0,
              isOfflineOnly: rawLearnerProfile['isOfflineOnly'] == true,
            )
          : null,
      skillMemory: skillMemory,
      reviewQueue: (json['reviewQueue'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => reviewTaskFromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      dashboardStats: json['dashboardStats'] is Map
          ? dashboardStatsFromJson(
              (json['dashboardStats'] as Map).cast<String, dynamic>(),
            )
          : null,
      completedMilestoneIds: Set<String>.from(
        (json['completedMilestoneIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString()),
      ),
      pendingEvents: rawPendingEvents is List
          ? rawPendingEvents
              .whereType<Map>()
              .map(
                (item) => PendingSyncEvent(
                  clientEventId: item['clientEventId'] as String? ?? '',
                  type: LearnerSyncEventType.values.firstWhere(
                    (value) => value.name == item['type'],
                    orElse: () => LearnerSyncEventType.sessionStarted,
                  ),
                  occurredAt: DateTime.tryParse(
                        item['occurredAt'] as String? ?? '',
                      ) ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                  payload: ((item['payload'] as Map?) ?? const <String, Object?>{})
                      .cast<String, Object?>(),
                ),
              )
              .toList(growable: false)
          : const <PendingSyncEvent>[],
      lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
    );
  }
}
