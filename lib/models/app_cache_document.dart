import 'app_sync_models.dart';
import 'learning_models.dart';
import 'learning_serialization.dart';

class AppCacheDocument {
  const AppCacheDocument({
    required this.installId,
    required this.contentManifest,
    required this.tracks,
    required this.exercises,
    required this.topics,
    required this.domains,
    required this.tagSuggestions,
    required this.skillNodes,
    required this.learnerProfile,
    required this.skillMemory,
    required this.reviewQueue,
    required this.dashboardStats,
    required this.completedExerciseIds,
    required this.preferredLanguageId,
    required this.pendingEvents,
    required this.lastSyncedAt,
  });

  const AppCacheDocument.empty()
      : installId = null,
        contentManifest = null,
        tracks = const <LearningTrack>[],
        exercises = const <LearningExercise>[],
        topics = const <TopicDefinition>[],
        domains = const <DomainDefinition>[],
        tagSuggestions = const <String>[],
        skillNodes = const <SkillNode>[],
        learnerProfile = null,
        skillMemory = const <String, SkillMasteryRecord>{},
        reviewQueue = const <ReviewTask>[],
        dashboardStats = null,
        completedExerciseIds = const <String>{},
        preferredLanguageId = null,
        pendingEvents = const <PendingSyncEvent>[],
        lastSyncedAt = null;

  final String? installId;
  final ContentManifest? contentManifest;
  final List<LearningTrack> tracks;
  final List<LearningExercise> exercises;
  final List<TopicDefinition> topics;
  final List<DomainDefinition> domains;
  final List<String> tagSuggestions;
  final List<SkillNode> skillNodes;
  final LearnerProfile? learnerProfile;
  final Map<String, SkillMasteryRecord> skillMemory;
  final List<ReviewTask> reviewQueue;
  final DashboardStats? dashboardStats;
  final Set<String> completedExerciseIds;
  final String? preferredLanguageId;
  final List<PendingSyncEvent> pendingEvents;
  final DateTime? lastSyncedAt;

  AppCacheDocument copyWith({
    String? installId,
    ContentManifest? contentManifest,
    bool clearContentManifest = false,
    List<LearningTrack>? tracks,
    List<LearningExercise>? exercises,
    List<TopicDefinition>? topics,
    List<DomainDefinition>? domains,
    List<String>? tagSuggestions,
    List<SkillNode>? skillNodes,
    LearnerProfile? learnerProfile,
    bool clearLearnerProfile = false,
    Map<String, SkillMasteryRecord>? skillMemory,
    List<ReviewTask>? reviewQueue,
    DashboardStats? dashboardStats,
    bool clearDashboardStats = false,
    Set<String>? completedExerciseIds,
    String? preferredLanguageId,
    bool clearPreferredLanguageId = false,
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
      exercises: exercises ?? this.exercises,
      topics: topics ?? this.topics,
      domains: domains ?? this.domains,
      tagSuggestions: tagSuggestions ?? this.tagSuggestions,
      skillNodes: skillNodes ?? this.skillNodes,
      learnerProfile:
          clearLearnerProfile ? null : (learnerProfile ?? this.learnerProfile),
      skillMemory: skillMemory ?? this.skillMemory,
      reviewQueue: reviewQueue ?? this.reviewQueue,
      dashboardStats:
          clearDashboardStats ? null : (dashboardStats ?? this.dashboardStats),
      completedExerciseIds: completedExerciseIds ?? this.completedExerciseIds,
      preferredLanguageId: clearPreferredLanguageId
          ? null
          : (preferredLanguageId ?? this.preferredLanguageId),
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
      'exercises':
          exercises.map(learningExerciseToJson).toList(growable: false),
      'topics': topics.map(topicDefinitionToJson).toList(growable: false),
      'domains': domains.map(domainDefinitionToJson).toList(growable: false),
      'tagSuggestions': tagSuggestions,
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
      'reviewQueue': reviewQueue.map(reviewTaskToJson).toList(growable: false),
      'dashboardStats':
          dashboardStats == null ? null : dashboardStatsToJson(dashboardStats!),
      'completedExerciseIds': completedExerciseIds.toList(growable: false),
      'preferredLanguageId': preferredLanguageId,
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
    final completedExerciseIds =
        (json['completedExerciseIds'] as List<dynamic>?) ??
            (json['completedMilestoneIds'] as List<dynamic>?);

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
      exercises: (json['exercises'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => learningExerciseFromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      topics: (json['topics'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => topicDefinitionFromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      domains: (json['domains'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => domainDefinitionFromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      tagSuggestions:
          ((json['tagSuggestions'] as List<dynamic>?) ?? const <dynamic>[])
              .map((item) => item.toString())
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
      completedExerciseIds: Set<String>.from(
        (completedExerciseIds ?? const <dynamic>[])
            .map((item) => item.toString()),
      ),
      preferredLanguageId: json['preferredLanguageId'] as String?,
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
                  payload:
                      ((item['payload'] as Map?) ?? const <String, Object?>{})
                          .cast<String, Object?>(),
                ),
              )
              .toList(growable: false)
          : const <PendingSyncEvent>[],
      lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
    );
  }
}
