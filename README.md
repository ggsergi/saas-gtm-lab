# saas-gtm-lab

Analytics Engineering portfolio project: dbt customer retention modeling (NRR, churn) on a synthetic B2B SaaS dataset, using DuckDB as a local warehouse.

Built as directed practice for a **GTM Analytics Engineer** role — the goal wasn't just writing SQL, but applying the same kind of business reasoning that role demands: questioning data before trusting it, documenting decisions and limitations, and prioritizing data reliability over apparent completeness.

## Stack

- **Transformation:** dbt-core + dbt-duckdb
- **Warehouse:** DuckDB (local, no credentials)
- **Environment management:** uv
- **Tests:** dbt_utils + dbt_expectations
- **Source dataset:** [RavenStack Synthetic SaaS Dataset](https://www.kaggle.com/datasets/rivalytics/saas-subscription-and-churn-analytics-dataset) (River @ Rivalytics) — 5 relational tables: accounts, subscriptions, feature_usage, support_tickets, churn_events

## Architecture

```
seeds/                          → original CSVs loaded via dbt seed
models/
  staging/
    stg_ravenstack__accounts.sql
    stg_ravenstack__subscriptions.sql
    stg_ravenstack__feature_usage.sql
    stg_ravenstack__support_tickets.sql
    stg_ravenstack__churn_events.sql
  marts/
    dim_accounts.sql
    fct_subscriptions.sql
    fct_feature_usage.sql
    fct_support_tickets.sql
    fct_churn_events.sql
    int_subscriptions_monthly.sql     → monthly snapshot of the active subscription
    mart_retention_monthly.sql        → NRR and churn rate by month/industry/country/plan
    mart_churn_profile.sql            → churn profile by reason_code and prior downgrade
```

60 tests in total (dbt_utils + dbt_expectations), including `unique`, `not_null`, `relationships`, `accepted_values`, `equal_rowcount` and value-range checks.

## Modeling decisions and real findings

This project was built on the premise that **before interpreting a number, you have to confirm the data behind it is trustworthy**. Several discrepancies between what the dataset documented and what the actual data showed came up during modeling — documented here rather than hidden:

### 1. Composite key in `feature_usage`
The `usage_id` field, documented as the event's unique identifier, had 21 duplicate values pointing to genuinely different events (different subscription, date, and feature). This was investigated before assuming it was noise: the real unique key is the combination `(usage_id, subscription_id)`, not `usage_id` alone. The test was adjusted using `dbt_utils.unique_combination_of_columns` instead of silencing the failure with `severity: warn`.

### 2. Overlapping subscriptions and SCD-style reconstruction
90% of rows in `subscriptions` had a null `end_date`, averaging 10 rows per account — a literal interpretation ("every row without an `end_date` is active at once") would have inflated total MRR by 8x compared to treating each row as a version superseded by the next. The decision was to reconstruct monthly MRR as an SCD-style snapshot (`int_subscriptions_monthly`): for each account and month, the subscription with the most recent `start_date` in effect that month is used, treating earlier ones as obsolete. dbt's native `snapshot` function wasn't used because the full history was already loaded at once — there was no need to capture changes across successive pipeline runs.

### 3. `churn_events` and `fct_subscriptions` can't be joined with confidence
Only 7 of 601 churn events match an exact subscription end date; even relaxing the condition, 36% find no match at all. Additionally, `dim_accounts.churn_flag` is inconsistent with the events table (110 accounts flagged vs. 352 distinct accounts with an actual churn event). For this reason, **`mart_churn_profile` excludes lost MRR and plan_tier** — it only exposes what's 100% traceable directly from `churn_events` (counts, `reason_code`, `preceding_downgrade_flag`). Omitting a metric that a board deck could misread as exact was preferred over approximating it with a low-confidence join.

### 4. NRR noise at very fine-grained cuts
At the month × industry × country × plan_tier level, very small cohorts (a single account) can produce NRR values that are mathematically correct but extreme (e.g. 209%) due to the effect of one account's MRR changing. Explicitly documented in the model: NRR aggregated at the whole-table level (~100.4%) is the reliable read; very fine-grained cuts are expected sample-size noise, not a real business signal.

### 5. Model contracts on the final marts
`mart_retention_monthly` and `mart_churn_profile` have `contract: enforced: true`, with data types explicitly declared per column. Applying the contract revealed that DuckDB was automatically widening some types at runtime (`TIMESTAMP` instead of `DATE` when adding date intervals; `HUGEINT` instead of `BIGINT` on `SUM()` aggregations). Explicit casts were added in the SQL so the declared contract type matched the actual runtime type exactly, guaranteeing that any consumer (dashboard or AI layer) always receives the expected schema without surprises.

## How to run it

```bash
uv sync
DBT_PROFILES_DIR=. uv run dbt deps
DBT_PROFILES_DIR=. uv run dbt seed
DBT_PROFILES_DIR=. uv run dbt run
DBT_PROFILES_DIR=. uv run dbt test
DBT_PROFILES_DIR=. uv run dbt docs generate
DBT_PROFILES_DIR=. uv run dbt docs serve
```

## Context

Built with [Claude Code](https://claude.com/claude-code) as an implementation copilot, with modeling decisions reviewed and supervised at every step — the goal of this project wasn't just a working pipeline, but practicing the business judgment (which data is reliable, what should be documented as a limitation, what should be left out of a dashboard rather than shipping a misleading number) that a GTM Analytics Engineer role demands.
