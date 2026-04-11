import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_sync_models.dart';
import '../models/learning_models.dart';
import '../models/learning_serialization.dart';

class AppApiService {
  AppApiService({
    AppApiSettings? settings,
    http.Client? client,
  })  : _settings = settings ?? AppApiSettings.fromEnvironment(),
        _client = client ?? http.Client();

  final AppApiSettings _settings;
  final http.Client _client;

  bool get isConfigured => _settings.baseUrl.isNotEmpty;

  Future<LearnerProfile> bootstrapAnonymousLearner({
    required String installId,
    required DeviceInfoSnapshot deviceInfo,
  }) async {
    final payload = await _post(
      '/v1/anonymous/bootstrap',
      body: <String, Object?>{
        'install_id': installId,
        'device_info': <String, Object?>{
          'platform': deviceInfo.platform,
          'app_version': deviceInfo.appVersion,
          'locale': deviceInfo.locale,
        },
      },
    );

    return LearnerProfile(
      installId: installId,
      learnerId: payload['learner_id'] as String? ?? '',
      accessToken: payload['access_token'] as String? ?? '',
      syncCursor: payload['sync_cursor'] as int? ?? 0,
    );
  }

  Future<ContentManifest> fetchCatalogManifest() async {
    final payload = await _get('/v1/catalog/manifest');
    return ContentManifest(
      contentVersion: payload['content_version'] as String? ?? '0',
      publishedAt: DateTime.tryParse(payload['published_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      checksum: payload['checksum'] as String? ?? '',
    );
  }

  Future<CatalogApiSnapshot> fetchCatalog() async {
    final payload = await _get('/v1/catalog');
    return CatalogApiSnapshot(
      tracks: (payload['tracks'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => learningTrackFromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      skillNodes: (payload['skills'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => skillNodeFromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  Future<RemoteLearnerStateSnapshot> fetchLearnerState({
    required LearnerProfile learnerProfile,
  }) async {
    final progress = await _get(
      '/v1/me/progress',
      accessToken: learnerProfile.accessToken,
    );
    final dashboard = await _get(
      '/v1/me/dashboard',
      accessToken: learnerProfile.accessToken,
    );
    final reviewQueue = await _get(
      '/v1/me/review-queue',
      accessToken: learnerProfile.accessToken,
    );
    final skillMemory = await _get(
      '/v1/me/skill-memory',
      accessToken: learnerProfile.accessToken,
    );

    final rawSkillMemory =
        skillMemory['skill_memory'] as Map<String, dynamic>? ?? <String, dynamic>{};

    return RemoteLearnerStateSnapshot(
      dashboard: dashboardStatsFromJson(dashboard),
      reviewQueue:
          (reviewQueue['review_queue'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => reviewTaskFromJson(item.cast<String, dynamic>()))
              .toList(growable: false),
      skillMemory: <String, SkillMasteryRecord>{
        for (final entry in rawSkillMemory.entries)
          entry.key: skillMasteryRecordFromJson(entry.value),
      },
      completedMilestoneIds: Set<String>.from(
        (progress['completed_milestone_ids'] as List<dynamic>? ??
                const <dynamic>[])
            .map((item) => item.toString()),
      ),
      nextCursor: progress['sync_cursor'] as int? ?? learnerProfile.syncCursor,
    );
  }

  Future<SyncFlushResult> flushEvents({
    required LearnerProfile learnerProfile,
    required List<PendingSyncEvent> events,
  }) async {
    final payload = await _post(
      '/v1/sync/events',
      accessToken: learnerProfile.accessToken,
      body: <String, Object?>{
        'sync_cursor': learnerProfile.syncCursor,
        'events': events
            .map(
              (event) => <String, Object?>{
                'client_event_id': event.clientEventId,
                'type': event.type.name,
                'occurred_at': event.occurredAt.toIso8601String(),
                'payload': event.payload,
              },
            )
            .toList(growable: false),
      },
    );

    return SyncFlushResult(
      acceptedClientEventIds:
          (payload['accepted_client_event_ids'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((item) => item.toString())
              .toList(growable: false),
      nextCursor: payload['sync_cursor'] as int? ?? learnerProfile.syncCursor,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    String? accessToken,
  }) async {
    if (!isConfigured) {
      throw const SocketException('App API is not configured.');
    }

    final response = await _client.get(
      _settings.uri.resolve(path),
      headers: _headers(accessToken: accessToken),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    String? accessToken,
    required Map<String, Object?> body,
  }) async {
    if (!isConfigured) {
      throw const SocketException('App API is not configured.');
    }

    final response = await _client.post(
      _settings.uri.resolve(path),
      headers: _headers(accessToken: accessToken),
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Map<String, String> _headers({
    String? accessToken,
  }) {
    return <String, String>{
      'Content-Type': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'App API request failed (${response.statusCode}): ${response.body}',
      );
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      throw StateError('App API returned an unexpected response body.');
    }
    return payload;
  }
}

class AppApiSettings {
  const AppApiSettings({
    required this.baseUrl,
    this.usesDebugFallback = false,
  });

  factory AppApiSettings.fromEnvironment({
    String environmentBaseUrl =
        const String.fromEnvironment('APP_API_BASE_URL'),
    bool enableDebugFallback = kDebugMode,
    TargetPlatform? targetPlatform,
  }) {
    final trimmedBaseUrl = environmentBaseUrl.trim();
    if (trimmedBaseUrl.isNotEmpty) {
      return AppApiSettings(baseUrl: trimmedBaseUrl);
    }

    final fallbackBaseUrl = enableDebugFallback
        ? _debugFallbackBaseUrlFor(targetPlatform ?? defaultTargetPlatform)
        : '';

    return AppApiSettings(
      baseUrl: fallbackBaseUrl,
      usesDebugFallback: fallbackBaseUrl.isNotEmpty,
    );
  }

  final String baseUrl;
  final bool usesDebugFallback;

  Uri get uri => Uri.parse(
        baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
      );

  static String _debugFallbackBaseUrlFor(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8788';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return 'http://127.0.0.1:8788';
    }
  }
}

class CatalogApiSnapshot {
  const CatalogApiSnapshot({
    required this.tracks,
    required this.skillNodes,
  });

  final List<LearningTrack> tracks;
  final List<SkillNode> skillNodes;
}

class RemoteLearnerStateSnapshot {
  const RemoteLearnerStateSnapshot({
    required this.dashboard,
    required this.reviewQueue,
    required this.skillMemory,
    required this.completedMilestoneIds,
    required this.nextCursor,
  });

  final DashboardStats dashboard;
  final List<ReviewTask> reviewQueue;
  final Map<String, SkillMasteryRecord> skillMemory;
  final Set<String> completedMilestoneIds;
  final int nextCursor;
}
