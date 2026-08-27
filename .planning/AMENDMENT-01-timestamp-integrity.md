# Amendment 01 — Operative Timestamp Integrity

**Raised:** 2026-08-26, by the QC-05 abort in `05_qc_merge.sas`
**Affects:** Phase 3 (per-source normalization), Phase 5 (merge QC)
**Requires re-run:** Phase 3 → Phase 4 → Phase 5
**Status:** plans written, not executed
**Revised:** 2026-08-27 — PCM-D-08 resolved (flag, don't null); PCM-D-09 resolved (drop the ceilings); PCM-D-11 opened and closed

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
| **MRG-05** | `rt_envelope_flag` derived in the merge DATA step: 1 where either operative sub-interval exceeds `rt_RM_START_to_RM_END_mins`, else 0. Added to the MRG-04 unmapped-column exclusion list. | 4 |
| **QC-06** | Sub-interval containment asserted in the merged file: zero **unflagged** violations. The flagged count is reported, not asserted. | 5 |
| **QC-07** | The three QC-05 operative-interval ceilings (2000, 500, 2000) are REMOVED. Floors are retained via PREP-08 nulling; containment is covered by QC-06. | 5 |

**PREP-08 is deliberately scoped to three variables, not all `rt_*`.** Negative elapsed time
is invalid for a within-encounter duration, but the `rt_ANCHOR_to_*_days` variables are
offsets from an anchor date and **can legitimately be negative** — an admission preceding
the anchor is meaningful, not an error. Nulling those would destroy real data. PREP-09
reports them so the decision is made on evidence rather than by pattern-matching on the
`rt_` prefix.

## 5. Decisions — resolved 2026-08-27

### PCM-D-08 — the 9 contradictory rows: FLAG, don't null

**Resolved: add a flag column, keep the values.**

Each of the three timestamps in a violating row is individually plausible; it is the
*combination* that is impossible, and nothing identifies which of the three is wrong.
Nulling would pick a victim arbitrarily and destroy two good values to punish one bad one.
A flag preserves all three and lets the analyst decide.

`rt_envelope_flag` is derived in the **Phase 4 merge DATA step**, not in Phase 3. The
ownership map is built in Phase 2 from the SOURCE files, so a variable invented during prep
is not in it — and MRG-04 asserts zero unmapped columns in the merged file. A prep-created
flag would fail that assertion. Derived at merge time, it goes in the exclusion list beside
`n_sources` and `in_md1`–`in_md8`.

QC-06 is reframed accordingly: assert zero **unflagged** violations, report the flagged
count. That assertion stays meaningful indefinitely — it goes green now and fires again if a
future re-extract introduces a violation the flag logic misses. Asserting zero violations
would have meant either a permanently red pipeline or eventually deleting the check.

Still open, and worth doing regardless: report the 9 upstream to whoever generates the
extract.

### PCM-D-09 — the inert ceilings: DROP them

**Resolved: remove all three operative-interval ceilings from QC-05.**

2000, 500 and 2000 have never fired on any of 41,150 rows. Every QC-05 time failure was a
negative. The floors do real work and are now handled at source by PREP-08; containment is
handled by QC-06. A bound that has never fired and has no mechanism to fire is not a check,
it is decoration that invites someone to widen it later to make a run green.

QC-05 drops from 8 assertions to 5. The three `rt_*` counts and their `%assert_eq` calls come
out; the SECTION 5c distribution report is retained as a record of why.

### PCM-D-10 — negatives in the other `rt_*` variables: PENDING

Needs the PREP-09 report, which does not exist until 03-06 runs. Note in advance that
negatives in `rt_ANCHOR_to_*_days` are EXPECTED and correct — those are offsets from an
anchor date, not durations.

### PCM-D-11 — md3-owns missingness: CLOSED, costs nothing

Opened and closed 2026-08-27. See PCM-F-17.

## 5b. Additional finding

### PCM-F-17 — md3-owns inherits md3's missingness at zero cost

Ownership resolution gives md3 first claim on every variable it carries, so the merged file
inherits md3's missing values and discards any value another source holds for the same
patient. Measured on the three variables that drive the complete-case N:

| Variable | Comparison | Recoverable |
|---|---|---|
| `Admit_BMI` | md3 ← all seven others | 0 (PCM-F-07) |
| `Cognitive_Score` | md3 ← md5 | 0 |
| `Cognitive_Score` | md3 ← md6 | 0 |
| `Frailty_Score` | md3 ← md5 | 0 |
| `Frailty_Score` | md3 ← md6 | 0 |

Where md3 carries a column and the value is blank, no other source has a value for that
patient. Consistent with md3 being the fullest extract, not merely the widest.

**Caveat:** three variables, not all of them. But these three drive the 6,523 complete-case
N, so the ones that matter are checked. A patient present only in md3 cannot be recovered
from anywhere, so zero here means "no recoverable overlap," not "no missingness."

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

Expected on the Phase 5 re-run, after the 2026-08-27 decisions: **everything passes.**
- QC-05 is down to 5 assertions; the three operative-interval ceilings are gone (QC-07).
- QC-06 asserts zero UNFLAGGED violations and passes, logging `9 rows flagged`.
- The merged file gains one column, `rt_envelope_flag`.

An earlier version of this document predicted QC-06 failing at 9. That was correct under the
null-or-block reading of PCM-D-08; the flag resolution supersedes it.

## 7. Files changed

| File | Change |
|---|---|
| `.planning/PROJECT.md` | Add PCM-F-13..17, PCM-T-11, PCM-D-08..11, MRG-05, QC-06, QC-07 |
| `.planning/phases/03-per-source-normalization/03-06-PLAN.md` | NEW — PREP-08, PREP-09 |
| `.planning/phases/03-per-source-normalization/03-VALIDATION.md` | Add PREP-08/09 rows |
| `.planning/phases/05-merge-qc/05-03-PLAN.md` | NEW — QC-06, PCM-D-09 investigation |
| `.planning/phases/05-merge-qc/05-VALIDATION.md` | Add QC-06 row; assertion count 12 + n_md8_only + 1 |
| `sas/03_prep_md1..8.sas` | PREP-08 nulling + PREP-09 scan |
| `sas/04_merge.sas` | `rt_envelope_flag` derivation + MRG-04 exclusion (MRG-05) |
| `sas/05_qc_merge.sas` | QC-06 section; remove the three QC-05 ceilings (QC-07) |
| `docs/DECISIONS.md` | PCM-D-08, D-09, D-10 |
