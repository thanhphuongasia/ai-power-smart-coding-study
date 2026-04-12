# `plan-content-library-v2-multilanguage.md`

## Summary
- Thiết kế lại hệ thống nội dung từ model cũ `tracks + skills` sang **schema v2** với 2 entity chính: `Track` và `Exercise`.
- Giữ **3 lane riêng** vì behavior khác nhau: `DSA`, `LeetCode`, `Real Project`.
- Mỗi bài (`Exercise`) hỗ trợ **nhiều ngôn ngữ** bằng `language variants`; user chọn ngôn ngữ luyện theo preference cá nhân.
- Admin chuyển từ dashboard nặng visual sang **content workspace gọn**: filter bar + list + form editor theo lane.
- File cần tạo khi ra khỏi Plan Mode: `plan-content-library-v2-multilanguage.md`.

## Key Changes
### 1) Content schema v2
- `Track` và `Exercise` đều là first-class entity.
- Metadata chuẩn cho mọi content:
  - `id`, `title`, `summary`
  - `lane`: `dsa | leetcode | project`
  - `contentKind`
  - `level`: `foundation | intermediate | advanced`
  - `topicIds[]`
  - `domainIds[]`
  - `tags[]`
  - `skillIds[]`
  - workflow draft/published
- `Exercise` là đơn vị chính để browse, filter, luyện tập.
- `Track` là learning path / curated collection có thứ tự.
- Một `Exercise` có thể thuộc **nhiều tracks** hoặc đứng độc lập.

### 2) Lane model
- `DSA`
  - có `dsa exercises`
  - có thể có `dsa tracks` để gom theo pattern/chủ đề
  - không bắt buộc testcase judge-style
- `LeetCode`
  - có `leetcode exercises`
  - optional `leetcode tracks/sets`
  - testcase/judge config là bắt buộc
- `Real Project`
  - có `project tracks` với milestone flow
  - có `project exercises` độc lập để tái sử dụng ở nhiều track/domain
  - milestone trong project track tham chiếu `project exercise ids`

### 3) Multi-language exercise design
- Mỗi `Exercise` có:
  - metadata chung
  - `languageVariants[]`
- Mỗi `languageVariant` gồm:
  - `languageId`
  - `languageLabel`
  - `isDefault`
  - `starterCode`
  - `starterFiles`
  - `solutionCode`
  - `sandboxHarnessTemplate`
  - `runCommand`
  - `entryFilePath`
  - `demoFilePath`
  - testcase/config riêng nếu lane cần
- `level` là của exercise chung, **không override theo ngôn ngữ**.
- Learner app:
  - nhớ `preferred language` theo user
  - khi mở bài, chọn ngôn ngữ theo thứ tự:
    1. user preference nếu exercise support
    2. default variant của exercise
    3. variant đầu tiên hợp lệ
- Với LeetCode, mỗi variant được phép có testcase/harness riêng để hỗ trợ C#, Python khác runtime.
- Với DSA/Project, variant có thể chỉ khác starter/files/run command nếu testcase không bắt buộc.

### 4) Taxonomy & filters
- Taxonomy chuẩn:
  - `Topic`: `linq`, `concurrency`, `race-condition`, `ddd`, `sql`
  - `Domain`: `transaction-service`, `messaging-system`, `social-network`, `document-management`
- `tags[]` là free-form cho keyword cắt ngang như `list`, `pagination`, `query`, `cache`, `idempotency`.
- Filter chung cho admin và learner app:
  - `lane`
  - `contentKind`
  - `level`
  - `language`
  - `topic`
  - `domain`
  - `tags`
  - `status` trong admin
- Một bài có thể mang nhiều facet cùng lúc:
  - ví dụ “get list document” = `lane: project`, `topic: sql`, `domain: document-management`, `tags: [list, query]`

### 5) Admin redesign
- Bỏ home/dashboard hiện tại làm màn chính.
- Màn admin mặc định là workspace:
  - top filter bar
  - left list/table
  - right detail form
- Navigation:
  - `Tracks`
  - `Exercises`
  - `Topics`
  - `Domains`
  - `Skills`
- Tạo content bằng form riêng theo lane:
  - `New DSA Exercise`
  - `New LeetCode Exercise`
  - `New Project Exercise`
  - `New Track`
- Form `Exercise` gồm:
  - metadata chung
  - taxonomy selectors
  - lane-specific section
  - `Language Variants` section
  - advanced raw JSON section
- Form `Track` gồm:
  - lane
  - level
  - taxonomy
  - ordered references tới exercises hoặc milestones
- List view phải hiển thị ngay:
  - lane
  - level
  - supported languages
  - topics/domains/tags
  - publish status

### 6) Learner app redesign
- Home vẫn giữ 3 entry lớn: `Data Structures`, `LeetCode`, `Real Projects`.
- Mỗi lane có 2 tab:
  - `Tracks`
  - `Exercises`
- Filter sheet/chips trong lane:
  - level
  - language
  - topic
  - domain
  - tags
- Start session flow:
  - nếu bài có nhiều ngôn ngữ, dùng remembered preference hoặc default
  - user đổi ngôn ngữ được trước khi bắt đầu hoặc trong pre-session picker
- Progress:
  - exercise progress theo completion trực tiếp
  - track progress aggregate từ exercise refs
- Review queue vẫn derive từ `skillIds[]`, không derive từ tags/topics/domains.

## Public interfaces / types
- Catalog API v2:
  - `tracks[]`
  - `exercises[]`
  - `topics[]`
  - `domains[]`
  - `skills[]`
  - `tagSuggestions[]`
- Admin API CRUD:
  - `/admin/api/tracks`
  - `/admin/api/exercises`
  - `/admin/api/topics`
  - `/admin/api/domains`
  - `/admin/api/skills`
- Flutter/domain model cần tách:
  - `LearningTrack`
  - `LearningExercise`
  - `ExerciseLanguageVariant`
  - `TopicDefinition`
  - `DomainDefinition`
- Sandbox request shape cần đổi từ single `languageLabel` sang variant-derived payload.
- Validation rules:
  - `leetcode exercise` phải có testcase/judge config cho từng required variant
  - `project track` phải có ordered milestone/exercise refs
  - `exercise` phải có ít nhất 1 language variant
  - chỉ 1 default variant cho mỗi exercise

## TODO Tasks
- [x] Thiết kế type/schema v2 cho `Track`, `Exercise`, `ExerciseLanguageVariant`, `Topic`, `Domain`
- [x] Xác định `contentKind` enum theo lane
- [x] Thiết kế JSON wire format mới cho catalog/admin API
- [x] Viết migration strategy từ schema cũ sang reseed v2
- [x] Reseed demo data đủ 3 lane + multi-language examples
- [x] Thêm example bài `list` có cả `C#` và `Python`
- [x] Thêm examples theo topic: `LINQ`, `SQL`, `DDD`, `Concurrency`, `Race Condition`
- [x] Thêm examples theo domain: `Transaction Service`, `Messaging System`, `Twitter-like Social`
- [x] Refactor admin từ dashboard view sang compact workspace
- [ ] Tạo lane-specific form cho `DSA Exercise`, `LeetCode Exercise`, `Project Exercise`, `Track`
- [ ] Thêm filter UI cho `lane`, `level`, `language`, `topic`, `domain`, `tags`
  - Learner app đã có filter đầy đủ; admin workspace hiện mới có `lane`, `level`, `status`, search.
- [x] Thêm CRUD cho `topics` và `domains`
- [x] Refactor learner catalog sang `Tracks` + `Exercises`
- [x] Thêm language picker + persisted user language preference
- [x] Refactor sandbox flow để chạy theo selected language variant
- [x] Giữ review queue hoạt động qua `skillIds[]`
- [x] Cập nhật docs và sample fixtures

## Progress Update
- Updated on `2026-04-12`.
- Hoàn thành phần core execution cho schema v2, catalog/admin API, seed data, learner app, language variant flow, sandbox payload, và review queue.
- Admin workspace đã chuyển sang flow theo menu `content / taxonomy`: màn `list` có grouping + search/filter, click item mở `detail`, và từ `detail` mới đi tiếp sang `edit/delete`.
- Admin API không còn fail khi đọc `content-store.json` schema cũ; backend đã migrate legacy store vào model v2 trước khi validate.
- Còn lại 2 hạng mục admin chuyên sâu:
  - lane-specific form thay vì raw JSON scaffold
  - filter UI admin đầy đủ cho `language`, `topic`, `domain`, `tags`

## Test Plan
- Tạo exercise có 2 language variants (`C#`, `Python`) và verify user đổi ngôn ngữ được.
- Verify app nhớ language preference giữa các bài hỗ trợ cùng ngôn ngữ.
- Verify lane-specific validation:
  - LeetCode thiếu testcase bị chặn
  - Exercise không có variant bị chặn
  - Project track thiếu refs bị chặn
- Verify filter đúng theo:
  - lane
  - level
  - language
  - topic
  - domain
  - tags
- Verify một exercise:
  - đứng độc lập
  - thuộc nhiều tracks
  - mang nhiều tags/topic/domain
- Verify review queue vẫn đúng khi completion/failure đến từ exercise variant đã chọn.
- Verify reseed v2 sinh đủ demo content và không còn admin trống.

## Assumptions
- `Level` v1 chỉ dùng `foundation | intermediate | advanced`.
- `Topic` và `Domain` là curated multi-select; `tags` là free-form multi-select.
- `Skills` vẫn là taxonomy riêng cho review memory.
- `Track` và `Exercise` cùng tồn tại lâu dài.
- Migration strategy là **schema v2 + reseed**, không giữ backward compatibility đầy đủ cho JSON catalog cũ.
- Tên file plan cần tạo khi chuyển sang execution mode là `plan-content-library-v2-multilanguage.md`.
