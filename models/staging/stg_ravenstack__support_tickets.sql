WITH support_tickets AS (
    SELECT * FROM {{ ref('support_tickets') }}
)
SELECT
    ticket_id,
    account_id,
    submitted_at,
    closed_at,
    resolution_time_hours,
    priority,
    first_response_time_minutes,
    satisfaction_score,
    escalation_flag
FROM support_tickets
