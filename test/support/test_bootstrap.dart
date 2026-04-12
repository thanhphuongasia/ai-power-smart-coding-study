import 'package:ai_powerd_mobile_code_assitant/app/app_state.dart';
import 'package:ai_powerd_mobile_code_assitant/data/sample_curriculum.dart';
import 'package:ai_powerd_mobile_code_assitant/models/app_sync_models.dart';
import 'package:ai_powerd_mobile_code_assitant/repositories/catalog_repository.dart';
import 'package:ai_powerd_mobile_code_assitant/repositories/learner_repository.dart';
import 'package:ai_powerd_mobile_code_assitant/repositories/sync_repository.dart';
import 'package:ai_powerd_mobile_code_assitant/services/sandbox_api_service.dart';

Future<AppState> buildTestAppState({
  SandboxApiService? sandboxApiService,
}) {
  return AppState.bootstrap(
    catalogRepository: MemoryCatalogRepository(
      manifest: ContentManifest(
        contentVersion: 'test-1',
        publishedAt: DateTime.utc(2026, 1, 1),
        checksum: 'test-checksum',
      ),
      tracks: SeedData.tracks(),
      exercises: SeedData.exercises(),
      topics: SeedData.topics(),
      domains: SeedData.domains(),
      tagSuggestions: SeedData.tagSuggestions(),
      skillNodes: SeedData.skills(),
    ),
    learnerRepository: MemoryLearnerRepository(
      learnerProfile: const LearnerProfile(
        installId: 'test-install',
        learnerId: 'test-learner',
        accessToken: '',
        syncCursor: 0,
        isOfflineOnly: true,
      ),
      skillMemory: SeedData.skillMemory(),
    ),
    syncRepository: MemorySyncRepository(),
    sandboxApiService: sandboxApiService ??
        SandboxApiService(
          settings: const SandboxApiSettings(baseUrl: 'http://127.0.0.1:8787'),
        ),
  );
}
