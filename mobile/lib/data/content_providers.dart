/// Provider nội dung học hiện hành — mọi nơi trong app đọc qua đây.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/content.dart';
import 'seed.dart';

/// T-03: mặc định là seed; T-07 đổi sang nội dung tải từ API.
final contentIndexProvider = Provider<Content>(
  (ref) => Content(version: 'seed', themes: seedThemes),
);
