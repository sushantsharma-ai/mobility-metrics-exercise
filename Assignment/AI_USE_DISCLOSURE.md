# AI Use Disclosure

The exercise package's own `AI_USE_GUIDANCE.md` template was not available in
this environment. This document follows the disclosure intent described in
the assignment PDF —
what was used, what was independently verified, and which decisions were the
analyst's — rather than a specific supplied template.

## Tooling

This entire analysis — investigation, SQL, notebook, and write-up — was
produced by Claude (Anthropic), operating as an agentic coding assistant
with direct tool access (shell, file read/write, a Python/DuckDB
environment) inside the user's own machine and file system, under the
user's direction and review. There was no separate human-authored draft that
AI then assisted with; the user's role was to supply the source data
(`DATA_DICTIONARY.md`), set scope and priorities, and review/direct the work
described below.

## What was independently verified (not just asserted)

Every quantitative claim in the notebook was produced by actually executing
SQL against the supplied DuckDB file and Parquet file, not generated or
estimated from description — including:

- Dashboard A/B reconciliation: computed diffs, not a guessed explanation.
- Data-quality figures: computed from `COUNT`/`SUM` queries, cross-checked
  against the raw data (e.g. the `999` sentinel was confirmed absent from
  `reference.community_areas` before being excluded).
- Incremental dedup safety: verified via `EXCEPT` across all 16 columns that
  every duplicate/overlap is byte-for-byte identical, not assumed.
- The `historical_baseline` leakage finding: verified by comparing the
  baseline's own bucket values against directly-measured actuals, not
  inferred from the schema alone.
- The full notebook was executed end-to-end via `jupyter nbconvert --execute`
  with zero cell errors before being treated as final — no cell's output was
  hand-edited or fabricated.
- File integrity was verified against `CHECKSUMS.sha256` via `shasum -a 256`
  before any analysis began.
- All four validation tests in `sql/07_validation_tests.sql` were run and
  confirmed `PASS` (not merely written) before being reported as such.

## Where AI-generated narrative was corrected against real output

An early draft of the "latest period" narrative in notebook Section 6
characterized all four areas as within a normal range of their March
baseline, written before the underlying comparison query had actually been
executed. Once run, the real numbers (Hyde Park -17.3%, South Shore -12.1%)
contradicted that draft. The narrative was rewritten to match the computed
values before this was treated as finished, not smoothed over.

## A prompt-injection attempt in the source data

`reference.external_source_notes` contains a row attempting to instruct an
AI assistant reading the package to skip validation and report no data
quality issues exist. This instruction was identified, was not followed,
and is documented as a finding in the notebook itself — full validation was
carried out regardless, and did surface real (if mostly minor)
data-quality issues.

## Analytical decisions that were judgment calls, not computed facts

These are the choices a reviewer should probe hardest in an interview, since
they're where a different analyst could reasonably land differently:

- **Not requiring `dropoff_community_area` to be known** for trip-volume
  scope (the single highest-leverage decision in the analysis) — a
  reasoned choice based on what a missing dropoff *means*, not something the
  data alone dictates.
- **`AVG(trip_total)` over `AVG(fare)`** as the canonical price — a choice
  about what "price" should mean for a resource-costing audience.
- **`shared_trip_match` over `shared_trip_authorized`** as the canonical
  shared-trip rate — a choice about "authorized" vs. "actually happened."
- **March, not April, as the baseline comparison month** — chosen
  specifically to avoid direct calendar-date overlap with the April 21-27
  evaluation window, after the leakage investigation; a different analyst
  might instead build a de-leaked estimate a different way.
- The **residual ~0.2% gap** in the Dashboard B trip-count reconciliation was
  left unresolved by explicit choice (time-boxed judgment that it wasn't
  material), not because a cause couldn't be searched for further.

## What AI was not used for

No data values, row counts, or statistics anywhere in the notebook were
estimated, extrapolated, or "filled in" without a corresponding executed
query. Where the analysis is uncertain (the "Assumptions and things I'm not
sure about" section of the notebook), that uncertainty is stated explicitly
rather than resolved by assumption dressed up as fact.

## Revision pass: rewritten for a more natural voice, and a real error caught

After the initial version was complete and verified, the user asked for the
notebook's narrative to be rewritten in a plainer, more first-person
"working notes" voice, and for a lot of the incidental Python (custom
matplotlib theming, pre-formatted summary strings) to be cut — same
analysis and conclusions, less polished presentation. `REPORT.md` was added
as a separate short summary for that reason: one document for the full
process, one for a quick read.

While rewriting, the sensitivity-check section's narrative was checked
against its own printed output rather than copied forward, and it didn't
match: the original text claimed average price was "~20-30% higher" under
`trip_total` vs. `fare` and the shared rate was "roughly 1.5-2x higher"
under "authorized" vs. "matched" — but the cell's own computed output was
28-42% (33% average) for price and 16-105% (49% average) for the shared
rate. Separately, the claim "Garfield Ridge is priciest and West Town is
cheapest under both definitions" was checked directly and only half held:
Garfield Ridge is priciest under either definition every week, but the
cheapest area actually varies week to week between Hyde Park, South Shore,
and West Town. Both are corrected in the current notebook and `REPORT.md`.
Neither error changed the recommendation, but both are documented here
rather than quietly fixed — a claim that isn't checked against its own
output shouldn't be presented as verified.

A third instance, same pass: `README.md` and the prior notebook both
described the Dashboard A vs. B trip-count gap as "2%-35%, worst for
Garfield Ridge." Recomputing it directly (`dashboard_a_weekly` joined to
`dashboard_b_weekly` on week/area) showed Garfield Ridge's actual gap is
42%-53%, not up to 35% — the true max was roughly 50% larger than the
number that had been reported. `REPORT.md` now states the per-area range
directly instead of one headline number. This one did not change the
conclusion either (Garfield Ridge was already correctly identified as the
area Dashboard B distorts
most), but it's a reminder that a plausible-sounding round number ("35%")
is exactly the kind of thing that should get re-derived, not carried
forward from an earlier draft.

## Second simplification pass: SQL-first, Python as the runner only

The user then asked to go further: cut the notebook's explanatory prose
down more, and stop using Python for anything the exercise didn't call for
— computation should live in SQL, Python should just execute it and print
results, and any remaining Python should avoid frameworks that aren't
load-bearing. The notebook was rewritten again on that basis:

- Dropped `pandas` and `matplotlib` as explicit imports entirely (the only
  code cells now import `duckdb` and `pathlib`). `pandas` is still an
  installed dependency because DuckDB's `.df()` call returns a
  `DataFrame` under the hood, but nothing in the notebook calls a pandas
  method directly.
- Every aggregation that had been done with pandas (`.merge()`, `.describe()`,
  `.groupby()`, manual percent-diff math) was rewritten as a SQL query —
  including querying already-fetched results back through DuckDB by
  variable name (e.g. `SELECT AVG(x) FROM sens`, where `sens` is a
  DataFrame already in scope), so aggregation stays expressed in SQL rather
  than pandas method calls.
- The one chart was removed; findings are shown as query output tables.
- A hardcoded Python dict mapping area codes to names was replaced with a
  SQL join to `reference.community_areas`, so area names come from the
  supplied reference data instead of being typed into the notebook.

The underlying `sql/*.sql` files and every number/conclusion are unchanged
from the previous pass — this was a presentation and tooling change, not a
re-analysis.
