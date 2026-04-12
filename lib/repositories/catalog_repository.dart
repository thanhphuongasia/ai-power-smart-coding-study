import '../models/app_sync_models.dart';
import '../models/learning_models.dart';
import '../services/app_api_service.dart';
import '../storage/local_app_store.dart';

abstract class CatalogRepository {
  Future<ContentManifest?> readCachedManifest();

  Future<List<LearningTrack>> readCachedTracks();

  Future<List<LearningExercise>> readCachedExercises();

  Future<List<TopicDefinition>> readCachedTopics();

  Future<List<DomainDefinition>> readCachedDomains();

  Future<List<String>> readCachedTagSuggestions();

  Future<List<SkillNode>> readCachedSkillNodes();

  Future<bool> refreshCatalogIfNeeded({
    bool force = false,
  });
}

class AppApiCatalogRepository implements CatalogRepository {
  AppApiCatalogRepository({
    required LocalAppStore localAppStore,
    required AppApiService appApiService,
  })  : _localAppStore = localAppStore,
        _appApiService = appApiService;

  final LocalAppStore _localAppStore;
  final AppApiService _appApiService;

  @override
  Future<ContentManifest?> readCachedManifest() async {
    final document = await _localAppStore.read();
    return document.contentManifest;
  }

  @override
  Future<List<LearningTrack>> readCachedTracks() async {
    final document = await _localAppStore.read();
    return document.tracks;
  }

  @override
  Future<List<LearningExercise>> readCachedExercises() async {
    final document = await _localAppStore.read();
    return document.exercises;
  }

  @override
  Future<List<TopicDefinition>> readCachedTopics() async {
    final document = await _localAppStore.read();
    return document.topics;
  }

  @override
  Future<List<DomainDefinition>> readCachedDomains() async {
    final document = await _localAppStore.read();
    return document.domains;
  }

  @override
  Future<List<String>> readCachedTagSuggestions() async {
    final document = await _localAppStore.read();
    return document.tagSuggestions;
  }

  @override
  Future<List<SkillNode>> readCachedSkillNodes() async {
    final document = await _localAppStore.read();
    return document.skillNodes;
  }

  @override
  Future<bool> refreshCatalogIfNeeded({
    bool force = false,
  }) async {
    if (!_appApiService.isConfigured) {
      return false;
    }

    final document = await _localAppStore.read();
    final remoteManifest = await _appApiService.fetchCatalogManifest();
    final shouldRefresh = force ||
        document.contentManifest == null ||
        document.contentManifest!.checksum != remoteManifest.checksum ||
        document.contentManifest!.contentVersion !=
            remoteManifest.contentVersion;

    if (!shouldRefresh) {
      return false;
    }

    final remoteCatalog = await _appApiService.fetchCatalog();
    await _localAppStore.write(
      document.copyWith(
        contentManifest: remoteManifest,
        tracks: remoteCatalog.tracks,
        exercises: remoteCatalog.exercises,
        topics: remoteCatalog.topics,
        domains: remoteCatalog.domains,
        tagSuggestions: remoteCatalog.tagSuggestions,
        skillNodes: remoteCatalog.skillNodes,
      ),
    );
    return true;
  }
}

class MemoryCatalogRepository implements CatalogRepository {
  MemoryCatalogRepository({
    this.manifest,
    required this.tracks,
    required this.exercises,
    this.topics = const <TopicDefinition>[],
    this.domains = const <DomainDefinition>[],
    this.tagSuggestions = const <String>[],
    required this.skillNodes,
  });

  final ContentManifest? manifest;
  final List<LearningTrack> tracks;
  final List<LearningExercise> exercises;
  final List<TopicDefinition> topics;
  final List<DomainDefinition> domains;
  final List<String> tagSuggestions;
  final List<SkillNode> skillNodes;

  @override
  Future<ContentManifest?> readCachedManifest() async => manifest;

  @override
  Future<List<LearningTrack>> readCachedTracks() async => tracks;

  @override
  Future<List<LearningExercise>> readCachedExercises() async => exercises;

  @override
  Future<List<TopicDefinition>> readCachedTopics() async => topics;

  @override
  Future<List<DomainDefinition>> readCachedDomains() async => domains;

  @override
  Future<List<String>> readCachedTagSuggestions() async => tagSuggestions;

  @override
  Future<List<SkillNode>> readCachedSkillNodes() async => skillNodes;

  @override
  Future<bool> refreshCatalogIfNeeded({
    bool force = false,
  }) async {
    return false;
  }
}
