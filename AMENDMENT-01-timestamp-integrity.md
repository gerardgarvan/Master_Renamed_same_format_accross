# Amendment 01 — Operative Timestamp Integrity

**Raised:** 2026-08-26, by the QC-05 abort in `05_qc_merge.sas`
**Affects:** Phase 3 (per-source normalization), Phase 5 (merge QC)
**Requires re-run:** Phase 3 → Phase 4 → Phase 5
**Status:** plans written, not executed

---

## 1. Why this exists

Phase 5 ran clean through QC-01 to QC-04 and aborted on the first QC-05 time check:

```
ERROR: QC ASSERTION FAILED -- QC-05 rt_INCISE_to_DRESS_mins out of range 0-2000: expected 0 got 52
```

That is a real data finding, not a program defect. Investigating it turned up a second
problem that no range check can catch, and one measurement error of my own that is worth
recording so nobody repeats it.

## 2. Findings

### PCM-F-13 — every QC-05 time failure is a NEGATIVE value

| | rt_INCISE_to_DRESS_mins | rt_RM_START_to_INCISION_mins |
|---|---|---|
| Negative | **52** | **15** |
| Over ceiling (2000 / 500) | **0** | **0** |
| Exceeds room-interval envelope | 5 | 4 |

`rt_RM_START_to_RM_END_mins` has 0 negatives and 0 over 2000.

The two failing sets are **disjoint** (`n_both = 0`), so 67 distinct rows carry a negative
value, not 52 with overlap.

### PCM-F-14 — the negatives are small and clustered by Service

PROC UNIVARIATE on the 52 `rt_INCISE_to_DRESS_mins` failures:

| Statistic | Value |
|---|---|
| Min | −483 |
| 5th pct | −47 |
| Q1 | −6.5 |
| Median | −3 |
| Mode | −2 |
| Q3 | −2 |
| **Max** | **−1** |

Three-quarters sit between −6.5 and −1: the dressing timestamp lands one to seven minutes
*before* the incision timestamp. The extreme tail is a handful (−483, −68, −47, −35, −23).

Service concentration:

| Service | n | % of 52 |
|---|---|---|
| Neurosurgery | 24 | 46% |
| Adult Electrophysiology Cardio | 6 | 12% |
| Adult Interventional Cardiology | 4 | 8% |
| Minimally Invasive Surgery | 3 | 6% |
| Otolaryngology | 3 | 6% |
| nine other services | 12 | 23% |

Electrophysiology and interventional cardiology are largely **percutaneous** — there is no
incision or dressing in the surgical sense, so those fields are defaulted, auto-populated,
or charted as a formality. A negative interval there is not mysterious: the timestamps are
not measuring what the variable name implies. Neurosurgery at 46% may be the same story if
interventional neuroradiology (coiling, thrombectomy) sits under that service label — worth
confirming, but it does not change the fix.

`in_md8` is 45 of 52. Read that cautiously: md8 covers 54.6% of all rows, and
`rt_INCISE_to_DRESS_mins` is **md3-owned** in the merge, so the flag describes patient
overlap, not value provenance. The Service pattern is the stronger signal.

### PCM-F-15 — 9 rows are internally contradictory and QC-05 cannot catch them

5 rows have `rt_INCISE_to_DRESS_mins > rt_RM_START_to_RM_END_mins`; 4 have
`rt_RM_START_to_INCISION_mins > rt_RM_START_to_RM_END_mins`. A sub-interval cannot exceed
the room occupancy that contains it.

These have **positive** values inside the 0–2000 and 0–500 bounds. They pass QC-05 cleanly
while being impossible. A range check tests each variable against a constant; it
structurally cannot see a relationship between two variables. Hence QC-06 below.

### PCM-F-16 — both QC-05 time ceilings are inert

`rt1_over2000 = 0` and `rt2_over500 = 0` across all 41,150 rows. Neither upper bound has
ever fired. Either the data is genuinely well-behaved at the top end or the bounds are too
loose to be useful; nothing so far distinguishes those. See PCM-D-09.

## 3. New trap

### PCM-T-11 — an unguarded comparison counts missings as negatives

The diagnostic query that produced these numbers was written as:

```sas
sum(rt_INCISE_to_DRESS_mins < 0)   /* WRONG -- returned 8369 */
```

In SAS, missing is less than any number, so this counted 52 real negatives plus 8,317
missing values. The correct count needs the guard that QC-05 already uses:

```sas
sum(rt_INCISE_to_DRESS_mins is not missing and rt_INCISE_to_DRESS_mins < 0)   /* 52 */
```

This is Phase 5 RESEARCH Pitfall 4 restated. It was documented, and then walked into anyway
while writing an ad-hoc diagnostic. Elevated to a project-level trap because it produced a
number that was wrong by two orders of magnitude and looked entirely plausible.

**Rule:** every comparison against a numeric variable in this project carries an
`IS NOT MISSING` guard, including throwaway diagnostics. If a count comes back surprisingly
large, check for this before believing it.

## 4. New requirements

| ID | Requirement | Phase |
|---|---|---|
| **PREP-08** | Negative values in `rt_INCISE_to_DRESS_mins`, `rt_RM_START_to_INCISION_mins` and `rt_RM_START_to_RM_END_mins` are set to missing during per-source prep, with per-source per-variable counts logged. Asserted zero afterwards. | 3 |
| **PREP-09** | Every other `rt_*` variable is SCANNED for negative values and the counts reported to `logs/`. **No values are modified.** Feeds PCM-D-08. | 3 |
| **QC-06** | Sub-interval containment asserted in the merged file: neither `rt_INCISE_to_DRESS_mins` nor `rt_RM_START_to_INCISION_mins` may exceed `rt_RM_START_to_RM_END_mins`. | 5 |

**PREP-08 is deliberately scoped to three variables, not all `rt_*`.** Negative elapsed time
is invalid for a within-encounter duration, but the `rt_ANCHOR_to_*_days` variables are
offsets from an anchor date and **can legitimately be negative** — an admission preceding
the anchor is meaningful, not an error. Nulling those would destroy real data. PREP-09
reports them so the decision is made on evidence rather than by pattern-matching on the
`rt_` prefix.

## 5. New open decisions

- **PCM-D-08 — the 9 contradictory rows (PCM-F-15).** Null them, or investigate first? Nine
  rows is small enough to inspect individually. Knowing whether they fall in the same
  services as the 52 would say whether this is one upstream problem or two. QC-06 will fail
  until they are resolved either way, which is correct.
- **PCM-D-09 — the inert ceilings (PCM-F-16).** 2000 and 500 have never fired. Plan 05-03
  produces the distribution needed to decide whether to recalibrate them the way
  `Admit_BMI` was, or drop them and rely on the containment check.
- **PCM-D-10 — negatives in the other `rt_*` variables.** PREP-09's report answers whether
  any exist and where. For the `rt_ANCHOR_to_*_days` family the answer may be "negative is
  correct, leave alone."

**For Erin:** if the source system records incision and dressing times for percutaneous
procedures that do not have them, that affects anyone using operative duration in this
cohort, not just this merge. Worth raising with the PeCAN data group independently.

## 6. Re-run sequence

PREP-08 changes Phase 3 output, so everything downstream is stale:

```
1. Phase 3   03_prep_all.sas          -> regenerates g.prep_md1..8
2. Phase 4   04_merge.sas             -> regenerates g.master_data_merged
3. Phase 5   05_qc_merge.sas          -> QC-01..QC-06
```

Between each, **restart the SAS session**. Every program in this pipeline can end in
`%abort cancel`, which leaves an interactive session in a state where the next submit is
swallowed without executing — that already cost one debugging cycle.

Expected on the Phase 5 re-run: QC-05's three time assertions pass (negatives are now
missing, and the `IS NOT MISSING` guards skip them), and **QC-06 fails at 9** until PCM-D-08
is resolved. That is the designed behavior, not a regression.

## 7. Files changed

| File | Change |
|---|---|
| `.planning/PROJECT.md` | Add PCM-F-13..16, PCM-T-11, PCM-D-08..10 |
| `.planning/phases/03-per-source-normalization/03-06-PLAN.md` | NEW — PREP-08, PREP-09 |
| `.planning/phases/03-per-source-normalization/03-VALIDATION.md` | Add PREP-08/09 rows |
| `.planning/phases/05-merge-qc/05-03-PLAN.md` | NEW — QC-06, PCM-D-09 investigation |
| `.planning/phases/05-merge-qc/05-VALIDATION.md` | Add QC-06 row; assertion count 12 + n_md8_only + 1 |
| `sas/03_prep_md1..8.sas` | PREP-08 nulling + PREP-09 scan |
| `sas/05_qc_merge.sas` | QC-06 section |
| `docs/DECISIONS.md` | PCM-D-08, D-09, D-10 |
