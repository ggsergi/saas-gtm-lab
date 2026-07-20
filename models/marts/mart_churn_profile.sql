-- MRR and plan_tier are deliberately excluded here: they would require
-- joining to fct_subscriptions by account_id + nearest date, which we
-- verified is unreliable (see _marts.yml for the numbers). Only churn_events
-- columns, which are 100% reliable, are used.
WITH churn_events AS (
    SELECT * FROM {{ ref('fct_churn_events') }}
)
SELECT
    reason_code,
    preceding_downgrade_flag,
    COUNT(*) AS churn_event_count,
    COUNT(DISTINCT account_id) AS distinct_account_count
FROM churn_events
GROUP BY reason_code, preceding_downgrade_flag
