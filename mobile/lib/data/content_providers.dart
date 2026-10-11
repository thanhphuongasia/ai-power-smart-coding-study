/// Provider nội dung học hiện hành — mọi nơi trong app đọc qua đây.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/content.dart';
import 'content_repository.dart';
import 'seed.dart';

/// T-03: mặc định là seed; T-09 mới đổi sang nội dung tải từ API.
final contentIndexProvider = Provider<Content>(
  (ref) => Content(version: 'seed', themes: seedThemes),
);

final contentRepositoryProvider = Provider<ContentRepository>(
  (ref) => ContentRepository(),
);

/// Trạng thái tải nội dung từ server (loading / lỗi / dữ liệu + nguồn).
final contentProvider = AsyncNotifierProvider<ContentController, ContentLoad>(
  ContentController.new,
);

class ContentController extends AsyncNotifier<ContentLoad> {
  @override
  Future<ContentLoad> build() => ref.read(contentRepositoryProvider).load();

  /// Tải lại; dữ liệu cũ vẫn hiển thị trong lúc tải.
  Future<void> refresh() async {
    state = const AsyncLoading<ContentLoad>();
    state = await AsyncValue.guard(
      () => ref.read(contentRepositoryProvider).load(),
    );
  }
}
