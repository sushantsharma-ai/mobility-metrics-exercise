-- 02_trusted_views.sql
-- Canonical trusted trip universe and weekly metrics. Run 00_setup.sql first.
--
-- Scope rules applied uniformly to every trusted metric in this project:
--   1. pickup_community_area IN (24, 41, 43, 56)  -- the four study areas;
--      excludes the pickup_community_area = 999 sentinel found in the
--      incremental file (25 rows total; not present in reference.community_areas,
--      dropoff areas on those rows are ordinary Chicago community areas, so 999
--      reads as an out-of-scope/placeholder pickup code, not a real area).
--   2. Deduplicated by trip_id across raw.trips_initial UNION incremental_raw.
--      Every trip_id that appears in both sources (50 trips) and every
--      in-incremental duplicate (100 trips) is byte-for-byte identical across
--      all 16 fields (validated in notebooks/analysis.ipynb section 3) --
--      these are re-deliveries, not corrected/conflicting records. Dedup is
--      therefore a safe, lossless "keep one" with no conflict-resolution logic
--      needed for THIS delivery. Documented as an assumption, not a guarantee:
--      a future delivery that re-sends a trip_id with genuinely different field
--      values would silently pick an arbitrary version under this logic; there
--      is no ingestion timestamp in the schema to prefer "latest", so a future
--      pipeline should either get one (preferred) or apply a documented
--      tie-break (e.g. prefer the row with fewer NULLs).
--   3. We deliberately do NOT require dropoff_community_area IS NOT NULL. That
--      is dashboard B's filter, and it is a data-completeness artifact (dropoff
--      geocoding gap), not a business-meaningful scope boundary -- excluding on
--      it drops ~30% of Garfield Ridge (area 56) trips vs ~2-9% elsewhere,
--      systematically understating that area's activity. See 03_data_quality.sql.

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

-- Canonical measure definitions (rationale in REPORT / notebook section 5):
--   trip_volume       : COUNT(DISTINCT trip_id) of in-scope trips.
--   avg_trip_price     : AVG(trip_total) -- full rider-paid amount
--                        (fare + tip + additional_charges), not base fare
--                        alone; a resource-costing audience cares about total
--                        economic value per trip. NULL trip_total rows
--                        (~0.3% of trips) are excluded from this average only
--                        -- they still count toward trip_volume.
--   shared_trip_rate   : share of trips with shared_trip_match = TRUE, i.e.
--                        trips that were ACTUALLY pooled with another rider,
--                        not merely authorized for pooling. shared_trip_match
--                        implies shared_trip_authorized in 100% of rows
--                        (validated), so this is the more conservative,
--                        operationally-relevant of the two candidate rates.
CREATE OR REPLACE VIEW trusted_weekly_metrics AS
SELECT
    date_trunc('week', trip_start_timestamp)                       AS week_start,
    pickup_community_area,
    COUNT(DISTINCT trip_id)                                        AS trip_volume,
    AVG(trip_total)                                                AS avg_trip_price,
    AVG(CASE WHEN shared_trip_match THEN 1.0 ELSE 0.0 END)         AS shared_trip_rate,
    COUNT(*) FILTER (WHERE trip_total IS NULL)                     AS price_excluded_null_total
FROM trusted_trips
GROUP BY 1, 2
ORDER BY 1, 2;
