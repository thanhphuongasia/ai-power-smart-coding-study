# Flashcard App: Tkinter + Pandas (Section 31)

## 🎯 Requirements

Xây dựng Flashcard app học tiếng Pháp dùng Tkinter GUI + pandas đọc CSV.

1. Hiện mặt trước card: từ **tiếng Pháp** (nền xanh dương)
2. Sau 3 giây tự động lật sang mặt sau: từ **tiếng Anh** (nền xanh lá)
3. User nhấn ✓ (biết rồi) → bỏ từ đó khỏi danh sách học
4. User nhấn ✗ (chưa biết) → giữ lại, chuyển sang từ tiếp theo
5. Lưu danh sách từ chưa học vào CSV để lần sau học tiếp

## 📦 Cấu trúc File

```text
flashcard-app/
├── main.py              # logic + UI
├── data/
│   ├── french_words.csv # 200 từ gốc (French, English)
│   └── words_to_learn.csv  # tự tạo — từ còn lại chưa thuộc
└── images/
    ├── card_front.png   # ảnh mặt trước (xanh dương)
    ├── card_back.png    # ảnh mặt sau (xanh lá)
    ├── right.png        # button ✓
    └── wrong.png        # button ✗
```

## 🔍 Code Breakdown — main.py

### Import và Load Data

```python
import pandas as pd
import random
from tkinter import *

# Load dữ liệu
try:
    # Nếu đã có file progress → load từ đó
    data = pd.read_csv("data/words_to_learn.csv")
except FileNotFoundError:
    # Lần đầu chạy → load từ file gốc
    original_data = pd.read_csv("data/french_words.csv")
    to_learn = original_data.to_dict(orient="records")
else:
    # Nếu try thành công
    to_learn = data.to_dict(orient="records")
```

Giải thích `try/except/else`:

```text
try:    → thử đọc words_to_learn.csv
except: → nếu file chưa có (FileNotFoundError) → đọc file gốc
else:   → nếu try THÀNH CÔNG → chạy khối else
```

`to_dict(orient="records")`:

```python
# CSV:
# French,English
# parti,gone
# affaire,matter

# → Python list of dicts:
# [{"French": "parti", "English": "gone"},
#  {"French": "affaire", "English": "matter"}]
```

### Random Card & Flip Logic

```python
current_card = {}   # dict lưu từ đang hiển thị
flip_timer = None   # reference đến timer đang chạy

def next_card():
    global current_card, flip_timer

    # Hủy timer cũ nếu còn đang chạy
    if flip_timer is not None:
        window.after_cancel(flip_timer)

    # Chọn ngẫu nhiên 1 từ
    current_card = random.choice(to_learn)

    # Update UI — mặt trước
    canvas.itemconfig(card_background, image=card_front_img)
    canvas.itemconfig(card_title, text="French", fill="black")
    canvas.itemconfig(card_word, text=current_card["French"], fill="black")

    # Đặt timer 3 giây → flip
    flip_timer = window.after(3000, flip_card)
    #                  ↑ 3000ms = 3 giây
```

`window.after(ms, function)`:

```text
Sau ms milliseconds → gọi function()
Không block UI (non-blocking) — khác với time.sleep()
Trả về timer ID để có thể cancel
```

```python
def flip_card():
    # Update UI — mặt sau (show tiếng Anh)
    canvas.itemconfig(card_background, image=card_back_img)
    canvas.itemconfig(card_title, text="English", fill="white")
    canvas.itemconfig(card_word, text=current_card["English"], fill="white")
```

### Save Progress — Known Word

```python
def is_known():
    """User biết từ này → xóa khỏi to_learn → save → next card"""
    to_learn.remove(current_card)

    # Save progress ra CSV
    data = pd.DataFrame(to_learn)
    data.to_csv("data/words_to_learn.csv", index=False)
    #                                       ↑ không ghi số thứ tự hàng

    next_card()
```

Flow dữ liệu:

```text
to_learn (Python list of dicts)
    → pd.DataFrame(to_learn)  [convert sang DataFrame]
    → .to_csv("file.csv")     [ghi ra file]
```

### Tkinter UI Setup

```python
window = Tk()
window.title("Flashy")
window.config(padx=50, pady=50, bg=BACKGROUND_COLOR)

# Canvas — vẽ card
canvas = Canvas(width=800, height=526, bg=BACKGROUND_COLOR, highlightthickness=0)
card_front_img = PhotoImage(file="images/card_front.png")
card_back_img = PhotoImage(file="images/card_back.png")
card_background = canvas.create_image(400, 263, image=card_front_img)
card_title = canvas.create_text(400, 150, text="Title", font=("Ariel", 40, "italic"))
card_word = canvas.create_text(400, 263, text="Word", font=("Ariel", 60, "bold"))
canvas.grid(row=0, column=0, columnspan=2)

# Buttons
cross_image = PhotoImage(file="images/wrong.png")
unknown_button = Button(image=cross_image, highlightthickness=0, command=next_card)
unknown_button.grid(row=1, column=0)

check_image = PhotoImage(file="images/right.png")
known_button = Button(image=check_image, highlightthickness=0, command=is_known)
known_button.grid(row=1, column=1)

# Khởi động
next_card()
window.mainloop()  # giữ cửa sổ mở, chờ events
```

## 🗂️ Data Flow Diagram

```text
french_words.csv
      │
      ▼ pd.read_csv()
  DataFrame
      │
      ▼ .to_dict(orient="records")
  to_learn [list of dicts]
      │
      ▼ random.choice()
  current_card {dict}
      │
      ├─► Canvas UI (French side)
      │
      ▼ after(3000, flip_card)
  flip_card()
      │
      ▼
  Canvas UI (English side)
      │
  [User clicks ✓]
      │
      ▼ is_known()
  to_learn.remove() → pd.DataFrame → .to_csv()
```

## 🧠 Concepts cần hiểu

| Concept | Giải thích |
| --- | --- |
| Tkinter | Built-in Python GUI library |
| Canvas | Widget vẽ hình, text, image |
| `canvas.itemconfig()` | Thay đổi property của item đã tạo |
| `window.after(ms, fn)` | Schedule function sau n milliseconds |
| `after_cancel(id)` | Hủy timer đang chờ |
| pandas DataFrame | Bảng dữ liệu 2D — rows & columns |
| `pd.read_csv()` | Đọc file CSV thành DataFrame |
| `to_dict(orient="records")` | DataFrame → list of dicts |
| `pd.DataFrame(list)` | list of dicts → DataFrame |
| `to_csv(index=False)` | Ghi DataFrame ra CSV |
| `try/except/else` | Error handling — except khi có lỗi, else khi không có lỗi |
| `global` | Cho phép sửa variable bên ngoài function |

### Tkinter Grid Layout

```text
column=0    column=1
[canvas] [canvas]    ← row=0, columnspan=2
[✗ btn] [✓ btn]      ← row=1
```

## 🔗 Liên quan

- Prerequisite: Section 18-20 (Tkinter cơ bản)
- pandas: `pip install pandas`
- CSV data: github.com/appbrewery/100-days-of-code-Python (resources)
