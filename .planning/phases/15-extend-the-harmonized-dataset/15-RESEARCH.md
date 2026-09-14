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
| HARM-07 | A written rule states which pipeline-derived columns are carried vs. dropped and is enforced in code; the rule must address the no-information columns: `in_md3` (constant) + every `h_*_src` companion (single-valued when no secondary fires) | Currently 12 such columns appear in `g.master_data_harmonized` (in_md3 + 11 companions); the count grows with every confirmed concept. Encode as a `%let drop_pipeline_noinfo = 1;` gate in `10b_concept_harmonize.sas` with a `drop=` dataset option, a `work.src_check` side output, a single-value premise assertion, and an absence assertion |
</phase_requirements>

---

## Summary

Phase 15 has two independent deliverables that can be developed in parallel but must both be proven before the final re-run is committed.

**Deliverable A (HARM-04):** Extend `docs/concept_decisions.csv` with the SSDI death family and CPT1 code/label entries from `docs/concept_decisions_EXT_TEMPLATE.csv`, after a human has filled CONFIRMED=YES. The existing `10b_concept_harmonize.sas` machinery reads this file, validates it with thirteen hard gates, proves redundancy in-run, and produces `g.master_data_harmonized`. No new SAS code is needed for the core harmonization step — only the CSV population and a re-run.

**Deliverable B (HARM-07):** State and enforce the pipeline-derived column rule. `in_md3` and every `h_*_src` companion must be named in a written rule inside the program and dropped via a guarded `drop=` dataset option on the DATA statement. `in_md3` needs no proof (structurally constant). The companions DO need one: the "single repeated value" premise was proven for the original 11 concepts only, and Phase 15 adds concepts whose secondaries may fire. The DATA step therefore writes the companions to a `work.src_check` side output and SECTION 6 asserts each is single-valued before the run passes, followed by an assertion that none remain in the harmonized output.

**Deliverable C (attribution):** HARM-04 decisions are attributed as PCM-D-13 (Plan 15-01); the HARM-07 rule is attributed separately as PCM-D-14 (Plan 15-02).

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
**PCM-D-13 — SSDI/CPT1/label-sweep concept harmonization: CONFIRMED 2026-09-NN by [reviewer]**
SSDI_DEATH_DATE_Y_N (priority 1) chosen as canonical h_ssdi_death ...
Deferred: <concept> (gate (m) — value contains quote / & / %) or "none"
```

**Pinned names:** `h_ssdi_death` (SSDI family), `h_cpt1` (CPT1 pair). The plan pins these so the reviewer is not choosing at the checkpoint; gate (c) is still checked in-run.

**Gate (m) is a screen, not a review item.** VALUE_TXT must equal the observed value exactly (SECTION 3 coverage), so a value containing a quote, `&`, or `%` cannot be mapped by the current 10b at all — substituting the character breaks coverage. Any concept with such a value is deferred and recorded in D-13; CPT labels make CPT1 the likely case. Plan 15-01 runs the screen before the reviewer judges anything.
```
```

### Pattern 2: HARM-07 Pipeline-Derived Column Rule

**What:** A written rule in the program header plus a conditional DROP block in the DATA step.

**The columns to address:**
- `in_md3` — constant 1 for all 41,150 rows (md3 is the spine; every row is in md3)
- Every `h_*_src` companion — currently eleven. Each holds a single repeated value *if* no secondary source ever fires. That was proven for the original eleven concepts (all secondaries redundant and dropped in Phase 10; force_src=1 emitted the companions anyway). It is NOT automatically true for concepts added in Phase 15: if SECTION 4b does not prove a new secondary redundant, that secondary stays in the file, can fire, and its companion then carries provenance. The rule must therefore assert the premise per companion, per run.

**Rule statement (to embed in program header):**
```
Pipeline-derived column rule (HARM-07):
  CARRY: in_md1, in_md2, in_md4..in_md8, n_sources, rt_envelope_flag, rt_*
         (these carry information: source membership, row count, clinical timing)
  DROP:  in_md3 (constant -- md3 is the spine; value is 1 for every row)
         every h_*_src companion (each must hold a single repeated value because no
         secondary source fires; ASSERTED in-run for every companion, not assumed)
  ENFORCEMENT: drop= dataset option on the SECTION 5 DATA statement; work.src_check
               side output; SECTION 6 assert_src_single (premise) and assert_harm07
               (absence); assert_merged_unchanged re-queries the merged file post-run.
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

The drop is a `drop=` DATASET OPTION on the DATA statement, not a DROP statement: a DROP statement applies to every output dataset, and the DATA step now has a second output (`work.src_check`) that must KEEP the companions for the premise proof.

```sas
data g.master_data_harmonized
  %if &drop_pipeline_noinfo = 1 %then %do;
    (drop=in_md3 %do _pi = 1 %to &n_h; %scan(&hnames, &_pi)._src %end;)
  %end;
  %if &n_h > 0 %then %do;
    work.src_check (keep=%do _pi = 1 %to &n_h; %scan(&hnames, &_pi)._src %end;)
  %end;
  ;
  set g.master_data_merged;
  %if %length(&droplist) > 0 %then %do;
    drop &droplist;          /* unchanged: applies to both outputs; keep= wins on src_check */
  %end;
  ...
```
Every row goes to both outputs (no explicit OUTPUT statement). The side output costs one 41,150-row WORK table with a handful of $32 columns — trivial.

**Assertion pattern (SECTION 6, three new macros called after %assert_all):**

1. `%assert_src_single` — premise. For each `%scan(&hnames,&_pi)._src`, `select count(distinct &_v) from work.src_check where not missing(&_v)`; any count > 1 means a secondary fired; %fail_out after the loop with the number of offenders. Runs regardless of the gate. See Example 2.
2. `%assert_harm07` — absence. Counts IN_MD3 + every `_SRC` in `dictionary.columns` for MASTER_DATA_HARMONIZED; %fail_out if > 0. Gated. See Example 3.
3. `%assert_merged_unchanged` — re-queries `dictionary.columns` (176) AND `dictionary.tables` nobs (= &n_rows) for MASTER_DATA_MERGED post-run. See Example 5.

If `%assert_src_single` fires, the remedy is in concept_decisions.csv (that concept's PRIORITY order or mapping), never in weakening the rule.

**CRITICAL SUBTLETY:** The `src_changed` assertion in SECTION 6 currently checks that no column vanishes from `g.master_data_harmonized` unless it was in `work.drop_ok`. The `h_*_src` columns were ADDED by this same program (they are not in `g.master_data_merged`), so the assertion queries `dictionary.columns WHERE libname='G' AND memname='MASTER_DATA_MERGED'` for the "before" list. The `h_*_src` and `in_md3` columns appear in merged, so they will be flagged as dropped without proof if the assertion is not updated. The fix: add the HARM-07 drop list to the exclusion clause alongside `work.drop_ok`.

Wait — `in_md3` IS in `g.master_data_merged` (it is a provenance flag from Phase 4). The `h_*_src` columns are NOT in `g.master_data_merged` (they are created by 10b). So:
- `in_md3`: IS in merged, will be caught by `src_changed`. Must be added to the exclusion list.
- `h_*_src`: NOT in merged, not touched by `src_changed`. Safe to drop without changing the assertion.

The `src_changed` query must exclude `in_md3` when `drop_pipeline_noinfo=1`. This is the only structural change needed to the assertion logic.

### Pattern 3: g.master_data_merged Must Remain Unmodified

**What:** The program reads `g.master_data_merged` with `set g.master_data_merged` and writes `g.master_data_harmonized` — they are separate datasets. The merged file is never written.

**Assertion (existing SECTION 6):** The program queries `n_rows` from `g.master_data_merged` BEFORE the DATA step and asserts `n_out = n_rows` after. That proves the harmonized row count, not the post-run state of the merged file. Success criterion 3 ("176 columns, 41,150 rows confirmed unmodified") needs BOTH counts re-queried AFTER the DATA step — see Example 5. Do not report `&n_rows` in the post-run NOTE as if it were re-measured.

### Anti-Patterns to Avoid

- **Do NOT add `CONFIRMED` rows to concept_decisions.csv by hand-editing values into 10b directly.** HARM-04's requirement is exactly that decisions are applied by program, not by hand.
- **Do NOT use `data g.master_data_merged; set g.master_data_merged;`** (PCM-T-02 — destroys dataset).
- **Do NOT use PROC SQL UPDATE** (PCM-T-01 — silent truncation).
- **Do NOT drop `in_md3` without the exclusion fix to `src_changed`.** The assertion will fail with a spurious "column dropped without proof" error.
- **Do NOT rely on `force_src=1` and `drop_pipeline_noinfo=1` simultaneously without reconciling the LENGTH block.** If `h_*_src` columns are declared in the LENGTH block but then dropped, SAS is fine (`drop=` removes from that output, not the PDV).
- **Do NOT drop the `h_*_src` companions on the strength of the Phase 10 proof alone.** The proof covered eleven concepts; every run must re-prove the premise for whatever `&hnames` contains (`%assert_src_single`).
- **Do NOT use a DROP statement for the HARM-07 drop.** It would apply to `work.src_check` too and defeat the premise proof; use the `drop=` dataset option.
- **Do NOT sanitize VALUE_TXT to get past gate (m).** VALUE_TXT must equal the observed value for coverage; defer the concept instead.
- **Do NOT copy `&qc_path/10b_harmonize_report.txt` into the repo `qc/` folder.** QC outputs live on P: and are not version-controlled; cite the path in the SUMMARY.

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

**Related — gate (m) on CPT1:** CPT labels routinely contain `&`, `%`, and quotes. Because VALUE_TXT must match the observed value exactly for SECTION 3 coverage, any such value makes the whole concept unmappable by the current 10b. Plan 15-01 Task 2 screens every EXT row for `["&%]` BEFORE the reviewer judges anything; concepts with hits are deferred and recorded in D-13. Warning sign if the screen was skipped: a gate (m) abort naming the offending value.

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

### Pitfall 7: A New Secondary Fires and the h_*_src Drop Destroys Provenance

**What goes wrong:** A Phase 15 concept (e.g. the three-source SSDI family) has a secondary that SECTION 4b does NOT prove redundant. The secondary stays in the file and populates the harmonized column on some rows; its `_src` companion then holds two or more distinct values. The blanket `_src` drop silently discards which source supplied each row.

**Why it happens:** The rule's premise ("no secondary ever fires") was established on the original eleven concepts and does not transfer automatically.

**How to avoid:** `%assert_src_single` (Example 2) runs every time and fails the run if any companion has more than one distinct non-missing value. The fix on failure is in concept_decisions.csv (PRIORITY order or the mapping), not in the rule.

**Warning signs:** "HARM-07 premise violated -- N h_*_src companion(s) not single-valued" in the SAS log.

---

## Code Examples

### Example 1: HARM-07 drop= and work.src_check side output (SECTION 5)

```sas
/* HARM-07: pipeline-derived column rule -------------------------------------
   in_md3 is constant (md3 is the spine). Every h_*_src companion is asserted
   single-valued in SECTION 6 (assert_src_single) and dropped from the harmonized
   output here. g.master_data_merged is untouched by this drop.
   Set drop_pipeline_noinfo=0 to retain the columns for diagnostics.            */
%let drop_pipeline_noinfo = 1;
/* ... inside build_harmonized, %local i k h emit_src _pi; ... */

data g.master_data_harmonized
  %if &drop_pipeline_noinfo = 1 %then %do;
    (drop=in_md3 %do _pi = 1 %to &n_h; %scan(&hnames, &_pi)._src %end;)
  %end;
  %if &n_h > 0 %then %do;
    work.src_check (keep=%do _pi = 1 %to &n_h; %scan(&hnames, &_pi)._src %end;)
  %end;
  ;
  set g.master_data_merged;
  %if %length(&droplist) > 0 %then %do;
    drop &droplist;
  %end;
  length ... ;
  /* ... rules ... */
run;
```

### Example 2: Premise assertion -- every h_*_src single-valued

```sas
%macro assert_src_single;
  %local _pi _v n_dist n_bad;
  %let n_bad = 0;
  %if &n_h > 0 %then %do;
    %do _pi = 1 %to &n_h;
      %let _v = %scan(&hnames, &_pi)._src;
      proc sql noprint;
        select count(distinct &_v) into :n_dist trimmed
        from work.src_check
        where not missing(&_v);
      quit;
      %if &n_dist > 1 %then %do;
        %put ERROR: [10b] &_v holds &n_dist distinct values -- a secondary source fires -- cannot be dropped by rule.;
        %let n_bad = %eval(&n_bad + 1);
      %end;
    %end;
  %end;
  %if &n_bad > 0 %then %do;
    %fail_out(msg=HARM-07 premise violated -- &n_bad h_*_src companion(s) not single-valued);
  %end;
  %put NOTE: [10b] HARM-07 premise OK -- every h_*_src companion is single-valued.;
%mend assert_src_single;
%assert_src_single;
```

### Example 3: Absence assertion

```sas
%macro assert_harm07;
  %local _pi n_noinfo_present;
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
      %put ERROR: [10b] &n_noinfo_present no-information pipeline column(s) still present.;
      %fail_out(msg=HARM-07 violation -- in_md3 or h_*_src columns not dropped);
    %end;
    %put NOTE: [10b] HARM-07 OK -- in_md3 and every h_*_src companion dropped.;
  %end;
  %else %do;
    %put NOTE: [10b] HARM-07 gate is 0 -- no-information columns RETAINED for diagnostics.;
  %end;
%mend assert_harm07;
%assert_harm07;
```

### Example 4: src_changed exclusion fix

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

### Example 5: Post-run merged unchanged -- columns AND rows re-queried

```sas
%macro assert_merged_unchanged;
  %local n_merged_cols n_merged_rows;
  proc sql noprint;
    select count(*) into :n_merged_cols trimmed
    from dictionary.columns
    where libname='G' and memname='MASTER_DATA_MERGED';
    select nobs into :n_merged_rows trimmed
    from dictionary.tables
    where libname='G' and memname='MASTER_DATA_MERGED';
  quit;
  %if &n_merged_cols ne 176 %then %do;
    %fail_out(msg=g.master_data_merged has &n_merged_cols columns post-run -- expected 176 -- it was modified);
  %end;
  %if &n_merged_rows ne &n_rows %then %do;
    %fail_out(msg=g.master_data_merged has &n_merged_rows rows post-run -- expected &n_rows -- it was modified);
  %end;
  %put NOTE: [10b] g.master_data_merged confirmed post-run -- 176 columns and &n_merged_rows rows -- unmodified.;
%mend assert_merged_unchanged;
%assert_merged_unchanged;
```

---

## State of the Art

| Before Phase 15 | After Phase 15 | Impact |
|----------------|---------------|--------|
| `g.master_data_harmonized`: 187 cols, 11 h_ columns, 11 aliases dropped | + new h_ columns for concepts confirmed in 15-01; `in_md3` and every `h_*_src` dropped, premise asserted per run | HARM-04 and HARM-07 closed |
| No written rule for pipeline-derived columns | Rule in program header (PCM-D-14), enforced by drop= + premise + absence assertions | HARM-07 provably satisfied |
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
   - Recommendation: final column count = 176 - 11 - (newly dropped aliases) - 1 (in_md3) + 11 + (new h_ columns); no `_src` columns remain. CPT1 may be deferred by the gate (m) screen, so plan for one to two new h_ columns.

4. **Does DECISIONS.md have a slot for the HARM-07 rule (PCM-D-13 or next available)?**
   - What we know: D-11 and D-12 are the most recent; PCM-D-10 was closed 2026-09-14
   - What's unclear: Whether D-12 was assigned; D-12 appears in Phase 8 (abort cancel OS behavior)
   - Recommendation: PCM-D-13 = the HARM-04 confirmations and deferrals (Plan 15-01); PCM-D-14 = the HARM-07 rule (Plan 15-02). Two decisions, two IDs.

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
| Full suite command | Same — 10b is self-contained; all assertions are in-program. There is no separate Phase 15 program. |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| HARM-04 | concept_decisions.csv updated with EXT rows; program applies them; DECISIONS.md entry added | integration | Run `10b_concept_harmonize.sas`; check log for `NOTE: [10b] &n_con_yes concepts confirmed` matches expected count | `sas/10b_concept_harmonize.sas` — YES |
| HARM-07 | in_md3 + every h_*_src absent from g.master_data_harmonized; premise proven; rule stated in code | integration | `%assert_src_single` + `%assert_harm07`; both NOTE lines logged | Added in Phase 15 (Plan 15-02 Tasks 1-2) |
| SC-3 | g.master_data_merged unmodified: 176 cols, 41,150 rows | integration | `%assert_merged_unchanged` re-queries both counts post-run | Added in Phase 15 (Plan 15-02 Task 2) |
| SC-4 | Any newly dropped alias proven redundant (0 rows added, 0 disagreements) | integration | Existing SECTION 4b redundancy proof in 10b | YES — existing machinery |

### Wave 0 Gaps

- [ ] Phase 14 CSVs present on disk (15-01 Task 1 — the only true Wave 0 item)
- [ ] Gate (m) screen + human review of EXT template and label candidates (15-01 Task 2)
- [ ] `docs/concept_decisions.csv` extended; PCM-D-13 (15-01 Task 3)
- [ ] HARM-07 drop= + work.src_check in `sas/10b_concept_harmonize.sas` (15-02 Task 1)
- [ ] `%assert_src_single`, `%assert_harm07`, `src_changed` exclusion, `%assert_merged_unchanged` (15-02 Task 2)
- [ ] PCM-D-14 (15-02 Task 3)

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
