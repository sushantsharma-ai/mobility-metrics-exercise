-- 00_setup.sql
-- Attach the read-only source package and expose the incremental Parquet file
-- as a view. All downstream SQL in this folder assumes these objects exist in
-- the session (see notebooks/analysis.ipynb, which runs this file first).
--
-- Design choice: we never write into mobility_exercise.duckdb itself. All
-- analysis views live in the in-memory/session database and reference the
-- attached source as `src.<schema>.<table>`, so the original package stays a
-- pristine, re-attachable source of truth.

ATTACH 'data/mobility_exercise.duckdb' AS src (READ_ONLY);

CREATE OR REPLACE VIEW incremental_raw AS
    SELECT * FROM read_parquet('data/incremental_trips.parquet');
