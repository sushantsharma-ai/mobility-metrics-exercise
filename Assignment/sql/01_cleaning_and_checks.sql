-- 01_cleaning_and_checks.sql
-- Gets the raw trip data into one clean, trusted set of trips, and checks
-- that the cleaning actually did what it was supposed to. Run this file
-- first, then 02_analysis.sql, both against an in-memory duckdb connection.

-- Attach the original database read only, so nothing here can ever change
-- the source files, and point a view at the second delivery (the parquet
-- file) so it can be queried the same way as everything else.
ATTACH 'data/mobility_exercise.duckdb' AS src (READ_ONLY);

CREATE OR REPLACE VIEW incremental_raw AS
    SELECT * FROM read_parquet('data/incremental_trips.parquet');

-- Before combining the two deliveries, check whether they overlap. Fifty
-- trip ids show up in both files, and a hundred rows repeat inside the
-- incremental file on its own.
SELECT
    (SELECT COUNT(*) FROM src.raw.trips_initial) AS initial_rows,
    (SELECT COUNT(DISTINCT trip_id) FROM incremental_raw) AS incremental_distinct_ids,
    (SELECT COUNT(*) FROM incremental_raw) AS incremental_rows_including_dupes,
    (SELECT COUNT(*) FROM (
        SELECT i.trip_id FROM src.raw.trips_initial i
        JOIN (SELECT DISTINCT trip_id FROM incremental_raw) x USING (trip_id)
    )) AS overlap_trip_ids;

-- If those overlapping rows turned out to be conflicting versions of the
-- same trip, keeping one copy at random would be the wrong move. So check
-- first: every overlapping row matches its counterpart on every column, so
-- these are re-sent records, not corrections, and it is safe to just keep
-- one copy of each further down.
WITH initial_side AS (
    SELECT i.* FROM src.raw.trips_initial i
    JOIN (SELECT DISTINCT trip_id FROM incremental_raw) x USING (trip_id)
),
incremental_side AS (
    SELECT DISTINCT * FROM incremental_raw
    WHERE trip_id IN (SELECT trip_id FROM initial_side)
)
SELECT COUNT(*) AS conflicting_rows
FROM (SELECT * FROM initial_side EXCEPT SELECT * FROM incremental_side);

-- Also worth knowing: does the incremental file only contain new trips from
-- April 14 onward, or did some older trips arrive late too. A hundred and
-- thirty nine rows predate April 14, so those are genuine late arrivals,
-- not part of the expected new batch, and get folded in below along with
-- everything else.
SELECT MIN(trip_start_timestamp) AS earliest_late_arrival, COUNT(*) AS n_late_arrivals
FROM incremental_raw WHERE trip_start_timestamp < DATE '2025-04-14';

-- Now build the actual trusted trip universe. Combine both deliveries,
-- keep one copy of every trip id since the check above showed that is
-- safe, and drop pickup_community_area 999, a placeholder code that turns
-- up in twenty five incremental rows and is not one of the four study
-- areas at all.
CREATE OR REPLACE VIEW trusted_trips AS
WITH unioned AS (
    SELECT * FROM src.raw.trips_initial
    UNION
    SELECT * FROM incremental_raw
)
SELECT DISTINCT ON (trip_id) *
FROM unioned
WHERE pickup_community_area IN (24, 41, 43, 56)
ORDER BY trip_id;

-- Confirming that 999 code is really junk and not a real area code that
-- was just missing from the reference table.
SELECT pickup_community_area, COUNT(*) AS n_rows
FROM (SELECT * FROM src.raw.trips_initial UNION ALL SELECT * FROM incremental_raw)
WHERE pickup_community_area NOT IN (SELECT community_area_id FROM src.reference.community_areas)
GROUP BY 1;

-- With a clean trip universe in place, check the handful of fields the
-- trusted metrics actually depend on. Trip total is missing for about a
-- third of one percent of trips, which just gets left out of the price
-- average and nothing else.
SELECT
    COUNT(*) AS n_rows,
    SUM(CASE WHEN trip_total IS NULL THEN 1 ELSE 0 END) AS null_trip_total,
    ROUND(100.0 * SUM(CASE WHEN trip_total IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_null_trip_total
FROM trusted_trips;

-- Dropoff location is a different story. It is missing a lot more for some
-- areas than others, and this pattern turns out to be the actual reason
-- the two dashboards disagree, covered in the analysis file. Checking it
-- here against the initial delivery specifically, since that is the data
-- both dashboards were actually built from.
SELECT c.community_area_name, COUNT(*) AS n,
       ROUND(100.0 * SUM(CASE WHEN dropoff_community_area IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_missing_dropoff
FROM src.raw.trips_initial t
JOIN src.reference.community_areas c ON t.pickup_community_area = c.community_area_id
GROUP BY 1 ORDER BY 2;

-- percent_time_chicago and percent_distance_chicago are supposed to sit
-- between zero and one, but about nine percent of trips run slightly over
-- one, with a small tail of a hundred and forty eight rows going as high
-- as 3.79. Nothing here is used by any of the trusted metrics, so this is
-- just flagged for whoever owns the upstream pipeline rather than
-- excluded from anything.
SELECT
    SUM(CASE WHEN percent_time_chicago > 1 THEN 1 ELSE 0 END) AS trips_over_100_pct_time,
    MAX(percent_time_chicago) AS worst_value
FROM trusted_trips;

-- Two more sanity checks: the three price fields should always add up to
-- the total, and a trip actually counted as shared should never fail to
-- also be authorized for sharing. Both hold for every row, which is
-- reassurance rather than a finding, but worth confirming before trusting
-- anything built on top of these fields.
SELECT
    COUNT(*) FILTER (WHERE ABS(trip_total - (fare + tip + additional_charges)) > 0.01) AS mismatched_totals,
    COUNT(*) FILTER (WHERE shared_trip_match = TRUE AND shared_trip_authorized = FALSE) AS matched_without_authorization
FROM trusted_trips
WHERE trip_total IS NOT NULL AND fare IS NOT NULL;

-- Check 1 of 3 on the cleaning pipeline itself: no trip id should appear
-- twice in the trusted set.
SELECT CASE WHEN COUNT(*) = COUNT(DISTINCT trip_id) THEN 'pass' ELSE 'fail' END AS dedup_check,
       COUNT(*) AS n_rows, COUNT(DISTINCT trip_id) AS n_distinct_ids
FROM trusted_trips;

-- Check 2 of 3: the trusted row count should equal initial rows plus
-- distinct incremental rows, minus the overlap, minus the excluded 999
-- rows, with nothing lost or duplicated anywhere along the way.
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
         THEN 'pass' ELSE 'fail' END AS reconciliation_check,
    (SELECT COUNT(*) FROM trusted_trips) AS actual_trusted_rows,
    (n_initial + n_incremental_distinct - n_overlap - n_out_of_scope) AS expected_trusted_rows
FROM expected;
