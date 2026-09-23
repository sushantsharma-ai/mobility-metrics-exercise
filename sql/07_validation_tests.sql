-- 07_validation_tests.sql
-- Reproducible validation queries. Each returns a single `status` row that
-- should read 'PASS'; notebooks/analysis.ipynb asserts this programmatically.
-- Run 00_setup.sql and 02_trusted_views.sql first.

-- Test 1: trusted_trips has no duplicate trip_id (the whole point of the
-- DISTINCT ON dedup in 02_trusted_views.sql).
SELECT CASE WHEN COUNT(*) = COUNT(DISTINCT trip_id) THEN 'PASS' ELSE 'FAIL' END AS status,
       COUNT(*) AS n_rows, COUNT(DISTINCT trip_id) AS n_distinct_ids
FROM trusted_trips;

-- Test 2: trusted_trips row count reconciles exactly to
-- initial + incremental_distinct - overlap - out_of_scope_999_rows, i.e. no
-- silent row loss or duplication anywhere in the union/dedup/filter pipeline.
WITH expected AS (
    SELECT
        (SELECT COUNT(*) FROM src.raw.trips_initial) AS n_initial,
        (SELECT COUNT(DISTINCT trip_id) FROM incremental_raw) AS n_incremental_distinct,
        (SELECT COUNT(*) FROM (
            SELECT i.trip_id FROM src.raw.trips_initial i
            JOIN (SELECT DISTINCT trip_id FROM incremental_raw) x USING (trip_id)
        )) AS n_overlap,
        (SELECT COUNT(*) FROM (
            SELECT DISTINCT trip_id, pickup_community_area FROM src.raw.trips_initial
            UNION
            SELECT DISTINCT trip_id, pickup_community_area FROM incremental_raw
        ) WHERE pickup_community_area NOT IN (24,41,43,56)) AS n_out_of_scope
)
SELECT
    CASE WHEN (SELECT COUNT(*) FROM trusted_trips)
              = (n_initial + n_incremental_distinct - n_overlap - n_out_of_scope)
         THEN 'PASS' ELSE 'FAIL' END AS status,
    (SELECT COUNT(*) FROM trusted_trips) AS actual_trusted_rows,
    (n_initial + n_incremental_distinct - n_overlap - n_out_of_scope) AS expected_trusted_rows
FROM expected;

-- Test 3: avg_trip_price is never computed over an empty/null-only sample --
-- every week x area bucket in trusted_weekly_metrics has at least as many
-- trips contributing to price as price_excluded_null_total is less than
-- trip_volume (i.e. we never divide by zero and never lose an entire bucket
-- to nulls).
SELECT CASE WHEN SUM(CASE WHEN price_excluded_null_total >= trip_volume THEN 1 ELSE 0 END) = 0
            THEN 'PASS' ELSE 'FAIL' END AS status,
       COUNT(*) AS n_buckets_checked
FROM trusted_weekly_metrics;

-- Test 4: trip_total arithmetic identity holds for every trusted trip with
-- non-null components (fare + tip + additional_charges = trip_total).
SELECT CASE WHEN COUNT(*) FILTER (WHERE ABS(trip_total - (fare+tip+additional_charges)) > 0.01) = 0
            THEN 'PASS' ELSE 'FAIL' END AS status,
       COUNT(*) AS n_checked
FROM trusted_trips
WHERE trip_total IS NOT NULL AND fare IS NOT NULL;
