-- 05_baseline_comparison.sql
-- Compares the latest period against analytics.historical_baseline, and
-- documents/quantifies temporal leakage in that table. Run 00_setup.sql and
-- 02_trusted_views.sql first.

-- Q1. Characterize the baseline's construction: observation_count per month
-- matches exactly the number of times each weekday occurs in a SINGLE
-- calendar year 2025 (e.g. Feb has min=max=4 for every weekday, matching
-- 28 days / 7 exactly). This rules out multi-year pooling and confirms the
-- baseline is a single-year-2025, same-4-areas construction.
SELECT month_of_year, AVG(observation_count) AS avg_obs, MIN(observation_count) AS min_obs, MAX(observation_count) AS max_obs
FROM src.analytics.historical_baseline
GROUP BY 1 ORDER BY 1;

-- Q2. Direct evidence of leakage for month=4 (April): the baseline's own
-- April Monday-9am observations for area 24 are close to our actual measured
-- Monday value, and April's observation_count (4) means ALL FOUR April
-- Mondays -- including the ones inside our own delivery window -- are baked
-- into that bucket's average. Comparing our "latest period" against the
-- April baseline is therefore comparing our data against itself, not against
-- an independent expectation.
SELECT COUNT(*) AS actual_cnt
FROM trusted_trips
WHERE pickup_community_area = 24
  AND EXTRACT(month FROM trip_start_timestamp) = 4
  AND EXTRACT(isodow FROM trip_start_timestamp) = 1
  AND EXTRACT(hour FROM trip_start_timestamp) = 9;

SELECT avg_trip_count, observation_count
FROM src.analytics.historical_baseline
WHERE month_of_year = 4 AND day_of_week = 1 AND hour_of_day = 9 AND pickup_community_area = 24;

-- Q3. PRIMARY baseline comparison used in this analysis: latest period
-- (2025-04-21 to 2025-04-27, the most recent complete Mon-Sun week enabled by
-- the incremental delivery) vs the MARCH (month=3) baseline. March shares no
-- calendar dates with the evaluated week, so this avoids the direct-overlap
-- leakage in Q2 -- it is read as "vs. the prior month's typical weekday/hour
-- pattern", not a perfectly independent benchmark (the source is still the
-- same restricted 4-area 2025 extract).
WITH latest_week AS (
    SELECT pickup_community_area, COUNT(DISTINCT trip_id) AS trip_volume
    FROM trusted_trips
    WHERE trip_start_timestamp >= DATE '2025-04-21' AND trip_start_timestamp < DATE '2025-04-28'
    GROUP BY 1
),
march_baseline_week AS (
    -- sum of median_trip_count across every weekday x hour bucket approximates
    -- one typical 7-day week under the March pattern.
    SELECT pickup_community_area, SUM(median_trip_count) AS baseline_week_volume
    FROM src.analytics.historical_baseline
    WHERE month_of_year = 3
    GROUP BY 1
)
SELECT
    l.pickup_community_area,
    l.trip_volume                                                         AS latest_week_volume,
    ROUND(m.baseline_week_volume, 0)                                      AS march_typical_week_volume,
    ROUND(100.0 * (l.trip_volume - m.baseline_week_volume) / m.baseline_week_volume, 1) AS pct_vs_march_typical
FROM latest_week l
JOIN march_baseline_week m USING (pickup_community_area)
ORDER BY 1;

-- Q4. Clean, leakage-free cross-check: week-over-week trend using only our
-- own observed trip-level data (no baseline table involved at all).
SELECT
    date_trunc('week', trip_start_timestamp) AS week_start,
    pickup_community_area,
    COUNT(DISTINCT trip_id) AS trip_volume
FROM trusted_trips
GROUP BY 1, 2
ORDER BY 1, 2;
