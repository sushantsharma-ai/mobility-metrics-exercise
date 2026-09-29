# Trusted Mobility Metrics — Take-Home Exercise

Analysis of why `reporting.dashboard_a_weekly` and `reporting.dashboard_b_weekly`
disagree, canonical trusted metric definitions, and what happened in the
latest period (incorporating the incremental delivery), for four Chicago
community areas (West Town, Hyde Park, South Shore, Garfield Ridge).

**Start here:** [`REPORT.md`](REPORT.md) — the short version, for anyone
who just wants the findings and recommendation. For the full working
process (every query, what it returned, why the next step followed from
it), see [`notebooks/analysis_report.html`](notebooks/analysis_report.html)
(rendered, open directly in a browser) or `notebooks/analysis.ipynb`
(executable source).

## Repo layout

```
REPORT.md                   Short, stakeholder-facing report: findings, definitions, recommendation
DATA_DICTIONARY.md          Source schema/scope/limitations (supplied by the exercise)
AI_USE_DISCLOSURE.md        AI-use transparency notes
data/                       Copies of the supplied .duckdb and .parquet files (untouched; read-only)
sql/                        All SQL, as standalone reusable/re-runnable files
  00_setup.sql                 Attach source DB read-only + expose incremental parquet
  01_dashboard_reconciliation.sql  Reverse-engineers dashboard A/B definitions
  02_trusted_views.sql         Canonical trusted_trips + trusted_weekly_metrics views
  03_data_quality.sql          Data-quality checks
  04_incremental_reconciliation.sql  Validates dedup/overlap/late-arrival handling
  05_baseline_comparison.sql   Latest period vs. historical_baseline, with leakage analysis
  06_sensitivity_check.sql     Alternative-definition sensitivity check
  07_validation_tests.sql      Reproducible pass/fail validation queries
notebooks/
  analysis.ipynb               Executable notebook — the investigation, run top to bottom
  analysis_report.html         Rendered, static version of the same notebook
  build_notebook.py            Generates analysis.ipynb from source (for editing/regenerating)
```

## Setup and execution

Requires Python 3.10+.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install duckdb pandas pyarrow jupyter nbformat nbclient nbconvert ipykernel
python -m ipykernel install --user --name mobility-exercise --display-name "mobility-exercise"
```

**Data files are not committed to this repo** (`mobility_exercise.duckdb` is
103MB, over GitHub's 100MB push limit, and re-submitting the exercise's own
input package seemed redundant). Copy the two source files from the original
exercise ZIP into `data/` before running anything:

```bash
cp /path/to/mobility_exercise.duckdb /path/to/incremental_trips.parquet data/
```

`sql/00_setup.sql` attaches the `.duckdb` file **read-only** and never writes
to it. To verify integrity against the exercise's own manifest once the files
are in place:

```bash
shasum -a 256 data/mobility_exercise.duckdb data/incremental_trips.parquet
diff <(shasum -a 256 data/mobility_exercise.duckdb data/incremental_trips.parquet) \
     <(grep -E "mobility_exercise.duckdb|incremental_trips.parquet" data/CHECKSUMS.sha256)
```

To re-run the full analysis end to end:

```bash
python notebooks/build_notebook.py                                            # regenerate analysis.ipynb from source
jupyter nbconvert --to notebook --execute --inplace notebooks/analysis.ipynb  # execute it
jupyter nbconvert --to html notebooks/analysis.ipynb --output analysis_report.html
```

Or open `notebooks/analysis.ipynb` directly in Jupyter/VS Code and run all
cells (select the `mobility-exercise` kernel).

To run any individual SQL file standalone against the package (e.g. to
re-verify a single claim):

```bash
python3 -c "
import duckdb, pathlib
con = duckdb.connect(':memory:')
con.execute(pathlib.Path('sql/00_setup.sql').read_text())
con.execute(pathlib.Path('sql/02_trusted_views.sql').read_text())
print(con.execute(pathlib.Path('sql/03_data_quality.sql').read_text().split(';')[0]).fetchdf())
"
```

## What's in the analysis

1. **Why the two dashboards disagree** — three undocumented definition
   differences (trip scope, price basis, shared-trip definition), found by
   recomputing candidate formulas from the raw trips and diffing against
   the supplied tables.
2. **Canonical trusted definitions** for trip volume, average trip price,
   and shared-trip rate, with rationale.
3. **Data-quality findings**, focused on what's actually material.
4. **Incremental delivery handling** — dedup logic, checked (not assumed)
   to be lossless for this delivery.
5. **Latest-period findings** vs. an appropriately-chosen historical
   baseline — including catching that the supplied baseline table
   overlaps with the evaluation period, and switching to March instead.
6. **A sensitivity check** against each measure's alternative definition.
7. **Reproducible validation tests** (4 pass/fail checks).
8. **One recommendation** for an Operations stakeholder, plus assumptions,
   limitations, and uncertainty.

`REPORT.md` has the short version. `notebooks/analysis.ipynb` shows the
actual process — what was checked, in what order, and why each next step
followed from the last.
