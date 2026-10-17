# Habit Tracker: Pixela API (Section 37)

## 🎯 Requirements

Build habit tracker dùng Pixela (pixe.la) — visualize daily activity (giống GitHub contribution graph).

1. Tạo user account trên Pixela
2. Tạo graph (habit)
3. POST pixel — log hoạt động hôm nay (số phút tập gym)
4. PUT pixel — update số phút nếu nhập sai
5. DELETE pixel — xóa record của ngày nào đó

## 🎯 Học gì ở đây?

Section này focus vào **HTTP Methods** — khác với các section trước chỉ dùng GET.

| Method | Mục đích | Tương đương |
| --- | --- | --- |
| GET | Lấy dữ liệu | Read |
| POST | Tạo mới | Create |
| PUT | Cập nhật | Update |
| DELETE | Xóa | Delete |

→ Đây là nền tảng của **REST API** — sẽ dùng nhiều khi làm backend.

## 🔍 Code Breakdown

### Cấu hình ban đầu

```python
import requests
from datetime import datetime

USERNAME = "phuongtt"              # tên user trên Pixela
TOKEN = "your_secret_token"        # password/token tự đặt
GRAPH_ID = "graph1"

pixela_endpoint = "https://pixe.la/v1/users"
```

### Bước 1: Tạo User (POST — chỉ chạy 1 lần)

```python
user_params = {
    "token": TOKEN,
    "username": USERNAME,
    "agreeTermsOfService": "yes",
    "notMinor": "yes",
}

response = requests.post(pixela_endpoint, json=user_params)
#                                          ↑ gửi JSON body (không phải params)
print(response.text)
```

GET vs POST:

```python
# GET — params đi vào URL
requests.get(url, params={"key": "val"})
# → url?key=val

# POST — data đi vào body (ẩn, an toàn hơn)
requests.post(url, json={"key": "val"})
# → body: {"key": "val"}
```

### Bước 2: Tạo Graph (POST)

```python
graph_endpoint = f"{pixela_endpoint}/{USERNAME}/graphs"

graph_config = {
    "id": GRAPH_ID,
    "name": "Cycling Graph",
    "unit": "Km",
    "type": "float",
    "color": "momiji",   # màu của pixel: shibafu/momiji/sora/ichou/ajisai/kuro
}

# Pixela dùng "X-USER-TOKEN" header để auth, không dùng params
headers = {
    "X-USER-TOKEN": TOKEN
}

response = requests.post(
    graph_endpoint,
    json=graph_config,
    headers=headers
)
print(response.text)

# Xem graph tại:
# https://pixe.la/v1/users/{USERNAME}/graphs/{GRAPH_ID}.html
```

Concept Headers:

```text
Headers = metadata đi kèm HTTP request
Dùng để: Authentication, Content-Type, Accept, ...

Ví dụ:
headers = {
    "X-USER-TOKEN": "mysecrettoken",   # Pixela auth
    "Content-Type": "application/json",
    "Authorization": "Bearer eyJ..."   # JWT auth
}
```

### Bước 3: POST pixel — Log hôm nay

```python
pixel_creation_endpoint = f"{pixela_endpoint}/{USERNAME}/graphs/{GRAPH_ID}"

today = datetime.now()
pixel_data = {
    "date": today.strftime("%Y%m%d"),  # "20261014" — format Pixela yêu cầu
    "quantity": input("How many kilometers did you cycle today? "),
}

response = requests.post(
    pixel_creation_endpoint,
    json=pixel_data,
    headers=headers
)
print(response.text)
```

`strftime` — format ngày giờ:

```python
today = datetime.now()
# datetime(2026, 10, 14, 15, 30, 0)

today.strftime("%Y%m%d")   # → "20261014"
today.strftime("%d/%m/%Y") # → "14/10/2026"
today.strftime("%Y-%m-%d") # → "2026-10-14"

# %Y = year 4 chữ số
# %m = month 2 chữ số (01-12)
# %d = day 2 chữ số (01-31)
```

### Bước 4: PUT pixel — Update

```python
update_endpoint = f"{pixela_endpoint}/{USERNAME}/graphs/{GRAPH_ID}/20261013"
#                                                                  ↑ ngày cụ thể

new_pixel_data = {
    "quantity": "4.5"
}

response = requests.put(
    update_endpoint,
    json=new_pixel_data,
    headers=headers
)
print(response.text)
```

→ **PUT** endpoint = URL + `/date` — chỉ định cụ thể resource muốn update.

### Bước 5: DELETE pixel — Xóa

```python
delete_endpoint = f"{pixela_endpoint}/{USERNAME}/graphs/{GRAPH_ID}/20261013"

response = requests.delete(delete_endpoint, headers=headers)
print(response.text)
```

→ **DELETE** không cần body. Chỉ cần URL + headers auth.

## 🗂️ REST API Summary — CRUD

```text
Resource: /users/{username}/graphs/{graph_id}/{date}

POST   /users                        → Create user
POST   /users/{u}/graphs             → Create graph
POST   /users/{u}/graphs/{g}         → Create pixel (log today)
PUT    /users/{u}/graphs/{g}/{date}  → Update pixel
DELETE /users/{u}/graphs/{g}/{date}  → Delete pixel
GET    /users/{u}/graphs/{g}.html    → View graph
```

## 🧠 Concepts trong Section 37

| Concept | Giải thích |
| --- | --- |
| HTTP Methods | GET/POST/PUT/DELETE — bộ 4 của REST API |
| `requests.post()` | Gửi POST request với JSON body |
| `requests.put()` | Update resource |
| `requests.delete()` | Xóa resource |
| `json=dict` | Serialize Python dict → JSON, tự set Content-Type header |
| `headers=dict` | Metadata đi kèm request (auth, content-type) |
| `strftime(format)` | Format datetime → string theo pattern |
| `datetime.now()` | Lấy ngày giờ hiện tại |
| f-string URL | Build URL động: `f"{base}/{username}/graphs"` |
| REST | Representational State Transfer — kiến trúc API dùng HTTP methods |

### So sánh params vs json vs data

```python
# params → query string trong URL (GET)
requests.get(url, params={"page": 1})
# → url?page=1

# json → JSON body (POST/PUT) — tự set Content-Type: application/json
requests.post(url, json={"name": "test"})

# data → form data body (HTML form submit)
requests.post(url, data={"name": "test"})
# Content-Type: application/x-www-form-urlencoded
```

## 🔗 Liên quan

- Prerequisite: Section 34-36 (API & requests)
- Pixela API docs: docs.pixe.la
- Sau khi học xong: Section 57-60 (Flask — tự xây REST API)
