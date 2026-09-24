# Phase 7: Cohort & Missingness -- Research

**Researched:** 2026-08-27
**Revised:** 2026-08-27 (see Revision Notes)
**Domain:** SAS 9.4 cohort definition, missingness profiling, analytic-ready dataset documentation
**Confidence:** HIGH (all findings drawn from project artifacts and established decisions)

---

## Revision Notes

**R1 -- The "53% gap" direction was stated both ways and one of them was wrong.**
The original Summary said "12,726 of the ~24,000 admitted patients HAVE Admit_BMI";
the Known Numbers section said the figure "references the ~53% of admitted patients
who LACK Admit_BMI." 12,726 / ~24,000 is approximately 53% HAVING the measurement,
so roughly 47% lack it. The two statements are complements, not the same fact. Every
occurrence now states the direction explicitly and labels the value as pending
measurement rather than fixed. See Pitfall 6.

**R2 -- PCM-F-07 vs PCM-F-17.** The BMI-unrecoverability finding was cited as PCM-F-17
in one line and PCM-F-07 in another. Standardized on PCM-F-07, which is what the
Known Numbers table and the downstream plans use. Confirm against REQUIREMENTS.md
before execution; if PCM-F-17 is correct, one edit fixes it here.

**R3 -- Added Pitfalls 6-9** covering defects found during plan review: the ODS path
separator, ODS truncation on reopen, ACCESS=READONLY vs writing to the same library,
and macro-variable scoping in the assertion macro.

---

## Summary

Phase 7 defines the analytic cohort from `g.master_data_merged` and documents the
missingness profile per key analysis variable. The cohort question (PCM-D-05) is the only
remaining open pipeline decision. Everything else -- the complete-case Ns, the md3-owns
missingness trade-off, the admission-type variable name -- is known from prior phases.

The phase produces one new SAS program (`07_cohort.sas`) that reads `g.master_data_merged`
as a read-only input, writes a filtered cohort dataset, asserts the known complete-case Ns
as code, and writes a committed missingness summary to `qc/`.

Approximately 12,726 of the roughly 24,000 admitted patients have a non-missing
Admit_BMI -- that is, about 53% HAVE the measurement and about 47% lack it. Both the
denominator and the percentage must be MEASURED in SECTION 2/3, not carried forward from
this document. This is a data-availability fact, not a pipeline defect. It must be stated
plainly, with its direction unambiguous, so downstream analysts do not mistake the
41,150-row file for a 12,726-row analysis file.

**Primary recommendation:** Define the cohort by `Patient_Type IN ('INPATIENT','OBSERVATION')`,
assert the known complete-case Ns in code, document the missingness profile in a committed QC
file, and close PCM-D-05 in `docs/DECISIONS.md`.

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PCM-D-05 | Analytic cohort INPATIENT/OBSERVATION restriction -- pending, Phase 7 | Variable `Patient_Type` already in merged file (md3-owned); restriction is defensible because geriatric assessments were never administered to ambulatory patients (PCM-F-12) |
| PCM-F-11 | Missingness profile documented per analysis variable | Known Ns from STATE.md metrics: BMI 12,726; Cognitive 20,540; Frailty 23,311; all-three 6,523 |
| PCM-F-12 | INPATIENT/OBSERVATION restriction justified by assessment eligibility | Documented rationale: ambulatory patients were never eligible for the geriatric assessments; restriction is pre-specifiable, not data-driven |
</phase_requirements>

---

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| SAS 9.4M8 | 9.4M8 | All pipeline computation | Project constraint -- no alternatives |
| `g.master_data_merged` | Phase 4/5 output | Read-only input to cohort program | Established merge output; 41,150 rows |
| `qclib.ownership_map` | Phase 2 output | Variable-to-source map if needed | Already used in Phases 4 and 5 |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| PROC FREQ | Missingness profile table (N missing, N non-missing per variable) | Preferred for tabular output; works without sorting |
| PROC MEANS | Complete-case N by variable group | Handles numeric and char (via NMISS/N options) |
| PROC SQL SELECT COUNT | Assertion counts matching known Ns | Established project pattern; never use &SQLOBS |
| `%abort cancel` | Fail loudly if assertions misfire | Required inside named %macro per PCM-R-05 |
| `assert_eq` macro | Row-count assertions | Already defined in 05_qc_merge.sas; copy or %include |
| `data _null_; file "..." mod;` | Appending prose to a QC text file | 06_reconcile.sas pattern; does NOT truncate, unlike reopening ODS LISTING |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| PROC FREQ for missingness | PROC MEANS NMISS | Both work; PROC FREQ is more self-documenting for binary present/missing |
| WHERE filter in DATA step | Separate PROC SQL CREATE TABLE | WHERE in DATA step is simpler; no PDV risk; preferred |
| ODS LISTING FILE= for the whole QC file | ODS for proc output + `file ... mod` DATA steps for prose | Mixing is fine, but reopening ODS LISTING FILE= on the same path TRUNCATES it. See Pitfall 7 |

**Installation:** No new packages. Project uses base SAS 9.4M8 only.

---

## Architecture Patterns

### Recommended Program Structure

```
sas/07_cohort.sas
  SECTION 0 -- Preconditions (libname g open WRITABLE, g.master_data_merged exists, row count = 41,150)
  SECTION 1 -- Measure Patient_Type distribution (PCM-D-05 evidence) BEFORE filtering
  SECTION 2 -- Derive g.analytic_cohort; measure admitted N
  SECTION 3 -- Missingness profile per key variable, on BOTH the merged file and the cohort
  SECTION 4 -- Assert complete-case Ns as code (BMI 12,726; Cognitive 20,540; Frailty 23,311; all-three 6,523)
  SECTION 5 -- Record md3-owns missingness trade-off (verified for three variables, unchecked elsewhere)
  SECTION 6 -- Write qc/07_cohort_missingness.txt summary; close log
```

### Pattern 1: Filtered Dataset (chosen) vs Cohort Flag

**What:** Either add a binary flag `in_analytic_cohort` to a NEW dataset, or produce
`g.analytic_cohort` as a filtered copy. Both are valid; the flag approach preserves the
full 41,150-row file for reference.

**Decision for this phase:** produce `g.analytic_cohort` (filtered), and leave
`g.master_data_merged` untouched as the provenance record.

**Critical consequence:** the `g` library must be WRITABLE. Do NOT open it with
`ACCESS=READONLY` -- that makes the whole library read-only, and the DATA step below
fails with "Library G is read only." Read-only intent toward the SOURCE dataset is
enforced by never naming it on the left of a DATA statement, not by a libname option.
See Pitfall 8.

```sas
/* WRONG -- never data X; set X; (PCM-T-02) */
data g.master_data_merged;
  set g.master_data_merged;
run;
```

```sas
/* CORRECT: filtered cohort to a new dataset name */
data g.analytic_cohort;
  set g.master_data_merged;
  where upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION');
run;
```

```sas
/* CORRECT alternative: flag column on a new dataset */
data g.master_data_cohort_flagged;
  set g.master_data_merged;
  length in_analytic_cohort 8;
  if upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION')
    then in_analytic_cohort = 1;
    else in_analytic_cohort = 0;
run;
```

### Pattern 2: Complete-Case Assertion

**What:** Assert exact Ns in code so they fail loudly on a re-extract.

```sas
/* Established project pattern: SELECT COUNT(*) INTO :macvar TRIMMED, never &SQLOBS */
%macro assert_complete_case_n(dsn=, var=, expected=, label=);
  %local actual;   /* REQUIRED -- see Pitfall 9 */
  proc sql noprint;
    select count(*) into :actual trimmed
    from &dsn
    where &var is not missing;
  quit;
  %if &actual ne &expected %then %do;
    %put ERROR: &label complete-case N = &actual, expected &expected;
    %abort cancel;
  %end;
  %put NOTE: &label complete-case N = &actual (assertion passed);
%mend assert_complete_case_n;

%assert_complete_case_n(dsn=g.master_data_merged, var=Admit_BMI,       expected=12726, label=Admit_BMI);
%assert_complete_case_n(dsn=g.master_data_merged, var=Cognitive_Score,  expected=20540, label=Cognitive_Score);
%assert_complete_case_n(dsn=g.master_data_merged, var=Frailty_Score,    expected=23311, label=Frailty_Score);
```

`INTO :macvar TRIMMED` already strips padding. Do NOT wrap the comparison in `%trim()`
-- that is an autocall macro, not a core macro function, so it adds a dependency on
`SASAUTOS` resolution for no benefit.

All-three simultaneous non-missing:
```sas
proc sql noprint;
  select count(*) into :actual_all trimmed
  from g.master_data_merged
  where Admit_BMI is not missing
    and Cognitive_Score is not missing
    and Frailty_Score is not missing;
quit;
/* assert actual_all = 6523 inside a named macro */
```

### Pattern 3: Missingness Profile Table

```sas
proc means data=g.master_data_merged n nmiss;
  var Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter;
  ods output Summary=work.miss_profile;
run;

/* Same again on g.analytic_cohort -- the cohort denominators are what
   downstream analysts actually need (Pitfall 2) */
proc means data=g.analytic_cohort n nmiss;
  var Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter;
  ods output Summary=work.miss_profile_cohort;
run;

/* For character variables use PROC FREQ with MISSING option */
proc freq data=g.master_data_merged;
  tables Patient_Type / missing;
run;
```

### Pattern 4: QC file path construction

```sas
/* CORRECT -- the trailing dot terminates the macro name and is consumed,
   so the backslash must be written explicitly */
ods listing file="&qc_path.\07_cohort_missingness.txt";
data _null_; file "&qc_path.\07_cohort_missingness.txt" mod; ... run;
```

```sas
/* WRONG -- resolves to ...\merge\qc07_cohort_missingness.txt, no separator */
ods listing file="&qc_path.07_cohort_missingness.txt";
```

This mirrors 06_reconcile.sas, which writes `"&qc_path.\06_reconcile_summary.txt"`.

### Anti-Patterns to Avoid

- **`data X; set X;`** -- destroys the dataset during the read (PCM-T-02). Never modify
  `g.master_data_merged` in place. Write to a new dataset name.
- **`&SQLOBS`** -- unreliable after a PROC SQL step with multiple queries. Always use
  `SELECT COUNT(*) INTO :macvar TRIMMED` (established project pattern).
- **`%abort cancel` outside a named macro** -- leaves an interactive SAS session that
  silently swallows the next submit (PCM-R-05). Wrap every abort in a named %macro,
  INCLUDING the dataset-existence precondition.
- **PROC SQL UPDATE on a SAS dataset** -- silent truncation trap (PCM-T-01). Never used.
- **`ACCESS=READONLY` on a library you also write to** -- see Pitfall 8.
- **Reopening `ods listing file=` on a path you already wrote to** -- see Pitfall 7.
- **Hard-coding the admitted N** -- the admitted-patient count depends on the `Patient_Type`
  distribution and should be MEASURED, not assumed. Assert what you know (the three
  complete-case Ns from prior analysis); measure what you do not (the admitted-patient N
  and every percentage derived from it).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Missingness tabulation | Custom DATA step counting loops | PROC MEANS NMISS / PROC FREQ MISSING | Built-in, handles all types, no off-by-one risk |
| Cohort row assertion | Manual count comparison | The established `assert_eq` macro pattern or a direct %abort | Already in 05_qc_merge.sas; reuse the macro |
| Decision documentation | Inline comments only | Entry in `docs/DECISIONS.md` + committed QC file | Project convention; PCM-D-05 must be formally closed there |

**Key insight:** All the data work in this phase is read-only QC over `g.master_data_merged`
plus one filtered copy. The only "new" computation is the cohort filter and the missingness
table. Both are two-line SAS procedures; do not build complexity around them.

---

## Common Pitfalls

### Pitfall 1: Asserting the admitted-patient N without measuring it first
**What goes wrong:** The INPATIENT/OBSERVATION count is assumed rather than measured.
If the source system returns different Patient_Type values (e.g., trailing spaces, mixed case),
the filter silently excludes rows and the assertion passes a wrong N.
**Why it happens:** The N is referenced in narrative (the "~53% gap") but was never
stated as an exact code-level assertion in prior phases.
**How to avoid:** MEASURE the admitted-patient N with a WHERE + COUNT before asserting
anything about it. Use `upcase(strip(Patient_Type))` in all comparisons.
**Warning signs:** The admitted N does not match expectations; BMI missingness percentage
inside the cohort differs materially from the ~47% expected.

### Pitfall 2: Conflating the 41,150-row file N with the analytic cohort N
**What goes wrong:** Complete-case Ns (12,726 / 20,540 / 23,311 / 6,523) are stated
against the full 41,150 rows. Those Ns do NOT automatically apply to the filtered cohort:
some non-missing values may sit on ambulatory rows and drop out of the cohort. A reader
comparing file N to complete-case N gets the wrong denominator.
**How to avoid:** State the denominator explicitly in every N statement, and run the
missingness profile on BOTH datasets. "12,726 of 41,150 merged rows have non-missing
Admit_BMI; X of N_admitted admitted rows do, where both X and N_admitted are measured in
SECTION 3." Do not assume X = 12,726.

### Pitfall 3: Closing PCM-D-05 in code comments but not in DECISIONS.md
**What goes wrong:** The cohort restriction is implemented in `07_cohort.sas` but
`docs/DECISIONS.md` still shows PCM-D-05 as "Pending". Phase 8 then cannot confirm all
decisions are resolved.
**How to avoid:** One of the Phase 7 plans must include a task to update DECISIONS.md
with the PCM-D-05 resolution -- reason, owner, date.

### Pitfall 4: Modifying g.master_data_merged
**What goes wrong:** A flag column is added by writing `data g.master_data_merged; set g.master_data_merged;` --
this is PCM-T-02 and destroys the dataset during the read.
**How to avoid:** Write any derived dataset to a NEW name (`g.analytic_cohort` or
`g.master_data_cohort_flagged`).

### Pitfall 5: The md3-owns missingness caveat applies to variables beyond Admit_BMI
**What goes wrong:** PCM-D-11 closed with "costs nothing" because verification confirmed
zero recoverable values for Admit_BMI, Cognitive_Score, and Frailty_Score. The caveat --
"this has NOT been verified for other md3-owned variables" -- is documented in
`data_dictionary_notes.txt` but is easy to forget.
**How to avoid:** The missingness profile should call out which variables were verified
(the three above) and which were not. Do not state "md3-owns missingness is always free"
as a global fact.

### Pitfall 6: Stating the BMI gap in the wrong direction
**What goes wrong:** "~53%" describes the share of admitted patients who HAVE Admit_BMI
(12,726 of roughly 24,000). Writing "53% lack Admit_BMI" inverts it -- the correct
complement is about 47%. An inverted figure copied into DECISIONS.md becomes a permanent
artifact and misleads anyone sizing a downstream analysis.
**Why it happens:** "the 53% gap" is ambiguous shorthand; "gap" reads as absence.
**How to avoid:** Never write a bare percentage. Write "X of N admitted rows (P%) HAVE
non-missing Admit_BMI; N-X (100-P%) lack it," with X, N, and P all measured in SECTION 3.
Retire the phrase "the 53% gap" from all Phase 7 artifacts.

### Pitfall 7: ODS LISTING truncates when reopened on the same path
**What goes wrong:** `ods listing file="...";` opened in SECTION 1, closed, then reopened
in SECTION 6 to "append" the summary lines. The second open OVERWRITES the file, so the
PROC FREQ and PROC MEANS output written earlier is silently lost. The file exists, the
greps for `admitted_n=` pass, and the missingness profile is gone.
**How to avoid:** Either keep ONE ODS LISTING destination open from SECTION 1 to SECTION 6
and close it once, or use ODS for procedure output and `data _null_; file "..." mod;` for
prose lines, which is the 06_reconcile.sas pattern and appends correctly.

### Pitfall 8: ACCESS=READONLY on a library the program writes to
**What goes wrong:** `libname g "&g_path" access=readonly;` makes the ENTIRE library
read-only. The subsequent `data g.analytic_cohort;` fails with "Library G is read only."
The intent -- protect `g.master_data_merged` -- is real, but the mechanism is wrong.
**How to avoid:** Open `g` writable (as 06_reconcile.sas does) and enforce read-only
intent toward the source by never naming `g.master_data_merged` on the left of a DATA
statement. If a hard guarantee is wanted, open a second READONLY libref for reading and
a writable one for the cohort output -- but two librefs on the same physical path is
itself a trap, so prefer the convention.

### Pitfall 9: Macro variable not scoped %local in the assertion macro
**What goes wrong:** `%macro assert_complete_case_n` populates `&actual` without a
`%local` declaration, so it lands in the global symbol table. If a PROC SQL step fails
(bad variable name, locked dataset), `&actual` retains the PREVIOUS call's value and the
assertion compares against stale data -- passing when it should fail.
**How to avoid:** `%local actual;` as the first statement of the macro.

---

## Known Numbers (from Prior Phases -- HIGH confidence, verified in project artifacts)

| Metric | Value | Source |
|--------|-------|--------|
| Full merged file rows | 41,150 | QC-01, Phase 5 |
| Admit_BMI non-missing | 12,726 | STATE.md performance metrics |
| Cognitive_Score non-missing | 20,540 | STATE.md performance metrics |
| Frailty_Score non-missing | 23,311 | STATE.md performance metrics |
| All three non-missing | 6,523 | STATE.md performance metrics |
| Admit_BMI missing (total file) | 28,424 | `41150 - 12726`; verified as unrecoverable (PCM-F-07, PCM-D-11) |
| md3-owns BMI recovery | 0 rows | Verified vs all 7 other sources (PCM-F-07) |
| md3-owns Cognitive recovery | 0 rows | Verified vs md5, md6 (PCM-D-11) |
| md3-owns Frailty recovery | 0 rows | Verified vs md5, md6 (PCM-D-11) |

### Numbers that are NOT yet known -- measure, do not assume

| Metric | Status | Where measured |
|--------|--------|----------------|
| Admitted-patient N (INPATIENT+OBSERVATION) | Approximately 24,000, never fixed as an assertion | SECTION 2 |
| Admit_BMI non-missing WITHIN the cohort | Unknown; not necessarily 12,726 | SECTION 3 |
| Percent of admitted rows HAVING Admit_BMI | Approximately 53% if all 12,726 fall inside the cohort | SECTION 3 |
| Percent of admitted rows LACKING Admit_BMI | Approximately 47%, the complement of the above | SECTION 3 |

The phrase "the ~53% gap" appears in STATE.md and the ROADMAP. It refers to the share
of admitted patients who HAVE Admit_BMI. Do not restate it without naming the direction.

---

## PCM-D-05: What the Planner Needs to Resolve

**The decision:** Restrict the analytic cohort to patients with
`Patient_Type IN ('INPATIENT','OBSERVATION')`.

**Rationale to document:** Ambulatory patients were never eligible for the geriatric
assessments that produce Admit_BMI, Cognitive_Score, and Frailty_Score. A restriction based
on assessment eligibility is pre-specifiable and clinically defensible; a restriction based
on data availability (i.e., only keep patients with non-missing BMI) introduces selection
bias on the outcome.

**What Phase 7 must produce:**
1. The `Patient_Type` values actually present in `g.master_data_merged` -- MEASURE first
   (PROC FREQ with MISSING option to catch blanks).
2. The admitted-patient N (row count where Patient_Type IN ('INPATIENT','OBSERVATION')).
3. The complete-case Ns asserted against the merged file, AND measured within the cohort.
4. The PCM-D-05 entry in DECISIONS.md updated to Resolved, with measured values transcribed.

**Inherited from Phase 6 (PCM-D-07):** The age floor question (min observed = 64, QC-05
floor = 18) is inherited by Phase 7. Current recommendation from the data dictionary notes:
do NOT tighten the QC-05 floor to 64; if an age floor is wanted, add it as a cohort criterion
distinct from the QC-05 guard.

---

## Environment Availability

Step 2.6: SKIPPED -- Phase 7 is a SAS computation over existing datasets, producing one
new dataset in an existing library. No external tools, services, or CLIs beyond SAS 9.4M8
and the established P: drive libnames.

**Execution mode:** SAS 9.4M8 on Windows, submitted interactively or via a batch wrapper.
There is no confirmed `sas` command-line executable on this workstation. Validation
documents must not assume a CLI invocation without confirming it.

---

## Validation Architecture

No Nyquist-style automated test framework is in use (SAS 9.4 batch pipeline; no pytest/jest
config detected). Validation is via SAS `%abort cancel` assertions inside named macros, which
is the established project pattern.

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | How Verified |
|--------|----------|-----------|--------------|
| PCM-D-05 | INPATIENT/OBSERVATION restriction applied and documented | Assertion + log | `SELECT COUNT(*)` of admitted rows written to log; PCM-D-05 entry in DECISIONS.md updated to Resolved |
| PCM-F-11 | Missingness profile documented per analysis variable | Output artifact | PROC MEANS NMISS / PROC FREQ output written to `qc/07_cohort_missingness.txt` for BOTH merged file and cohort |
| PCM-F-12 | INPATIENT/OBSERVATION restriction justified by assessment eligibility | Documentation | PCM-D-05 resolution entry in DECISIONS.md states the eligibility rationale explicitly |
| COH-01 | `07_cohort.sas` runs and produces documented cohort | Run pass | Program completes without abort; output file written |
| COH-02 | Missingness profile for all key variables | Output artifact | Committed `qc/07_cohort_missingness.txt` |
| COH-03 | Complete-case Ns re-asserted as code | Assertion | `%abort cancel` fires if any of the four known Ns mismatches |
| COH-04 | INPATIENT/OBSERVATION restriction documented with rationale | Documentation | DECISIONS.md PCM-D-05 closed; QC summary references it |

### Wave 0 Gaps
- [ ] `sas/07_cohort.sas` -- does not yet exist; must be created in plan Wave 1
- [ ] `qc/07_cohort_missingness.txt` -- output file; path on P: drive (outside git); copy to `qc/` in repo if commit history is wanted
- [ ] DECISIONS.md PCM-D-05 entry -- currently "Pending -- Phase 7 | TBD"; must be updated to Resolved

**Filename note:** the QC artifact is `07_cohort_missingness.txt` in every Phase 7
document. Any reference to `07_cohort_summary.txt` is stale and should be corrected.

---

## Open Questions

1. **Does the planner want a filtered dataset or a flag column?**
   - Recommendation: produce `g.analytic_cohort` (filtered) AND document the restriction.
     The filtered dataset is what downstream analysts actually load. Keep
     `g.master_data_merged` untouched (it is the provenance record).
   - RESOLVED for planning purposes: filtered dataset. Requires a writable `g` library.

2. **Is the admitted-patient N already known?**
   - What we know: the "~53%" figure implies the admitted N is approximately 24,000.
   - What's unclear: the exact admitted N was never fixed as a code assertion.
   - Recommendation: MEASURE it in SECTION 2; do not hard-code it.

3. **Do the complete-case Ns hold within the cohort?**
   - What we know: 12,726 / 20,540 / 23,311 / 6,523 are counts within the full 41,150 rows.
   - What's unclear: whether any non-missing values sit on ambulatory rows and drop out.
   - Recommendation: assert the four Ns against `g.master_data_merged` (where they were
     derived) and MEASURE the corresponding within-cohort counts separately. Do not
     assert the within-cohort values until they have been observed once.

4. **Age floor (PCM-D-07, inherited from Phase 6):**
   - Recommendation: do not add a new age floor unless there is clinical justification
     beyond the observed minimum. Document in the PCM-D-05 resolution that the cohort
     does not apply an additional age filter, and note the observed minimum of 64 as a
     data characteristic.

---

## Sources

### Primary (HIGH confidence)
- `.planning/STATE.md` -- complete-case Ns, established decisions, performance metrics
- `.planning/ROADMAP.md` -- Phase 7 goal, requirements, success criteria
- `.planning/REQUIREMENTS.md` -- COH-01 through COH-04 requirement text
- `docs/DECISIONS.md` -- PCM-D-05 open status, PCM-D-11 closed, all prior decisions
- `docs/data_dictionary_notes.txt` -- md3-owns missingness caveat, PCM-D-07 age floor note
- `sas/06_reconcile.sas` -- established coding patterns (named macros, COUNT INTO TRIMMED,
  `file ... mod` appending, `"&qc_path.\file.txt"` path construction)

### Secondary (MEDIUM confidence)
- SAS 9.4 documentation (PROC MEANS NMISS, PROC FREQ MISSING option) -- standard options,
  no version sensitivity at SAS 9.4M8

---

## Metadata

**Confidence breakdown:**
- Known Ns (complete-case, full file): HIGH -- asserted in code (Phase 5), recorded in STATE.md
- Cohort restriction variable (`Patient_Type`): HIGH -- md3-owned, present in merged file
- Missingness mechanics (md3-owns): HIGH -- verified for the three primary analysis variables
- Admitted-patient N: MEDIUM -- approximate (~24,000); must be measured
- Within-cohort complete-case Ns: LOW -- never measured; do not assume they equal the
  full-file values

**Research date:** 2026-08-27
**Valid until:** Phase 7 execution. If 03-06 re-run changes `g.master_data_merged` row count,
re-confirm the four complete-case Ns before asserting them in 07_cohort.sas.
