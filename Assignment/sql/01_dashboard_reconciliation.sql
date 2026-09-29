-- 01_dashboard_reconciliation.sql
-- Reverse-engineers the business logic behind reporting.dashboard_a_weekly
-- and reporting.dashboard_b_weekly by recomputing each candidate definition
-- from raw.trips_initial and diffing against the supplied tables.
--
-- Finding (validated to within floating-point/rounding noise across all
-- 24 week x area rows -- see notebooks/analysis.ipynb section 2 for the
-- full diff table):
--
--   Dashboard A                          Dashboard B
--   ------------------------------------ ------------------------------------
--   scope:  ALL trips (no dropoff filter) scope:  dropoff_community_area IS NOT NULL
--   price:  AVG(fare)                     price:  AVG(trip_total)  [fare+tip+fees]
--   shared: rate of shared_trip_authorized shared: rate of shared_trip_match
--
-- B's dropoff-known filter is a *data-completeness* filter, not a geographic
-- scope filter (dropoff need not be one of the 4 study areas -- it just must
-- be non-NULL). It removes trips unevenly across pickup areas because
-- dropoff-capture rate itself varies by area (worst in Garfield Ridge / area
-- 56, ~30% missing, vs ~2-9% elsewhere) -- see 03_data_quality.sql.

-- Recompute A's definition and diff against the supplied table.
WITH recomputed_a AS (
    SELECT
        date_trunc('week', trip_start_timestamp)   AS week_start,
        pickup_community_area,
        COUNT(*)                                    AS trip_count,
        AVG(fare)                                   AS avg_trip_price,
        AVG(CASE WHEN shared_trip_authorized THEN 1.0 ELSE 0.0 END) AS shared_trip_rate
    FROM src.raw.trips_initial
    GROUP BY 1, 2
)
SELECT
    r.week_start, r.pickup_community_area,
    r.trip_count - a.trip_count                                    AS trip_count_diff,
    ROUND(r.avg_trip_price - a.avg_trip_price, 4)                   AS avg_price_diff,
    ROUND(r.shared_trip_rate - a.shared_trip_rate, 6)                AS shared_rate_diff
FROM recomputed_a r
JOIN src.reporting.dashboard_a_weekly a USING (week_start, pickup_community_area)
ORDER BY 1, 2;

-- Recompute B's definition and diff against the supplied table.
WITH recomputed_b AS (
    SELECT
        date_trunc('week', trip_start_timestamp)   AS week_start,
        pickup_community_area,
        COUNT(*)                                    AS trip_count,
        AVG(trip_total)                             AS avg_trip_price,
        AVG(CASE WHEN shared_trip_match THEN 1.0 ELSE 0.0 END) AS shared_trip_rate
    FROM src.raw.trips_initial
    WHERE dropoff_community_area IS NOT NULL
    GROUP BY 1, 2
)
SELECT
    r.week_start, r.pickup_community_area,
    r.trip_count - b.trip_count                                     AS trip_count_diff,
    ROUND(100.0 * (r.trip_count - b.trip_count) / b.trip_count, 3)   AS trip_count_pct_diff,
    ROUND(r.avg_trip_price - b.avg_trip_price, 4)                    AS avg_price_diff,
    ROUND(r.shared_trip_rate - b.shared_trip_rate, 6)                AS shared_rate_diff
FROM recomputed_b r
JOIN src.reporting.dashboard_b_weekly b USING (week_start, pickup_community_area)
ORDER BY 1, 2;

-- Why the trip-count match for B is close but not bit-exact (residual <=0.21%,
-- mean -0.03%, one row exact): we could not find an additional single-column
-- filter that closes the remainder exactly (tested trip_seconds>0/trip_miles>0,
-- trip_total IS NOT NULL, fare IS NOT NULL -- none improve the fit). The gap is
-- small enough (a few dozen rows out of tens of thousands per bucket) that it
-- does not change any conclusion in this analysis; treated as an unresolved
-- minor residual and documented as a limitation rather than chased further,
-- consistent with the exercise's guidance to focus on material discrepancies.
