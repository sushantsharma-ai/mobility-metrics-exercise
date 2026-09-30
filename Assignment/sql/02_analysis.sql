-- 02_analysis.sql
-- The actual analysis: why the two dashboards disagree, the canonical
-- metrics built on the trusted trip universe from 01_cleaning_and_checks.sql,
-- the latest period against a historical baseline, and a check on how much
-- the definition choices actually matter. Run 01_cleaning_and_checks.sql
-- first in the same connection.

-- Start simple. Does an unfiltered count of trips per week and area match
-- dashboard A exactly.
WITH recomputed_a AS (
    SELECT
        date_trunc('week', trip_start_timestamp) AS week_start,
        pickup_community_area,
        COUNT(*) AS trip_count,
        AVG(fare) AS avg_trip_price,
        AVG(CASE WHEN shared_trip_authorized THEN 1.0 ELSE 0.0 END) AS shared_trip_rate
    FROM src.raw.trips_initial
    GROUP BY 1, 2
)
SELECT
    MAX(ABS(r.trip_count - a.trip_count)) AS max_count_diff,
    MAX(ABS(r.avg_trip_price - a.avg_trip_price)) AS max_price_diff
FROM recomputed_a r
JOIN src.reporting.dashboard_a_weekly a USING (week_start, pickup_community_area);

-- That comes back at zero difference, so dashboard A is every trip, base
-- fare as the price, and a shared trip means the rider opted in. Dashboard
-- B's counts are lower and not by the same amount in every area, which
-- points at a filter tied to something that is missing more often in some
-- areas than others. Dropoff location was the obvious guess given the
-- pattern already seen in the cleaning file, so test it directly: recompute
-- B's numbers using only trips with a known dropoff, and using trip_total
-- and shared_trip_match instead of fare and shared_trip_authorized.
WITH recomputed_b AS (
    SELECT
        date_trunc('week', trip_start_timestamp) AS week_start,
        pickup_community_area,
        COUNT(*) AS trip_count,
        AVG(trip_total) AS avg_trip_price,
        AVG(CASE WHEN shared_trip_match THEN 1.0 ELSE 0.0 END) AS shared_trip_rate
    FROM src.raw.trips_initial
    WHERE dropoff_community_area IS NOT NULL
    GROUP BY 1, 2
)
SELECT
    MIN(100.0 * (r.trip_count - b.trip_count) / b.trip_count) AS min_pct_off,
    MAX(100.0 * (r.trip_count - b.trip_count) / b.trip_count) AS max_pct_off
FROM recomputed_b r
JOIN src.reporting.dashboard_b_weekly b USING (week_start, pickup_community_area);

-- That comes back within a fraction of a percent everywhere, close enough
-- to call it confirmed: dashboard B only counts trips with a known dropoff,
-- prices on the full amount the rider paid, and counts a trip as shared
-- only when the rider was actually matched with someone else, not just
-- authorized. Three separate, undocumented choices stacked together, not
-- one bug.

-- Canonical trusted metrics, built on the trusted_trips view from the
-- cleaning file. Trip volume counts every trusted trip regardless of
-- whether the dropoff is known, since a missing dropoff is a geocoding gap
-- and not proof the trip did not happen, and it is missing far more often
-- for Garfield Ridge than anywhere else. Average price uses trip_total,
-- the full amount the rider paid, since that is the economically relevant
-- figure for a resource costing audience. The shared trip rate uses
-- shared_trip_match, meaning the rider was actually matched, which is the
-- more conservative and operationally meaningful of the two candidate
-- definitions.
CREATE OR REPLACE VIEW trusted_weekly_metrics AS
SELECT
    date_trunc('week', trip_start_timestamp) AS week_start,
    pickup_community_area,
    COUNT(DISTINCT trip_id) AS trip_volume,
    AVG(trip_total) AS avg_trip_price,
    AVG(CASE WHEN shared_trip_match THEN 1.0 ELSE 0.0 END) AS shared_trip_rate,
    COUNT(*) FILTER (WHERE trip_total IS NULL) AS price_excluded_null_total
FROM trusted_trips
GROUP BY 1, 2;

SELECT c.community_area_name, t.week_start,
       t.trip_volume, ROUND(t.avg_trip_price, 2) AS avg_trip_price, ROUND(t.shared_trip_rate, 3) AS shared_trip_rate
FROM trusted_weekly_metrics t
JOIN src.reference.community_areas c ON t.pickup_community_area = c.community_area_id
ORDER BY 1, 2;

-- Before comparing the latest period against the historical_baseline
-- table, check whether that table is actually an independent benchmark or
-- partly built from the same period being evaluated. Its observation
-- count per month only makes sense if it comes from a single calendar
-- year: February shows exactly four for every weekday, which is 28 days
-- divided by 7 and only works for one year, not several pooled together.
SELECT month_of_year, AVG(observation_count) AS avg_observation_count
FROM src.analytics.historical_baseline
GROUP BY 1 ORDER BY 1;

-- Confirming the leakage directly for April: there are three April Mondays
-- in the data we actually have, at 517, 510, and 501 trips for the nine am
-- hour in West Town, averaging 509. The baseline table's own figure for
-- that exact bucket is 495.75, within three percent of that average, which
-- is close enough to say the baseline was built from the same days we are
-- trying to evaluate, not an independent period.
SELECT CAST(trip_start_timestamp AS DATE) AS trip_date, COUNT(*) AS n
FROM trusted_trips
WHERE pickup_community_area = 24
  AND EXTRACT(month FROM trip_start_timestamp) = 4
  AND EXTRACT(isodow FROM trip_start_timestamp) = 1
  AND EXTRACT(hour FROM trip_start_timestamp) = 9
GROUP BY 1 ORDER BY 1;

SELECT avg_trip_count, observation_count
FROM src.analytics.historical_baseline
WHERE month_of_year = 4 AND day_of_week = 1 AND hour_of_day = 9 AND pickup_community_area = 24;

-- So March is used instead as the baseline for the latest period, April 21
-- through 27, since it shares no calendar dates with the week being
-- evaluated.
WITH latest_week AS (
    SELECT pickup_community_area, COUNT(DISTINCT trip_id) AS trip_volume
    FROM trusted_trips
    WHERE trip_start_timestamp >= DATE '2025-04-21' AND trip_start_timestamp < DATE '2025-04-28'
    GROUP BY 1
),
march_baseline_week AS (
    SELECT pickup_community_area, SUM(median_trip_count) AS baseline_week_volume
    FROM src.analytics.historical_baseline
    WHERE month_of_year = 3
    GROUP BY 1
)
SELECT c.community_area_name,
       l.trip_volume AS latest_week_volume,
       ROUND(m.baseline_week_volume, 0) AS march_typical_week_volume,
       ROUND(100.0 * (l.trip_volume - m.baseline_week_volume) / m.baseline_week_volume, 1) AS pct_vs_march_typical
FROM latest_week l
JOIN march_baseline_week m USING (pickup_community_area)
JOIN src.reference.community_areas c ON l.pickup_community_area = c.community_area_id
ORDER BY 1;

-- Last question: how much would the story change under each measure's
-- alternative, dashboard A style definition. Fare only instead of
-- trip_total for price, and shared_trip_authorized instead of
-- shared_trip_match for the shared rate.
SELECT
    c.community_area_name,
    t.week_start,
    t.avg_trip_price AS canonical_avg_price,
    alt.avg_fare AS alt_avg_price_fare_only,
    ROUND(100.0 * (t.avg_trip_price - alt.avg_fare) / alt.avg_fare, 1) AS pct_higher_under_canonical,
    t.shared_trip_rate AS canonical_shared_rate,
    alt.shared_authorized_rate AS alt_shared_rate_authorized,
    ROUND(100.0 * (alt.shared_authorized_rate - t.shared_trip_rate) / NULLIF(t.shared_trip_rate, 0), 1) AS pct_higher_under_alt
FROM trusted_weekly_metrics t
JOIN src.reference.community_areas c ON t.pickup_community_area = c.community_area_id
JOIN (
    SELECT
        date_trunc('week', trip_start_timestamp) AS week_start,
        pickup_community_area,
        AVG(fare) AS avg_fare,
        AVG(CASE WHEN shared_trip_authorized THEN 1.0 ELSE 0.0 END) AS shared_authorized_rate
    FROM trusted_trips
    GROUP BY 1, 2
) alt ON t.week_start = alt.week_start AND t.pickup_community_area = alt.pickup_community_area
ORDER BY 1, 2;

-- Check 3 of 3, picking up from the cleaning file: no week and area bucket
-- should end up with every single trip_total value missing, which would
-- silently turn an average into a divide by zero.
SELECT CASE WHEN SUM(CASE WHEN price_excluded_null_total >= trip_volume THEN 1 ELSE 0 END) = 0
            THEN 'pass' ELSE 'fail' END AS no_empty_price_bucket_check,
       COUNT(*) AS n_buckets_checked
FROM trusted_weekly_metrics;
