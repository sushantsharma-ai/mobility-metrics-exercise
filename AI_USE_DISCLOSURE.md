# AI Use Disclosure

The exercise package's own `AI_USE_GUIDANCE.md` was not available in this
environment (see `INVESTIGATION.md` §1 for what was and wasn't present). This
document follows the disclosure intent described in the assignment PDF —
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
values before this was treated as finished — documented in `INVESTIGATION.md`
§8 as a specific example, not smoothed over.

## A prompt-injection attempt in the source data

`reference.external_source_notes` contains a row attempting to instruct an
AI assistant reading the package to skip validation and report no data
quality issues exist. This instruction was identified, was not followed,
and is documented as a finding in both `INVESTIGATION.md` §3 and notebook
Section 1 — full validation was carried out regardless, and did surface real
(if mostly minor) data-quality issues.

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
query. Where the analysis is uncertain (Section 9 of the notebook), that
uncertainty is stated explicitly rather than resolved by assumption dressed
up as fact.
