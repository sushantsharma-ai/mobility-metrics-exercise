# Trusted Mobility Metrics — Take-Home Exercise

Two existing reports, dashboard_a_weekly and dashboard_b_weekly, disagree
on trip volume, average price, and shared-trip rate for the same weeks and
the same four Chicago community areas (West Town, Hyde Park, South Shore,
Garfield Ridge). This works out why, defines trusted versions of those
three measures, and covers what the latest period looks like once a second
data delivery is folded in.

**Start here:** [`INVESTIGATION.md`](INVESTIGATION.md) — the write-up:
why the dashboards disagree, the trusted definitions, findings, a
sensitivity check, assumptions and limitations, and a recommendation.

The two SQL files behind it are in `sql/`. `notebooks/analysis_report.html`
runs both files and shows every query's actual output, as a validation
that the numbers in `INVESTIGATION.md` are real query results, not
hand-typed.

## Repo layout

```
INVESTIGATION.md             The write-up — start here
DATA_DICTIONARY.md           Source schema/scope/limitations (supplied by the exercise)
AI_USE_DISCLOSURE.md         AI-use transparency notes
data/                        Copies of the supplied .duckdb and .parquet files (untouched, read-only)
sql/
  01_cleaning_and_checks.sql   Builds the trusted trip set (dedup, scope filter) and checks it
  02_analysis.sql              Dashboard reconciliation, trusted metrics, baseline comparison, sensitivity check
notebooks/
  analysis.ipynb                Runs both SQL files and prints every result
  analysis_report.html          Rendered, static version of the same notebook
  build_notebook.py             Generates analysis.ipynb from source
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

`sql/01_cleaning_and_checks.sql` attaches the `.duckdb` file **read-only**
and never writes to it. To verify integrity against the exercise's own
manifest once the files are in place:

```bash
shasum -a 256 data/mobility_exercise.duckdb data/incremental_trips.parquet
diff <(shasum -a 256 data/mobility_exercise.duckdb data/incremental_trips.parquet) \
     <(grep -E "mobility_exercise.duckdb|incremental_trips.parquet" data/CHECKSUMS.sha256)
```

To re-run everything end to end:

```bash
python notebooks/build_notebook.py
jupyter nbconvert --to notebook --execute --inplace notebooks/analysis.ipynb
jupyter nbconvert --to html notebooks/analysis.ipynb --output analysis_report.html
```

Or open `notebooks/analysis.ipynb` directly in Jupyter/VS Code and run all
cells (select the `mobility-exercise` kernel).

## What's in the analysis

Why the two dashboards disagree, three undocumented definition differences
found by recomputing candidate formulas against the raw trips and diffing
them against the supplied tables. Canonical definitions for trip volume,
average price, and shared-trip rate, with the reasoning behind each.
Data-quality findings, kept to what actually matters. How the second
delivery was folded in, with the dedup checked rather than assumed safe.
Latest-period findings against a historical baseline, including catching
that the supplied baseline table overlaps with the period being evaluated
and switching to the prior month instead. A sensitivity check against each
measure's alternative definition. Three pass or fail validation checks.
One recommendation for Operations, plus assumptions, limitations, and
uncertainty. All of it is in `INVESTIGATION.md`.
