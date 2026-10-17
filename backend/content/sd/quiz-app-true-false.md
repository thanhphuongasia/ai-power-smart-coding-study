# Quiz App: True/False Questions (Section 17)

## 🎯 Requirements

Xây dựng Quiz App hỏi 10 câu hỏi True/False, track score, dùng OOP.

1. Fetch câu hỏi từ Open Trivia Database API (opentdb.com)
2. Hỏi user từng câu một (True/False)
3. Check answer đúng/sai, báo kết quả ngay
4. Hiển thị score hiện tại sau mỗi câu
5. Kết thúc khi hết câu hỏi

## 📦 Phân tích Class

| File | Class | Vai trò |
| --- | --- | --- |
| `data.py` | — | Fetch câu hỏi từ API, lưu vào list |
| `question_model.py` | `Question` | Blueprint cho 1 câu hỏi |
| `quiz_brain.py` | `QuizBrain` | Logic điều khiển quiz |
| `main.py` | — | Entry point, kết nối tất cả |

## 🔍 Chi tiết từng Class

### Question — question_model.py

```python
class Question:
    def __init__(self, q_text, q_answer):
        self.text = q_text      # nội dung câu hỏi (string)
        self.answer = q_answer  # đáp án đúng: "True" hoặc "False"
```

Class đơn giản nhất, chỉ lưu data. Không có method phức tạp.

### QuizBrain — quiz_brain.py

```python
class QuizBrain:
    def __init__(self, q_list):
        self.question_number = 0        # đang ở câu số mấy
        self.score = 0                  # điểm hiện tại
        self.question_list = q_list     # list Question objects

    def still_has_questions(self):
        """Còn câu hỏi không? — dùng làm điều kiện while loop"""
        return self.question_number < len(self.question_list)

    def next_question(self):
        """Lấy câu tiếp theo, hỏi user, check answer"""
        current_question = self.question_list[self.question_number]
        self.question_number += 1
        user_answer = input(
            f"Q.{self.question_number}: {current_question.text} (True/False)?: "
        )
        self.check_answer(user_answer, current_question.answer)

    def check_answer(self, user_answer, correct_answer):
        """So sánh answer, update score"""
        if user_answer.lower() == correct_answer.lower():
            self.score += 1
            print("You got it right!")
        else:
            print("That's wrong.")
        print(f"The correct answer was: {correct_answer}.")
        print(f"Your current score is: {self.score}/{self.question_number}\n")
```

Giải thích `still_has_questions` — tại sao dùng thế này:

```python
return self.question_number < len(self.question_list)
# self.question_number bắt đầu từ 0, tăng dần
# len(self.question_list) = 10 (số câu hỏi)
# Khi đã hỏi 10 câu: 10 < 10 = False → dừng
```

Giải thích `next_question` — indexing list:

```python
current_question = self.question_list[self.question_number]
# Lấy phần tử thứ question_number trong list
# question_list[0] = câu đầu tiên
# Sau đó tăng question_number TRƯỚC khi hỏi
# → khi hỏi câu 0, hiển thị "Q.1" (user-friendly)
```

### data.py — Fetch từ API

```python
import requests

parameters = {
    "amount": 10,           # lấy 10 câu hỏi
    "type": "boolean",      # True/False
}

response = requests.get("https://opentdb.com/api.php", params=parameters)
response.raise_for_status()  # raise exception nếu status != 200

data = response.json()
question_data = data["results"]
# question_data là list of dict, mỗi dict có:
# {"question": "...", "correct_answer": "True", "difficulty": "easy", ...}
```

Concept: `response.json()` parse JSON string → Python dictionary. `["results"]` lấy value của key "results".

### main.py — Kết nối tất cả

```python
from question_model import Question
from data import question_data
from quiz_brain import QuizBrain

# Tạo list Question objects từ raw data API
question_bank = []
for question in question_data:
    question_text = question["question"]
    question_answer = question["correct_answer"]
    new_question = Question(question_text, question_answer)
    question_bank.append(new_question)

# Tạo QuizBrain object
quiz = QuizBrain(question_bank)

# Chạy quiz
while quiz.still_has_questions():
    quiz.next_question()

# Kết thúc
print("You've completed the quiz!")
print(f"Your final score was: {quiz.score}/{quiz.question_number}")
```

List Comprehension version (ngắn hơn):

```python
question_bank = [
    Question(q["question"], q["correct_answer"])
    for q in question_data
]
# Tương đương for loop phía trên nhưng Pythonic hơn
# Đọc: "Tạo Question(q...) for mỗi q trong question_data"
```

Concept: **List Comprehension** — cú pháp tạo list ngắn gọn trong Python.

## 🗂️ Class Diagram

```text
┌────────────────┐         ┌──────────────────────┐
│   Question     │◄────────│      QuizBrain        │
├────────────────┤  list   ├──────────────────────┤
│ + text: str    │         │ - question_number: int│
│ + answer: str  │         │ - score: int          │
└────────────────┘         │ - question_list: List │
                           ├──────────────────────┤
                           │ + still_has_questions()│
         API               │ + next_question()     │
    ┌──────────┐           │ + check_answer()      │
    │ OpenTrivia│──────────└──────────────────────┘
    │  API     │  JSON data
    └──────────┘

Flow: API → data.py → question_bank → QuizBrain → main.py
```

## 🧠 Concepts mới trong Section 17

| Concept | Giải thích |
| --- | --- |
| API Request | Gửi HTTP GET đến server, nhận JSON data về |
| `requests` library | `pip install requests` — thư viện gọi HTTP |
| `response.json()` | Parse JSON string → Python dict/list |
| `params=` | Thêm query parameters vào URL (`?amount=10&type=boolean`) |
| List Comprehension | `[expr for item in list]` — tạo list ngắn gọn |
| HTML Entities | API trả về entity thay vì ký tự thật — cần `html.unescape()` để fix |

### Fix HTML Entities

```python
import html

# API trả về: "According to &quot;Seinfeld&quot;..."
# Cần đổi thành: 'According to "Seinfeld"...'

question_text = html.unescape(question["question"])
```

## 🔗 Liên quan

- Prerequisite: Section 16 (OOP cơ bản)
- Next: Section 18 (Turtle / GUI)
- API docs: opentdb.com/api_config.php
