import 'package:flutter/foundation.dart';

enum LearnerSyncEventType {
  sessionStarted,
  hintRevealed,
  checkPassed,
  checkFailed,
  sandboxBuild,
  sandboxRun,
  milestoneCompleted,
}

@immutable
class ContentManifest {
  const ContentManifest({
    required this.contentVersion,
    required this.publishedAt,
    required this.checksum,
  });

  final String contentVersion;
  final DateTime publishedAt;
  final String checksum;
}

@immutable
class LearnerProfile {
  const LearnerProfile({
    required this.installId,
    required this.learnerId,
    required this.accessToken,
    required this.syncCursor,
    this.isOfflineOnly = false,
  });

  final String installId;
  final String learnerId;
  final String accessToken;
  final int syncCursor;
  final bool isOfflineOnly;

  LearnerProfile copyWith({
    String? installId,
    String? learnerId,
    String? accessToken,
    int? syncCursor,
    bool? isOfflineOnly,
  }) {
    return LearnerProfile(
      installId: installId ?? this.installId,
      learnerId: learnerId ?? this.learnerId,
      accessToken: accessToken ?? this.accessToken,
      syncCursor: syncCursor ?? this.syncCursor,
      isOfflineOnly: isOfflineOnly ?? this.isOfflineOnly,
    );
  }
}

@immutable
class PendingSyncEvent {
  const PendingSyncEvent({
    required this.clientEventId,
    required this.type,
    required this.occurredAt,
    required this.payload,
  });

  final String clientEventId;
  final LearnerSyncEventType type;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
}

@immutable
class SyncFlushResult {
  const SyncFlushResult({
    required this.acceptedClientEventIds,
    required this.nextCursor,
  });

  final List<String> acceptedClientEventIds;
  final int nextCursor;
}

@immutable
class DeviceInfoSnapshot {
  const DeviceInfoSnapshot({
    required this.platform,
    required this.appVersion,
    required this.locale,
  });

  final String platform;
  final String appVersion;
  final String locale;
}
