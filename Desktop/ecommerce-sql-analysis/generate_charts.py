import psycopg2
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import getpass
import os

password = getpass.getpass("Enter your PostgreSQL password: ")

conn = psycopg2.connect(
    host="localhost", port=5432, database="olist",
    user="postgres", password=password
)

os.makedirs("outputs", exist_ok=True)

# --- Chart 1: RFM Segment Distribution ---
rfm_query = """
WITH rfm AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp)::date AS last_order,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(oi.price + oi.freight_value) AS monetary
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
scored AS (
    SELECT *,
        NTILE(4) OVER (ORDER BY last_order DESC) AS r_score,
        NTILE(4) OVER (ORDER BY frequency)        AS f_score,
        NTILE(4) OVER (ORDER BY monetary)         AS m_score
    FROM rfm
),
segments AS (
    SELECT *,
        CASE
            WHEN r_score = 4 AND f_score >= 3 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 2 THEN 'Loyal Customers'
            WHEN r_score >= 3 AND f_score = 1  THEN 'Potential Loyalists'
            WHEN r_score = 2                   THEN 'At Risk'
            ELSE 'Lost'
        END AS segment
    FROM scored
)
SELECT segment, COUNT(*) AS customer_count FROM segments GROUP BY segment ORDER BY customer_count DESC;
"""

df_rfm = pd.read_sql(rfm_query, conn)
fig, ax = plt.subplots(figsize=(10, 6))
colors = ['#2ecc71','#3498db','#f39c12','#e74c3c','#95a5a6']
bars = ax.barh(df_rfm['segment'], df_rfm['customer_count'], color=colors[:len(df_rfm)])
ax.set_xlabel('Number of Customers', fontsize=12)
ax.set_title('RFM Customer Segment Distribution', fontsize=14, fontweight='bold')
for bar, val in zip(bars, df_rfm['customer_count']):
    ax.text(bar.get_width() + 50, bar.get_y() + bar.get_height()/2,
            f'{val:,}', va='center', fontsize=10)
plt.tight_layout()
plt.savefig('outputs/rfm_segment_distribution.png', dpi=150)
plt.close()
print("✓ rfm_segment_distribution.png saved")

# --- Chart 2: Cohort Retention Matrix ---
cohort_query = """
WITH cohort AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', MIN(o.order_purchase_timestamp)) AS cohort_month,
        DATE_TRUNC('month', o.order_purchase_timestamp)      AS order_month
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, DATE_TRUNC('month', o.order_purchase_timestamp)
),
indexed AS (
    SELECT *,
        ROUND(EXTRACT(EPOCH FROM (order_month - cohort_month)) / 2592000) AS month_index
    FROM cohort
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_unique_id) AS cohort_size
    FROM indexed WHERE month_index = 0
    GROUP BY cohort_month
),
retention AS (
    SELECT i.cohort_month, i.month_index, COUNT(DISTINCT i.customer_unique_id) AS retained
    FROM indexed i
    GROUP BY i.cohort_month, i.month_index
)
SELECT r.cohort_month, r.month_index,
       ROUND(100.0 * r.retained / cs.cohort_size, 1) AS retention_rate
FROM retention r
JOIN cohort_sizes cs ON r.cohort_month = cs.cohort_month
WHERE r.cohort_month >= '2017-01-01' AND r.month_index <= 6
ORDER BY r.cohort_month, r.month_index;
"""

df_cohort = pd.read_sql(cohort_query, conn)
df_pivot = df_cohort.pivot(index='cohort_month', columns='month_index', values='retention_rate')
df_pivot.index = df_pivot.index.strftime('%Y-%m')

fig, ax = plt.subplots(figsize=(12, 8))
sns.heatmap(df_pivot, annot=True, fmt='.1f', cmap='YlGnBu',
            linewidths=0.5, ax=ax, cbar_kws={'label': 'Retention %'})
ax.set_title('Cohort Retention Matrix (% Retained by Month
Ctrl+C
cd ~/Desktop/ecommerce-sql-analysis
open -a TextEdit ~/Desktop/generate_charts.py
