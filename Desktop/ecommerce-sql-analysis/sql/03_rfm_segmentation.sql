-- ============================================================
-- 03_RFM_SEGMENTATION.SQL
-- Olist E-Commerce | Phase 4: Customer RFM Scoring
-- ============================================================

-- ─────────────────────────────────────────────
-- 1. RAW RFM METRICS PER CUSTOMER
-- ─────────────────────────────────────────────
WITH reference_date AS (
    -- Use the day after the latest order as the "today" reference
    SELECT MAX(order_purchase_timestamp)::DATE + 1 AS ref_date
    FROM orders
    WHERE order_status NOT IN ('canceled', 'unavailable')
),

customer_rfm_raw AS (
    SELECT
        o.customer_id,
        c.customer_state,
        c.customer_city,
        DATEDIFF('day',
            MAX(o.order_purchase_timestamp)::DATE,
            (SELECT ref_date FROM reference_date))          AS recency_days,
        COUNT(DISTINCT o.order_id)                          AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2)          AS monetary_value,
        MIN(o.order_purchase_timestamp)::DATE               AS first_order_date,
        MAX(o.order_purchase_timestamp)::DATE               AS last_order_date
    FROM orders o
    JOIN order_items oi ON o.order_id   = oi.order_id
    JOIN customers c    ON o.customer_id = c.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY o.customer_id, c.customer_state, c.customer_city
),

-- ─────────────────────────────────────────────
-- 2. SCORE EACH DIMENSION 1–5 USING NTILE
--    Recency: lower days = better = score 5
--    Frequency & Monetary: higher = better = score 5
-- ─────────────────────────────────────────────
rfm_scored AS (
    SELECT
        customer_id,
        customer_state,
        customer_city,
        recency_days,
        frequency,
        monetary_value,
        first_order_date,
        last_order_date,
        -- Recency: invert so recent = high score
        6 - NTILE(5) OVER (ORDER BY recency_days DESC)  AS r_score,
        NTILE(5)     OVER (ORDER BY frequency       ASC) AS f_score,
        NTILE(5)     OVER (ORDER BY monetary_value  ASC) AS m_score
    FROM customer_rfm_raw
),

-- ─────────────────────────────────────────────
-- 3. COMPOSITE RFM SCORE & SEGMENT ASSIGNMENT
-- ─────────────────────────────────────────────
rfm_segmented AS (
    SELECT
        customer_id,
        customer_state,
        customer_city,
        recency_days,
        frequency,
        monetary_value,
        first_order_date,
        last_order_date,
        r_score,
        f_score,
        m_score,
        (r_score + f_score + m_score)                   AS rfm_total,
        CONCAT(r_score, f_score, m_score)               AS rfm_cell,
        CASE
            -- Champions: bought recently, buy often, spend most
            WHEN r_score = 5 AND f_score >= 4 AND m_score >= 4
                THEN 'Champions'
            -- Loyal Customers
            WHEN r_score >= 3 AND f_score >= 4
                THEN 'Loyal Customers'
            -- Potential Loyalists
            WHEN r_score >= 4 AND f_score IN (1,2) AND m_score >= 2
                THEN 'Potential Loyalists'
            -- Recent Customers
            WHEN r_score = 5 AND f_score = 1
                THEN 'Recent Customers'
            -- Promising
            WHEN r_score = 4 AND f_score = 1
                THEN 'Promising'
            -- Customers Needing Attention
            WHEN r_score = 3 AND f_score <= 2 AND m_score <= 3
                THEN 'Need Attention'
            -- About to Sleep
            WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 3
                THEN 'About to Sleep'
            -- At Risk: big spenders who haven't bought lately
            WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
                THEN 'At Risk'
            -- Can't Lose: top spenders who left
            WHEN r_score = 1 AND f_score >= 4 AND m_score >= 4
                THEN 'Cannot Lose Them'
            -- Hibernating
            WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2
                THEN 'Hibernating'
            -- Lost
            WHEN r_score = 1 AND f_score = 1
                THEN 'Lost'
            ELSE 'Others'
        END AS rfm_segment
    FROM rfm_scored
)

-- ─────────────────────────────────────────────
-- 4. FULL RFM TABLE (for export / BI tool)
-- ─────────────────────────────────────────────
SELECT *
FROM rfm_segmented
ORDER BY rfm_total DESC;


-- ─────────────────────────────────────────────
-- 5. SEGMENT SUMMARY: SIZE, REVENUE, RECENCY
-- ─────────────────────────────────────────────
WITH rfm_base AS (
    -- Re-run the CTE chain above; in practice use a VIEW or temp table
    WITH reference_date AS (
        SELECT MAX(order_purchase_timestamp)::DATE + 1 AS ref_date
        FROM orders WHERE order_status NOT IN ('canceled','unavailable')
    ),
    raw AS (
        SELECT o.customer_id,
               DATEDIFF('day', MAX(o.order_purchase_timestamp)::DATE,
                        (SELECT ref_date FROM reference_date))       AS recency_days,
               COUNT(DISTINCT o.order_id)                            AS frequency,
               ROUND(SUM(oi.price + oi.freight_value), 2)            AS monetary_value
        FROM orders o JOIN order_items oi ON o.order_id = oi.order_id
        WHERE o.order_status NOT IN ('canceled','unavailable')
        GROUP BY o.customer_id
    ),
    scored AS (
        SELECT *,
               6 - NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
               NTILE(5)     OVER (ORDER BY frequency       ASC) AS f_score,
               NTILE(5)     OVER (ORDER BY monetary_value  ASC) AS m_score
        FROM raw
    )
    SELECT *,
           CASE
               WHEN r_score = 5 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
               WHEN r_score >= 3 AND f_score >= 4                  THEN 'Loyal Customers'
               WHEN r_score >= 4 AND f_score IN (1,2) AND m_score >= 2 THEN 'Potential Loyalists'
               WHEN r_score = 5 AND f_score = 1                    THEN 'Recent Customers'
               WHEN r_score = 4 AND f_score = 1                    THEN 'Promising'
               WHEN r_score = 3 AND f_score <= 2 AND m_score <= 3  THEN 'Need Attention'
               WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 3 THEN 'About to Sleep'
               WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk'
               WHEN r_score = 1 AND f_score >= 4 AND m_score >= 4  THEN 'Cannot Lose Them'
               WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Hibernating'
               WHEN r_score = 1 AND f_score = 1                    THEN 'Lost'
               ELSE 'Others'
           END AS rfm_segment
    FROM scored
)
SELECT
    rfm_segment,
    COUNT(*)                        AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_customers,
    ROUND(AVG(recency_days), 1)     AS avg_recency_days,
    ROUND(AVG(frequency), 2)        AS avg_frequency,
    ROUND(AVG(monetary_value), 2)   AS avg_monetary_value,
    ROUND(SUM(monetary_value), 2)   AS total_revenue,
    ROUND(SUM(monetary_value) * 100.0 / SUM(SUM(monetary_value)) OVER (), 2) AS pct_of_revenue
FROM rfm_base
GROUP BY rfm_segment
ORDER BY total_revenue DESC;


-- ─────────────────────────────────────────────
-- 6. HIGH-VALUE CUSTOMER LIST (Champions + Loyal)
-- ─────────────────────────────────────────────
WITH reference_date AS (
    SELECT MAX(order_purchase_timestamp)::DATE + 1 AS ref_date
    FROM orders WHERE order_status NOT IN ('canceled','unavailable')
),
raw AS (
    SELECT o.customer_id, c.customer_state, c.customer_city,
           DATEDIFF('day', MAX(o.order_purchase_timestamp)::DATE,
                    (SELECT ref_date FROM reference_date)) AS recency_days,
           COUNT(DISTINCT o.order_id)                      AS frequency,
           ROUND(SUM(oi.price + oi.freight_value), 2)      AS monetary_value
    FROM orders o JOIN order_items oi ON o.order_id = oi.order_id
                  JOIN customers c    ON o.customer_id = c.customer_id
    WHERE o.order_status NOT IN ('canceled','unavailable')
    GROUP BY o.customer_id, c.customer_state, c.customer_city
),
scored AS (
    SELECT *, 6 - NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
              NTILE(5)     OVER (ORDER BY frequency       ASC) AS f_score,
              NTILE(5)     OVER (ORDER BY monetary_value  ASC) AS m_score
    FROM raw
)
SELECT customer_id, customer_state, customer_city,
       recency_days, frequency, monetary_value,
       r_score, f_score, m_score,
       CASE
           WHEN r_score = 5 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 4                  THEN 'Loyal Customers'
       END AS rfm_segment
FROM scored
WHERE (r_score = 5 AND f_score >= 4 AND m_score >= 4)
   OR (r_score >= 3 AND f_score >= 4)
ORDER BY monetary_value DESC
LIMIT 500;
