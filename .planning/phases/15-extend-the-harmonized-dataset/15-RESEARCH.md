# Phase 15: Extend the Harmonized Dataset — Research

**Researched:** 2026-09-14
**Domain:** SAS 9.4 concept harmonization; `10b_concept_harmonize.sas` extension; pipeline-derived column rule
**Confidence:** HIGH (all findings drawn from committed project code and planning artifacts)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| HARM-04 | Every canonical-name decision recorded in `concept_decisions.csv`, attributed and dated, applied by program rather than by hand | Existing `10b_concept_harmonize.sas` reads `concept_decisions.csv` and applies it; Phase 15 extends the same file with the EXT template rows; the attribution/date convention must be established in the CSV itself |
| HARM-07 | A written rule states which pipeline-derived columns are carried vs. dropped and is enforced in code; the rule must address the 12 no-information columns: `in_md3` (constant) + eleven `h_*_src` companions (each single-value) | These 12 columns currently appear in `g.master_data_harmonized`; the rule should be encoded as a `%let drop_pipeline_noinfo = 1;` gate in `10b_concept_harmonize.sas` with explicit DROP statements and a post-run assertion |
</phase_requirements>

---

## Summary

Phase 15 has two independent deliverables that can be developed in parallel but must both be proven before the final re-run is committed.

**Deliverable A (HARM-04):** Extend `docs/concept_decisions.csv` with the SSDI death family and CPT1 code/label entries from `docs/concept_decisions_EXT_TEMPLATE.csv`, after a human has filled CONFIRMED=YES. The existing `10b_concept_harmonize.sas` machinery reads this file, validates it with thirteen hard gates, proves redundancy in-run, and produces `g.master_data_harmonized`. No new SAS code is needed for the core harmonization step — only the CSV population and a re-run.

**Deliverable B (HARM-07):** State and enforce the pipeline-derived column rule. The twelve no-information columns (`in_md3` + eleven `h_*_src` companions) must be named in a written rule inside the program and dropped via a guarded DROP block in the DATA step. Dropping them does NOT require a redundancy proof (they are not alias columns — they are derivations with a structural reason to drop); the enforcement is a direct DROP with an assertion that all twelve are absent from the harmonized output.

**Primary recommendation:** Run `10b_concept_harmonize.sas` twice — first with only the EXT rows added (proves the new concepts, generates the new `h_` columns, re-proves the existing eleven redundancies), then verify the HARM-07 rule is enforced. Both can live in the same re-run if the program is extended first.

---

## Standard Stack

### Core

| Library/Program | Version | Purpose | Why Standard |
|-----------------|---------|---------|--------------|
| `sas/10b_concept_harmonize.sas` | Current (2026-08-27) | Reads `concept_decisions.csv`, validates, proves redundancy, produces `g.master_data_harmonized` | Existing machinery; Phase 15 extends it, does not replace it |
| `docs/concept_decisions.csv` | Current (11 concepts) | Human decision file read by 10b | The existing pattern; HARM-04 extends it with EXT rows |
| `docs/concept_decisions_EXT_TEMPLATE.csv` | Phase 14 output | Value-level template for SSDI + CPT1 concepts | Produced by `14_label_similarity.sas`; human fills CONFIRMED=YES column |
| `docs/label_similarity_candidates.csv` | Phase 14 output | Human-review candidate list from label sweep | Human reviews to determine which (if any) label-matched pairs to confirm |

### Supporting

| Library/Program | Purpose | When to Use |
|-----------------|---------|-------------|
| `sas/00_config.sas` | Macro variables for all paths (`g_path`, `docs_path`, `qc_path`, `logs_path`) | Always `%include` before any program that reads/writes those paths |
| `dictionary.columns` | Runtime column metadata (type, length, name) | Used by 10b for collision checks and type-safe comparisons |

**No new packages to install.** This phase works entirely within the existing SAS 9.4 environment.

---

## Architecture Patterns

### Recommended Structure

```
Phase 15 touches these files:
docs/
  concept_decisions.csv          ← extend with EXT rows (human step)
  concept_decisions_EXT_TEMPLATE.csv  ← source for EXT rows (Phase 14 output)
sas/
  10b_concept_harmonize.sas      ← add HARM-07 drop block
qc/
  10b_harmonize_report.txt       ← re-generated on run (on P:, not git)
```

### Pattern 1: Extending concept_decisions.csv

**What:** Append SSDI and CPT1 rows from the EXT template into the main decision file, with CONFIRMED=YES and an attribution comment field.

**When to use:** Whenever Phase 14 produces confirmed candidates.

**How:** The EXT template already has the correct 10b schema:
```
concept, varname, value_txt, target_value, confirmed, harmonized_name, priority
```
The human opens `concept_decisions_EXT_TEMPLATE.csv`, reviews `CONCEPT_EVIDENCE_EXT.xlsx`, and sets CONFIRMED=YES for each concept they accept. Then the rows are appended to `concept_decisions.csv`. The CONFIRMED column is the only gate; rows where CONFIRMED is blank are silently ignored by 10b.

**Attribution requirement (HARM-04):** The CSV has no date/author column natively. The standard approach in this project is DECISIONS.md. The HARM-04 requirement says "attributed and dated" — this must be satisfied by an entry in `docs/DECISIONS.md` that names the decision, the date, and who confirmed it. The CSV itself records the decision; DECISIONS.md records the provenance.

**Example DECISIONS.md entry pattern (from existing D-01 through D-11):**
```
**PCM-D-13 — SSDI concept harmonization: CONFIRMED 2026-09-NN by [reviewer]**
SSDI_DEATH_DATE_Y_N (priority 1) chosen as canonical h_ssdi_death_date_yn ...
```

### Pattern 2: HARM-07 Pipeline-Derived Column Rule

**What:** A written rule in the program header plus a conditional DROP block in the DATA step.

**The twelve columns to address:**
- `in_md3` — constant 1 for all 41,150 rows (md3 is the spine; every row is in md3)
- Eleven `h_*_src` companions — each holds a single repeated value because no secondary source ever fires (all eleven secondaries were proven redundant and dropped in Phase 10; force_src=1 emitted them anyway)

**Rule statement (to embed in program header):**
```
Pipeline-derived column rule (HARM-07):
  CARRY: in_md1, in_md2, in_md4..in_md8, n_sources, rt_envelope_flag, rt_*
         (these carry information: source membership, row count, clinical timing)
  DROP:  in_md3 (constant -- md3 is the spine; value is 1 for all 41,150 rows)
         h_*_src companions (each a single repeated value -- the redundancy proof
         showed no secondary source ever fires; these columns carry no information)
  ENFORCEMENT: DROP statements in the DATA step; assertion that all 12 are absent
               from g.master_data_harmonized after the DATA step completes.
```

**Implementation in 10b_concept_harmonize.sas:**

The program already has `%let force_src = 1;` which emits all `h_*_src` companions. For HARM-07, add a second gate:

```sas
/* HARM-07: pipeline-derived column rule ----------------------------------- */
%let drop_pipeline_noinfo = 1;
/* in_md3 is constant (md3 is the spine; value=1 for all 41,150 rows).
   h_*_src companions each hold a single repeated string because no secondary
   source ever fires: all secondaries were proven redundant in the Phase 10
   run. Both classes carry no information and are dropped.
   Set drop_pipeline_noinfo=0 to retain them for diagnostic purposes.       */
```

The DROP itself must go in the DATA step alongside the existing `drop &droplist;`:

```sas
data g.master_data_harmonized;
  set g.master_data_merged;
  %if %length(&droplist) > 0 %then %do;
    drop &droplist;
  %end;
  %if &drop_pipeline_noinfo = 1 %then %do;
    drop in_md3
    /* h_*_src list: built from &hnames at compile time */
    %do i = 1 %to &n_h;
      %scan(&hnames, &i)._src
    %end;
    ;
  %end;
  ...
```

**Assertion pattern (SECTION 6, extend existing assert_all macro):**

```sas
/* HARM-07 assertion: the twelve no-information columns must be absent */
%if &drop_pipeline_noinfo = 1 %then %do;
  proc sql noprint;
    select count(*) into :n_noinfo_present trimmed
    from dictionary.columns
    where libname='G' and memname='MASTER_DATA_HARMONIZED'
      and upcase(name) in ('IN_MD3'
        %do i = 1 %to &n_h; , upcase("%scan(&hnames,&i)_SRC") %end; );
  quit;
  %if &n_noinfo_present > 0 %then %do;
    %fail_out(msg=&n_noinfo_present no-information pipeline columns remain in the harmonized file);
  %end;
  %put NOTE: [10b] HARM-07 OK -- in_md3 and all h_*_src columns dropped.;
%end;
```

**CRITICAL SUBTLETY:** The `src_changed` assertion in SECTION 6 currently checks that no column vanishes from `g.master_data_harmonized` unless it was in `work.drop_ok`. The `h_*_src` columns were ADDED by this same program (they are not in `g.master_data_merged`), so the assertion queries `dictionary.columns WHERE libname='G' AND memname='MASTER_DATA_MERGED'` for the "before" list. The `h_*_src` and `in_md3` columns appear in merged, so they will be flagged as dropped without proof if the assertion is not updated. The fix: add the HARM-07 drop list to the exclusion clause alongside `work.drop_ok`.

Wait — `in_md3` IS in `g.master_data_merged` (it is a provenance flag from Phase 4). The `h_*_src` columns are NOT in `g.master_data_merged` (they are created by 10b). So:
- `in_md3`: IS in merged, will be caught by `src_changed`. Must be added to the exclusion list.
- `h_*_src`: NOT in merged, not touched by `src_changed`. Safe to drop without changing the assertion.

The `src_changed` query must exclude `in_md3` when `drop_pipeline_noinfo=1`. This is the only structural change needed to the assertion logic.

### Pattern 3: g.master_data_merged Must Remain Unmodified

**What:** The program reads `g.master_data_merged` with `set g.master_data_merged` and writes `g.master_data_harmonized` — they are separate datasets. The merged file is never written.

**Assertion (already in SECTION 6):** The program queries `n_rows` from `g.master_data_merged` before any DATA step and asserts `n_out = n_rows` after. This covers row count. Column count for `g.master_data_merged` is not currently asserted post-run; HARM-07's success criterion 3 ("176 columns, 41,150 rows confirmed unmodified") requires a post-run column count assertion on `g.master_data_merged`.

Add to SECTION 6:
```sas
proc sql noprint;
  select count(*) into :n_merged_cols trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED';
quit;
%if &n_merged_cols ne 176 %then %do;
  %fail_out(msg=g.master_data_merged has &n_merged_cols columns after run -- expected 176);
%end;
```

### Anti-Patterns to Avoid

- **Do NOT add `CONFIRMED` rows to concept_decisions.csv by hand-editing values into 10b directly.** HARM-04's requirement is exactly that decisions are applied by program, not by hand.
- **Do NOT use `data g.master_data_merged; set g.master_data_merged;`** (PCM-T-02 — destroys dataset).
- **Do NOT use PROC SQL UPDATE** (PCM-T-01 — silent truncation).
- **Do NOT drop `in_md3` without the exclusion fix to `src_changed`.** The assertion will fail with a spurious "column dropped without proof" error.
- **Do NOT rely on `force_src=1` and `drop_pipeline_noinfo=1` simultaneously without reconciling the LENGTH block.** If `h_*_src` columns are declared in the LENGTH block but then dropped, SAS is fine (DROP removes from output, not PDV). But the `src_changed` exclusion must account for them being absent from the final file.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Value-level mapping of source to canonical | Custom IF/THEN trees in a new program | `10b_concept_harmonize.sas` reading `concept_decisions.csv` | 10b has 13 validation gates, priority-tie detection, coverage proof, redundancy proof. All of that would need to be re-implemented |
| Redundancy proof for new aliases | Manual data review | SECTION 4b of 10b (n_would_add, n_disagree) | SECTION 4b re-proves on live data in every run; a "looked at it and it seemed fine" claim is exactly what the project rules forbid |
| Pipeline column rule documentation | A comment only | Written rule in program header + `%let drop_pipeline_noinfo` gate + assertion | HARM-07 requires the rule to be "enforced in code" — a comment satisfies "written" but not "enforced" |

---

## Common Pitfalls

### Pitfall 1: src_changed Fires on in_md3

**What goes wrong:** After adding the HARM-07 DROP block, running 10b raises "1 columns vanished or changed type/length WITHOUT being proven redundant" for `IN_MD3`.

**Why it happens:** `src_changed` compares `g.master_data_merged` columns against `g.master_data_harmonized` columns and expects every merged column to be present unless it is in `work.drop_ok` (redundant alias). `in_md3` is in merged but not in the HARM-07 sense a redundant alias — it is a provenance flag being dropped by the new rule.

**How to avoid:** Extend the `src_changed` WHERE clause to also exclude HARM-07 drops:
```sas
and a.name not in (select strip(upcase(varname)) from work.drop_ok)
/* HARM-07 exclusion */
%if &drop_pipeline_noinfo = 1 %then %do;
and a.name ne 'IN_MD3'
%end;
```

**Warning signs:** Error message "columns vanished or changed type/length WITHOUT being proven redundant" for `IN_MD3`.

### Pitfall 2: Partial Confirmation Triggers Gate (k)

**What goes wrong:** If the human confirms some SSDI rows but forgets CPT1 rows (or vice versa), 10b aborts at gate (k) with "partially confirmed concept".

**Why it happens:** Gate (k) requires ALL rows of a concept to be YES or all blank — no mixing. The EXT template has two concepts: `SSDI_DEATH_FLAG` and `CPT1_CODE_LABEL`. Each must be confirmed in full or left completely blank.

**How to avoid:** When filling the template, confirm or skip each concept as a unit. Review the concept groupings in `concept_decisions_EXT_TEMPLATE.csv` before editing.

**Warning signs:** "N concepts are only PARTIALLY confirmed" in the SAS log.

### Pitfall 3: concept_decisions.csv Still Uses the Gitignore-Excluded Path

**What goes wrong:** The updated `concept_decisions.csv` is not committed because it matches `*.csv` in `.gitignore`. The next clean-session run of 10b uses the old file (or finds no file and aborts).

**Why it happens:** `.gitignore` excludes `*.csv`. The original `concept_decisions.csv` was committed with `git add -f`. A newly written or overwritten file loses that force-add status.

**How to avoid:** After modifying `concept_decisions.csv`, always use `git add -f docs/concept_decisions.csv` before committing. Same for `label_similarity_candidates.csv` if it is to be committed as an artifact.

**Warning signs:** `git status` shows `concept_decisions.csv` as untracked after modification, or `git diff --cached` does not include it.

### Pitfall 4: h_*_src LENGTH Block Present but Columns Dropped

**What goes wrong:** The LENGTH block inside the DATA step declares `&h._src $32` for all harmonized names (because `force_src=1`), but the DROP block then removes them. This is legal SAS (DROP removes from output, not PDV). However, if HARM-07 is implemented by setting `force_src=0` instead of a separate DROP block, the LENGTH declarations disappear, and any downstream macro or report that references the `_src` columns by name will get a compile-time error.

**How to avoid:** Implement HARM-07 as a DROP (removes from output) rather than by setting `force_src=0` (removes from PDV and compile). Keep `force_src=1` as-is; add the HARM-07 DROP block separately.

### Pitfall 5: New h_ Columns Collide with Existing Names

**What goes wrong:** If a reviewer chooses a harmonized name (e.g., `h_ssdi_death`) that already exists in `g.master_data_merged`, gate (c) fires: "harmonized names collide with an existing column".

**Why it happens:** The merged file has `SSDI_DEATH`, `SSDI_DEATH_Y_N`, `SSDI_DEATH_DATE_Y_N`. A harmonized name of `H_SSDI_DEATH` would collide with an uppercase match against `SSDI_DEATH` only if those are literally the same after upcase — they are not (H_SSDI_DEATH vs SSDI_DEATH), so the typical `h_` prefix avoids this.

**How to avoid:** Follow the `h_` prefix convention strictly and verify with a PROC SQL against `dictionary.columns WHERE libname='G' AND memname='MASTER_DATA_MERGED'` before finalizing names.

### Pitfall 6: label_similarity_candidates.csv Has Not Been Run

**What goes wrong:** Phase 15 assumes the Phase 14 SAS program has been executed and its two CSV outputs exist. The VERIFICATION report for Phase 14 documents that as of 2026-08-29 both CSVs were absent from disk (program not yet run) and that the human checkpoint was marked APPROVED in the SUMMARY but the files were never force-committed.

**Why it happens:** Phase 14 VERIFICATION status is `gaps_found`. The program is complete; the SAS run and force-commit steps may not have been completed.

**How to avoid:** Before beginning Phase 15 plan execution, verify that `docs/label_similarity_candidates.csv` and `docs/concept_decisions_EXT_TEMPLATE.csv` exist on disk (not necessarily committed — but present so the human can review them). If absent, run `sas/14_label_similarity.sas` in a fresh SAS 9.4 session first.

---

## Code Examples

### Example 1: HARM-07 Drop Block in 10b DATA Step

```sas
/* HARM-07: drop no-information pipeline columns --------------------------------
   in_md3 is constant (md3 is the spine; value=1 for all &n_rows rows).
   h_*_src companions each carry one distinct value: all secondaries were proven
   redundant and never fire, so the source provenance string is the same on
   every populated row. Both classes carry no information.
   g.master_data_merged is untouched by this DROP.
   Set drop_pipeline_noinfo=0 to retain for diagnostic purposes.               */
%let drop_pipeline_noinfo = 1;
/* ... (after SECTION 4: rule extraction) ... */

data g.master_data_harmonized;
  set g.master_data_merged;
  %if %length(&droplist) > 0 %then %do;
    drop &droplist;
  %end;
  %if &drop_pipeline_noinfo = 1 %then %do;
    drop in_md3
    %do _pi = 1 %to &n_h;
      %scan(&hnames, &_pi)._src
    %end;
    ;
  %end;
  length ... ;
  /* ... rules ... */
run;
```

### Example 2: HARM-07 Assertion in assert_all

```sas
/* HARM-07: confirm 12 no-information columns are absent */
%if &drop_pipeline_noinfo = 1 %then %do;
  proc sql noprint;
    create table work.noinfo_present as
    select name from dictionary.columns
    where libname='G' and memname='MASTER_DATA_HARMONIZED'
      and ( upcase(name) = 'IN_MD3'
            %do _pi = 1 %to &n_h;
            or upcase(name) = upcase("%scan(&hnames,&_pi)_SRC")
            %end; );
    select count(*) into :n_noinfo_present trimmed from work.noinfo_present;
  quit;
  %if &n_noinfo_present > 0 %then %do;
    %put ERROR: &n_noinfo_present no-information pipeline column(s) still present.;
    %fail_out(msg=HARM-07 violation -- no-information columns not dropped);
  %end;
  %put NOTE: [10b] HARM-07 OK -- in_md3 and all h_*_src companions dropped.;
%end;
```

### Example 3: src_changed Exclusion Fix

```sas
/* In SECTION 6, the src_changed WHERE clause -- extend the exclusion: */
create table work.src_changed as
  select ...
  from (...) as a
  left join (...) as b on a.name = b.name
  where (b.name is null or a.type ne b.type or a.length ne b.length)
    and a.name not in (select strip(upcase(varname)) from work.drop_ok)
    /* HARM-07 exclusion -- in_md3 is dropped by rule, not by redundancy proof */
    %if &drop_pipeline_noinfo = 1 %then %do;
    and a.name ne 'IN_MD3'
    %end;
  ;
```

### Example 4: Post-Run Merged Column Count Assertion

```sas
/* Confirm g.master_data_merged unchanged: 176 columns */
proc sql noprint;
  select count(*) into :n_merged_cols trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED';
quit;
%macro assert_merged_unchanged;
  %if &n_merged_cols ne 176 %then %do;
    %fail_out(msg=g.master_data_merged has &n_merged_cols columns -- expected 176 -- it was modified);
  %end;
  %put NOTE: [10b] g.master_data_merged confirmed 176 columns and &n_rows rows -- unmodified.;
%mend assert_merged_unchanged;
%assert_merged_unchanged;
```

---

## State of the Art

| Before Phase 15 | After Phase 15 | Impact |
|----------------|---------------|--------|
| `g.master_data_harmonized`: 187 cols, 11 h_ columns, 11 aliases dropped | + new h_ columns for SSDI and CPT1 groups confirmed in Phase 14; `in_md3` and eleven `h_*_src` columns dropped | HARM-04 and HARM-07 closed |
| No written rule for pipeline-derived columns | Rule in program header, enforced by DROP + assertion | HARM-07 provably satisfied |
| `concept_decisions.csv` covers 11 original concepts | Extends to cover SSDI + CPT1 (if confirmed) | HARM-04 satisfied |

---

## Open Questions

1. **Has sas/14_label_similarity.sas been run and are the two CSVs present on disk?**
   - What we know: Phase 14 VERIFICATION status is `gaps_found`; the SUMMARY records the human checkpoint as APPROVED, implying the program ran
   - What's unclear: Whether the CSVs were force-committed; they may exist on P: but not in git
   - Recommendation: Plan 15 Wave 0 should include a human-verify step: confirm both CSVs exist on disk before any other task executes

2. **Which label-similarity candidates (if any) from Section A does the human want to confirm?**
   - What we know: `docs/label_similarity_candidates.csv` lists pairs above the 0.20 edit-distance threshold
   - What's unclear: The human has not yet reviewed the candidate list and marked any pairs CONFIRMED
   - Recommendation: This is a human decision gate. Plan 15 must include a human checkpoint to review `label_similarity_candidates.csv` and `CONCEPT_EVIDENCE_EXT.xlsx`, then fill CONFIRMED=YES in the extended template before the SAS run step

3. **How many new h_ columns will result from the SSDI and CPT1 confirmations?**
   - What we know: Two concept groups are in the template; SSDI_DEATH_FLAG and CPT1_CODE_LABEL; each will produce one h_ column
   - What's unclear: Whether any label-similarity candidates from Section A are confirmed (those would produce additional h_ columns)
   - Recommendation: Plan conservatively for at least two new h_ columns; column count in the final `g.master_data_harmonized` will be (187 - 12 dropped) + new h_ columns

4. **Does DECISIONS.md have a slot for the HARM-07 rule (PCM-D-13 or next available)?**
   - What we know: D-11 and D-12 are the most recent; PCM-D-10 was closed 2026-09-14
   - What's unclear: Whether D-12 was assigned; D-12 appears in Phase 8 (abort cancel OS behavior)
   - Recommendation: Assign the next available decision ID (likely PCM-D-13) for the HARM-07 rule and the SSDI/CPT1 confirmations

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|---------|
| SAS 9.4M8 | All SAS execution steps | Assumed yes (project runtime) | 9.4M8 | None — SAS is the pipeline |
| `g.master_data_harmonized` | 10b re-run | Must exist (Phase 10 output) | 187 cols, 41,150 rows | Re-run Phase 10 if absent |
| `docs/concept_decisions.csv` | 10b re-run | Must exist (Phase 10 output) | 11 concepts confirmed | Re-run Phase 10 if absent |
| `docs/concept_decisions_EXT_TEMPLATE.csv` | Human review gate | Probably exists on P: (Phase 14 ran per SUMMARY) | SSDI + CPT1 value-level rows | Run 14_label_similarity.sas if absent |
| `docs/label_similarity_candidates.csv` | Human review gate | Probably exists on P: (Phase 14 ran per SUMMARY) | Candidate pairs from Section A | Run 14_label_similarity.sas if absent |

**Missing dependencies with no fallback:**
- None (SAS environment assumed available; all upstream phases confirmed complete)

**Missing dependencies with fallback:**
- `docs/concept_decisions_EXT_TEMPLATE.csv` — if absent from disk, re-run `sas/14_label_similarity.sas` before beginning Phase 15

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS 9.4 `%abort cancel` assertion pattern (no external test runner) |
| Config file | `sas/00_config.sas` |
| Quick run command | Submit `sas/10b_concept_harmonize.sas` in a fresh SAS 9.4 session |
| Full suite command | Same — 10b is self-contained; all assertions are in-program |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| HARM-04 | concept_decisions.csv updated with EXT rows; program applies them; DECISIONS.md entry added | integration | Run `10b_concept_harmonize.sas`; check log for `NOTE: [10b] &n_con_yes concepts confirmed` matches expected count | `sas/10b_concept_harmonize.sas` — YES |
| HARM-07 | 12 no-information columns absent from g.master_data_harmonized; rule stated in code | integration | HARM-07 assertion block in assert_all macro; `n_noinfo_present = 0` logged | Added in Phase 15 — Wave 0 gap |
| SC-3 | g.master_data_merged unmodified: 176 cols, 41,150 rows | integration | Post-run column count assertion `n_merged_cols = 176` | Added in Phase 15 — Wave 0 gap |
| SC-4 | Any newly dropped alias proven redundant (0 rows added, 0 disagreements) | integration | Existing SECTION 4b redundancy proof in 10b | YES — existing machinery |

### Wave 0 Gaps

- [ ] HARM-07 DROP block in `sas/10b_concept_harmonize.sas` — covers HARM-07
- [ ] HARM-07 assertion in `assert_all` macro — covers HARM-07
- [ ] `src_changed` exclusion fix for `in_md3` — prerequisite for HARM-07 to not false-fire
- [ ] Post-run `g.master_data_merged` column count assertion — covers success criterion 3
- [ ] Human review of `label_similarity_candidates.csv` and EXT template — prerequisite for HARM-04 (cannot be automated)
- [ ] `docs/concept_decisions.csv` extended with EXT rows — HARM-04 input
- [ ] DECISIONS.md entry for new confirmations — HARM-04 attribution requirement

---

## Sources

### Primary (HIGH confidence)

- `sas/10b_concept_harmonize.sas` (1051 lines, committed) — all 10b patterns, validation gates, and DATA step structure drawn directly from this file
- `.planning/phases/14-label-similarity-sweep/14-VERIFICATION.md` — Phase 14 artifact status (gaps_found: two CSVs absent from git)
- `.planning/phases/14-label-similarity-sweep/14-02-SUMMARY.md` — EXT template schema, SSDI/CPT1 concept groups, human checkpoint APPROVED
- `.planning/REQUIREMENTS.md` — HARM-04 and HARM-07 definitions, accepted text
- `.planning/ROADMAP.md` — Phase 15 success criteria (all four)
- `.planning/STATE.md` — established decisions (PCM-T-01, PCM-T-02, no PROC SQL UPDATE, no data X; set X)

### Secondary (MEDIUM confidence)

- None required — all findings drawn from committed project artifacts

### Tertiary (LOW confidence)

- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — drawn directly from committed program code
- Architecture: HIGH — all patterns extracted from `10b_concept_harmonize.sas` internal structure
- Pitfalls: HIGH — each pitfall traceable to a specific gate, assertion, or VERIFICATION finding in the project artifacts

**Research date:** 2026-09-14
**Valid until:** Indefinite for stable SAS-only pipeline; reassess only if `10b_concept_harmonize.sas` is substantially refactored before Phase 15 executes
