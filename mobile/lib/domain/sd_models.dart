/// Domain models cho chế độ System Design: tài liệu → section → thẻ, task,
/// lượt nộp. Server không bao giờ trả rubric/keywords nên model cũng không có.
library;

import 'models.dart' show jsonField, jsonObjects, jsonStrings;

/// Field tuỳ chọn kiểu [T]: thiếu hoặc null → null; sai kiểu → FormatException.
T? _opt<T>(Map<String, dynamic> json, String key, String where) {
  final v = json[key];
  if (v == null) return null;
  if (v is T) return v;
  throw FormatException('$where: field "$key" sai kiểu (${v.runtimeType})');
}

/// Số nguyên bắt buộc (JSON có thể đưa double nếu server đổi → ép an toàn).
int _int(Map<String, dynamic> json, String key, String where) =>
    jsonField<num>(json, key, where).toInt();

/// Một dòng ở danh sách tài liệu.
class SdDocSummary {
  const SdDocSummary({
    required this.id,
    required this.title,
    required this.sections,
    required this.sectionsDone,
    required this.cards,
    required this.cardsRead,
    required this.phase2Unlocked,
    required this.tasks,
    required this.tasksDone,
  });

  factory SdDocSummary.fromJson(Map<String, dynamic> json) {
    const w = 'SdDocSummary';
    return SdDocSummary(
      id: jsonField<String>(json, 'id', w),
      title: jsonField<String>(json, 'title', w),
      sections: _int(json, 'sections', w),
      sectionsDone: _int(json, 'sections_done', w),
      cards: _int(json, 'cards', w),
      cardsRead: _int(json, 'cards_read', w),
      phase2Unlocked: jsonField<bool>(json, 'phase2_unlocked', w),
      tasks: _int(json, 'tasks', w),
      tasksDone: _int(json, 'tasks_done', w),
    );
  }

  final String id;
  final String title;
  final int sections;
  final int sectionsDone;
  final int cards;
  final int cardsRead;
  final bool phase2Unlocked;
  final int tasks;
  final int tasksDone;
}

/// Một thẻ nội dung (`kind` do server định nghĩa, vd text/code).
class SdCard {
  const SdCard({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.lang,
  });

  factory SdCard.fromJson(Map<String, dynamic> json) {
    const w = 'SdCard';
    return SdCard(
      id: jsonField<String>(json, 'id', w),
      kind: jsonField<String>(json, 'kind', w),
      title: jsonField<String>(json, 'title', w),
      body: jsonField<String>(json, 'body', w),
      lang: _opt<String>(json, 'lang', w),
    );
  }

  final String id;
  final String kind;
  final String title;
  final String body;
  final String? lang;
}

class SdSection {
  const SdSection({
    required this.id,
    required this.position,
    required this.chapter,
    required this.chapterPosition,
    required this.title,
    required this.cards,
    required this.read,
    required this.done,
    required this.unlocked,
  });

  factory SdSection.fromJson(Map<String, dynamic> json) {
    const w = 'SdSection';
    return SdSection(
      id: jsonField<String>(json, 'id', w),
      position: _int(json, 'position', w),
      chapter: jsonField<String>(json, 'chapter', w),
      chapterPosition: _int(json, 'chapter_position', w),
      title: jsonField<String>(json, 'title', w),
      cards: [
        for (final c in jsonObjects(json, 'cards', w)) SdCard.fromJson(c),
      ],
      read: jsonStrings(json, 'read', w).toSet(),
      done: jsonField<bool>(json, 'done', w),
      unlocked: jsonField<bool>(json, 'unlocked', w),
    );
  }

  final String id;
  final int position;
  final String chapter;
  final int chapterPosition;
  final String title;
  final List<SdCard> cards;

  /// Id các thẻ đã đọc.
  final Set<String> read;
  final bool done;
  final bool unlocked;
}

class SdTask {
  const SdTask({
    required this.id,
    required this.position,
    required this.name,
    required this.unlocked,
    required this.done,
    required this.attempts,
    required this.hints,
    this.prompt,
    this.refSectionId,
  });

  factory SdTask.fromJson(Map<String, dynamic> json) {
    const w = 'SdTask';
    return SdTask(
      id: jsonField<String>(json, 'id', w),
      position: _int(json, 'position', w),
      name: jsonField<String>(json, 'name', w),
      unlocked: jsonField<bool>(json, 'unlocked', w),
      done: jsonField<bool>(json, 'done', w),
      attempts: _int(json, 'attempts', w),
      prompt: _opt<String>(json, 'prompt', w),
      hints: jsonStrings(json, 'hints', w),
      refSectionId: _opt<String>(json, 'ref_section_id', w),
    );
  }

  final String id;
  final int position;
  final String name;
  final bool unlocked;
  final bool done;
  final int attempts;

  /// Đề bài; null khi task còn khoá.
  final String? prompt;
  final List<String> hints;

  /// Section nên đọc lại trước khi làm task này.
  final String? refSectionId;
}

class SdDoc {
  const SdDoc({
    required this.id,
    required this.title,
    required this.sections,
    required this.phase2Unlocked,
    required this.context,
    required this.tasks,
  });

  factory SdDoc.fromJson(Map<String, dynamic> json) {
    const w = 'SdDoc';
    return SdDoc(
      id: jsonField<String>(json, 'id', w),
      title: jsonField<String>(json, 'title', w),
      sections: [
        for (final s in jsonObjects(json, 'sections', w)) SdSection.fromJson(s),
      ],
      phase2Unlocked: jsonField<bool>(json, 'phase2_unlocked', w),
      context: [
        for (final c in jsonObjects(json, 'context', w)) SdCard.fromJson(c),
      ],
      tasks: [
        for (final t in jsonObjects(json, 'tasks', w)) SdTask.fromJson(t),
      ],
    );
  }

  final String id;
  final String title;
  final List<SdSection> sections;
  final bool phase2Unlocked;
  final List<SdCard> context;
  final List<SdTask> tasks;
}

/// Một tiêu chí chấm của lượt nộp.
class SdAttemptItem {
  const SdAttemptItem({
    required this.text,
    required this.ok,
    required this.note,
  });

  factory SdAttemptItem.fromJson(Map<String, dynamic> json) {
    const w = 'SdAttemptItem';
    return SdAttemptItem(
      text: jsonField<String>(json, 'text', w),
      ok: jsonField<bool>(json, 'ok', w),
      note: jsonField<String>(json, 'note', w),
    );
  }

  final String text;
  final bool ok;
  final String note;
}

class SdAttempt {
  const SdAttempt({
    required this.id,
    required this.n,
    required this.answer,
    required this.createdAt,
    required this.source,
    required this.score,
    required this.items,
    this.feedback,
    this.reviewedAt,
  });

  factory SdAttempt.fromJson(Map<String, dynamic> json) {
    const w = 'SdAttempt';
    return SdAttempt(
      id: _int(json, 'id', w),
      n: _int(json, 'n', w),
      answer: jsonField<String>(json, 'answer', w),
      createdAt: jsonField<String>(json, 'created_at', w),
      source: jsonField<String>(json, 'source', w),
      score: jsonField<num>(json, 'score', w),
      items: [
        for (final i in jsonObjects(json, 'items', w))
          SdAttemptItem.fromJson(i),
      ],
      feedback: _opt<String>(json, 'feedback', w),
      reviewedAt: _opt<String>(json, 'reviewed_at', w),
    );
  }

  final int id;

  /// Lần nộp thứ n của task.
  final int n;
  final String answer;

  /// Chuỗi thời gian ISO như server trả.
  final String createdAt;

  /// `auto` (máy chấm) hoặc `reviewed` (đã có người duyệt).
  final String source;
  final num score;
  final List<SdAttemptItem> items;
  final String? feedback;
  final String? reviewedAt;
}

class SdProgressResult {
  const SdProgressResult({
    required this.sectionId,
    required this.read,
    required this.done,
    required this.phase2Unlocked,
    this.nextSectionId,
  });

  factory SdProgressResult.fromJson(Map<String, dynamic> json) {
    const w = 'SdProgressResult';
    return SdProgressResult(
      sectionId: jsonField<String>(json, 'section_id', w),
      read: jsonStrings(json, 'read', w).toSet(),
      done: jsonField<bool>(json, 'done', w),
      nextSectionId: _opt<String>(json, 'next_section_id', w),
      phase2Unlocked: jsonField<bool>(json, 'phase2_unlocked', w),
    );
  }

  final String sectionId;
  final Set<String> read;
  final bool done;
  final String? nextSectionId;
  final bool phase2Unlocked;
}
