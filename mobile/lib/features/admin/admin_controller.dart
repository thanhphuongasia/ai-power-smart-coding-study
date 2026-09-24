/// Hàng chờ duyệt nội dung Claude sinh qua MCP — giữ trong bộ nhớ, chưa có
/// backend.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/seed.dart';
import '../../domain/models.dart';

class AdminController extends Notifier<List<PendingContent>> {
  @override
  List<PendingContent> build() => seedPendingContent;

  void approve(String id) => _set(id, ApprovalStatus.approved);

  void reject(String id) => _set(id, ApprovalStatus.rejected);

  /// Đưa một mục đã xử lý về lại hàng chờ.
  void undo(String id) => _set(id, ApprovalStatus.pending);

  void _set(String id, ApprovalStatus status) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(status: status) else item,
    ];
  }
}

final adminProvider = NotifierProvider<AdminController, List<PendingContent>>(
  AdminController.new,
);
