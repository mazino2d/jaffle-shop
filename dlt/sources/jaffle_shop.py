"""
Jaffle Shop dlt source.

Simulates backend data using Faker. Tables are split into two categories:
- SCD tables (customers, orders, products): use write_disposition='replace'
  because records can be updated in-place on the backend.
- Log tables (payments, order_items): use write_disposition='append'
  because they are immutable event logs.
"""

import random
from datetime import datetime, timedelta

import dlt
from faker import Faker

fake = Faker()
Faker.seed(42)
random.seed(42)

CUSTOMER_COUNT = 200
PRODUCT_COUNT = 30
ORDER_COUNT = 800

# Use a fixed "now" so a single pipeline run is internally consistent.
_NOW = datetime.now()
_ONE_YEAR_AGO = _NOW - timedelta(days=365)
_SIX_MONTHS_AGO = _NOW - timedelta(days=180)
_ONE_MONTH_AGO = _NOW - timedelta(days=30)


def _random_date(start: datetime, end: datetime) -> datetime:
    delta = end - start
    return start + timedelta(seconds=random.randint(0, int(delta.total_seconds())))


@dlt.resource(name="customers", write_disposition="replace", primary_key="id")
def customers():
    """Customer master data — updated in-place on the backend (SCD source)."""
    statuses = ["active", "churned", "at_risk"]
    for i in range(1, CUSTOMER_COUNT + 1):
        created = _random_date(_ONE_YEAR_AGO, _SIX_MONTHS_AGO)
        yield {
            "id": i,
            "name": fake.name(),
            "email": fake.email(),
            "country": fake.country_code(),
            "status": random.choices(statuses, weights=[70, 15, 15])[0],
            "created_at": created.isoformat(),
            "updated_at": _random_date(_ONE_MONTH_AGO, _NOW).isoformat(),
        }


@dlt.resource(name="products", write_disposition="replace", primary_key="id")
def products():
    """Product catalog — prices and names can change (SCD source)."""
    categories = ["Food", "Beverage", "Merchandise"]
    for i in range(1, PRODUCT_COUNT + 1):
        created = _random_date(_ONE_YEAR_AGO, _SIX_MONTHS_AGO)
        yield {
            "id": i,
            "name": fake.bs().title()[:40],
            "category": random.choice(categories),
            "price": round(random.uniform(3.0, 25.0), 2),
            "is_active": random.random() > 0.1,
            "created_at": created.isoformat(),
            "updated_at": _random_date(_ONE_MONTH_AGO, _NOW).isoformat(),
        }


@dlt.resource(name="orders", write_disposition="replace", primary_key="id")
def orders():
    """Order records — status transitions over time (SCD source)."""
    statuses = ["placed", "shipped", "completed", "returned"]
    _ONE_WEEK_AGO = _NOW - timedelta(days=7)
    for i in range(1, ORDER_COUNT + 1):
        placed_at = _random_date(_ONE_YEAR_AGO, _NOW)
        # Recent orders (placed in the last 7 days) may still be in-flight;
        # older orders were resolved within 14 days of placement.
        if placed_at >= _ONE_WEEK_AGO:
            updated_at = _random_date(placed_at, _NOW)
        else:
            updated_at = placed_at + timedelta(days=random.randint(0, 14))
        yield {
            "id": i,
            "customer_id": random.randint(1, CUSTOMER_COUNT),
            "status": random.choices(statuses, weights=[5, 10, 75, 10])[0],
            "amount": round(random.uniform(10.0, 200.0), 2),
            "placed_at": placed_at.isoformat(),
            "updated_at": updated_at.isoformat(),
        }


@dlt.resource(name="payments", write_disposition="append", primary_key="id")
def payments():
    """Payment events — immutable log, append-only."""
    methods = ["credit_card", "debit_card", "bank_transfer", "gift_card"]
    statuses = ["success", "failed", "refunded"]
    for i in range(1, ORDER_COUNT + 1):
        n_payments = random.randint(1, 2)
        for j in range(n_payments):
            yield {
                "id": (i - 1) * 2 + j + 1,
                "order_id": i,
                "method": random.choice(methods),
                "status": random.choices(statuses, weights=[85, 10, 5])[0],
                "amount": round(random.uniform(5.0, 120.0), 2),
                "created_at": _random_date(_ONE_MONTH_AGO, _NOW).isoformat(),
            }


@dlt.resource(name="order_items", write_disposition="append", primary_key="id")
def order_items():
    """Line items per order — immutable log, append-only."""
    item_id = 1
    for order_id in range(1, ORDER_COUNT + 1):
        for _ in range(random.randint(1, 5)):
            yield {
                "id": item_id,
                "order_id": order_id,
                "product_id": random.randint(1, PRODUCT_COUNT),
                "quantity": random.randint(1, 4),
                "unit_price": round(random.uniform(3.0, 25.0), 2),
                "created_at": _random_date(_ONE_MONTH_AGO, _NOW).isoformat(),
            }
            item_id += 1


@dlt.source
def jaffle_shop():
    """All Jaffle Shop tables as a single dlt source."""
    return [customers(), products(), orders(), payments(), order_items()]
