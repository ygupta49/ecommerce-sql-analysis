-- ============================================================
-- 04_SELLER_PERFORMANCE.SQL
-- Olist E-Commerce | Phase 5: Seller & Operational Performance
-- ============================================================

-- ─────────────────────────────────────────────
-- 1. AVERAGE DELIVERY TIME PER SELLER
--    vs. Estimated Delivery (SLA tracking)
-- ─────────────────────────────────────────────
WITH seller_delivery AS (
    SELECT
        oi.seller_id,
        s.seller_state,
        s.seller_city,
        o.order_id,
        o.order_purchase_timestamp,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,

        -- Actual transit time: purchase → delivered to customer
        DATEDIFF('day',
            o.order_purchase_timestamp,
            o.order_delivered_customer_date)            AS actual_delivery_days,

        -- Estimated transit time
        DATEDIFF('day',
            o.order_purchase_timestamp,
            o.order_estimated_delivery_date)            AS estimated_delivery_days,

        -- Delay: positive = late, negative = early
        DATEDIFF('day',
            o.order_estimated_delivery_date,
            o.order_delivered_customer_date)            AS delay_days,

        -- SLA breach flag
        CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 1 ELSE 0
        END AS is_late
    FROM order_items oi
    JOIN orders o   ON oi.order_id  = o.order_id
    JOIN sellers s  ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    seller_id,
    seller_state,
    seller_city,
    COUNT(DISTINCT order_id)                        AS total_orders,
    ROUND(AVG(actual_delivery_days), 1)             AS avg_actual_days,
    ROUND(AVG(estimated_delivery_days), 1)          AS avg_estimated_days,
    ROUND(AVG(delay_days), 1)                       AS avg_delay_days,
    SUM(is_late)                                    AS late_orders,
    ROUND(SUM(is_late) * 100.0 / COUNT(*), 2)       AS sla_breach_rate_pct,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
          (ORDER BY actual_delivery_days), 1)       AS median_delivery_days,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP
          (ORDER BY actual_delivery_days), 1)       AS p95_delivery_days
FROM seller_delivery
GROUP BY seller_id, seller_state, seller_city
HAVING COUNT(DISTINCT order_id) >= 10            -- Exclude low-volume sellers
ORDER BY sla_breach_rate_pct DESC;


-- ─────────────────────────────────────────────
-- 2. SELLER REVENUE RANKING WITH RANK()
-- ─────────────────────────────────────────────
WITH seller_revenue AS (
    SELECT
        oi.seller_id,
        s.seller_state,
        ROUND(SUM(oi.price), 2)             AS total_revenue,
        ROUND(SUM(oi.freight_value), 2)     AS total_freight,
        COUNT(DISTINCT oi.order_id)         AS total_orders,
        COUNT(DISTINCT oi.product_id)       AS unique_products,
        ROUND(AVG(oi.price), 2)             AS avg_item_price,
        COUNT(DISTINCT o.customer_id)       AS unique_customers
    FROM order_items oi
    JOIN orders o  ON oi.order_id  = o.order_id
    JOIN sellers s ON oi.seller_id = s.seller_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY oi.seller_id, s.seller_state
)
SELECT
    seller_id,
    seller_state,
    total_revenue,
    total_freight,
    total_orders,
    unique_products,
    unique_customers,
    avg_item_price,
    RANK()       OVER (ORDER BY total_revenue DESC)  AS revenue_rank,
    RANK()       OVER (ORDER BY total_orders  DESC)  AS orders_rank,
    NTILE(10)    OVER (ORDER BY total_revenue DESC)  AS revenue_decile,
    ROUND(total_revenue * 100.0 / SUM(total_revenue) OVER (), 2) AS revenue_share_pct,
    -- Running total of revenue from top sellers down
    SUM(total_revenue) OVER (ORDER BY total_revenue DESC
                             ROWS UNBOUNDED PRECEDING) AS cumulative_revenue
FROM seller_revenue
ORDER BY revenue_rank
LIMIT 100;


-- ─────────────────────────────────────────────
-- 3. UNDERPERFORMING SELLERS
--    Low revenue AND high SLA breach rate
-- ─────────────────────────────────────────────
WITH seller_revenue AS (
    SELECT
        oi.seller_id,
        ROUND(SUM(oi.price), 2)         AS total_revenue,
        COUNT(DISTINCT oi.order_id)     AS total_orders
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY oi.seller_id
),
seller_sla AS (
    SELECT
        oi.seller_id,
        COUNT(*) AS delivered_orders,
        ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                            > o.order_estimated_delivery_date
                       THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS sla_breach_pct
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY oi.seller_id
),
seller_reviews AS (
    SELECT
        oi.seller_id,
        ROUND(AVG(r.review_score), 2)   AS avg_review_score
    FROM order_items oi
    JOIN orders o         ON oi.order_id = o.order_id
    JOIN order_reviews r  ON o.order_id  = r.order_id
    GROUP BY oi.seller_id
)
SELECT
    sr.seller_id,
    s.seller_state,
    sr.total_revenue,
    sr.total_orders,
    sl.sla_breach_pct,
    rv.avg_review_score,
    CASE
        WHEN sr.total_revenue < PERCENTILE_CONT(0.25) WITHIN GROUP
             (ORDER BY sr.total_revenue) OVER ()
         AND sl.sla_breach_pct > 30
        THEN 'High Priority Review'
        WHEN sl.sla_breach_pct > 50
        THEN 'SLA Critical'
        WHEN sr.total_revenue < PERCENTILE_CONT(0.25) WITHIN GROUP
             (ORDER BY sr.total_revenue) OVER ()
        THEN 'Low Revenue'
        ELSE 'Standard'
    END AS performance_flag
FROM seller_revenue sr
JOIN seller_sla     sl ON sr.seller_id = sl.seller_id
JOIN seller_reviews rv ON sr.seller_id = rv.seller_id
JOIN sellers         s ON sr.seller_id = s.seller_id
WHERE sl.delivered_orders >= 5
ORDER BY sl.sla_breach_pct DESC, sr.total_revenue ASC;


-- ─────────────────────────────────────────────
-- 4. DELIVERY TIME BY CUSTOMER STATE
-- ─────────────────────────────────────────────
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)                          AS total_orders,
    ROUND(AVG(DATEDIFF('day',
        o.order_purchase_timestamp,
        o.order_delivered_customer_date)), 1)           AS avg_delivery_days,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP
          (ORDER BY DATEDIFF('day',
              o.order_purchase_timestamp,
              o.order_delivered_customer_date)), 1)     AS median_delivery_days,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                        > o.order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS late_delivery_pct,
    RANK() OVER (ORDER BY AVG(DATEDIFF('day',
        o.order_purchase_timestamp,
        o.order_delivered_customer_date)) DESC)        AS slowest_state_rank
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_delivery_days DESC;


-- ─────────────────────────────────────────────
-- 5. MONTHLY SLA TREND — are delays improving?
-- ─────────────────────────────────────────────
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month,
    COUNT(*)                                         AS total_delivered,
    SUM(CASE WHEN o.order_delivered_customer_date
                  > o.order_estimated_delivery_date
             THEN 1 ELSE 0 END)                      AS late_count,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                        > o.order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                             AS late_pct,
    ROUND(AVG(DATEDIFF('day',
              o.order_estimated_delivery_date,
              o.order_delivered_customer_date)), 1)  AS avg_delay_days,
    LAG(ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                            > o.order_estimated_delivery_date
                       THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2))
        OVER (ORDER BY DATE_TRUNC('month', o.order_purchase_timestamp)) AS prev_month_late_pct
FROM orders o
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
ORDER BY order_month;
