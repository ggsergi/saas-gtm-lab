WITH churn_events AS (
    SELECT * FROM {{ ref('churn_events') }}
)
SELECT
    churn_event_id,
    account_id,
    churn_date,
    reason_code,
    refund_amount_usd,
    preceding_upgrade_flag,
    preceding_downgrade_flag,
    is_reactivation,
    feedback_text
FROM churn_events
