# Phase 16: Rebuild the Analytic Cohort - Research

**Researched:** 2026-09-21
**Domain:** SAS 9.4M8 cohort rebuild -- reading g.master_data_harmonized, producing g.analytic_cohort
**Confidence:** HIGH (all findings from direct codebase inspection, no external research needed)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Hardcode INPATIENT+OBSERVATION filter. PCM-D-05 is resolved as "admitted-only,
because Admit_BMI forces it." Filter variable: Patient_Type (confirmed below). Exact match
values: `upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION')` -- identical to 07_cohort.sas
line 183. No parameterization gate needed.

**D-02:** DECISIONS.md PCM-D-05 entry must state what the restriction actually does (clinically
different population, not a convenience filter), with all five figures:
- Charlson 0: 60.8% (full) -> 34.5% (cohort)
- General anaesthesia: 57.6% -> 84.2%
- GI service: 18.4% -> 1.7%
- Colonoscopy: 8.5% -> 0.4%
- RACE=WHITE: 79.8% -> 87.1% (7.3-point shift)

**D-03:** New standalone program `sas/16_cohort_rebuild.sas` -- but see NUMBERING COLLISION
FINDING below. Leaves `sas/07_cohort.sas` unmodified.

**D-03a:** Before creating any 16_* artifact, confirm the ROADMAP has no other Phase 16.
FINDING: `sas/16_raw_inventory.sas` and `sas/16_summary_docx.sas` already exist in git.
The prefix `16_` is taken. This must be resolved (renumber this phase or confirm those files
are reassigned) before the planner chooses a file name.

**D-04:** Do NOT add `16_cohort_rebuild.sas` to `sas/99_run_all.sas`. That is Phase 8's job.

**D-05:** Re-measure complete-case Ns from g.master_data_harmonized. Assert on full file:
Admit_BMI=12,726; Cognitive_Score=20,540; Frailty_Score=23,311. Measure within-cohort
Cognitive and Frailty (do not assert). May assert within-cohort Admit_BMI=12,726 (D-01
rationale).

**D-06:** Drop the all-three simultaneous assertion (was 6,523 -- stale). Measure it;
record in 16-0X-SUMMARY.md and STATE.md.

**D-07:** Measure h_* harmonized column Ns within the cohort; report in QC file, do not assert.

**D-08:** Assert g.master_data_harmonized is unmodified post-run (174 cols, 41,150 rows),
mirroring the `%assert_merged_unchanged` pattern from 10b_concept_harmonize.sas.

**D-09:** g.analytic_cohort carries all 174 columns from g.master_data_harmonized (full
pass-through, admitted rows only). No curated subset.

### Claude's Discretion

Program section structure, macro naming, ODS LISTING handling, log routing, and QC file
format: follow the 07_cohort.sas and 10b_concept_harmonize.sas patterns already established
in the codebase.

PCM violations to avoid: PCM-T-01, T-02, T-11, R-02, R-05; no SQLOBS; no non-ASCII; no
in-place dataset rewrite; every abort inside named macro.

### Deferred Ideas (OUT OF SCOPE)

None -- discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HARM-10 | g.analytic_cohort rebuilt from g.master_data_harmonized; carries h_ columns; no dropped aliases | D-09 (full pass-through, 174 cols); numbering collision must be resolved to produce the correct file name |
| PCM-D-05 | Cohort restriction resolved and recorded with attribution, BMI-forces-it rationale, five population-shift figures | D-01 (filter logic confirmed), D-02 (figures from ROADMAP SC-3/SC-4, transcribe not re-measure) |
</phase_requirements>

---

## Summary

Phase 16 writes a single SAS program that reads `g.master_data_harmonized` (174 cols,
41,150 rows, confirmed Phase 15), applies the INPATIENT+OBSERVATION Patient_Type filter,
and promotes the validated candidate to `g.analytic_cohort`. It also resolves and records
PCM-D-05 in `docs/DECISIONS.md`.

The filter variable and its exact values are fully confirmed from `sas/07_cohort.sas`
(line 183): `where upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION')`. The
admitted-cohort N of 13,890 (INPATIENT 13,223 + OBSERVATION 667) is recorded in STATE.md
and is the reference for the degenerate-cohort guard and `%verify_promotion`. The full-file
complete-case Ns to assert (12,726 / 20,540 / 23,311) are confirmed in STATE.md and
07_cohort.sas SECTION 4.

**The critical planning blocker:** `sas/16_raw_inventory.sas` and `sas/16_summary_docx.sas`
already exist in the repository. The prefix `16_` is taken. The planner must either assign
this cohort program a different prefix (e.g., `16b_cohort_rebuild.sas`) or confirm the
existing 16_* files are renumbered before naming any artifact.

**Primary recommendation:** Plan two tasks -- Plan 01: resolve numbering and write the SAS
program; Plan 02: write the DECISIONS.md PCM-D-05 entry and record baselines in SUMMARY.md
and STATE.md.

---

## Standard Stack

This phase is pure SAS 9.4M8. No new libraries or packages are introduced.

| Asset | Version/Location | Purpose |
|-------|-----------------|---------|
| SAS 9.4M8 | Installed on workstation | Execution environment |
| g library | P:\...\merge | Source (harmonized) and target (cohort) |
| 00_config.sas | sas/00_config.sas | g_path, qc_path, logs_path |
| 07_cohort.sas | sas/07_cohort.sas | Pattern source; do not modify |
| 10b_concept_harmonize.sas | sas/10b_concept_harmonize.sas | assert_merged_unchanged pattern |

---

## Architecture Patterns

### Established Program Structure (from 07_cohort.sas)

```
SECTION 0: Options, paths, %fail_out, %check_dir, PROC PRINTTO, preconditions
SECTION 1: PROC FREQ on Patient_Type (ODS LISTING FILE= -> separate tables file)
SECTION 2: Build work.cohort_candidate (DATA step WHERE filter), %classify_cohort
SECTION 3: PROC MEANS missingness profile; within-cohort Ns measured; ODS LISTING closed
SECTION 4: Full-file complete-case assertions (%assert_complete_case_n x3)
           h_* column Ns measured (D-07, not asserted)
           All-three N measured (D-06, not asserted)
SECTION 5: Promote work.cohort_candidate -> g.analytic_cohort, %verify_promotion
SECTION 6: %assert_harmonized_unchanged (174 cols, 41,150 rows) [new, from 10b pattern]
SECTION 7: QC summary (data _null_ file mod), %gate_on_status
PROC PRINTTO (restore log)
```

The SECTIONS 1-5 structure mirrors 07_cohort.sas exactly, with the source dataset name
changed from g.master_data_merged to g.master_data_harmonized. SECTION 6 adds the
post-run dataset-unchanged assertion (new in this program, borrowed from 10b).

### Filter Logic (confirmed from 07_cohort.sas line 183)

```sas
data work.cohort_candidate;
  set g.master_data_harmonized;
  where upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION');
run;
```

Patient_Type is confirmed present in g.master_data_harmonized: it was a column in
g.master_data_merged and the harmonization step (10b) does a full pass-through; none of
the harmonization drops Patient_Type (the drops were 13 redundant aliases + in_md3 +
12 h_*_src columns). Confirmed also by 07-01-SUMMARY.md: %check_vars_present verified
Patient_Type present in merged; 10b carries it forward intact.

### Reusable Macros (copy verbatim or adapt)

| Macro | Source file | Adaptation needed |
|-------|-------------|-------------------|
| `%fail_out(msg=)` | 07_cohort.sas | Change program name in put statements |
| `%check_dir(path=, label=)` | 07_cohort.sas | None |
| `%assert_complete_case_n(var=, expected=, outvar=)` | 07_cohort.sas | None -- reuse as-is |
| `%classify_cohort` | 07_cohort.sas | Change n_merged reference to n_harmonized |
| `%gate_on_status` | 07_cohort.sas | None |
| `%verify_promotion` | 07_cohort.sas | None |
| `%assert_merged_unchanged` pattern | 10b_concept_harmonize.sas | Adapt: check harmonized (174 cols, 41,150 rows) not merged |

### Dataset-Unchanged Assertion Pattern (from 10b, SECTION 6)

```sas
%macro assert_harmonized_unchanged;
  %local n_cols n_rows;
  proc sql noprint;
    select count(*) into :n_cols trimmed
    from dictionary.columns
    where libname='G' and upcase(memname)='MASTER_DATA_HARMONIZED';
    select count(*) into :n_rows trimmed
    from g.master_data_harmonized;
  quit;
  %if &n_cols ne 174 or &n_rows ne 41150 %then
    %fail_out(msg=g.master_data_harmonized changed: &n_cols cols and &n_rows rows -- expected 174 and 41150);
  %put NOTE: g.master_data_harmonized confirmed post-run -- 174 columns and 41150 rows -- unmodified;
%mend assert_harmonized_unchanged;
```

### QC Output Files

| File | Written by | Content |
|------|-----------|---------|
| `&qc_path.\16_cohort_missingness.txt` | data _null_ file / file mod | grep-able key=value summary |
| `&qc_path.\16_cohort_tables.txt` | ODS LISTING FILE= | PROC FREQ, PROC MEANS tables |
| `&logs_path.\16_cohort_rebuild.log` | PROC PRINTTO | Full SAS log |

Note: file names carry the `16_` prefix. If the program is renumbered (e.g., `16b_`), these
file names must also change consistently.

### Anti-Patterns to Avoid

- **Writing g.analytic_cohort before all assertions pass:** build in WORK first, promote in
  one DATA step after every check passes (D-05 / 07_cohort.sas design).
- **`&SQLOBS`:** never use; all counts via `SELECT COUNT(*) INTO :macvar TRIMMED`.
- **`ods listing close;`:** use `ods listing;` (reopen default) -- close leaves destination
  shut for the rest of the session.
- **Asserting within-cohort Cognitive/Frailty Ns:** after MRG-06 most values are ambulatory,
  so within-cohort Ns are well below 20,540 / 23,311 by design. Asserting them would fire
  legitimately, not by anomaly (D-05).
- **Asserting the all-three N of 6,523:** this was asserted in 07_cohort.sas SECTION 4
  (`assert_all_three`). It is pre-coalesce and stale. Measure only, do not assert (D-06).
- **`data g.master_data_harmonized; set g.master_data_harmonized;`:** in-place rewrite
  destroys the dataset (PCM-T-02). The program reads harmonized but must never write it.
- **Non-ASCII characters in the program file:** SAS 9.4M8 session encoding is not UTF-8
  (PCM-F-10). Comments and PUT statements must be pure ASCII.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Degenerate cohort guard | Custom IF/THEN | `%classify_cohort` / `%gate_on_status` from 07_cohort.sas |
| Row count after promotion | Manual re-query | `%verify_promotion` from 07_cohort.sas |
| Post-run source dataset check | Ad hoc | `%assert_harmonized_unchanged` adapted from 10b SECTION 6 |
| BMI HAVE/LACK percentages | Independent rounding | `%bmi_pct` pattern from 07_cohort.sas (LACK derived FROM HAVE; no two-quotient rounding error) |

---

## Numbering Collision Finding (D-03a -- RESOLVED BY RESEARCH)

**Finding:** The `16_` prefix is taken by two programs already in the repository:

| File | Purpose |
|------|---------|
| `sas/16_raw_inventory.sas` | Profiles supplemental raw files (Phase 18 precursor) |
| `sas/16_summary_docx.sas` | (Purpose: separate summary program) |

**What 07_cohort.sas asserted (D-05 scope question):** 07_cohort.sas SECTION 4 asserted
complete-case Ns AGAINST `g.master_data_merged` (the full 41,150-row file), NOT within the
cohort. The `%assert_complete_case_n` macro queries `g.master_data_merged` directly (line 327:
`from g.master_data_merged`). Within-cohort Ns were MEASURED only (SECTION 3). This confirms
D-05: Phase 16 must assert full-file Ns against g.master_data_harmonized, and measure (not
assert) within-cohort Ns for Cognitive and Frailty.

**Resolution the planner must make:** Use a prefix that does not collide. Options:
- `16b_cohort_rebuild.sas` -- acknowledges the existing 16_* files; consistent with `10b_` precedent
- Renumber this Phase 16 to Phase 19 or 20 -- cleaner but requires ROADMAP/STATE update
- Confirm 16_raw_inventory.sas and 16_summary_docx.sas should be renumbered first

The planner must choose one option and apply it consistently to the program name, log name,
and QC file names before writing any artifact.

---

## Admitted Cohort N -- Confirmed (D-01 open item)

STATE.md Performance Metrics table (line 97-98):

```
Admitted cohort N        : 13,890  (INPATIENT 13,223 + OBSERVATION 667)
Within-cohort BMI        : 12,726  (91.6%) -- ALL BMI values are inside the admitted cohort
Within-cohort Cognitive  :  7,252  (52.2%) -- 13,288 of 20,540 sit OUTSIDE the cohort
Within-cohort Frailty    :  8,150  (58.7%) -- 15,161 of 23,311 sit OUTSIDE the cohort
```

The admitted-cohort N of **13,890** is the reference for `%classify_cohort`,
`%gate_on_status`, and `%verify_promotion`. Use it as the denominator for the HAVE/LACK
BMI percentages in the QC summary.

The all-three N (D-06 baseline) is **NOT in STATE.md** -- it was flagged as stale
(6,523 was pre-coalesce). The program measures it fresh and that measured value becomes
the new baseline, recorded in SUMMARY.md and STATE.md.

---

## Price Status on PCM-D-05 (D-01 open item -- partially resolved)

CONTEXT.md D-01 states Price's status is TBD (consulted vs informed after the fact).
The DECISIONS.md entry must name both the decider (Gerard, 2026-09-21) and Price's status.

**Research finding:** No source in the codebase or planning artifacts confirms Price's
status. This remains an open item. The planner must either:
1. Record it as "Gerard decided; Price to be informed" and create a task to update
   DECISIONS.md if Price's involvement changes, or
2. Block Plan 02 (DECISIONS.md entry) until Gerard confirms Price's status.

ROADMAP requires PCM-D-05 to be "resolved and attributed" -- not just resolved.

---

## h_* Column List for SECTION 4 Measurement (D-07)

The 12 harmonized columns in g.master_data_harmonized (from 15-02-SUMMARY.md):

| Column | N Populated | Pct |
|--------|------------|-----|
| H_DEATH_YN | 22,917 | 55.7% |
| H_DIABETES | 5,983 | 14.5% |
| H_FRAILTY_ACTIVITY | 14,025 | 34.1% |
| H_FRAILTY_EXHAUST | 14,181 | 34.5% |
| H_FRAILTY_GRIP | 13,699 | 33.3% |
| H_FRAILTY_WALKING | 13,989 | 34.0% |
| H_FRAILTY_WEIGHT | 14,156 | 34.4% |
| H_HYPERLIPIDEMIA | 11,207 | 27.2% |
| H_HYPERTENSION | 12,546 | 30.5% |
| H_MOVEMENT_DISORDER | 1,357 | 3.3% |
| H_SLEEP_APNEA | 3,812 | 9.3% |
| H_SSDI_DEATH | 29,316 | 71.2% |

These are the full-file Ns. The within-cohort Ns (admitted rows only) have never been
established -- they are D-07 baselines, reported to the QC file but not asserted.

---

## Common Pitfalls

### Pitfall 1: Asserting 07_cohort.sas within-cohort Ns in the new program

**What goes wrong:** Copying the within-cohort `%assert_complete_case_n` calls from
07_cohort.sas would fire by design after MRG-06, because most Cognitive and Frailty
values now sit on ambulatory rows (excluded from the cohort). The assert would abort
a correctly-running program.

**How to avoid:** Full-file assertions only (12,726 / 20,540 / 23,311). Within-cohort
Cognitive and Frailty are measured and reported, not asserted.

### Pitfall 2: Asserting the all-three N of 6,523

**What goes wrong:** 07_cohort.sas has `%macro assert_all_three` with `expected=6523`.
This figure was established pre-MRG-06 coalesce. After coalesce most cognitive/frailty
values are ambulatory, so the within-cohort all-three N is substantially lower than 6,523.
Asserting it would abort on correct data.

**How to avoid:** Remove `assert_all_three` entirely. Measure the value, write to QC file,
record in SUMMARY.md and STATE.md as the new baseline.

### Pitfall 3: Writing g.analytic_cohort before validation passes

**What goes wrong:** g.analytic_cohort is promoted over the Phase 7 version (which was
built from g.master_data_merged). If the program promotes before assertions pass, a
partial or incorrect cohort replaces the old one permanently.

**How to avoid:** Build in `work.cohort_candidate`, validate fully, promote in one DATA
step in SECTION 5 only after every assertion passes.

### Pitfall 4: `ods listing close;` leaves the session destination closed

**What goes wrong:** Later PROCs in this session produce no output. The 07_cohort.sas
revision notes document this explicitly: use `ods listing;` (reopen default) not
`ods listing close;`.

**How to avoid:** Use `ods listing;` after the ODS LISTING FILE= section closes.

### Pitfall 5: Prefix collision with 16_raw_inventory.sas

**What goes wrong:** A program named `16_cohort_rebuild.sas` produces QC files
`16_cohort_missingness.txt` and `16_cohort_tables.txt`, which are visually adjacent to
`16_raw_inventory.txt` in the qc/ folder. More critically, the SAS log file
`16_cohort_rebuild.log` is a different program from `16_raw_inventory.sas` but sits in
the same logs/ directory under the same phase prefix. No runtime collision occurs, but
the naming breaks the convention that `16_*` refers to the raw inventory program.

**How to avoid:** Resolve D-03a before writing any file. See Numbering Collision section.

### Pitfall 6: ODS LISTING FILE= truncates the QC summary file

**What goes wrong:** Opening an ODS destination with FILE= creates or replaces, it does
not append. If ODS LISTING FILE= points to `16_cohort_missingness.txt`, it truncates the
header written by the opening `data _null_` step.

**How to avoid:** ODS LISTING FILE= must point to the TABLES file (`16_cohort_tables.txt`).
The missingness summary file is written exclusively by `data _null_; file "..." mod;` steps.

---

## DECISIONS.md PCM-D-05 Entry Requirements

Plan 02 writes the PCM-D-05 entry in docs/DECISIONS.md. It must contain:

1. **Rationale (new, not old):** Admit_BMI forces the restriction -- all 12,726 values are
   inside the admitted cohort; zero are ambulatory. The old rationale (PCM-F-12: ambulatory
   patients never eligible for geriatric assessments) is void after MRG-06 and PCM-F-19.

2. **BMI HAVE/LACK percentages:** computed by the program from the admitted-cohort N (13,890).
   Expected: 91.6% HAVE, 8.4% LACK. Both directions spelled out. Denominator named explicitly.
   Do NOT use the shorthand "the ~53% gap" (per CONTEXT.md Specifics).

3. **Five population-shift figures** (from Phase 13 measurements; transcribe, do not re-measure):
   - Charlson 0: 60.8% -> 34.5%
   - General anaesthesia: 57.6% -> 84.2%
   - GI service: 18.4% -> 1.7%
   - Colonoscopy: 8.5% -> 0.4%
   - RACE=WHITE: 79.8% -> 87.1% (7.3-point shift -- required in methods sections)

4. **Attribution:** decided by Gerard (2026-09-21); Price's status (TBD -- to be filled in).

5. **Cohort N:** 13,890 (INPATIENT 13,223 + OBSERVATION 667).

---

## Environment Availability

Step 2.6 SKIPPED for external tools -- this phase is SAS-only, using the established pipeline
paths from 00_config.sas. No new external dependencies. The g library, qc_path, and logs_path
are on P: drive; they are confirmed available from prior phase runs through Phase 15.

SAS 9.4M8 interactive submission required (no confirmed CLI executable on this workstation,
per 07-01-SUMMARY.md Task 2 note).

---

## Validation Architecture

nyquist_validation is not explicitly disabled in .planning/config.json (file not found),
so validation applies.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS 9.4M8 -- assertions embedded in program (pipeline convention) |
| Config file | none -- assertions are SAS macros within 16_cohort_rebuild.sas |
| Quick run command | Interactive SAS submission (no CLI executable confirmed) |
| Full suite command | Submit 16_cohort_rebuild.sas in a fresh SAS session |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Command | Exists? |
|--------|----------|-----------|---------|---------|
| HARM-10 | g.analytic_cohort derives from harmonized; carries h_ columns; no dropped aliases | in-program assertion | %verify_promotion + %assert_harmonized_unchanged | No -- Wave 0 |
| HARM-10 | Filter keeps only INPATIENT+OBSERVATION | in-program assertion | %assert_cohort_values (post-filter invariant) | No -- Wave 0 |
| PCM-D-05 | DECISIONS.md PCM-D-05 entry present with attribution and five figures | manual review | Human reads docs/DECISIONS.md | No -- Wave 0 |
| PCM-D-05 | Full-file Ns 12,726/20,540/23,311 asserted | in-program assertion | %assert_complete_case_n x3 | No -- Wave 0 |

### Wave 0 Gaps

- [ ] `sas/16_cohort_rebuild.sas` (or renumbered equivalent) -- covers HARM-10, PCM-D-05
- [ ] PCM-D-05 entry in `docs/DECISIONS.md` -- covers PCM-D-05 attribution requirement

---

## Open Questions

1. **Program prefix / numbering collision**
   - What we know: `sas/16_raw_inventory.sas` and `sas/16_summary_docx.sas` exist with
     the `16_` prefix. The CONTEXT.md named the program `16_cohort_rebuild.sas`.
   - What's unclear: whether `16_raw_inventory.sas` was supposed to be renumbered to
     Phase 18 (which is where the raw inventory work landed in the ROADMAP), or whether
     the cohort rebuild should use a non-colliding prefix.
   - Recommendation: planner should name the program `16b_cohort_rebuild.sas` consistent
     with the `10b_` precedent already in the repo, or confirm with Gerard that
     16_raw_inventory.sas / 16_summary_docx.sas should be renamed first.

2. **Price's status on PCM-D-05**
   - What we know: CONTEXT.md says [TBD: consulted / informed after the fact].
   - What's unclear: whether the DECISIONS.md entry can be committed without confirming
     Price's involvement, or whether that requires a human checkpoint.
   - Recommendation: treat as a required human checkpoint in Plan 02 before the commit.

3. **All-three N new baseline**
   - What we know: the SAS program will measure the new all-three N on the first clean run.
   - What's unclear: exact value (not in STATE.md because it was flagged stale).
   - Recommendation: Plan 02 task must include reading the QC output and recording the
     measured value in 16-02-SUMMARY.md and STATE.md before the phase is closed.

---

## Sources

### Primary (HIGH confidence)

- `sas/07_cohort.sas` -- filter variable, filter values, macro patterns, assertion scope
  (full-file vs within-cohort), ODS LISTING pitfall, %fail_out, %verify_promotion
- `sas/10b_concept_harmonize.sas` -- %assert_merged_unchanged pattern (adapted to harmonized)
- `.planning/STATE.md` -- admitted cohort N (13,890), within-cohort Ns, stale 6,523 flag
- `.planning/phases/15-extend-the-harmonized-dataset/15-02-SUMMARY.md` -- g.master_data_harmonized
  spec (174 cols, 41,150 rows), h_* column list and full-file coverage Ns
- `.planning/phases/07-cohort-missingness/07-01-SUMMARY.md` -- assertion scope confirmation
  (SECTION 4 queries g.master_data_merged, not cohort_candidate)
- `docs/DECISIONS.md` -- current PCM-D-05 status ("Pending -- Phase 7 | TBD")
- `sas/` directory listing -- confirmed 16_raw_inventory.sas and 16_summary_docx.sas exist

### Secondary (MEDIUM confidence)

- `.planning/ROADMAP.md` Phase 16 -- success criteria SC-3 and SC-4 for the five figures
  (figures are stated as facts from Phase 13; Phase 16 transcribes them)

---

## Metadata

**Confidence breakdown:**
- Filter logic and macros: HIGH -- read directly from 07_cohort.sas source
- Admitted N: HIGH -- from STATE.md, consistent with D-01 rationale
- h_* columns: HIGH -- from 15-02-SUMMARY.md (SAS run confirmed 2026-09-21)
- Numbering collision: HIGH -- ls of sas/ directory confirmed two 16_* files
- Price's status: LOW -- not documented anywhere in the codebase; requires human input

**Research date:** 2026-09-21
**Valid until:** Until Phase 15 SAS run changes g.master_data_harmonized schema (not expected)
