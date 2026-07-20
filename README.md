[README.md](https://github.com/user-attachments/files/30195124/README.md)
# saas-gtm-lab

Proyecto de portfolio de Analytics Engineering: modelado dbt de retención de clientes (NRR, churn) sobre un dataset sintético de SaaS B2B, usando DuckDB como warehouse local.

Construido como práctica dirigida a un puesto de **GTM Analytics Engineer** — el objetivo no era solo escribir SQL, sino aplicar el mismo tipo de razonamiento de negocio que ese rol exige: cuestionar los datos antes de confiar en ellos, documentar decisiones y limitaciones, y priorizar la fiabilidad del dato sobre la completitud aparente.

## Stack

- **Transformación:** dbt-core + dbt-duckdb
- **Warehouse:** DuckDB (local, sin credenciales)
- **Gestión de entorno:** uv
- **Tests:** dbt_utils + dbt_expectations
- **Dataset fuente:** [RavenStack Synthetic SaaS Dataset](https://www.kaggle.com/datasets/rivalytics/saas-subscription-and-churn-analytics-dataset) (River @ Rivalytics) — 5 tablas relacionales: accounts, subscriptions, feature_usage, support_tickets, churn_events

## Arquitectura

```
seeds/                          → CSVs originales cargados vía dbt seed
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
    int_subscriptions_monthly.sql     → snapshot mensual de suscripción vigente
    mart_retention_monthly.sql        → NRR y churn rate por mes/industry/país/plan
    mart_churn_profile.sql            → perfil de churn por reason_code y downgrade previo
```

60 tests en total (dbt_utils + dbt_expectations), incluyendo `unique`, `not_null`, `relationships`, `accepted_values`, `equal_rowcount` y rangos de valores.

## Decisiones de modelado y hallazgos reales

Este proyecto se construyó siguiendo la premisa de que **antes de interpretar un número, hay que confirmar que el dato que lo sostiene es fiable**. Durante el modelado surgieron varias discrepancias entre lo que documentaba el dataset y lo que mostraban los datos reales — se documentan aquí en vez de ocultarlas:

### 1. Clave compuesta en `feature_usage`
El campo `usage_id`, documentado como identificador único del evento, tenía 21 valores duplicados apuntando a eventos genuinamente distintos (distinta suscripción, fecha y feature). Se investigó antes de asumir que era ruido: la clave única real es la combinación `(usage_id, subscription_id)`, no `usage_id` en solitario. El test se ajustó con `dbt_utils.unique_combination_of_columns` en vez de silenciar el fallo con `severity: warn`.

### 2. Suscripciones solapadas y reconstrucción tipo SCD
El 90% de las filas de `subscriptions` tenían `end_date` nulo, con una media de 10 filas por cuenta — una interpretación literal ("todas las filas sin `end_date` están activas a la vez") habría inflado el MRR total en 8x frente a tratar cada fila como una versión reemplazada por la siguiente. Se optó por reconstruir el MRR mensual como un snapshot tipo SCD (`int_subscriptions_monthly`): para cada cuenta y mes, se toma la suscripción con `start_date` más reciente vigente ese mes, tratando las anteriores como obsoletas. No se usó la función `dbt snapshot` nativa porque el histórico completo ya venía cargado de una vez — no había que capturar cambios entre ejecuciones sucesivas del pipeline.

### 3. `churn_events` y `fct_subscriptions` no son cruzables con confianza
Solo 7 de 601 eventos de churn coinciden con una fecha exacta de fin de suscripción; incluso relajando la condición, un 36% no encuentra ningún match. Además, `dim_accounts.churn_flag` es inconsistente con la tabla de eventos (110 cuentas marcadas vs. 352 cuentas distintas con evento de churn real). Por esta razón, **`mart_churn_profile` no incluye MRR perdido ni plan_tier** — solo expone lo que es 100% trazable desde `churn_events` directamente (conteos, `reason_code`, `preceding_downgrade_flag`). Se prefirió omitir una métrica que un board deck pudiera malinterpretar como exacta, antes que aproximarla con un join de baja confianza.

### 4. Ruido de NRR en cortes muy finos
A nivel de mes × industry × país × plan_tier, cohortes muy pequeñas (una sola cuenta) pueden producir valores de NRR matemáticamente correctos pero extremos (p. ej. 209%) debido al efecto de una única cuenta cambiando de MRR. Documentado explícitamente en el modelo: el NRR agregado a nivel de toda la tabla (~100.4%) es la lectura fiable; los cortes muy finos son ruido esperado de tamaño de muestra, no una señal de negocio real.

### 5. Contratos de modelo en los marts finales
`mart_retention_monthly` y `mart_churn_profile` tienen `contract: enforced: true`, con tipos de dato declarados explícitamente por columna. Al aplicar el contrato, se detectó que DuckDB ampliaba automáticamente algunos tipos en tiempo de ejecución (`TIMESTAMP` en vez de `DATE` al sumar intervalos de fecha; `HUGEINT` en vez de `BIGINT` en agregaciones `SUM()`). Se añadieron casts explícitos en el SQL para que el tipo declarado en el contrato coincidiera exactamente con el tipo real, garantizando que cualquier consumidor (dashboard o capa de IA) reciba siempre el esquema esperado sin sorpresas.

## Cómo correrlo

```bash
uv sync
DBT_PROFILES_DIR=. uv run dbt deps
DBT_PROFILES_DIR=. uv run dbt seed
DBT_PROFILES_DIR=. uv run dbt run
DBT_PROFILES_DIR=. uv run dbt test
DBT_PROFILES_DIR=. uv run dbt docs generate
DBT_PROFILES_DIR=. uv run dbt docs serve
```

## Contexto

Construido con [Claude Code](https://claude.com/claude-code) como copiloto de implementación, con revisión y decisiones de modelado supervisadas en cada paso — el objetivo del proyecto no era solo tener un pipeline funcionando, sino practicar el criterio de negocio (qué datos son fiables, qué se debe documentar como limitación, qué se debe dejar fuera de un dashboard antes que dar un número engañoso) que un rol de GTM Analytics Engineer exige.
