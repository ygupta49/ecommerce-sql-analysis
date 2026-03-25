-- ============================================================
-- 01_REVENUE_ANALYSIS.SQL
-- Olist E-Commerce | Phase 2: Revenue & Category Performance
-- ============================================================

-- ─────────────────────────────────────────────
-- 1. MONTHLY GMV TREND WITH MoM GROWTH
--    Uses LAG() window function
-- ─────────────────────────────────────────────
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month,
        ROUND(SUM(oi.price + oi.freight_value), 2)      AS gmv,
        COUNT(DISTINCT o.order_id)                       AS total_orders,
        COUNT(DISTINCT o.customer_id)                    AS unique_customers,
        ROUND(AVG(oi.price + oi.freight_value), 2)       AS aov
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
)
SELECT
    order_month,
    gmv,
    total_orders,
    unique_customers,
    aov,
    LAG(gmv) OVER (ORDER BY order_month)                            AS prev_month_gmv,
    ROUND(
        (gmv - LAG(gmv) OVER (ORDER BY order_month))
        / NULLIF(LAG(gmv) OVER (ORDER BY order_month), 0) * 100, 2
    )                                                                AS mom_growth_pct,
    SUM(gmv) OVER (ORDER BY order_month ROWS UNBOUNDED PRECEDING)   AS cumulative_gmv
FROM monthly_revenue
ORDER BY order_month;


-- ─────────────────────────────────────────────
-- 2. TOP 10 CATEGORIES BY REVENUE, ORDERS & AOV
-- ─────────────────────────────────────────────
WITH category_revenue AS (
    SELECT
        COALESCE(p.product_category_name, 'unknown') AS category,
        ROUND(SUM(oi.price), 2)                       AS total_revenue,
        COUNT(DISTINCT o.order_id)                    AS total_orders,
        COUNT(DISTINCT oi.product_id)                 AS unique_products,
        ROUND(AVG(oi.price), 2)                       AS avg_item_price,
        ROUND(SUM(oi.freight_value), 2)               AS total_freight,
        ROUND(SUM(oi.freight_value) / NULLIF(SUM(oi.price), 0) * 100, 2) AS freight_to_revenue_pct
    FROM order_items oi
    JOIN orders o      ON oi.order_id  = o.order_id
    JOIN products p    ON oi.product_id = p.product_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY COALESCE(p.product_category_name, 'unknown')
)
SELECT
    category,
    total_revenue,
    total_orders,
    unique_products,
    avg_item_price,
    freight_to_revenue_pct,
    ROUND(total_revenue / SUM(total_revenue) OVER () * 100, 2)  AS revenue_share_pct,
    RANK() OVER (ORDER BY total_revenue DESC)                    AS revenue_rank,
    RANK() OVER (ORDER BY total_orders  DESC)                    AS orders_rank
FROM category_revenue
ORDER BY total_revenue DESC
LIMIT 10;


-- ─────────────────────────────────────────────
-- 3. PAYMENT METHOD BREAKDOWN BY CATEGORY
-- ─────────────────────────────────────────────
WITH payment_by_category AS (
    SELECT
        COALESCE(p.product_category_name, 'unknown')    AS category,
        op.payment_type,
        COUNT(DISTINCT o.order_id)                       AS order_count,
        ROUND(SUM(op.payment_value), 2)                  AS total_payment_value,
        ROUND(AVG(op.payment_installments), 1)           AS avg_installments
    FROM orders o
    JOIN order_items oi      ON o.order_id  = oi.order_id
    JOIN products p          ON oi.product_id = p.product_id
    JOIN order_payments op   ON o.order_id  = op.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY
        COALESCE(p.product_category_name, 'unknown'),
        op.payment_type
)
SELECT
    category,
    payment_type,
    order_count,
    total_payment_value,
    avg_installments,
    ROUND(order_count * 100.0 / SUM(order_count) OVER (PARTITION BY category), 2) AS pct_of_category_orders
FROM payment_by_category
ORDER BY category, total_payment_value DESC;


-- ─────────────────────────────────────────────
-- 4. REVENUE BY STATE (CUSTOMER LOCATION)
-- ─────────────────────────────────────────────
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)              AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_gmv,
    ROUND(AVG(oi.price + oi.freight_value), 2) AS avg_order_value,
    COUNT(DISTINCT o.customer_id)           AS unique_customers,
    RANK() OVER (ORDER BY SUM(oi.price + oi.freight_value) DESC) AS gmv_rank
FROM orders o
JOIN order_items oi ON o.order_id  = oi.order_id
JOIN customers c    ON o.customer_id = c.customer_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_state
ORDER BY total_gmv DESC;


-- ─────────────────────────────────────────────
-- 5. QUARTERLY REVENUE BREAKDOWN
-- ─────────────────────────────────────────────
SELECT
    EXTRACT(YEAR  FROM o.order_purchase_timestamp) AS yr,
    EXTRACT(QUARTER FROM o.order_purchase_timestamp) AS qtr,
    ROUND(SUM(oi.price + oi.freight_value), 2)   AS quarterly_gmv,
    COUNT(DISTINCT o.order_id)                    AS orders,
    ROUND(AVG(oi.price), 2)                       AS avg_item_price
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY
    EXTRACT(YEAR  FROM o.order_purchase_timestamp),
    EXTRACT(QUARTER FROM o.order_purchase_timestamp)
ORDER BY yr, qtr;


-- ─────────────────────────────────────────────
-- 6. DAY-OF-WEEK REVENUE PATTERN
-- ─────────────────────────────────────────────
SELECT
    EXTRACT(DOW FROM o.order_purchase_timestamp) AS day_of_week_num,
    TO_CHAR(o.order_purchase_timestamp, 'Day')   AS day_name,
    COUNT(DISTINCT o.order_id)                   AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)   AS total_gmv,
    ROUND(AVG(oi.price + oi.freight_value), 2)   AS avg_order_value
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY
    EXTRACT(DOW FROM o.order_purchase_timestamp),
    TO_CHAR(o.order_purchase_timestamp, 'Day')
ORDER BY day_of_week_num;
