#!/usr/bin/env python
"""Synthetic EL loader for the dbt learning sandbox.

Simulates what an extract-load tool (Fivetran, Airbyte, ...) would do: land
raw, slightly messy source-system tables in the `raw` schema of the warehouse.
dbt takes it from there -- dbt never loads data, it only transforms what is
already in the warehouse (the "T" in ELT).

Design goals (they matter for the lessons, not just for tidiness):

* Deterministic: every attribute is a pure function of (entity id, day), via
  purpose-seeded RNGs. Day N produces identical business data no matter when
  or how often you run it. Only `_synced_at` is wall-clock, so that
  `dbt source freshness` stays a live, honest demo.
* Idempotent: loading a day twice deletes that day's rows first
  (DELETE WHERE _batch_day = N) and re-inserts them.
* Mutable history: each load also UPDATEs earlier rows -- orders advance along
  a predetermined lifecycle and some customers move to a new address. That is
  the raw material for incremental models and snapshots. Because mutations are
  a pure function of (id, current max day), the warehouse state after loading
  days 1..N is always the same.

Usage:
    python scripts/generate_data.py --days 2   # load days 1..2 (skips loaded)
    python scripts/generate_data.py --day 3    # (re)load exactly day 3
    python scripts/generate_data.py --reset    # drop + recreate empty schema
"""

from __future__ import annotations

import argparse
import os
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv
from faker import Faker

REPO_ROOT = Path(__file__).resolve().parents[1]

# Day 1 of business time. Keep in sync with the `training_start_date` var in
# jaffle_shop/dbt_project.yml, which feeds `begin` on the microbatch model
# (fct_events). Kept close to the present on purpose: microbatch models create
# one batch per day between `begin` and now, so a date far in the past would
# mean hundreds of empty batches on the first run.
BASE_DATE = datetime(2026, 7, 1)

COUNTRIES = ["US", "BR", "PT", "GB", "DE", "FR", "CA", "AU", "JP", "MX"]
PAYMENT_METHODS = ["credit_card", "debit_card", "pix", "bank_transfer", "gift_card"]
EVENT_TYPES = ["page_view", "search", "add_to_cart", "checkout"]
EVENT_WEIGHTS = [60, 15, 15, 10]
PRODUCT_CATEGORIES = ["beans", "brewing_gear", "mugs", "pastries", "merch"]
CATEGORY_NOUN = {
    "beans": "Roast Beans",
    "brewing_gear": "Brewer",
    "mugs": "Mug",
    "pastries": "Pastry Box",
    "merch": "Tote",
}
ADJECTIVES = ["Dark", "Golden", "Velvet", "Morning", "Midnight",
              "Rustic", "Bold", "Silky", "Cosmic", "Alpine"]

N_PRODUCTS = 30
N_CUSTOMERS_DAY1 = 200
N_CUSTOMERS_PER_DAY = 10
MOVE_PROBABILITY = 0.03  # chance a customer moves house on any given day

# Every order follows one predetermined lifecycle; loading day N reveals the
# state `age = N - order_day` steps along it (the last state repeats forever).
LIFECYCLES = [
    (60, ["placed", "shipped", "completed"]),
    (15, ["placed", "shipped", "shipped", "completed"]),   # slow carrier
    (10, ["placed", "placed", "shipped", "completed"]),    # slow warehouse
    (8,  ["placed", "shipped", "returned"]),
    (7,  ["placed", "cancelled"]),
]

TABLES = ["raw_customers", "raw_products", "raw_orders",
          "raw_order_items", "raw_payments", "raw_events"]

DDL = """
create schema if not exists raw;

create table if not exists raw.raw_customers (
    id           integer primary key,
    first_name   text,
    last_name    text,
    email        text,
    address      text,
    city         text,
    country_code text,
    created_at   timestamp,
    updated_at   timestamp,
    _synced_at   timestamptz not null,
    _batch_day   integer not null
);

create table if not exists raw.raw_products (
    id          integer primary key,
    name        text,
    category    text,
    price_cents integer,
    created_at  timestamp,
    _synced_at  timestamptz not null,
    _batch_day  integer not null
);

create table if not exists raw.raw_orders (
    id          integer primary key,
    customer_id integer,
    status      text,
    ordered_at  timestamp,
    updated_at  timestamp,
    _synced_at  timestamptz not null,
    _batch_day  integer not null
);

create table if not exists raw.raw_order_items (
    id               integer primary key,
    order_id         integer,
    product_id       integer,
    quantity         integer,
    unit_price_cents integer,
    _synced_at       timestamptz not null,
    _batch_day       integer not null
);

create table if not exists raw.raw_payments (
    id             integer primary key,
    order_id       integer,
    payment_method text,
    amount_cents   integer,
    paid_at        timestamp,
    _synced_at     timestamptz not null,
    _batch_day     integer not null
);

create table if not exists raw.raw_events (
    id          bigint primary key,
    customer_id integer,
    event_type  text,
    page        text,
    event_ts    timestamp,
    _synced_at  timestamptz not null,
    _batch_day  integer not null
);
"""


# --------------------------------------------------------------------------
# Pure attribute functions (no DB state, no global RNG state)
# --------------------------------------------------------------------------

def biz_ts(day: int, rng: random.Random) -> datetime:
    """A business-hours timestamp on the given day (day 1 == BASE_DATE)."""
    return BASE_DATE + timedelta(
        days=day - 1,
        hours=rng.randint(7, 21),
        minutes=rng.randint(0, 59),
        seconds=rng.randint(0, 59),
    )


def mangle_case(text: str, rng: random.Random) -> str:
    """Source systems are messy: sometimes SHOUTING, sometimes whispering."""
    roll = rng.random()
    if roll < 0.10:
        return text.upper()
    if roll < 0.20:
        return text.lower()
    return text


def product_attrs(pid: int) -> dict:
    rng = random.Random(f"prod-{pid}")
    category = rng.choice(PRODUCT_CATEGORIES)
    name = f"{rng.choice(ADJECTIVES)} {CATEGORY_NOUN[category]} No. {pid}"
    return {
        "name": name,
        "category": category,
        "price_cents": rng.randint(300, 15000),
        "created_at": biz_ts(1, rng),
    }


def customer_attrs(cid: int) -> dict:
    rng = random.Random(f"cust-{cid}")
    Faker.seed(f"cust-{cid}")
    fake = Faker()
    first, last = fake.first_name(), fake.last_name()
    email = f"{first}.{last}.{cid}@example.com".lower()
    return {
        "first_name": mangle_case(first, rng),
        "last_name": mangle_case(last, rng),
        "email": email.upper() if rng.random() < 0.10 else email,
        "country_code": rng.choice(COUNTRIES),
        "created_at": biz_ts(customer_first_day(cid), rng),
    }


def address_of(cid: int, move_day: int) -> tuple[str, str]:
    """Address + city after the customer's move on `move_day` (0 = original)."""
    Faker.seed(f"addr-{cid}-{move_day}")
    fake = Faker()
    return fake.street_address(), fake.city()


def order_state(oid: int, age: int) -> tuple[str, int]:
    """Status of an order `age` days after placement, plus the age at which
    the status last changed (drives updated_at). Pure function of (oid, age)."""
    rng = random.Random(f"lifecycle-{oid}")
    total = sum(w for w, _ in LIFECYCLES)
    roll = rng.uniform(0, total)
    path = LIFECYCLES[-1][1]
    for weight, candidate in LIFECYCLES:
        roll -= weight
        if roll <= 0:
            path = candidate
            break
    idx = min(age, len(path) - 1)
    last_change = 0
    for i in range(1, idx + 1):
        if path[i] != path[i - 1]:
            last_change = i
    return path[idx], last_change


def customer_move_day(cid: int, first_day: int, as_of_day: int) -> int:
    """Latest day <= as_of_day this customer moved house, or 0 (never)."""
    last = 0
    for day in range(first_day + 1, as_of_day + 1):
        if random.Random(f"move-{cid}-{day}").random() < MOVE_PROBABILITY:
            last = day
    return last


# --------------------------------------------------------------------------
# Deterministic id arithmetic (so ids are stable without querying the DB)
# --------------------------------------------------------------------------

def n_orders(day: int) -> int:
    return random.Random(f"n-orders-{day}").randint(90, 110)

def n_events(day: int) -> int:
    return random.Random(f"n-events-{day}").randint(900, 1100)

def order_id_start(day: int) -> int:
    return 1 + sum(n_orders(d) for d in range(1, day))

def items_count(oid: int) -> int:
    return random.Random(f"items-{oid}").randint(1, 4)

def item_id_start(day: int) -> int:
    return 1 + sum(
        items_count(oid)
        for d in range(1, day)
        for oid in range(order_id_start(d), order_id_start(d) + n_orders(d))
    )

def max_customer_id(day: int) -> int:
    return N_CUSTOMERS_DAY1 + N_CUSTOMERS_PER_DAY * (day - 1)

def customer_first_day(cid: int) -> int:
    if cid <= N_CUSTOMERS_DAY1:
        return 1
    return 2 + (cid - N_CUSTOMERS_DAY1 - 1) // N_CUSTOMERS_PER_DAY


# --------------------------------------------------------------------------
# Row generation for one day
# --------------------------------------------------------------------------

def gen_customers(day: int, synced: datetime) -> list[tuple]:
    if day == 1:
        ids = range(1, N_CUSTOMERS_DAY1 + 1)
    else:
        ids = range(max_customer_id(day - 1) + 1, max_customer_id(day) + 1)
    rows = []
    for cid in ids:
        a = customer_attrs(cid)
        address, city = address_of(cid, 0)
        rows.append((cid, a["first_name"], a["last_name"], a["email"], address, city,
                     a["country_code"], a["created_at"], a["created_at"], synced, day))
    return rows


def gen_products(day: int, synced: datetime) -> list[tuple]:
    if day != 1:
        return []
    rows = []
    for pid in range(1, N_PRODUCTS + 1):
        p = product_attrs(pid)
        rows.append((pid, p["name"], p["category"], p["price_cents"],
                     p["created_at"], synced, day))
    return rows


def order_attrs(oid: int, day: int) -> tuple[int, datetime]:
    """Customer and placement time of an order -- shared by orders and payments
    so both see identical timestamps."""
    rng = random.Random(f"order-{oid}")
    customer = rng.randint(1, max_customer_id(day))
    ordered_at = biz_ts(day, rng)
    return customer, ordered_at


def gen_orders(day: int, synced: datetime) -> list[tuple]:
    rows = []
    start = order_id_start(day)
    for oid in range(start, start + n_orders(day)):
        customer, ordered_at = order_attrs(oid, day)
        status, _ = order_state(oid, 0)  # everything starts as 'placed'
        rows.append((oid, customer, status, ordered_at, ordered_at, synced, day))
    return rows


def gen_order_items(day: int, synced: datetime) -> list[tuple]:
    rows = []
    item_id = item_id_start(day)
    start = order_id_start(day)
    for oid in range(start, start + n_orders(day)):
        rng = random.Random(f"items-{oid}")
        k = rng.randint(1, 4)  # same first draw as items_count()
        for pid in rng.sample(range(1, N_PRODUCTS + 1), k):
            quantity = rng.randint(1, 3)
            price = product_attrs(pid)["price_cents"]
            if rng.random() < 0.15:  # occasional promo discount
                price = int(price * 0.9)
            rows.append((item_id, oid, pid, quantity, price, synced, day))
            item_id += 1
    return rows


def gen_payments(day: int, synced: datetime) -> list[tuple]:
    """Exactly one payment per order, covering the order total (id == order id)."""
    totals: dict[int, int] = {}
    for _, oid, _, quantity, price, _, _ in gen_order_items(day, synced):
        totals[oid] = totals.get(oid, 0) + quantity * price
    rows = []
    start = order_id_start(day)
    for oid in range(start, start + n_orders(day)):
        rng = random.Random(f"pay-{oid}")
        method = rng.choices(PAYMENT_METHODS, weights=[45, 20, 20, 10, 5])[0]
        if rng.random() < 0.05:
            method = method.upper()  # messy source system strikes again
        _, ordered_at = order_attrs(oid, day)
        paid_at = ordered_at + timedelta(minutes=rng.randint(0, 120))
        rows.append((oid, oid, method, totals[oid], paid_at, synced, day))
    return rows


def gen_events(day: int, synced: datetime) -> list[tuple]:
    rows = []
    for i in range(n_events(day)):
        eid = day * 100_000 + i
        rng = random.Random(f"event-{eid}")
        customer = None if rng.random() < 0.20 else rng.randint(1, max_customer_id(day))
        etype = rng.choices(EVENT_TYPES, weights=EVENT_WEIGHTS)[0]
        if etype == "checkout":
            page = "/checkout"
        elif etype == "search":
            page = "/search"
        elif etype == "add_to_cart":
            page = f"/products/{rng.randint(1, N_PRODUCTS)}"
        else:
            page = rng.choice(["/", "/products", f"/products/{rng.randint(1, N_PRODUCTS)}",
                               "/cart", "/about"])
        event_ts = BASE_DATE + timedelta(days=day - 1, seconds=rng.randint(0, 86_399))
        rows.append((eid, customer, etype, page, event_ts, synced, day))
    return rows


# --------------------------------------------------------------------------
# Database operations
# --------------------------------------------------------------------------

def connect():
    load_dotenv(REPO_ROOT / ".env")  # does not override already-set env vars
    return psycopg2.connect(
        host=os.getenv("DBT_HOST", "localhost"),
        port=int(os.getenv("DBT_PORT", "5432")),
        user=os.getenv("DBT_USER", "dbt"),
        password=os.getenv("DBT_PASSWORD", "dbt"),
        dbname=os.getenv("DBT_DBNAME", "jaffle_shop"),
    )


def loaded_days(conn) -> set[int]:
    with conn.cursor() as cur:
        cur.execute("select distinct _batch_day from raw.raw_orders")
        return {row[0] for row in cur.fetchall()}


def delete_day(conn, day: int) -> None:
    with conn.cursor() as cur:
        for table in TABLES:
            cur.execute(f"delete from raw.{table} where _batch_day = %s", (day,))


def load_day(conn, day: int) -> None:
    synced = datetime.now(timezone.utc)
    inserts = {
        "raw_customers": gen_customers(day, synced),
        "raw_products": gen_products(day, synced),
        "raw_orders": gen_orders(day, synced),
        "raw_order_items": gen_order_items(day, synced),
        "raw_payments": gen_payments(day, synced),
        "raw_events": gen_events(day, synced),
    }
    with conn.cursor() as cur:
        for table, rows in inserts.items():
            if rows:
                execute_values(cur, f"insert into raw.{table} values %s", rows)
    counts = ", ".join(f"{t.removeprefix('raw_')}={len(r)}" for t, r in inserts.items() if r)
    print(f"day {day}: loaded {counts}")


def reconcile(conn, as_of_day: int) -> None:
    """Bring mutable state (order status, customer address) to `as_of_day`.

    An EL tool would re-sync rows that changed in the source system; we model
    that by recomputing each row's expected state and updating the ones that
    differ (bumping updated_at with business time and _synced_at with wall
    clock, exactly like a real sync would).
    """
    synced = datetime.now(timezone.utc)

    order_updates = []
    with conn.cursor() as cur:
        cur.execute("select id, _batch_day, status from raw.raw_orders where _batch_day < %s",
                    (as_of_day,))
        for oid, batch_day, current_status in cur.fetchall():
            status, last_change = order_state(oid, as_of_day - batch_day)
            if status != current_status:
                changed_day = batch_day + last_change
                updated_at = biz_ts(changed_day, random.Random(f"ordupd-{oid}-{last_change}"))
                order_updates.append((oid, status, updated_at, synced))
        if order_updates:
            execute_values(
                cur,
                """update raw.raw_orders as o
                   set status = v.status, updated_at = v.updated_at, _synced_at = v.synced_at
                   from (values %s) as v(id, status, updated_at, synced_at)
                   where o.id = v.id""",
                order_updates,
                template="(%s, %s, %s::timestamp, %s::timestamptz)",
            )

    customer_updates = []
    with conn.cursor() as cur:
        cur.execute("select id, _batch_day, address, city from raw.raw_customers")
        for cid, batch_day, current_address, current_city in cur.fetchall():
            move_day = customer_move_day(cid, batch_day, as_of_day)
            address, city = address_of(cid, move_day)
            if (address, city) != (current_address, current_city):
                updated_at = biz_ts(move_day, random.Random(f"custupd-{cid}-{move_day}"))
                customer_updates.append((cid, address, city, updated_at, synced))
        if customer_updates:
            execute_values(
                cur,
                """update raw.raw_customers as c
                   set address = v.address, city = v.city,
                       updated_at = v.updated_at, _synced_at = v.synced_at
                   from (values %s) as v(id, address, city, updated_at, synced_at)
                   where c.id = v.id""",
                customer_updates,
                template="(%s, %s, %s, %s::timestamp, %s::timestamptz)",
            )

    print(f"reconciled to day {as_of_day}: "
          f"{len(order_updates)} order status changes, "
          f"{len(customer_updates)} customer moves")


def summary(conn) -> None:
    with conn.cursor() as cur:
        for table in TABLES:
            cur.execute(f"select count(*) from raw.{table}")
            print(f"  raw.{table:<16} {cur.fetchone()[0]:>6} rows")
        cur.execute("""select status, count(*) from raw.raw_orders
                       group by status order by count(*) desc""")
        statuses = ", ".join(f"{s}={n}" for s, n in cur.fetchall())
        print(f"  order statuses: {statuses}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--days", type=int, metavar="N", help="load days 1..N (skips loaded days)")
    group.add_argument("--day", type=int, metavar="N", help="(re)load exactly day N")
    group.add_argument("--reset", action="store_true", help="drop and recreate the raw schema")
    args = parser.parse_args()

    conn = connect()
    try:
        with conn.cursor() as cur:
            if args.reset:
                cur.execute("drop schema if exists raw cascade")
            cur.execute(DDL)
        conn.commit()
        if args.reset:
            print("raw schema reset (empty)")
            return

        already = loaded_days(conn)
        if args.day is not None:
            missing = set(range(1, args.day)) - already
            if missing:
                sys.exit(f"error: days {sorted(missing)} not loaded yet -- "
                         f"run --days {args.day} instead")
            delete_day(conn, args.day)
            load_day(conn, args.day)
        else:
            for day in range(1, args.days + 1):
                if day in already:
                    print(f"day {day}: already loaded, skipping")
                else:
                    load_day(conn, day)

        reconcile(conn, max(loaded_days(conn)))
        conn.commit()
        summary(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
