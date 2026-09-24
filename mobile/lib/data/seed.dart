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
              Exercise(
                id: 'split-chunks',
                title: 'Cắt văn bản thành các đoạn cố định',
                functionName: 'split_chunks',
                params: const ['text', 'size'],
                blocks: [
                  Block(
                    id: 'split-chunks-b0',
                    title: 'Khai báo hàm',
                    prompt:
                        'Khai báo hàm split_chunks nhận vào text và size.',
                    indentLevel: 0,
                    acceptedAnswers: const [
                      'def split_chunks(text, size):',
                    ],
                    expectedOutput: 'Đã khai báo hàm split_chunks.',
                    hints: const [
                      'Dùng từ khoá def để khai báo hàm.',
                      'Tên hàm là split_chunks, tham số gồm text và size.',
                      'def split_chunks(text, size):',
                    ],
                    vocab: const ['def', 'text', 'size'],
                  ),
                  Block(
                    id: 'split-chunks-b1',
                    title: 'Khởi tạo danh sách rỗng',
                    prompt: 'Tạo biến chunks là một danh sách rỗng để chứa kết quả.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'chunks = []',
                    ],
                    expectedOutput: 'Đã khởi tạo danh sách chunks rỗng.',
                    hints: const [
                      'Cần một biến để gom các đoạn văn bản đã cắt.',
                      'Danh sách rỗng trong Python viết bằng dấu ngoặc vuông.',
                      'chunks = []',
                    ],
                    vocab: const ['chunks', 'list'],
                  ),
                  Block(
                    id: 'split-chunks-b2',
                    title: 'Vòng lặp theo bước size',
                    prompt:
                        'Viết vòng lặp duyệt text từ chỉ số 0 đến độ dài text, '
                        'mỗi bước nhảy cách nhau size ký tự.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'for i in range(0, len(text), size):',
                    ],
                    expectedOutput: 'Đã tạo vòng lặp.',
                    hints: const [
                      'Lặp qua các chỉ số bắt đầu từ 0 đến độ dài text, bước nhảy là size.',
                      'Dùng range(0, len(text), size) để tạo chỉ số.',
                      'for i in range(0, len(text), size):',
                    ],
                    vocab: const ['for', 'range', 'len'],
                  ),
                  Block(
                    id: 'split-chunks-b3',
                    title: 'Cắt và thêm vào danh sách',
                    prompt:
                        'Bên trong vòng lặp, cắt đoạn text[i:i + size] '
                        'rồi thêm vào danh sách chunks.',
                    indentLevel: 2,
                    acceptedAnswers: const [
                      'chunks.append(text[i:i + size])',
                    ],
                    expectedOutput: 'Đã cắt text thành các đoạn theo size.',
                    hints: const [
                      'Bên trong vòng lặp, cắt đoạn text từ i đến i+size rồi thêm vào danh sách.',
                      'Dùng text[i:i + size] để cắt, append để thêm vào chunks.',
                      'chunks.append(text[i:i + size])',
                    ],
                    vocab: const ['append', 'chunks', 'text'],
                  ),
                  Block(
                    id: 'split-chunks-b4',
                    title: 'Trả về kết quả',
                    prompt: 'Trả về danh sách chunks đã cắt.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'return chunks',
                    ],
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
              Exercise(
                id: 'overlap-chunks',
                title: 'Cắt đoạn có phần chồng lấn (overlap)',
                functionName: 'overlap_chunks',
                params: const ['text', 'size', 'overlap'],
                blocks: [
                  Block(
                    id: 'overlap-chunks-b0',
                    title: 'Khai báo hàm',
                    prompt:
                        'Khai báo hàm overlap_chunks nhận text, size, overlap.',
                    indentLevel: 0,
                    acceptedAnswers: const [
                      'def overlap_chunks(text, size, overlap):',
                    ],
                    expectedOutput: 'Đã khai báo hàm overlap_chunks.',
                    hints: const [
                      'Dùng từ khoá def để khai báo hàm.',
                      'Tham số gồm text, size và overlap.',
                      'def overlap_chunks(text, size, overlap):',
                    ],
                    vocab: const ['def', 'overlap'],
                  ),
                  Block(
                    id: 'overlap-chunks-b1',
                    title: 'Khởi tạo danh sách rỗng',
                    prompt: 'Tạo biến chunks là danh sách rỗng.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'chunks = []',
                    ],
                    expectedOutput: 'Đã khởi tạo danh sách chunks rỗng.',
                    hints: const [
                      'Cần một biến để gom kết quả.',
                      'Danh sách rỗng viết bằng dấu ngoặc vuông.',
                      'chunks = []',
                    ],
                    vocab: const ['chunks', 'list'],
                  ),
                  Block(
                    id: 'overlap-chunks-b2',
                    title: 'Lặp và cắt đoạn có chồng lấn',
                    prompt:
                        'Lặp theo bước (size - overlap), mỗi lần cắt đoạn '
                        'text[i:i + size] rồi thêm vào chunks.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'for i in range(0, len(text), size - overlap):\n'
                          '    chunks.append(text[i:i + size])',
                    ],
                    expectedOutput: 'Đã cắt text thành các đoạn có chồng lấn.',
                    hints: const [
                      'Bước nhảy nhỏ hơn size để tạo phần chồng lấn.',
                      'Bước nhảy tính bằng size trừ overlap.',
                      'for i in range(0, len(text), size - overlap):\n'
                          '    chunks.append(text[i:i + size])',
                    ],
                    vocab: const ['range', 'overlap', 'append'],
                  ),
                  Block(
                    id: 'overlap-chunks-b3',
                    title: 'Trả về kết quả',
                    prompt: 'Trả về danh sách chunks đã cắt.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'return chunks',
                    ],
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
                blocks: [
                  Block(
                    id: 'clean-text-b0',
                    title: 'Khai báo hàm',
                    prompt: 'Khai báo hàm clean_text nhận vào text.',
                    indentLevel: 0,
                    acceptedAnswers: const [
                      'def clean_text(text):',
                    ],
                    expectedOutput: 'Đã khai báo hàm clean_text.',
                    hints: const [
                      'Dùng từ khoá def để khai báo hàm.',
                      'Tham số duy nhất là text.',
                      'def clean_text(text):',
                    ],
                    vocab: const ['def', 'text'],
                  ),
                  Block(
                    id: 'clean-text-b1',
                    title: 'Trả về text đã strip khoảng trắng',
                    prompt: 'Trả về text sau khi bỏ khoảng trắng thừa ở đầu/cuối.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'return text.strip()',
                    ],
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
                blocks: [
                  Block(
                    id: 'save-document-b0',
                    title: 'Khai báo hàm',
                    prompt:
                        'Khai báo hàm save_document nhận store và document.',
                    indentLevel: 0,
                    acceptedAnswers: const [
                      'def save_document(store, document):',
                    ],
                    expectedOutput: 'Đã khai báo hàm save_document.',
                    hints: const [
                      'Dùng từ khoá def để khai báo hàm.',
                      'Tham số gồm store và document.',
                      'def save_document(store, document):',
                    ],
                    vocab: const ['def', 'store', 'document'],
                  ),
                  Block(
                    id: 'save-document-b1',
                    title: 'Thêm document vào store',
                    prompt: 'Thêm document vào danh sách store.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'store.append(document)',
                    ],
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
                blocks: [
                  Block(
                    id: 'like-post-b0',
                    title: 'Khai báo hàm',
                    prompt: 'Khai báo hàm like_post nhận vào post.',
                    indentLevel: 0,
                    acceptedAnswers: const [
                      'def like_post(post):',
                    ],
                    expectedOutput: 'Đã khai báo hàm like_post.',
                    hints: const [
                      'Dùng từ khoá def để khai báo hàm.',
                      'Tham số duy nhất là post.',
                      'def like_post(post):',
                    ],
                    vocab: const ['def', 'post'],
                  ),
                  Block(
                    id: 'like-post-b1',
                    title: 'Tăng số lượt thích',
                    prompt: 'Tăng post["likes"] lên 1.',
                    indentLevel: 1,
                    acceptedAnswers: const [
                      'post["likes"] += 1',
                    ],
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

/// Số block đã hoàn thành sẵn khi mở app, theo exerciseId.
/// split-chunks: đang dở (2/5 block). Các exercise khác trong seed: 0, trừ
/// clean-text (đã xong hẳn).
final Map<String, int> seedCompletedBlocks = {
  'split-chunks': 2,
  'overlap-chunks': 0,
  'clean-text': 2,
  'save-document': 0,
  'like-post': 0,
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
