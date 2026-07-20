WITH feature_usage AS (
    SELECT * FROM {{ ref('feature_usage') }}
)
SELECT
    usage_id,
    subscription_id,
    usage_date,
    feature_name,
    usage_count,
    usage_duration_secs,
    error_count,
    is_beta_feature
FROM feature_usage
