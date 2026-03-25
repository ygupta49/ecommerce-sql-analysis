-- ============================================================
-- 05_REVIEW_SCORE_ANALYSIS.SQL
-- Olist E-Commerce | Phase 6: Review Score Predictors
-- ============================================================

-- ─────────────────────────────────────────────
-- 1. OVERALL REVIEW SCORE DISTRIBUTION
-- ─────────────────────────────────────────────
SELECT
    review_score,
    COUNT(*)                                           AS review_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_reviews,
    ROUND(AVG(DATEDIFF('day',
        o.order_purchase_timestamp,
        r.review_creation_date)), 1)                   AS avg_days_to_review
FROM order_reviews r
JOIN orders o ON r.order_id = o.order_id
GROUP BY review_score
ORDER BY review_score;


-- ─────────────────────────────────────────────
-- 2. DELIVERY DELAY vs. REVIEW SCORE
--    Core hypothesis: late orders = bad reviews
-- ─────────────────────────────────────────────
WITH delivery_review AS (
    SELECT
        o.order_id,
        r.review_score,
        DATEDIFF('day',
            o.order_estimated_delivery_date,
            o.order_delivered_customer_date)  AS delay_days,
        DATEDIFF('day',
            o.order_purchase_timestamp,
            o.order_delivered_customer_date)  AS actual_delivery_days,
        CASE
            WHEN o.order_delivered_customer_date
                 <= o.order_estimated_delivery_date THEN 'On Time / Early'
            WHEN DATEDIFF('day',
                 o.order_estimated_delivery_date,
                 o.order_delivered_customer_date) BETWEEN 1 AND 3  THEN 'Late 1-3 days'
            WHEN DATEDIFF('day',
                 o.order_estimated_delivery_date,
                 o.order_delivered_customer_date) BETWEEN 4 AND 7  THEN 'Late 4-7 days'
            WHEN DATEDIFF('day',
                 o.order_estimated_delivery_date,
                 o.order_delivered_customer_date) BETWEEN 8 AND 14 THEN 'Late 8-14 days'
            ELSE 'Late 15+ days'
        END AS delay_bucket
    FROM orders o
    JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    delay_bucket,
    COUNT(*)                            AS order_count,
    ROUND(AVG(review_score), 3)         AS avg_review_score,
    SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS low_score_count,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                AS low_score_pct,
    SUM(CASE WHEN review_score  = 5 THEN 1 ELSE 0 END) AS five_star_count,
    ROUND(SUM(CASE WHEN review_score  = 5 THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                AS five_star_pct
FROM delivery_review
GROUP BY delay_bucket
ORDER BY
    CASE delay_bucket
        WHEN 'On Time / Early'   THEN 1
        WHEN 'Late 1-3 days'     THEN 2
        WHEN 'Late 4-7 days'     THEN 3
        WHEN 'Late 8-14 days'    THEN 4
        WHEN 'Late 15+ days'     THEN 5
    END;


-- ─────────────────────────────────────────────
-- 3. PERCENTAGE OF ORDERS WITH REVIEWS < 3 STARS
-- ─────────────────────────────────────────────
SELECT
    COUNT(*)                                                        AS total_reviewed_orders,
    SUM(CASE WHEN r.review_score < 3  THEN 1 ELSE 0 END)           AS below_3_star,
    SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)           AS one_or_two_star,
    SUM(CASE WHEN r.review_score = 1  THEN 1 ELSE 0 END)           AS one_star,
    ROUND(SUM(CASE WHEN r.review_score < 3 THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                                   AS pct_below_3_stars,
    ROUND(SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                                   AS pct_one_star
FROM order_reviews r
JOIN orders o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';


-- ─────────────────────────────────────────────
-- 4. PRODUCT CATEGORIES WITH LOWEST AVG RATINGS
-- ─────────────────────────────────────────────
WITH category_reviews AS (
    SELECT
        COALESCE(p.product_category_name, 'unknown') AS category,
        r.review_score,
        COUNT(*)                                       AS review_count,
        AVG(r.review_score)                            AS avg_score
    FROM order_reviews r
    JOIN orders o        ON r.order_id  = o.order_id
    JOIN order_items oi  ON o.order_id  = oi.order_id
    JOIN products p      ON oi.product_id = p.product_id
    WHERE o.order_status = 'delivered'
    GROUP BY COALESCE(p.product_category_name, 'unknown'), r.review_score
)
SELECT
    category,
    COUNT(*)                                AS total_reviews,
    ROUND(AVG(review_score), 3)             AS avg_review_score,
    SUM(CASE WHEN review_score <= 2 THEN review_count ELSE 0 END) AS low_reviews,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN review_count ELSE 0 END)
          * 100.0 / SUM(review_count), 2)   AS low_score_rate_pct,
    RANK() OVER (ORDER BY AVG(review_score) ASC) AS worst_category_rank
FROM category_reviews
GROUP BY category
HAVING COUNT(*) >= 50
ORDER BY avg_review_score ASC
LIMIT 15;


-- ─────────────────────────────────────────────
-- 5. SELLER-LEVEL REVIEW PERFORMANCE
--    Sellers with worst review scores
-- ─────────────────────────────────────────────
SELECT
    oi.seller_id,
    s.seller_state,
    COUNT(DISTINCT r.order_id)              AS reviewed_orders,
    ROUND(AVG(r.review_score), 3)           AS avg_review_score,
    SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) AS low_score_orders,
    ROUND(SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                    AS low_score_pct,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                        > o.order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                    AS late_delivery_pct,
    RANK() OVER (ORDER BY AVG(r.review_score) ASC) AS worst_seller_rank
FROM order_reviews r
JOIN orders o        ON r.order_id  = o.order_id
JOIN order_items oi  ON o.order_id  = oi.order_id
JOIN sellers s       ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY oi.seller_id, s.seller_state
HAVING COUNT(DISTINCT r.order_id) >= 20
ORDER BY avg_review_score ASC
LIMIT 50;


-- ─────────────────────────────────────────────
-- 6. ORDER PRICE BUCKET vs. REVIEW SCORE
--    Do expensive orders get better/worse reviews?
-- ─────────────────────────────────────────────
WITH order_totals AS (
    SELECT
        o.order_id,
        r.review_score,
        SUM(oi.price)                     AS order_value,
        CASE
            WHEN SUM(oi.price) < 50    THEN 'Under R$50'
            WHEN SUM(oi.price) < 150   THEN 'R$50–149'
            WHEN SUM(oi.price) < 300   THEN 'R$150–299'
            WHEN SUM(oi.price) < 500   THEN 'R$300–499'
            ELSE                            'R$500+'
        END AS price_bucket
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, r.review_score
)
SELECT
    price_bucket,
    COUNT(*)                            AS order_count,
    ROUND(AVG(review_score), 3)         AS avg_review_score,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                AS low_score_pct
FROM order_totals
GROUP BY price_bucket
ORDER BY
    CASE price_bucket
        WHEN 'Under R$50'  THEN 1
        WHEN 'R$50–149'    THEN 2
        WHEN 'R$150–299'   THEN 3
        WHEN 'R$300–499'   THEN 4
        WHEN 'R$500+'      THEN 5
    END;


-- ─────────────────────────────────────────────
-- 7. REVIEW SCORE TREND OVER TIME
-- ─────────────────────────────────────────────
SELECT
    DATE_TRUNC('month', r.review_creation_date)   AS review_month,
    COUNT(*)                                       AS review_count,
    ROUND(AVG(r.review_score), 3)                  AS avg_score,
    SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END) AS five_star,
    SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END) AS one_star,
    ROUND(SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                           AS low_score_pct,
    -- MoM change in average score
    ROUND(AVG(r.review_score) -
          LAG(AVG(r.review_score)) OVER
          (ORDER BY DATE_TRUNC('month', r.review_creation_date)), 3) AS mom_score_change
FROM order_reviews r
GROUP BY DATE_TRUNC('month', r.review_creation_date)
ORDER BY review_month;
