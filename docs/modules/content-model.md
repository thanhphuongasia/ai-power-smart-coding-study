# Content model (cây nội dung: theme → module lồng nhau → file → bài → ô)

> Hình dạng dữ liệu học đi từ `content.json` tới Postgres, `/content` và app: ai soạn bài hoặc sửa loader/parser cần biết cây này, module con và bài method hoạt động thế nào.

## Là gì

Nội dung học là một cây. Theme chứa module (trong code gọi là `topics`), module chứa file và có thể chứa module con ở độ sâu tuỳ ý, file chứa danh sách bài, bài chứa các ô TODO. Một bài là hàm rời hoặc method của một class; nếu là method thì có thêm `class_name`. Bài nằm riêng trong `exercises` theo id, cây chỉ tham chiếu id, nên cùng một bài có thể xuất hiện ở nhiều file. Cây này là bản duy nhất của nội dung: backend lưu vào Postgres, phát cho app, còn app không giữ nội dung học nào ngoài bản tải về.

## Dùng khi nào

Khi soạn thêm module/bài trong `backend/content/content.json`, khi sửa loader (`backend/app/load_content.py`), schema (`backend/app/content_schema.py`), `GET /content` (`backend/app/content_api.py`) hoặc parser Dart (`mobile/lib/domain/content.dart`, `models.dart`). Hai phía Python và Dart giữ khớp bằng tay, nên đổi một phía phải đổi phía kia.

## Cách hoạt động

| Khái niệm | Trong `content.json` / schema | Trong DB | Trong app |
|---|---|---|---|
| Module con | `Topic.modules: list[Topic]`, key bắt buộc (rỗng = `[]`) — backend/app/content_schema.py:66-73 | `topics.parent_id` (FK tự trỏ, CASCADE, có index) — backend/app/tables.py:38 | `Topic.modules`, `allFiles`, `allModules` — mobile/lib/domain/models.dart:116-135 |
| Thứ tự anh em | thứ tự mảng | `topics.position` = số thứ tự preorder trong theme — backend/app/tables.py:5,41 | giữ nguyên thứ tự `/content` |
| Bài method | `Exercise.class_name: str \| None`, key bắt buộc, `null` = hàm rời — backend/app/content_schema.py:52 | `exercises.class_name` nullable — backend/app/tables.py:67 | `Exercise.className`, `qualifiedName` — mobile/lib/domain/models.dart:316-320 |
| Sơ đồ class (theo theme) | `Theme.diagram: ClassDiagram` — `classes[{name,file,attributes[{name,type,group}],methods[]}]`, `relations[{from,to,kind,label,via[]}]`, key bắt buộc (rỗng = `{"classes": [], "relations": []}`) — backend/app/content_schema.py:76-113 | `themes.diagram` JSONB, NOT NULL — backend/app/tables.py:30 | `StudyTheme.diagram`, `ClassDiagram.classNamed/relationsOf` — mobile/lib/domain/models.dart:53,224-243 |
| Case chấm | `judge.cases[]`: dạng `args` hoặc dạng kịch bản `{steps, call, expect}` | `exercises.judge_cases` (JSON) | không có: `/content` không trả `judge` |

Loader duyệt cây trước cha sau con để gán `position` và `parent_id`:

```python
def _walk_topics(topics: list[dict], parent_id: str | None = None):
    """Duyệt trước (preorder) cây module: yield (topic, parent_id) — cha trước con."""
    for tp in topics:
        yield tp, parent_id
        yield from _walk_topics(tp.get("modules", []), tp.get("id"))
```
(backend/app/load_content.py:42-46)

`GET /content` dựng lại cây từ `parent_id` (module cấp 1 có `parent_id` rỗng), và xếp `exercises` theo thứ tự xuất hiện đầu tiên khi duyệt cây — file của module trước, rồi tới module con — cùng thứ tự với `Topic.allFiles` ở app (backend/app/content_api.py:72-80,90-107). Vị trí ô (hàm/method/class) không nằm trong dữ liệu mà app suy từ template (mobile/lib/domain/merge.dart:135-175).

Sơ đồ class: loader kiểm tên class duy nhất, `from`/`to` là class có trong sơ đồ, `via` là tập con methods của `from` (backend/app/load_content.py:70-87, gọi ở dòng 118). `kind` ∈ association/aggregation/composition/dependency và `group` ∈ core/support chặn bằng `Literal` (backend/app/content_schema.py:79,98). Key quan hệ chỉ là `from` — `from_` bị từ chối vì `extra="forbid"` (backend/app/content_schema.py:96, test backend/tests/test_load_content.py:221). `/content` phát nguyên `theme.diagram` (backend/app/content_api.py:118). Sơ đồ khớp code bài do test Dart kiểm: thuộc tính (`self.<attr> =`) và method (`def <m>(`) phải có trong đúng thân `class <Name>` ở code ghép của các bài cùng theme (mobile/test/content_contract_test.dart:13-27,383-425).

Kiểm lúc nạp: `validate` bắt id trùng, `exercise_ids` trỏ bài không có, label ô trùng, case kịch bản không compile được, và bài `class_name` có case không phải dạng `call` (backend/app/load_content.py:74-132).

## Ranh giới & đánh đổi

Tên class là thuộc tính của bài, không phải bảng `classes`: chưa có thứ gì cần gắn vào class ngoài tên, và bảng riêng kéo theo thêm FK, thêm thứ tự và thêm chỗ để hai bên lệch. Cái giá là cùng tên class lặp ở nhiều bài, và màn Topic nhóm bài theo class bằng cách so `className` của hai bài liền kề (mobile/lib/features/browse/topic_detail_screen.dart:55-64).

Cây lồng nhau dùng `parent_id` + `position` preorder thay vì cột đường dẫn hay bảng đóng: đọc cả cây bằng một SELECT mỗi bảng rồi ghép trong bộ nhớ, không cần truy vấn đệ quy ở Postgres. Đổi lại, thứ tự anh em chỉ đúng nếu loader là nơi duy nhất ghi.

Hạ cấp migration 0002 bỏ hai cột và mất quan hệ cha–con cùng `class_name`. Chấp nhận được vì bảng nội dung là bản dẫn xuất của `content.json`, chạy lại `python -m app.load_content` là có đủ (backend/migrations/versions/0002_module_tree_class.py:33-35).

Sơ đồ soạn tay, không suy từ code, vì quan hệ (vd FlightService giữ Flight) không có trong code mẫu rút gọn; đổi lại có thể lệch, và test chỉ chặn member không có thật, không chặn nhãn/quan hệ sai nghĩa. Hạ cấp 0003 bỏ cột `diagram`, nạp lại `content.json` là đủ (backend/migrations/versions/0003_theme_diagram.py:37-38).

Không làm: giới hạn độ sâu module; tiến độ theo module (thẻ module chỉ hiện số bài, mobile/lib/features/browse/topic_detail_screen.dart:136-144).

## Giới hạn đã biết

- Loader chưa kiểm `via` rỗng/trùng, thuộc tính trùng, quan hệ tự trỏ, và class trùng tên cho lỗi nhiễu; test không kiểm nhãn quan hệ khớp code (planning/crew/2026-10-11-class-diagram/STATUS.md, Backlog).
- `/content` không kiểm module con có cùng `theme_id` với cha; chỉ đúng khi DB do loader ghi, sửa DB tay có thể làm sai (planning/crew/2026-10-11-project-tree-airline/STATUS.md, Backlog T-07).
- Dựng danh sách bài dùng `in` trên list, O(n²), chưa đo (backend/app/content_api.py:99; STATUS.md Backlog T-07).
- Sub-module hiện trước file của chính module cha ở màn Topic; thẻ module chưa có tiến độ; chưa test ≥3 tầng ở 375px (STATUS.md Backlog T-06).
- Chưa có test cho bài dùng chung giữa file cha và module con (STATUS.md Backlog, `content_json_test`).

## Nguồn

- Loader + validate: backend/app/load_content.py:42-132,135-205
- Schema: backend/app/content_schema.py:49-73
- Bảng + migration: backend/app/tables.py:31-67, backend/migrations/versions/0002_module_tree_class.py:22-35
- Phát cây: backend/app/content_api.py:64-125
- Domain Dart: mobile/lib/domain/models.dart:57-135,304-360; mobile/lib/domain/content.dart:28-64
- Seed mẫu: backend/content/content.json:6,36-51,195
- Tổng quan: docs/ARCHITECTURE.md mục "Cây nội dung"; case kịch bản: docs/modules/judge-backend.md
- Run: planning/crew/2026-10-11-project-tree-airline/PLAN.md, STATUS.md, DEVIATIONS.md
- Sơ đồ class (loader/schema/migration/test): backend/app/load_content.py:70-87, backend/app/content_schema.py:76-113, backend/migrations/versions/0003_theme_diagram.py:22-38, mobile/test/content_contract_test.dart:367-426; run: planning/crew/2026-10-11-class-diagram/PLAN.md, STATUS.md
