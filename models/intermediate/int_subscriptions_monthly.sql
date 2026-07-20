{{
  config(
    materialized = 'table'
  )
}}

WITH subscriptions AS (
    SELECT * FROM {{ ref('stg_ravenstack__subscriptions') }}
),

-- Snapshot cutoff for the dataset: subscriptions with a NULL end_date are
-- treated as active through this date, not through the real "today".
months AS (
    SELECT CAST(t AS DATE) AS month_start
    FROM generate_series(
        (SELECT DATE_TRUNC('month', MIN(start_date)) FROM subscriptions),
        DATE_TRUNC('month', CAST('{{ var("retention_as_of_date") }}' AS DATE)),
        INTERVAL 1 MONTH
    ) AS t(t)
),

-- All subscriptions whose own date range covers the month (this still
-- contains overlaps: see the SCD note in _intermediate.yml).
active_in_month AS (
    SELECT
        m.month_start,
        s.subscription_id,
        s.account_id,
        s.plan_tier,
        s.mrr_amount,
        s.seats,
        s.churn_flag,
        s.start_date,
        s.end_date
    FROM months AS m
    INNER JOIN subscriptions AS s
        ON s.start_date <= (m.month_start + INTERVAL 1 MONTH - INTERVAL 1 DAY)
        AND (s.end_date IS NULL OR s.end_date >= m.month_start)
),

-- Resolve overlaps: per account per month, the subscription with the most
-- recent start_date wins (see _intermediate.yml for why).
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY account_id, month_start
            ORDER BY start_date DESC
        ) AS rn
    FROM active_in_month
)

SELECT
    month_start,
    account_id,
    subscription_id,
    plan_tier,
    mrr_amount,
    seats,
    churn_flag,
    start_date,
    end_date
FROM ranked
WHERE rn = 1
