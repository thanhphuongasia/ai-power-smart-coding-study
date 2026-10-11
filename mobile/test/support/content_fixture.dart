// Nội dung học cho test: đọc thẳng backend/content/content.json (nguồn thật).
// `flutter test` chạy với cwd = thư mục mobile/.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:smart_coding_study/data/content_providers.dart';
import 'package:smart_coding_study/domain/content.dart';

import 'progress_fixture.dart';

final Map<String, dynamic> contentJson =
    jsonDecode(File('../backend/content/content.json').readAsStringSync())
        as Map<String, dynamic>;

final Content testContent = Content.fromJson(contentJson);

/// Override gốc: mọi ProviderScope/ProviderContainer trong test cần cái này.
/// Gồm tiến độ demo (xem progress_fixture.dart) vì nhiều test dựa vào nó.
final List<Override> contentOverrides = [
  contentIndexProvider.overrideWithValue(testContent),
  ...demoProgressOverrides(),
];

/// Container dựng sẵn override nội dung (gộp thêm [overrides] của test).
ProviderContainer testContainer({List<Override> overrides = const []}) =>
    ProviderContainer(overrides: [...contentOverrides, ...overrides]);
