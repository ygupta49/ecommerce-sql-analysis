# Customer Revenue Intelligence: End-to-End SQL Analysis
### Brazilian E-Commerce (Olist) — 100K+ Orders · 8 Tables · 6 Analysis Phases

---

## Business Context

This project delivers a structured analytical framework for a mid-size e-commerce retailer's
commercial analytics team. Using the **Olist Brazilian E-Commerce Dataset** (Kaggle), it
answers six critical business questions across revenue performance, customer behavior,
operational efficiency, and seller reliability — directly informing Q3 planning decisions.

**Dataset:** [Olist E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
~100K anonymized orders (2016–2018), 8 relational tables, Brazilian market.

---

## Repository Structure

```
ecommerce-sql-analysis/
│
├── README.md
├── data/
│   └── schema_diagram.png          ← ERD showing all 8 table relationships
├── sql/
│   ├── 00_data_quality_checks.sql  ← Row counts, nulls, orphan records, distributions
│   ├── 01_revenue_analysis.sql     ← GMV trends, category mix, payment methods
│   ├── 02_cohort_retention.sql     ← Cohort matrix, repeat purchase rate
│   ├── 03_rfm_segmentation.sql     ← RFM scoring, segment assignment & summary
│   ├── 04_seller_performance.sql   ← SLA breach rates, delivery time, ranking
│   └── 05_review_score_analysis.sql ← Delay/review correlation, category ratings
├── outputs/
│   ├── cohort_retention_matrix.png
│   ├── rfm_segment_distribution.png
│   └── monthly_revenue_trend.png
└── docs/
    └── executive_summary.pdf
```

---

## Key Findings

### 1. Revenue is Heavily Concentrated in Q4 / Nov–Dec
Monthly GMV analysis (with LAG-based MoM growth) shows a pronounced November spike
driven by Black Friday. The top 3 categories — **health_beauty**, **watches_gifts**, and
**bed_bath_table** — account for ~28% of total platform revenue. Categories like
**computers_accessories** punch above their weight on Average Order Value (R$180+ AOV).

### 2. Retention Drops Sharply After Month 0
Cohort analysis reveals that while Month 0 (acquisition) retention is 100% by definition,
**Month 1 retention averages just 3–4%** across cohorts — indicating the platform skews
heavily toward one-time transactional purchases rather than repeat engagement. Only
~3% of customers place more than one order, making first-purchase experience critical.

### 3. RFM Segmentation Uncovers a Lopsided Value Distribution
Champions and Loyal Customers (~8% of the customer base) generate approximately
**45–50% of total platform revenue**. The "At Risk" and "Cannot Lose" segments represent
high-value customers with recency decay — prime candidates for win-back campaigns.
The majority of customers (60%+) fall into Hibernating or Lost segments.

### 4. Delivery Delays Directly Tank Review Scores
Orders delivered **on time or early** average a **4.3★ review score**. Orders that arrive
15+ days late average **2.1★** — a 50% score collapse. Late deliveries account for roughly
8% of all delivered orders but generate ~30% of 1-star reviews.

### 5. 20% of Sellers Generate 80% of Revenue (Pareto Effect)
RANK() and NTILE analysis confirms that the top revenue decile of sellers drives the
majority of GMV. Meanwhile, ~15% of active sellers exhibit both low revenue contribution
AND SLA breach rates above 30% — these are flagged as "High Priority Review" accounts.

---

## Methodology & SQL Skills Used

| SQL Concept | Queries Applied |
|---|---|
| Multi-table JOINs (3–5 tables) | All revenue, seller, and review queries |
| CTEs (`WITH` clauses) | RFM scoring, cohort prep, underperformer detection |
| Window Functions (`LAG`, `RANK`, `NTILE`, `SUM OVER`) | MoM growth, seller ranking, RFM scoring, running totals |
| Aggregations (`SUM`, `COUNT`, `AVG`, `PERCENTILE_CONT`) | KPIs throughout |
| `CASE` Statements | RFM segments, delay buckets, review flags, SLA breaches |
| Date Functions (`DATEDIFF`, `DATE_TRUNC`, `EXTRACT`) | Cohort periods, delivery time, monthly grouping |
| Subqueries | Nested segmentation, reference date for RFM |
| `HAVING`, `GROUP BY`, `ORDER BY` | All category/seller rollups |

**SQL Dialect:** Standard SQL (PostgreSQL-compatible). Minor adjustments needed for MySQL
(replace `DATEDIFF('day', ...)` with `DATEDIFF(date1, date2)`) or BigQuery.

---

## Setup Instructions

### 1. Download the Dataset
```
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
```
Download and extract all 8 CSV files.

### 2. Create Tables & Load Data (PostgreSQL)
```sql
-- Example: create and load the orders table
CREATE TABLE orders (
    order_id                        VARCHAR(32) PRIMARY KEY,
    customer_id                     VARCHAR(32),
    order_status                    VARCHAR(20),
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP
);

COPY orders FROM '/path/to/olist_orders_dataset.csv'
    CSV HEADER DELIMITER ',';
```
Repeat for all 8 tables: `customers`, `order_items`, `sellers`, `products`,
`order_payments`, `order_reviews`, `geolocation`.

### 3. Run Queries in Order
```
00 → 01 → 02 → 03 → 04 → 05
```
Each file is self-contained with CTEs; no persistent temp tables required.

---

## Table Schema Summary

| Table | Rows (approx) | Key Columns |
|---|---|---|
| `orders` | 99,441 | order_id, customer_id, order_status, timestamps |
| `order_items` | 112,650 | order_id, product_id, seller_id, price, freight_value |
| `customers` | 99,441 | customer_id, customer_state, customer_city |
| `sellers` | 3,095 | seller_id, seller_state, seller_city |
| `products` | 32,951 | product_id, product_category_name, dimensions |
| `order_payments` | 103,886 | order_id, payment_type, payment_value, installments |
| `order_reviews` | 99,224 | order_id, review_score, review_creation_date |
| `geolocation` | 1,000,163 | zip_code_prefix, lat, lng, city, state |

---

## Data Quality Notes
- ~600 orders have no matching payment record (flagged in Phase 1)
- ~3% of delivered orders are missing a `order_delivered_customer_date`
- Product categories use Portuguese names; an English translation table is
  available in the original Kaggle dataset
- The `geolocation` table has duplicate zip codes — aggregate before joining

---

## Author Notes
Built as a portfolio project demonstrating production-grade SQL analysis patterns.
All data is public, anonymized, and provided under the Olist/Kaggle open license.
