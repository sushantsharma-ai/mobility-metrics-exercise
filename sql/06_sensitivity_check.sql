-- 06_sensitivity_check.sql
-- Sensitivity check: recompute the trusted weekly metrics under one
-- reasonable alternative definition per measure (mirroring dashboard A's
-- choices) and quantify how much the "story" would change.
-- Run 00_setup.sql and 02_trusted_views.sql first.

SELECT
    t.week_start,
    t.pickup_community_area,
    t.avg_trip_price                                              AS canonical_avg_price_trip_total,
    alt.avg_fare                                                  AS alt_avg_price_fare_only,
    ROUND(100.0 * (t.avg_trip_price - alt.avg_fare) / alt.avg_fare, 1) AS pct_higher_under_canonical,
    t.shared_trip_rate                                            AS canonical_shared_rate_match,
    alt.shared_authorized_rate                                    AS alt_shared_rate_authorized,
    ROUND(100.0 * (alt.shared_authorized_rate - t.shared_trip_rate) / NULLIF(t.shared_trip_rate,0), 1) AS pct_higher_under_alt
FROM trusted_weekly_metrics t
JOIN (
    SELECT
        date_trunc('week', trip_start_timestamp) AS week_start,
        pickup_community_area,
        AVG(fare) AS avg_fare,
        AVG(CASE WHEN shared_trip_authorized THEN 1.0 ELSE 0.0 END) AS shared_authorized_rate
    FROM trusted_trips
    GROUP BY 1, 2
) alt USING (week_start, pickup_community_area)
ORDER BY 1, 2;
