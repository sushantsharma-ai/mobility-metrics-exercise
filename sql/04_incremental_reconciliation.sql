-- 04_incremental_reconciliation.sql
-- Validates how the incremental delivery was incorporated. Run 00_setup.sql first.

-- Q1. Row counts and overlap between initial and incremental deliveries.
SELECT
    (SELECT COUNT(*) FROM src.raw.trips_initial)                                   AS initial_rows,
    (SELECT COUNT(DISTINCT trip_id) FROM incremental_raw)                          AS incremental_distinct_ids,
    (SELECT COUNT(*) FROM incremental_raw)                                         AS incremental_rows_including_dupes,
    (SELECT COUNT(*) FROM (
        SELECT i.trip_id FROM src.raw.trips_initial i
        JOIN (SELECT DISTINCT trip_id FROM incremental_raw) x USING (trip_id)
    ))                                                                              AS overlap_trip_ids;

-- Q2. Confirm every overlapping trip_id is byte-for-byte identical between the
-- two deliveries (a late re-send, not a correction) -- if this ever returns a
-- nonzero row count in a future delivery, the naive "keep one" dedup in
-- 02_trusted_views.sql must be replaced with explicit conflict resolution.
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

-- Q3. Late-arriving records: incremental rows whose trip_start_timestamp falls
-- inside the initial delivery's own window (Mar 3 - Apr 13), i.e. genuinely
-- late arrivals rather than the expected Apr 14-27 batch.
SELECT
    MIN(trip_start_timestamp) AS earliest_late_arrival,
    MAX(trip_start_timestamp) AS latest_late_arrival,
    COUNT(*)                  AS n_late_arrivals
FROM incremental_raw
WHERE trip_start_timestamp < DATE '2025-04-14';

-- Q4. Post-dedup trusted universe size reconciles exactly:
-- initial + incremental_distinct - overlap = trusted row count (before the
-- pickup-area scope filter; trusted_trips additionally drops the 25
-- pickup_community_area = 999 rows).
SELECT COUNT(*) AS trusted_trips_all_areas
FROM (
    SELECT DISTINCT trip_id FROM src.raw.trips_initial
    UNION
    SELECT DISTINCT trip_id FROM incremental_raw
);
