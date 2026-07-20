WITH snapshot AS (
    SELECT
        s.month_start,
        s.account_id,
        s.plan_tier,
        s.mrr_amount,
        a.industry,
        a.country
    FROM {{ ref('int_subscriptions_monthly') }} AS s
    INNER JOIN {{ ref('dim_accounts') }} AS a
        ON a.account_id = s.account_id
),

-- Cohort = accounts present in month M-1. industry/country/plan_tier are
-- pinned to their M-1 ("starting") values so plan/segment migrations don't
-- get misread as churn in one segment and new business in another.
cohort AS (
    SELECT
        prior.month_start + INTERVAL 1 MONTH AS metric_month,
        prior.account_id,
        prior.industry,
        prior.country,
        prior.plan_tier,
        prior.mrr_amount AS starting_mrr,
        curr.mrr_amount AS ending_mrr,
        (curr.account_id IS NULL) AS churned_flag
    FROM snapshot AS prior
    LEFT JOIN snapshot AS curr
        ON curr.account_id = prior.account_id
        AND curr.month_start = prior.month_start + INTERVAL 1 MONTH
    -- the most recent month has no "next" month to evaluate yet (right-censored)
    WHERE prior.month_start < (SELECT MAX(month_start) FROM snapshot)
)

SELECT
    metric_month,
    industry,
    country,
    plan_tier,
    COUNT(*) AS starting_accounts,
    SUM(starting_mrr) AS starting_mrr,
    SUM(COALESCE(ending_mrr, 0)) AS ending_mrr,
    SUM(COALESCE(ending_mrr, 0)) / NULLIF(SUM(starting_mrr), 0) AS nrr,
    SUM(CASE WHEN churned_flag THEN 1 ELSE 0 END) AS churned_accounts,
    SUM(CASE WHEN churned_flag THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS churn_rate_accounts,
    SUM(CASE WHEN churned_flag THEN starting_mrr ELSE 0 END) AS churned_mrr,
    SUM(CASE WHEN churned_flag THEN starting_mrr ELSE 0 END) / NULLIF(SUM(starting_mrr), 0) AS churn_rate_mrr
FROM cohort
GROUP BY metric_month, industry, country, plan_tier
