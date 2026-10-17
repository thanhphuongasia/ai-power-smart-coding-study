# Stock Trading News Alert (Section 36)

## 🎯 Requirements

Auto-monitor giá cổ phiếu Tesla (TSLA), nếu thay đổi >5% thì gửi SMS với top 3 tin tức.

1. Lấy giá TSLA hôm nay và hôm qua từ **Alpha Vantage API**
2. Tính % thay đổi
3. Nếu thay đổi > 5% → fetch top 3 bài báo từ **News API**
4. Gửi SMS cho mỗi bài báo qua **Twilio** với format:

```text
TSLA: 🔺2%
Headline: Tesla hits record high
Brief: The EV maker...
```

## 🔑 APIs cần dùng

| API | Mục đích | Free tier |
| --- | --- | --- |
| Alpha Vantage | Giá cổ phiếu theo ngày | 25 req/day |
| NewsAPI | Tin tức theo keyword | 100 req/day |
| Twilio | Gửi SMS | trial $15 |

## 🔍 Code Breakdown

### Bước 1: Lấy giá cổ phiếu

```python
import requests
from datetime import datetime

STOCK = "TSLA"
COMPANY_NAME = "Tesla Inc"
STOCK_API_KEY = "YOUR_ALPHA_VANTAGE_KEY"

stock_params = {
    "function": "TIME_SERIES_DAILY",
    "symbol": STOCK,
    "apikey": STOCK_API_KEY,
}

response = requests.get(
    "https://www.alphavantage.co/query",
    params=stock_params
)
response.raise_for_status()
data = response.json()

# Data structure từ API:
# {
#   "Time Series (Daily)": {
#     "2026-10-14": {"1. open": "250.5", "4. close": "255.3", ...},
#     "2026-10-13": {"1. open": "248.2", "4. close": "249.8", ...},
#   }
# }

time_series = data["Time Series (Daily)"]

# Lấy list ngày, sort giảm dần (ngày mới nhất trước)
data_list = [value for (key, value) in time_series.items()]
# → list of dicts, index 0 = hôm nay, index 1 = hôm qua

yesterday_data = data_list[0]
yesterday_closing = float(yesterday_data["4. close"])

day_before_yesterday_data = data_list[1]
day_before_closing = float(day_before_yesterday_data["4. close"])
```

Giải thích `[value for (key, value) in time_series.items()]`:

```python
# time_series.items() → [(date_str, price_dict), ...]
# (key, value) → unpack tuple
# Lấy value (dict giá) cho từng ngày
# → list các dicts giá theo thứ tự ngày mới → cũ
```

### Bước 2: Tính % thay đổi

```python
# Tính phần trăm thay đổi
difference = yesterday_closing - day_before_closing
up_down = "🔺" if difference > 0 else "🔻"

change_percent = round((difference / day_before_closing) * 100)

print(f"{STOCK}: {up_down}{abs(change_percent)}%")
```

Công thức:

```text
% thay đổi = (giá hôm nay - giá hôm qua) / giá hôm qua × 100
```

### Bước 3: Fetch tin tức nếu thay đổi lớn

```python
NEWS_API_KEY = "YOUR_NEWS_API_KEY"

# Chỉ fetch news nếu thay đổi >= 5%
if abs(change_percent) >= 5:
    news_params = {
        "apiKey": NEWS_API_KEY,
        "qInTitle": COMPANY_NAME,   # keyword trong title bài báo
        "language": "en",
    }

    news_response = requests.get(
        "https://newsapi.org/v2/everything",
        params=news_params
    )
    articles = news_response.json()["articles"]

    # Lấy 3 bài đầu tiên
    top_3_articles = articles[:3]
    # [:3] = slice — lấy index 0, 1, 2 (không bao gồm 3)
```

Giải thích slice `[:3]`:

```python
my_list = [a, b, c, d, e]
my_list[:3]  # → [a, b, c]  từ đầu đến index 3 (không bao gồm)
my_list[1:3] # → [b, c]     từ index 1 đến 3
my_list[-1]  # → e          phần tử cuối cùng
```

### Bước 4: Gửi SMS qua Twilio

```python
from twilio.rest import Client

TWILIO_SID = "YOUR_SID"
TWILIO_AUTH_TOKEN = "YOUR_AUTH_TOKEN"
TWILIO_NUMBER = "+15017122661"
MY_PHONE = "+84xxxxxxxxx"

client = Client(TWILIO_SID, TWILIO_AUTH_TOKEN)

# Format và gửi từng bài báo
formatted_articles = [
    f"{STOCK}: {up_down}{abs(change_percent)}%\n"
    f"Headline: {article['title']}\n"
    f"Brief: {article['description']}"
    for article in top_3_articles
]

for article in formatted_articles:
    message = client.messages.create(
        body=article,
        from_=TWILIO_NUMBER,
        to=MY_PHONE
    )
    print(message.status)
```

Concept: `client.messages.create()` gọi Twilio API → gửi SMS. `from_` dùng underscore vì `from` là **keyword** của Python.

### Environment Variables (QUAN TRỌNG)

> Không bao giờ hardcode API key vào code!

```python
import os

# Đọc từ environment variable
STOCK_API_KEY = os.environ.get("ALPHA_VANTAGE_KEY")
NEWS_API_KEY = os.environ.get("NEWS_API_KEY")

# Trên terminal:
# export ALPHA_VANTAGE_KEY="your_actual_key"
# export NEWS_API_KEY="your_actual_key"

# Hoặc dùng python-dotenv:
from dotenv import load_dotenv
load_dotenv()   # đọc file .env
```

## 🗂️ Flow Diagram

```text
Alpha Vantage API
       │
       ▼ GET /query?function=TIME_SERIES_DAILY&symbol=TSLA
  JSON: {Time Series (Daily): {date: {close: ...}}}
       │
       ▼ Tính % thay đổi
  |change| >= 5%?
       │ YES
       ▼
  News API
       │
       ▼ GET /v2/everything?qInTitle=Tesla
  articles[:3]
       │
       ▼
  Twilio Client
       │
       ▼ POST SMS → điện thoại
```

## 🧠 Concepts trong Section 36

| Concept | Giải thích |
| --- | --- |
| `params=dict` | Query string trong URL: `?key=val&key2=val2` |
| `response.raise_for_status()` | Raise exception nếu HTTP error (4xx, 5xx) |
| `response.json()` | Parse JSON → Python dict/list |
| Slice `[:3]` | Lấy n phần tử đầu của list |
| `abs()` | Giá trị tuyệt đối (bỏ dấu âm) |
| `dict.items()` | Iterate key-value pairs của dict |
| List comprehension | `[expr for item in list if condition]` |
| Environment variables | Bảo mật API key — không commit lên Git |
| f-string multiline | `f"...\n..."` — xuống dòng trong string |
| Twilio SDK | `pip install twilio` — gửi SMS qua API |

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

- Prerequisite: Section 34 (API basics), Section 35 (Auth & keys)
- Twilio docs: twilio.com/docs/sms
- Alpha Vantage docs: alphavantage.co/documentation
