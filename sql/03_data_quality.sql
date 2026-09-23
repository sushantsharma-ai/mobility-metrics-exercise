-- 03_data_quality.sql
-- Focused data-quality checks on the trip-level sources. Run 00_setup.sql first.

-- Q1. Null rates on fields used by the trusted metrics (initial delivery).
SELECT
    COUNT(*)                                                        AS n_rows,
    SUM(CASE WHEN trip_id IS NULL THEN 1 ELSE 0 END)                AS null_trip_id,
    SUM(CASE WHEN pickup_community_area IS NULL THEN 1 ELSE 0 END)  AS null_pickup_area,
    SUM(CASE WHEN dropoff_community_area IS NULL THEN 1 ELSE 0 END) AS null_dropoff_area,
    SUM(CASE WHEN fare IS NULL THEN 1 ELSE 0 END)                   AS null_fare,
    SUM(CASE WHEN trip_total IS NULL THEN 1 ELSE 0 END)             AS null_trip_total,
    ROUND(100.0 * SUM(CASE WHEN trip_total IS NULL THEN 1 ELSE 0 END) / COUNT(*), 3) AS pct_null_trip_total
FROM src.raw.trips_initial;

-- Q2. Dropoff-capture rate by pickup area -- explains dashboard A/B divergence
-- and shows it is NOT uniform (i.e. filtering on it is not a neutral choice).
SELECT
    pickup_community_area,
    COUNT(*)                                                        AS n_rows,
    SUM(CASE WHEN dropoff_community_area IS NULL THEN 1 ELSE 0 END) AS dropoff_null,
    ROUND(100.0 * SUM(CASE WHEN dropoff_community_area IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_dropoff_null
FROM trusted_trips
GROUP BY 1 ORDER BY 1;

-- Q3. Out-of-scope pickup sentinel (999) -- confirmed not in reference.community_areas,
-- excluded from trusted_trips.
SELECT pickup_community_area, COUNT(*) AS n_rows
FROM (
    SELECT * FROM src.raw.trips_initial
    UNION ALL
    SELECT * FROM incremental_raw
)
WHERE pickup_community_area NOT IN (SELECT community_area_id FROM src.reference.community_areas)
GROUP BY 1 ORDER BY 1;

-- Q4. percent_time_chicago / percent_distance_chicago out of the documented
-- [0,1] range. Most excess is trivial rounding noise (<=1.01); a small tail
-- is a genuine anomaly (up to 3.79) -- neither is used to filter trusted
-- metrics, but both are worth surfacing to the data engineering team.
SELECT
    SUM(CASE WHEN percent_time_chicago > 1 OR percent_time_chicago < 0 THEN 1 ELSE 0 END)        AS pct_time_out_of_range,
    SUM(CASE WHEN percent_time_chicago > 1.01 OR percent_time_chicago < -0.01 THEN 1 ELSE 0 END)  AS pct_time_severely_out_of_range,
    MAX(percent_time_chicago)                                                                     AS max_pct_time_chicago,
    SUM(CASE WHEN percent_distance_chicago > 1 OR percent_distance_chicago < 0 THEN 1 ELSE 0 END) AS pct_dist_out_of_range
FROM trusted_trips;

-- Q5. Internal consistency: trip_total should equal fare + tip + additional_charges.
SELECT
    COUNT(*) FILTER (WHERE trip_total IS NOT NULL AND fare IS NOT NULL)                     AS n_checked,
    COUNT(*) FILTER (WHERE ABS(trip_total - (fare + tip + additional_charges)) > 0.01)      AS n_mismatched
FROM trusted_trips;

-- Q6. Logical consistency: shared_trip_match should never be TRUE without
-- shared_trip_authorized also TRUE.
SELECT COUNT(*) AS n_invalid_match_without_authorization
FROM trusted_trips
WHERE shared_trip_match = TRUE AND shared_trip_authorized = FALSE;

-- Q7. Non-positive trip_miles / trip_seconds and end-before-start timestamps
-- (small counts; flagged, not excluded from volume/price/shared metrics
-- since none of those metrics depend on duration or distance).
SELECT
    SUM(CASE WHEN trip_miles <= 0 THEN 1 ELSE 0 END)                          AS nonpositive_miles,
    SUM(CASE WHEN trip_seconds <= 0 THEN 1 ELSE 0 END)                        AS nonpositive_seconds,
    SUM(CASE WHEN trip_end_timestamp < trip_start_timestamp THEN 1 ELSE 0 END) AS end_before_start
FROM trusted_trips;
