-- ============================================================
-- 02_COHORT_RETENTION.SQL
-- Olist E-Commerce | Phase 3: Customer Cohort Retention
-- ============================================================

-- ─────────────────────────────────────────────
-- 1. DEFINE COHORTS BY FIRST PURCHASE MONTH
-- ─────────────────────────────────────────────
WITH first_purchase AS (
    -- Each customer's very first order date
    SELECT
        o.customer_id,
        MIN(DATE_TRUNC('month', o.order_purchase_timestamp)) AS cohort_month
    FROM orders o
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY o.customer_id
),

-- All subsequent purchases for every customer
all_purchases AS (
    SELECT
        o.customer_id,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS purchase_month
    FROM orders o
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),

-- Link each purchase back to the customer's cohort
cohort_activity AS (
    SELECT
        fp.cohort_month,
        ap.purchase_month,
        -- Period index: 0 = acquisition month, 1 = Month 1, etc.
        DATEDIFF('month', fp.cohort_month, ap.purchase_month) AS period_number,
        COUNT(DISTINCT ap.customer_id)                          AS active_customers
    FROM first_purchase fp
    JOIN all_purchases ap ON fp.customer_id = ap.customer_id
    GROUP BY fp.cohort_month, ap.purchase_month,
             DATEDIFF('month', fp.cohort_month, ap.purchase_month)
),

-- Cohort size (customers acquired in each cohort month)
cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_id) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
)

-- ─────────────────────────────────────────────
-- 2. COHORT RETENTION MATRIX
--    Rows = cohort, Cols = period 0..12
-- ─────────────────────────────────────────────
SELECT
    ca.cohort_month,
    cs.cohort_customers                                         AS cohort_size,
    ca.period_number,
    ca.active_customers,
    ROUND(ca.active_customers * 100.0 / cs.cohort_customers, 2) AS retention_rate_pct
FROM cohort_activity ca
JOIN cohort_size cs ON ca.cohort_month = cs.cohort_month
WHERE ca.period_number BETWEEN 0 AND 12
ORDER BY ca.cohort_month, ca.period_number;


-- ─────────────────────────────────────────────
-- 3. PIVOTED COHORT MATRIX (periods 0-6)
--    One row per cohort, columns per period
-- ─────────────────────────────────────────────
WITH first_purchase AS (
    SELECT
        o.customer_id,
        MIN(DATE_TRUNC('month', o.order_purchase_timestamp)) AS cohort_month
    FROM orders o
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY o.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
),
all_activity AS (
    SELECT
        fp.cohort_month,
        fp.customer_id,
        DATEDIFF('month', fp.cohort_month,
                 DATE_TRUNC('month', o.order_purchase_timestamp)) AS period_number
    FROM first_purchase fp
    JOIN orders o ON fp.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
)
SELECT
    aa.cohort_month,
    cs.cohort_customers,
    ROUND(SUM(CASE WHEN period_number = 0  THEN 1 ELSE 0 END) * 100.0 / cs.cohort_customers, 1) AS "M0_%",
    ROUND(SUM(CASE WHEN period_number = 1  THEN 1 ELSE 0 END) * 100.0 / cs.cohort_customers, 1) AS "M1_%",
    ROUND(SUM(CASE WHEN period_number = 2  THEN 1 ELSE 0 END) * 100.0 / cs.cohort_customers, 1) AS "M2_%",
    ROUND(SUM(CASE WHEN period_number = 3  THEN 1 ELSE 0 END) * 100.0 / cs.cohort_customers, 1) AS "M3_%",
    ROUND(SUM(CASE WHEN period_number = 4  THEN 1 ELSE 0 END) * 100.0 / cs.cohort_customers, 1) AS "M4_%",
    ROUND(SUM(CASE WHEN period_number = 5  THEN 1 ELSE 0 END) * 100.0 / cs.cohort_customers, 1) AS "M5_%",
    ROUND(SUM(CASE WHEN period_number = 6  THEN 1 ELSE 0 END) * 100.0 / cs.cohort_customers, 1) AS "M6_%"
FROM all_activity aa
JOIN cohort_size cs ON aa.cohort_month = cs.cohort_month
GROUP BY aa.cohort_month, cs.cohort_customers
ORDER BY aa.cohort_month;


-- ─────────────────────────────────────────────
-- 4. AVERAGE RETENTION RATE BY PERIOD
--    Aggregate across all cohorts
-- ─────────────────────────────────────────────
WITH first_purchase AS (
    SELECT
        o.customer_id,
        MIN(DATE_TRUNC('month', o.order_purchase_timestamp)) AS cohort_month
    FROM orders o
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY o.customer_id
),
cohort_activity AS (
    SELECT
        fp.cohort_month,
        DATEDIFF('month', fp.cohort_month,
                 DATE_TRUNC('month', o.order_purchase_timestamp)) AS period_number,
        COUNT(DISTINCT fp.customer_id)                             AS active_customers
    FROM first_purchase fp
    JOIN orders o ON fp.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY fp.cohort_month,
             DATEDIFF('month', fp.cohort_month,
                      DATE_TRUNC('month', o.order_purchase_timestamp))
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
)
SELECT
    ca.period_number,
    ROUND(AVG(ca.active_customers * 100.0 / cs.cohort_customers), 2) AS avg_retention_pct,
    MIN(ca.active_customers * 100.0 / cs.cohort_customers)            AS min_retention_pct,
    MAX(ca.active_customers * 100.0 / cs.cohort_customers)            AS max_retention_pct,
    COUNT(DISTINCT ca.cohort_month)                                    AS cohorts_included
FROM cohort_activity ca
JOIN cohort_size cs ON ca.cohort_month = cs.cohort_month
WHERE ca.period_number BETWEEN 0 AND 12
GROUP BY ca.period_number
ORDER BY ca.period_number;


-- ─────────────────────────────────────────────
-- 5. REPEAT PURCHASE RATE (SIMPLE)
-- ─────────────────────────────────────────────
WITH customer_order_counts AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS num_orders
    FROM orders
    WHERE order_status NOT IN ('canceled', 'unavailable')
    GROUP BY customer_id
)
SELECT
    COUNT(*)                                                          AS total_customers,
    SUM(CASE WHEN num_orders > 1 THEN 1 ELSE 0 END)                  AS repeat_customers,
    ROUND(SUM(CASE WHEN num_orders > 1 THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                              AS repeat_purchase_rate_pct,
    AVG(num_orders)                                                   AS avg_orders_per_customer,
    MAX(num_orders)                                                   AS max_orders_single_customer
FROM customer_order_counts;
