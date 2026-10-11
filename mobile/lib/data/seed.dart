import '../domain/models.dart';

/// Dữ liệu học seed sẵn: 3 theme, mỗi theme có ít nhất 1 topic/1 exercise.
/// Theme `rag` là nhánh chính, có đủ topic Chunking với file chunker.py
/// (exercise `split-chunks` đang dở, `overlap-chunks` chưa làm) và
/// preprocessor.py (exercise đã xong hẳn).
final List<StudyTheme> seedThemes = [
  StudyTheme(
    id: 'rag',
    name: 'Semantic RAG system',
    description:
        'Xây hệ thống truy xuất tăng cường (RAG) từ những bước nhỏ nhất: '
        'chia nhỏ văn bản, tiền xử lý dữ liệu trước khi đưa vào embedding.',
    tags: const ['python', 'rag', 'nlp'],
    topics: [
      Topic(
        id: 'rag-chunking',
        name: 'Chunking',
        description:
            'Chia văn bản dài thành các đoạn nhỏ để đưa vào mô hình embedding.',
        files: [
          CodeFile(
            id: 'rag-chunker-py',
            name: 'chunker.py',
            exercises: [
              splitChunksExercise,
              Exercise(
                id: 'overlap-chunks',
                title: 'Cắt đoạn có phần chồng lấn (overlap)',
                functionName: 'overlap_chunks',
                params: const ['text', 'size', 'overlap'],
                template: 'def overlap_chunks(text, size, overlap):\n    chunks = []\n    # TODO A\n        # TODO B\n    # TODO C',
                challenge: Challenge(
                  statement: 'Viết hàm overlap_chunks(text, size, overlap) cắt text thành các đoạn dài tối đa size ký tự, mỗi đoạn lặp lại overlap ký tự cuối của đoạn trước.',
                  motivation: 'Cắt cứng có thể làm đứt câu giữa chừng. Cho các đoạn chồng lên nhau một chút thì ý nằm ở ranh giới vẫn xuất hiện trọn vẹn trong ít nhất một đoạn.',
                  small: Example(
                    caption: 'Cắt "abcdefghij", đoạn 4 ký tự, chồng 1 ký tự',
                    input: 'print(overlap_chunks("abcdefghij", 4, 1))',
                    output: '[\'abcd\', \'defg\', \'ghij\', \'j\']',
                    note: 'Mỗi đoạn bắt đầu cách đoạn trước size - overlap = 3 ký tự.',
                  ),
                  project: Example(
                    caption: 'Cắt sổ tay nhân sự để câu không bị đứt ở ranh giới',
                    input: 'handbook = "Nhân viên được nghỉ phép 12 ngày/năm. Phép chưa dùng hết được cộng dồn sang quý 1 năm sau."\nprint(overlap_chunks(handbook, 30, 10))',
                    output: '[\'Nhân viên được nghỉ phép 12 ng\', \'phép 12 ngày/năm. Phép chưa dù\', \'ép chưa dùng hết được cộng dồn\', \'c cộng dồn sang quý 1 năm sau.\', \'1 năm sau.\']',
                    note: 'Cụm "phép 12 ngày/năm" nay xuất hiện trọn trong đoạn thứ hai.',
                  ),
                ),
                blocks: [
                  Block(
                    id: 'overlap-chunks-a',
                    label: 'A',
                    title: 'Vòng lặp với bước size - overlap',
                    prompt: 'Duyệt i từ 0 đến len(text), mỗi lần nhảy size - overlap.',
                    indentLevel: 1,
                    acceptedAnswers: const ['for i in range(0, len(text), size - overlap):'],
                    explanation: 'Bước nhảy nhỏ hơn size nên đoạn sau bắt đầu sớm hơn chỗ đoạn trước kết thúc, tạo phần chồng lấn overlap ký tự.',
                    expectedOutput: 'Đã tạo vòng lặp.',
                    hints: const [
                      'Bước nhảy phải nhỏ hơn size để các đoạn chồng lên nhau.',
                      'Bước nhảy tính bằng size - overlap.',
                      'for i in range(0, len(text), size - overlap):',
                    ],
                    vocab: const ['range', 'overlap', 'len'],
                  ),
                  Block(
                    id: 'overlap-chunks-b',
                    label: 'B',
                    title: 'Cắt và thêm vào danh sách',
                    prompt: 'Cắt text[i:i + size] rồi thêm vào chunks.',
                    indentLevel: 2,
                    acceptedAnswers: const ['chunks.append(text[i:i + size])'],
                    explanation: 'Mỗi đoạn vẫn dài tối đa size ký tự, chỉ có vị trí bắt đầu là dịch theo bước nhỏ hơn.',
                    expectedOutput: 'Đã cắt text thành các đoạn có chồng lấn.',
                    hints: const [
                      'Cắt đoạn từ i đến i + size rồi thêm vào danh sách.',
                      'Dùng text[i:i + size] và append.',
                      'chunks.append(text[i:i + size])',
                    ],
                    vocab: const ['append', 'chunks', 'text'],
                  ),
                  Block(
                    id: 'overlap-chunks-c',
                    label: 'C',
                    title: 'Trả về kết quả',
                    prompt: 'Trả về danh sách chunks.',
                    indentLevel: 1,
                    acceptedAnswers: const ['return chunks'],
                    explanation: 'return nằm ngoài vòng for để chỉ trả kết quả sau khi đã cắt hết.',
                    expectedOutput: '[\'...\', \'...\', \'...\']',
                    hints: const [
                      'Hàm cần trả kết quả ra ngoài bằng return.',
                      'Biến chứa kết quả là chunks.',
                      'return chunks',
                    ],
                    vocab: const ['return', 'chunks'],
                  ),
                ],
              ),
            ],
          ),
          CodeFile(
            id: 'rag-preprocessor-py',
            name: 'preprocessor.py',
            exercises: [
              Exercise(
                id: 'clean-text',
                title: 'Chuẩn hoá văn bản trước khi chunking',
                functionName: 'clean_text',
                params: const ['text'],
                template: 'def clean_text(text):\n    # TODO A',
                challenge: Challenge(
                  statement: 'Viết hàm clean_text(text) trả về text sau khi bỏ khoảng trắng và xuống dòng thừa ở đầu và cuối.',
                  motivation: 'Văn bản lấy từ PDF hay web thường dính khoảng trắng, xuống dòng thừa. Làm sạch trước khi chunking giúp các đoạn không chứa rác và embedding chính xác hơn.',
                  small: Example(
                    caption: 'Bỏ khoảng trắng hai đầu',
                    input: 'print(repr(clean_text("  hello  ")))',
                    output: '\'hello\'',
                  ),
                  project: Example(
                    caption: 'Làm sạch tiêu đề đọc từ một file PDF',
                    input: 'title = "\\n  Chính sách nghỉ phép năm 2026  \\n"\nprint(repr(clean_text(title)))',
                    output: '\'Chính sách nghỉ phép năm 2026\'',
                    note: 'Khoảng trắng ở giữa chuỗi được giữ nguyên.',
                  ),
                ),
                blocks: [
                  Block(
                    id: 'clean-text-a',
                    label: 'A',
                    title: 'Trả về text đã strip',
                    prompt: 'Trả về text sau khi bỏ khoảng trắng thừa ở đầu và cuối.',
                    indentLevel: 1,
                    acceptedAnswers: const ['return text.strip()'],
                    explanation: 'strip() là hàm có sẵn của chuỗi: cắt khoảng trắng và xuống dòng ở hai đầu, trả về chuỗi mới.',
                    expectedOutput: 'Đã chuẩn hoá text (bỏ khoảng trắng thừa).',
                    hints: const [
                      'Python có sẵn hàm strip() cho chuỗi.',
                      'Nhớ return kết quả ra ngoài.',
                      'return text.strip()',
                    ],
                    vocab: const ['strip', 'return'],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  StudyTheme(
    id: 'doc-system',
    name: 'Document system',
    description:
        'Xây dựng hệ thống quản lý tài liệu: lưu trữ, tìm kiếm và tổ chức '
        'file theo thư mục.',
    tags: const ['python', 'file-system'],
    topics: [
      Topic(
        id: 'doc-text-processing',
        name: 'Text processing',
        description:
            'Cắt nội dung tài liệu thành đoạn nhỏ trước khi đánh chỉ mục.',
        files: [
          CodeFile(
            id: 'doc-chunker-py',
            name: 'chunker.py',
            exercises: [splitChunksExercise],
          ),
        ],
      ),
      Topic(
        id: 'doc-storage',
        name: 'Storage',
        description: 'Lưu trữ và đọc metadata của tài liệu.',
        files: [
          CodeFile(
            id: 'doc-storage-py',
            name: 'storage.py',
            exercises: [
              Exercise(
                id: 'save-document',
                title: 'Lưu tài liệu vào danh sách',
                functionName: 'save_document',
                params: const ['store', 'document'],
                template: 'def save_document(store, document):\n    # TODO A',
                challenge: Challenge(
                  statement: 'Viết hàm save_document(store, document) thêm document vào cuối danh sách store. Hàm sửa trực tiếp store, không cần return.',
                  motivation: 'Hệ thống quản lý tài liệu cần nơi lưu những file đã tải lên. Thêm vào danh sách là bước nền tảng của mọi thao tác lưu trữ.',
                  small: Example(
                    caption: 'Lưu một file vào danh sách rỗng',
                    input: 'store = []\nsave_document(store, "doc1.pdf")\nprint(store)',
                    output: '[\'doc1.pdf\']',
                  ),
                  project: Example(
                    caption: 'Thêm báo cáo mới vào kho tài liệu đã có',
                    input: 'store = ["hop-dong.pdf"]\nsave_document(store, "bao-cao-q3.docx")\nprint(store)',
                    output: '[\'hop-dong.pdf\', \'bao-cao-q3.docx\']',
                    note: 'Tài liệu cũ được giữ, tài liệu mới nằm cuối.',
                  ),
                ),
                blocks: [
                  Block(
                    id: 'save-document-a',
                    label: 'A',
                    title: 'Thêm document vào store',
                    prompt: 'Thêm document vào cuối danh sách store.',
                    indentLevel: 1,
                    acceptedAnswers: const ['store.append(document)'],
                    explanation: 'append thêm phần tử vào cuối list và sửa trực tiếp list đó, nên hàm không cần return.',
                    expectedOutput: 'Đã lưu document vào store.',
                    hints: const [
                      'store là một danh sách (list).',
                      'Thêm phần tử vào cuối list bằng append.',
                      'store.append(document)',
                    ],
                    vocab: const ['append', 'store'],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  StudyTheme(
    id: 'twitter-feed',
    name: 'Twitter feed',
    description:
        'Xây dựng bảng tin đơn giản kiểu Twitter: đăng bài và đếm lượt thích.',
    tags: const ['python', 'social'],
    topics: [
      Topic(
        id: 'feed-basics',
        name: 'Feed basics',
        description: 'Các thao tác cơ bản trên một bài đăng.',
        files: [
          CodeFile(
            id: 'feed-post-py',
            name: 'post.py',
            exercises: [
              Exercise(
                id: 'like-post',
                title: 'Tăng lượt thích cho bài đăng',
                functionName: 'like_post',
                params: const ['post'],
                template: 'def like_post(post):\n    # TODO A',
                challenge: Challenge(
                  statement: 'Viết hàm like_post(post) tăng giá trị post["likes"] lên 1. Hàm sửa trực tiếp post, không cần return.',
                  motivation: 'Mỗi lần người dùng bấm thích, mạng xã hội phải cộng thêm một lượt thích cho bài đăng. Đây là thao tác cập nhật đếm cơ bản nhất của một bảng tin.',
                  small: Example(
                    caption: 'Bài có 5 lượt thích',
                    input: 'post = {"likes": 5}\nlike_post(post)\nprint(post)',
                    output: '{\'likes\': 6}',
                  ),
                  project: Example(
                    caption: 'Bấm thích một bài đăng trên bảng tin',
                    input: 'post = {"id": 42, "text": "Hello Hanoi!", "likes": 120}\nlike_post(post)\nprint(post)',
                    output: '{\'id\': 42, \'text\': \'Hello Hanoi!\', \'likes\': 121}',
                    note: 'Các trường khác của bài đăng không đổi.',
                  ),
                ),
                blocks: [
                  Block(
                    id: 'like-post-a',
                    label: 'A',
                    title: 'Tăng số lượt thích',
                    prompt: 'Tăng post["likes"] lên 1.',
                    indentLevel: 1,
                    acceptedAnswers: const ['post["likes"] += 1'],
                    explanation: 'Toán tử += cộng thêm 1 vào giá trị hiện tại của khoá "likes" ngay trên dict post.',
                    expectedOutput: 'Đã tăng lượt thích lên 1.',
                    hints: const [
                      'post là một dict có khoá "likes".',
                      'Dùng toán tử += để tăng giá trị.',
                      'post["likes"] += 1',
                    ],
                    vocab: const ['likes', 'dict'],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];

/// Exercise split_chunks: dùng chung giữa `rag` (Chunking) và `doc-system`
/// (Text processing) — cùng file chunker.py nên làm một lần là tiến độ tính
/// cho cả hai theme (màn File cross-cut).
final Exercise splitChunksExercise = Exercise(
  id: 'split-chunks',
  title: 'Cắt văn bản thành các đoạn cố định',
  functionName: 'split_chunks',
  params: const ['text', 'size'],
  template: 'def split_chunks(text, size):\n    chunks = []\n    # TODO A\n        # TODO B\n    # TODO C',
  challenge: Challenge(
    statement: 'Viết hàm split_chunks(text, size) cắt chuỗi text thành các đoạn dài tối đa size ký tự, theo thứ tự, rồi trả về danh sách các đoạn.',
    motivation: 'Mô hình embedding chỉ nhận đoạn văn ngắn. Hệ thống RAG phải cắt tài liệu dài thành từng đoạn nhỏ trước khi lập chỉ mục để tìm kiếm.',
    small: Example(
      caption: 'Cắt "hello world" thành đoạn 4 ký tự',
      input: 'print(split_chunks("hello world", 4))',
      output: '[\'hell\', \'o wo\', \'rld\']',
      note: 'Đoạn cuối ngắn hơn size vẫn được giữ.',
    ),
    project: Example(
      caption: 'Cắt sổ tay nhân sự (HR handbook) để đưa vào RAG',
      input: 'handbook = "Nhân viên được nghỉ phép 12 ngày/năm. Phép chưa dùng hết được cộng dồn sang quý 1 năm sau."\nprint(split_chunks(handbook, 30))',
      output: '[\'Nhân viên được nghỉ phép 12 ng\', \'ày/năm. Phép chưa dùng hết đượ\', \'c cộng dồn sang quý 1 năm sau.\']',
      note: 'Cắt cứng theo ký tự nên có thể cắt giữa từ; bài sau sẽ xử lý bằng overlap.',
    ),
  ),
  blocks: [
    Block(
      id: 'split-chunks-a',
      label: 'A',
      title: 'Vòng lặp theo bước size',
      prompt: 'Duyệt chỉ số i từ 0 đến len(text), mỗi lần nhảy size.',
      indentLevel: 1,
      acceptedAnswers: const ['for i in range(0, len(text), size):'],
      explanation: 'range(0, len(text), size) tạo các chỉ số 0, size, 2*size... nên mỗi vòng bắt đầu đúng đầu một đoạn.',
      expectedOutput: 'Đã tạo vòng lặp.',
      hints: const [
        'Lặp qua các chỉ số bắt đầu đoạn, cách nhau size.',
        'Dùng range(0, len(text), size).',
        'for i in range(0, len(text), size):',
      ],
      vocab: const ['for', 'range', 'len'],
    ),
    Block(
      id: 'split-chunks-b',
      label: 'B',
      title: 'Cắt và thêm vào danh sách',
      prompt: 'Cắt text[i:i + size] rồi thêm vào chunks.',
      indentLevel: 2,
      acceptedAnswers: const ['chunks.append(text[i:i + size])'],
      explanation: 'text[i:i + size] lấy tối đa size ký tự từ vị trí i; append đưa đoạn đó vào danh sách kết quả.',
      expectedOutput: 'Đã cắt text thành các đoạn theo size.',
      hints: const [
        'Cắt đoạn từ i đến i + size rồi thêm vào danh sách.',
        'Dùng text[i:i + size] và append.',
        'chunks.append(text[i:i + size])',
      ],
      vocab: const ['append', 'chunks', 'text'],
    ),
    Block(
      id: 'split-chunks-c',
      label: 'C',
      title: 'Trả về kết quả',
      prompt: 'Trả về danh sách chunks.',
      indentLevel: 1,
      acceptedAnswers: const ['return chunks'],
      explanation: 'return nằm ngoài vòng for nên chỉ chạy một lần, sau khi đã cắt xong mọi đoạn.',
      expectedOutput: '[\'...\', \'...\', \'...\']',
      hints: const [
        'Hàm cần trả kết quả ra ngoài bằng return.',
        'Biến chứa kết quả là chunks.',
        'return chunks',
      ],
      vocab: const ['return', 'chunks'],
    ),
  ],
);

/// Số block đã hoàn thành sẵn khi mở app, theo exerciseId.
/// (Sẽ bị xoá khi T-06 chuyển tiến độ sang `seedPassedExercises`/`seedDrafts`.)
/// split-chunks: 0; clean-text đã xong hẳn (1 ô); còn lại 0.
final Map<String, int> seedCompletedBlocks = {
  'split-chunks': 0,
  'overlap-chunks': 0,
  'clean-text': 1,
  'save-document': 0,
  'like-post': 0,
};

/// Bài đã chạy đúng toàn bộ unit test khi mở app.
final Set<String> seedPassedExercises = {'clean-text'};

/// Nháp có sẵn: exerciseId → (nhãn ô → code đã gõ). split-chunks đang làm dở.
final Map<String, Map<String, String>> seedDrafts = {
  'split-chunks': {'A': 'for i in range(0, len(text), size):'},
};

/// Tìm exercise theo id trên toàn bộ seed. Throw [StateError] nếu không có.
Exercise exerciseById(String id) {
  for (final theme in seedThemes) {
    for (final topic in theme.topics) {
      for (final file in topic.files) {
        for (final exercise in file.exercises) {
          if (exercise.id == id) return exercise;
        }
      }
    }
  }
  throw StateError('Không tìm thấy exercise với id: $id');
}

/// Tìm theme/topic/file chứa exercise có id [exerciseId].
({StudyTheme theme, Topic topic, CodeFile file}) locateExercise(
  String exerciseId,
) {
  for (final theme in seedThemes) {
    for (final topic in theme.topics) {
      for (final file in topic.files) {
        for (final exercise in file.exercises) {
          if (exercise.id == exerciseId) {
            return (theme: theme, topic: topic, file: file);
          }
        }
      }
    }
  }
  throw StateError('Không tìm thấy exercise với id: $exerciseId');
}

/// Mọi exercise trong seed, mỗi id một lần (exercise dùng chung giữa nhiều
/// file chỉ xuất hiện một lần), theo thứ tự theme → topic → file.
List<Exercise> uniqueExercises() {
  final seen = <String>{};
  return [
    for (final theme in seedThemes)
      for (final topic in theme.topics)
        for (final file in topic.files)
          for (final exercise in file.exercises)
            if (seen.add(exercise.id)) exercise,
  ];
}

/// Mọi nơi dùng file có tên [fileName] (vd 'chunker.py'), theo thứ tự theme.
List<({StudyTheme theme, Topic topic, CodeFile file})> locateFilesNamed(
  String fileName,
) {
  return [
    for (final theme in seedThemes)
      for (final topic in theme.topics)
        for (final file in topic.files)
          if (file.name == fileName) (theme: theme, topic: topic, file: file),
  ];
}

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
final Map<String, int> seedReviewDueInDays = {
  'clean-text-a': 1,
};

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
    description: 'Hàm băm, xử lý va chạm, chuyển hướng. Mỗi bài tối đa 5 block.',
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
