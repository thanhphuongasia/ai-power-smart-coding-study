import '../domain/models.dart';

/// Dữ liệu DEMO tiến độ (chưa có backend tiến độ). KHÔNG chứa nội dung học —
/// nội dung đến từ `GET /content`. Id bài không có trong nội dung bị bỏ qua.

/// Bài đã chạy đúng toàn bộ unit test khi mở app.
final Set<String> seedPassedExercises = {'clean-text'};

/// Nháp có sẵn: exerciseId → (nhãn ô → code đã gõ). split-chunks đang làm dở.
final Map<String, Map<String, String>> seedDrafts = {
  'split-chunks': {'A': 'for i in range(0, len(text), size):'},
};

/// Hoạt động 4 tuần gần nhất (block làm đúng + thẻ đã ôn mỗi ngày), theo số
/// ngày trước hôm nay. Ngày không có trong map = 0. Chuỗi hiện tại: 6 ngày
/// liên tiếp tới hôm qua.
final Map<int, int> seedActivityDaysAgo = {
  1: 3,
  2: 2,
  3: 4,
  4: 1,
  5: 2,
  6: 3,
  8: 2,
  9: 1,
  11: 3,
  12: 4,
  13: 2,
  15: 1,
  16: 2,
  18: 3,
  20: 1,
  22: 2,
  23: 4,
  25: 1,
  26: 2,
  27: 1,
};

/// Lịch ôn có sẵn cho vài block đã xong, theo số ngày tính từ hôm nay. Block
/// đã xong mà không có ở đây = thẻ mới, đến hạn ngay.
final Map<String, int> seedReviewDueInDays = {'clean-text-a': 1};

/// Nội dung Claude sinh qua MCP, đang chờ duyệt ở màn Admin.
const List<PendingContent> seedPendingContent = [
  PendingContent(
    id: 'pending-fanout-write',
    kind: ContentKind.exercise,
    title: 'fanout_write()',
    target: 'Twitter feed',
    description:
        'Đẩy bài đăng mới vào feed của mọi follower. Chia thành 5 block nhỏ.',
    tags: ['fanout', 'feed'],
    size: '5 block',
    hintPreview: 'Lấy danh sách follower trước, rồi lặp để đẩy bài vào feed.',
  ),
  PendingContent(
    id: 'pending-url-shortener',
    kind: ContentKind.theme,
    title: 'URL shortener system',
    target: 'Theme mới',
    description:
        'Hàm băm, xử lý va chạm, chuyển hướng. Mỗi bài tối đa 5 block.',
    tags: ['hashing', 'redirect'],
    size: '6 bài tập',
  ),
  PendingContent(
    id: 'pending-cosine-sim',
    kind: ContentKind.exercise,
    title: 'cosine_similarity()',
    target: 'Semantic RAG system',
    description: 'Tính độ tương đồng cosine giữa hai vector embedding.',
    tags: ['embedding', 'math'],
    size: '4 block',
    hintPreview: 'Tích vô hướng chia cho tích hai độ dài vector.',
  ),
];
