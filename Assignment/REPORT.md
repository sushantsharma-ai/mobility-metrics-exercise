# Mobility Metrics Report

For Operations. Covers West Town, Hyde Park, South Shore, and Garfield
Ridge, March 3 – April 27, 2025. Full detail is in
`notebooks/analysis_report.html` if you want the play-by-play — this is
the short version.

## Why the two dashboards don't match

Dashboard A and Dashboard B are quietly using three different definitions:

| | Dashboard A | Dashboard B |
|---|---|---|
| Which trips count | all of them | only if dropoff location is known |
| Price | base fare | fare + tip + fees |
| "Shared trip" | rider opted in | rider actually matched with someone |

The scope difference is the one that matters. Dropoff location is missing
for about 4% of West Town trips but 32% of Garfield Ridge trips — that's a
data gap, not proof those trips didn't happen. Dashboard B just drops
anything without a dropoff, so it understates Garfield Ridge way more than
anywhere else. Neither dashboard is really "wrong," they just never wrote
down which definition they were using, and both are internally consistent.

## Definitions used in this report

- **Trip volume** — every trip, dropoff known or not (`COUNT(DISTINCT trip_id)`)
- **Average trip price** — `AVG(trip_total)`, the full amount the rider paid, not just the fare
- **Shared-trip rate** — share of trips where the rider was actually matched with someone, not just opted in

## What we found

Garfield Ridge isn't shrinking, it's actually growing. Dashboard B makes it
look like it lost ~30% of its trips, but on a consistent definition it's up
9.9% vs. a typical March week — the best of the four areas.

Hyde Park and South Shore tell the opposite story: down 17.3% and 12.1%
vs. their typical March weeks. Two separate checks (the raw week-over-week
trend, and the March baseline) agree on this, so it looks real, not noise —
we can flag it, but this data doesn't say why.

And the dashboard gap itself isn't a rounding thing. It runs 2-4% for Hyde
Park and West Town, but 42-53% for Garfield Ridge. Picking the wrong
definition doesn't just nudge a number, it can flip the story for a
specific area.

## What we'd tell Operations to do

Stop using Dashboard B for area comparisons, especially Garfield Ridge,
until its dropoff filter gets fixed or at least relabeled. Right now it's
raising a false alarm on the area that's actually doing best. One
conversation with whoever owns Dashboard B — was that filter ever meant to
be a real business rule, or did it just creep in — settles this.

Separately, someone should look into why Hyde Park and South Shore are
softening. Service issue, competition, seasonality, who knows — this
analysis can size it, not explain it.

## Does the definition choice actually change anything?

A bit, yes. Fare-only pricing runs 28-42% lower than fare+tip+fees (33%
lower on average) — a real swing — but Garfield Ridge is still the most
expensive area either way, every single week. The shared-rate definition
moves things a lot less predictably: 16% to 105% higher depending on
week and area, not a clean multiplier. Either way, the April up/down split
and the overall story hold up — only the raw numbers shift, not the
conclusions.

## Assumptions and things worth knowing

- Biggest judgment call: counting trips even when the dropoff location is
  unknown. If Operations specifically wants "trips confirmed to have
  stayed in the tracked network," Dashboard B's filter is the one to use
  instead.
- The newer batch of trip data had 50 trips that also showed up in the
  first batch, plus 100 duplicates within itself — all exact re-sends, not
  corrections, so we kept one copy of each. There's no timestamp in the
  data to tell which copy is newer, so this would need a real rule if a
  future batch ever sends conflicting versions of the same trip.
- The "typical" baseline table isn't a clean, independent benchmark — its
  April numbers are partly built from the same April we're evaluating, so
  we used March instead. Treat any baseline comparison here as "vs. last
  month," not a controlled experiment.
- Only 4 of Chicago's community areas are in this data, and it only covers
  completed trips — nothing here speaks to requests or cancellations.
- Two things we didn't fully chase down: Dashboard B's trip count is still
  off from our recomputation by about 0.2%, and a small number of trips
  (148) have a value that looks like a real data glitch rather than
  rounding noise. We left both alone because neither would change a metric
  definition or flip a conclusion above — that's the bar we used for
  deciding what was worth digging into further and what wasn't.
