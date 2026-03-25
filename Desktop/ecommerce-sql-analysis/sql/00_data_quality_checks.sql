-- ============================================================
-- 00_DATA_QUALITY_CHECKS.SQL
-- Olist E-Commerce | Phase 1: Data Exploration & Quality
-- ============================================================

-- ─────────────────────────────────────────────
-- 1. ROW COUNTS FOR ALL 8 TABLES
-- ─────────────────────────────────────────────
SELECT 'orders'            AS table_name, COUNT(*) AS row_count FROM orders
UNION ALL
SELECT 'order_items',                     COUNT(*) FROM order_items
UNION ALL
SELECT 'customers',                       COUNT(*) FROM customers
UNION ALL
SELECT 'sellers',                         COUNT(*) FROM sellers
UNION ALL
SELECT 'products',                        COUNT(*) FROM products
UNION ALL
SELECT 'order_payments',                  COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews',                   COUNT(*) FROM order_reviews
UNION ALL
SELECT 'geolocation',                     COUNT(*) FROM geolocation
ORDER BY row_count DESC;


-- ─────────────────────────────────────────────
-- 2. DATE RANGE & ORDER STATUS DISTRIBUTION
-- ─────────────────────────────────────────────
SELECT
    MIN(order_purchase_timestamp)   AS earliest_order,
    MAX(order_purchase_timestamp)   AS latest_order,
    DATEDIFF('day',
        MIN(order_purchase_timestamp),
        MAX(order_purchase_timestamp))  AS date_span_days,
    COUNT(DISTINCT order_id)        AS total_orders
FROM orders;

SELECT
    order_status,
    COUNT(*)                        AS order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;


-- ─────────────────────────────────────────────
-- 3. NULL AUDIT — ORDERS TABLE
-- ─────────────────────────────────────────────
SELECT
    COUNT(*)                                        AS total_rows,
    SUM(CASE WHEN order_id                IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN customer_id             IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN order_status            IS NULL THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS null_purchase_ts,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS null_delivered_date,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS null_estimated_date
FROM orders;


-- ─────────────────────────────────────────────
-- 4. NULL AUDIT — ORDER_ITEMS TABLE
-- ─────────────────────────────────────────────
SELECT
    COUNT(*)                                            AS total_rows,
    SUM(CASE WHEN order_id    IS NULL THEN 1 ELSE 0 END) AS null_order_id,
    SUM(CASE WHEN product_id  IS NULL THEN 1 ELSE 0 END) AS null_product_id,
    SUM(CASE WHEN seller_id   IS NULL THEN 1 ELSE 0 END) AS null_seller_id,
    SUM(CASE WHEN price       IS NULL THEN 1 ELSE 0 END) AS null_price,
    SUM(CASE WHEN freight_value IS NULL THEN 1 ELSE 0 END) AS null_freight
FROM order_items;


-- ─────────────────────────────────────────────
-- 5. ORPHAN ORDERS — no matching payment record
-- ─────────────────────────────────────────────
SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp
FROM orders o
LEFT JOIN order_payments op ON o.order_id = op.order_id
WHERE op.order_id IS NULL
ORDER BY o.order_purchase_timestamp DESC;


-- ─────────────────────────────────────────────
-- 6. ORPHAN ORDERS — delivered but no delivery date
-- ─────────────────────────────────────────────
SELECT
    COUNT(*) AS delivered_missing_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;


-- ─────────────────────────────────────────────
-- 7. DUPLICATE ORDER CHECKS
-- ─────────────────────────────────────────────
SELECT order_id, COUNT(*) AS cnt
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;


-- ─────────────────────────────────────────────
-- 8. JOIN KEY VALIDATION
--    Confirm referential integrity across tables
-- ─────────────────────────────────────────────
-- Items with no matching order
SELECT COUNT(*) AS items_missing_order
FROM order_items oi
LEFT JOIN orders o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- Items with no matching product
SELECT COUNT(*) AS items_missing_product
FROM order_items oi
LEFT JOIN products p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Items with no matching seller
SELECT COUNT(*) AS items_missing_seller
FROM order_items oi
LEFT JOIN sellers s ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL;


-- ─────────────────────────────────────────────
-- 9. PRODUCT CATEGORY COVERAGE
-- ─────────────────────────────────────────────
SELECT
    product_category_name,
    COUNT(*) AS product_count
FROM products
GROUP BY product_category_name
ORDER BY product_count DESC
LIMIT 20;

SELECT
    SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) AS null_categories,
    COUNT(*) AS total_products,
    ROUND(SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS null_pct
FROM products;


-- ─────────────────────────────────────────────
-- 10. PRICE DISTRIBUTION SANITY CHECK
-- ─────────────────────────────────────────────
SELECT
    MIN(price)                              AS min_price,
    MAX(price)                              AS max_price,
    AVG(price)                              AS avg_price,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY price) AS p95_price,
    SUM(CASE WHEN price <= 0 THEN 1 ELSE 0 END) AS zero_or_neg_price
FROM order_items;
