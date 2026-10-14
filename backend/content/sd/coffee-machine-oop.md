# OOP: Coffee Machine (100 Days of Python — Section 16)

## 🎯 Mục tiêu / Requirements

Remake lại Coffee Machine từ Day 15 nhưng dùng **OOP** thay vì code procedural.

### Chương trình phải làm được

1. In report tất cả resources hiện có (water, milk, coffee, money)
2. Kiểm tra resources có đủ không trước khi làm
3. Xử lý nhận tiền coin từ user
4. Kiểm tra transaction thành công không (đủ tiền?)
5. Pha cà phê và trừ nguyên liệu

## 📦 Phân tích Class (Class Analysis)

### 4 class được cung cấp sẵn

Treat như external library — không cần sửa.

| Class | Vai trò |
| --- | --- |
| `MenuItem` | Blueprint cho 1 loại đồ uống |
| `Menu` | Danh sách tất cả đồ uống |
| `CoffeeMaker` | Máy pha cà phê — quản lý nguyên liệu |
| `MoneyMachine` | Quản lý tiền xu |

## 🔍 Chi tiết từng Class & Method

### MenuItem

```python
class MenuItem:
    def __init__(self, name, water, milk, coffee, cost):
        self.name = name          # tên đồ uống, ví dụ "latte"
        self.cost = cost          # giá tiền (float)
        self.ingredients = {
            "water": water,
            "milk": milk,
            "coffee": coffee
        }
```

Concept: `self` là instance của object. `ingredients` là **dictionary** lưu key-value.

### Menu

```python
class Menu:
    def __init__(self):
        self.menu = [
            MenuItem("latte", 200, 150, 24, 2.5),
            MenuItem("espresso", 50, 0, 18, 1.5),
            MenuItem("cappuccino", 250, 100, 24, 3.0),
        ]

    def get_items(self):
        """Trả về string tên tất cả đồ uống"""
        options = ""
        for item in self.menu:
            options += f"{item.name}/"
        return options

    def find_drink(self, order_name):
        """Tìm MenuItem theo tên, trả về None nếu không có"""
        for item in self.menu:
            if item.name == order_name:
                return item
        return None
```

Concept: `self.menu` là **List** chứa các `MenuItem` objects. Dùng **for loop** để iterate.

### CoffeeMaker

```python
class CoffeeMaker:
    def __init__(self):
        self.resources = {
            "water": 300,
            "milk": 200,
            "coffee": 100,
        }

    def print_report(self):
        """In report resources"""
        print(f"Water: {self.resources['water']}ml")
        print(f"Milk: {self.resources['milk']}ml")
        print(f"Coffee: {self.resources['coffee']}g")

    def is_resource_sufficient(self, drink):
        """Kiểm tra đủ nguyên liệu không — trả về True/False"""
        can_make = True
        for item in drink.ingredients:
            if drink.ingredients[item] > self.resources[item]:
                print(f"Sorry there is not enough {item}.")
                can_make = False
        return can_make

    def make_coffee(self, order, payment):
        """Trừ nguyên liệu và trả lại tiền thừa"""
        for item in order.ingredients:
            self.resources[item] -= order.ingredients[item]
        print(f"Here is your {order.name} ☕️. Enjoy!")
```

Concept quan trọng: `is_resource_sufficient` nhận `drink` (một `MenuItem` object) làm **argument** — đây là **dependency injection**.

### MoneyMachine

```python
class MoneyMachine:
    CURRENCY = "$"
    COIN_VALUES = {
        "quarters": 0.25,
        "dimes": 0.10,
        "nickels": 0.05,
        "pennies": 0.01
    }

    def __init__(self):
        self.profit = 0
        self.money_received = 0

    def report(self):
        print(f"Money: {self.CURRENCY}{self.profit}")

    def process_coins(self):
        """Hỏi user số lượng từng loại coin"""
        print("Please insert coins.")
        for coin in self.COIN_VALUES:
            self.money_received += int(input(f"How many {coin}?: ")) * self.COIN_VALUES[coin]
        return self.money_received

    def make_payment(self, cost):
        """Kiểm tra đủ tiền, trả về True/False"""
        if self.money_received >= cost:
            change = round(self.money_received - cost, 2)
            print(f"Here is {self.CURRENCY}{change} in change.")
            self.profit += cost
            self.money_received = 0
            return True
        else:
            print("Sorry that's not enough money. Money refunded.")
            self.money_received = 0
            return False
```

Concept: `CURRENCY` và `COIN_VALUES` là **class variable** (dùng chung cho tất cả instances, không phải riêng từng object).

## 🗂️ Class Diagram

```text
┌─────────────────┐     ┌─────────────────────┐
│   MenuItem      │◄────│       Menu          │
├─────────────────┤     ├─────────────────────┤
│ + name: str     │     │ - menu: List        │
│ + cost: float   │     ├─────────────────────┤
│ + ingredients: dict│  │ + get_items(): str  │
└─────────────────┘     │ + find_drink(): obj │
                        └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐
│    CoffeeMaker      │  │    MoneyMachine      │
├─────────────────────┤  ├─────────────────────┤
│ - resources: dict   │  │ - profit: float      │
├─────────────────────┤  │ - money_received:float│
│ + print_report()    │  ├─────────────────────┤
│ + is_resource_      │  │ + report()           │
│   sufficient(drink) │  │ + process_coins()    │
│ + make_coffee(order,│  │ + make_payment(cost) │
│   payment)          │  └─────────────────────┘
└─────────────────────┘
```

## 💻 Code chính — main.py (từng bước)

### Bước 1: Import và khởi tạo objects

```python
from menu import Menu, MenuItem
from coffee_maker import CoffeeMaker
from money_machine import MoneyMachine

money_machine = MoneyMachine()   # tạo object từ class MoneyMachine
coffee_maker = CoffeeMaker()     # tạo object từ class CoffeeMaker
menu = Menu()                    # tạo object từ class Menu
```

`MoneyMachine()` gọi `__init__` → tạo instance với profit=0, money_received=0.

### Bước 2: Main loop

```python
is_on = True

while is_on:
    # Hiện menu, hỏi user muốn gì
    options = menu.get_items()         # "latte/espresso/cappuccino/"
    choice = input(f"What would you like? ({options}): ")

    if choice == "off":
        is_on = False
    elif choice == "report":
        coffee_maker.print_report()    # in water, milk, coffee còn lại
        money_machine.report()         # in tiền lãi
    else:
        drink = menu.find_drink(choice)  # trả về MenuItem object hoặc None
```

Concept: `while True` loop giữ machine chạy liên tục cho đến khi gõ "off".

### Bước 3: Kiểm tra và pha cà phê

```python
        if drink:
            # Kiểm tra nguyên liệu
            if coffee_maker.is_resource_sufficient(drink):
                # Nhận tiền
                payment = money_machine.process_coins()
                # Kiểm tra đủ tiền
                if money_machine.make_payment(drink.cost):
                    # Pha cà phê
                    coffee_maker.make_coffee(drink, payment)
```

Concept: **Encapsulation** — mỗi class tự quản lý data của mình. `main.py` chỉ gọi methods, không cần biết bên trong làm gì.

## 🧠 Concepts cần hiểu trong section này

| Concept | Ý nghĩa |
| --- | --- |
| Class | Blueprint/khuôn mẫu để tạo objects |
| Object/Instance | Vật thể cụ thể tạo ra từ class |
| `__init__` | Constructor — chạy khi tạo object |
| `self` | Reference đến chính instance đó |
| Method | Function bên trong class |
| Attribute | Variable bên trong class (data của object) |
| Class variable | Dùng chung cho tất cả instances (CURRENCY, COIN_VALUES) |
| Instance variable | Riêng từng object (self.profit) |
| Encapsulation | Object tự quản lý data và method của mình |
| Dictionary | `{"key": value}` — dùng nhiều để lưu ingredients, resources |

## 🔗 Liên quan

- Prerequisite: Day 15 (Coffee Machine procedural version)
- Next: Day 17 (Quiz App — OOP tiếp tục)
