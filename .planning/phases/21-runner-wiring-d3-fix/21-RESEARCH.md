# Phase 21 Research

**Researched:** 2026-09-23
**Domain:** SAS batch runner architecture; SAS gate macro; Windows .cmd scripting
**Method:** Codebase-only (no web search required — architecture decisions already settled in CONTEXT.md)

---

## Q1: g.analysis_base Producer

> **Resolved after research (2026-09-23):** Option B -- program 17 is redirected to g.analytic_cohort
> (PCM-D-20). See 21-CONTEXT.md D-07a. Note that g.analytic_cohort is written by both 07_cohort.sas and
> 16b_cohort_rebuild.sas; the runner order makes 16b's version the one program 17 reads. The Q5 statement
> that no DATALINES row is needed for pecan_ID no longer holds -- see 21-CONTEXT.md D-10.

**Finding:** No SAS program in the repo writes `g.analysis_base`. The current `99_run_all.sas` runs only programs 1-8 (via `%include` of `03_prep_all.sas` for Phase 3). `g.analysis_base` is not produced by any file under `sas/`.

`17_summary_stats_by_domain.sas` line 22 declares: `Reads: g.analysis_base (read-only)`. Lines 234-274 assert its existence and check its row count at runtime. The program reads the dataset from the `g` libref (P: drive) — it is a P: drive artifact of unknown provenance.

`g.analytic_cohort` is produced by `07_cohort.sas` (Phase 7), which IS in the current runner. `g.analysis_base` is a separate, older dataset.

**Open question status (D-07a):** This is explicitly flagged as an open question in CONTEXT.md requiring Gerard's decision before plan execution. Two options are documented:
- Option A: Identify what created `g.analysis_base` and confirm equivalence to `g.analytic_cohort`; add explicit step or alias before program 17.
- Option B: Update program 17 to read `g.analytic_cohort` instead.

**Planning implication:** The plan cannot finalize program 17's treatment in the runner until Gerard decides Option A or B. The plan must document this blocker explicitly and treat D-07a as an open prerequisite for the RUN-01 acceptance test.

---

## Q2: 99_run_all.sas Program Order

**Finding:** The current `sas/99_run_all.sas` uses `%include` and covers only programs 1-8. The Phase 3 driver (`03_prep_all.sas`) is included as a single call — it internally `%include`s `03_prep_setup.sas` and `03_prep_md1.sas` through `03_prep_md8.sas`. The current file does NOT include programs 10b, 16b, 17, 18, 19, or 20.

**Current `%include` order in 99_run_all.sas (complete list):**

| Call order | File | Phase label in runner |
|-----------|------|-----------------------|
| 1 | `00_config.sas` | Config (not a phase program) |
| 2 | `01_verify_sources.sas` | Phase 1 |
| 3 | `02_ownership.sas` | Phase 2 |
| 4 | `03_prep_all.sas` | Phase 3 (driver; sub-includes: 03_prep_setup.sas, 03_prep_md1..8.sas) |
| 5 | `04_merge.sas` | Phase 4 |
| 6 | `05_qc_merge.sas` | Phase 5 |
| 7 | `06_reconcile.sas` | Phase 6 |
| 8 | `07_cohort.sas` | Phase 7 |
| 9 | `08_dictionary.sas` | Phase 8 |

**Programs confirmed to exist in `sas/` but NOT in the current runner:**
- `10b_concept_harmonize.sas`
- `16b_cohort_rebuild.sas`
- `17_summary_stats_by_domain.sas`
- `18_supplemental_raw_gap.sas`
- `19_raw_dir_inventory.sas`
- `20_pecan_id.sas`

**Target order per CONTEXT.md D-07 and DISCUSSION-LOG.md:**
Programs 1-8, then 19, then 20, then 10b, then 16b, then 17, then 18.

**Phase 3 treatment in the .cmd driver:** Phase 3 is currently driven by `03_prep_all.sas`, which internally chains the sub-files. In the new `.cmd` driver, D-07 says "The driver must enumerate file names explicitly (Phase 3 alone involves multiple prep programs)." This means the driver must call `sas.exe` separately for each Phase 3 sub-program OR call `03_prep_all.sas` as a single invocation. The existing runner uses a single `%include` of `03_prep_all.sas` — the `.cmd` driver can follow the same convention (one `sas.exe` call for `03_prep_all.sas`) unless the planner decides to atomize further.

**Programs 10 and 14 are explicitly excluded** from the driver (human-gated prerequisites per D-07).

**sas_path variable:** The runner header shows the batch usage pattern:
```
sas -sysin "C:\Master_Renamed_same_format_accross\sas\99_run_all.sas" ^
    -log   "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\99_run_all.log"
```
This is the only hardcoded path outside `00_config.sas` (per the header comment).

---

## Q3: %_set_pipeline_default in 00_config.sas

**Finding:** `00_config.sas` contains no `RUN_ALL` environment variable check. The macro `%_set_pipeline_default` is defined at lines 51-57 and called immediately at line 57.

**Current macro (lines 51-57):**
```sas
%macro _set_pipeline_default;
  %if not %symexist(in_pipeline) %then %do;
    %global in_pipeline;
    %let in_pipeline = 0;
  %end;
%mend _set_pipeline_default;
%_set_pipeline_default;
```

**What it does:** Only sets `in_pipeline = 0` when the macro variable does not yet exist. If `in_pipeline` is already defined (e.g., because `99_run_all.sas` set it to 1 before the `%include` of `00_config.sas`), the macro does nothing — the existing value is preserved.

**The problem for the new .cmd driver:** The old runner (`99_run_all.sas`) sets `%let in_pipeline = 1;` at line 46, AFTER including `00_config.sas` at line 42. That works because `in_pipeline` is already defined by the time the phase programs re-include `00_config.sas`.

In the new `.cmd` driver, each program runs in a SEPARATE `sas.exe` session. The `-set RUN_ALL 1` flag injects an OS environment variable, but `%_set_pipeline_default` does not check for it. Each program that re-includes `00_config.sas` will call `%_set_pipeline_default`, find that `in_pipeline` does NOT exist (fresh session), and set it to 0.

**Required change per CONTEXT.md D-05:** `%_set_pipeline_default` must be extended to check `envlen(RUN_ALL)` before defaulting to 0:

```sas
%macro _set_pipeline_default;
  %if not %symexist(in_pipeline) %then %do;
    %global in_pipeline;
    %if %sysfunc(envlen(RUN_ALL)) > 0 %then %do;
      %if %sysget(RUN_ALL) = 1 %then %let in_pipeline = 1;
      %else %let in_pipeline = 0;
    %end;
    %else %let in_pipeline = 0;
  %end;
%mend _set_pipeline_default;
```

**Insertion point:** Replace the existing `%macro _set_pipeline_default` ... `%mend` block (lines 51-56) plus its call at line 57. The `%_set_pipeline_default;` call at line 57 stays; only the macro body changes.

**Important:** `17_summary_stats_by_domain.sas` has its OWN `init_pipeline_flag` macro at lines 133-138 that duplicates `%_set_pipeline_default`. This macro also does not check `RUN_ALL`. However, per CONTEXT.md D-05, "The 13 existing programs need no changes" — because `00_config.sas` is `%include`d BEFORE `init_pipeline_flag` is called (line 130 vs line 133). Once `00_config.sas` sets `in_pipeline = 1`, `init_pipeline_flag`'s `%symexist` guard fires and the macro does nothing. No change needed in program 17.

---

## Q4: sas.exe Path and Working Directory

**Finding:** No `.bat` or `.cmd` files exist in the repo (Glob returned no results).

**SAS executable path found in `99_run_all.sas` header (line 26-27):**
```
sas -sysin "C:\Master_Renamed_same_format_accross\sas\99_run_all.sas" ^
    -log   "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\99_run_all.log"
```
The header uses bare `sas` (not a full path), which resolves via PATH. The CONTEXT.md D-02 specifies:
```
"C:\Program Files\SASHome\SASFoundation\9.4\sas.exe"
```

**`00_config.sas` line 15:** `%let sas_path = C:\Master_Renamed_same_format_accross\sas;`

This is the code path (C: drive, in git). All data, QC, and logs are on P: drive.

**Working directory:** No program uses `%sysfunc(getoption(sysin))`. All paths are resolved from macro variables defined in `00_config.sas`. The `.cmd` driver does not need to set a working directory — each `sas.exe` invocation uses `-sysin` with the full absolute path.

**Driver variable convention (per CONTEXT.md D-02 and D-07):**
- `sas.exe` path must be a variable at the top of the `.cmd` (varies by machine)
- SAS code path is `C:\Master_Renamed_same_format_accross\sas`
- Log path is `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs`

---

## Q5: Program 17 Inputs and Gates

### DOMAIN_MAP_APPROVED gate

**Line 145:** `%let DOMAIN_MAP_APPROVED = 0;`

**Lines 196-200:** `%gate_stats` macro definition:
```sas
%macro gate_stats;
  %if &DOMAIN_MAP_APPROVED ne 1 %then %do;
    %fail_out(msg=Domain map awaiting Checkpoint 1 approval -- run stopped before the statistics sections);
  %end;
%mend gate_stats;
```

Gate is checked in Sections 5-11 (the statistics and output sections). Sections 0-4 (discovery, domain map build) run regardless. Setting line 145 to `%let DOMAIN_MAP_APPROVED = 1;` is the entire code change required for FIX-01.

### DATALINES block

**Lines 1666-1673:** `data work.domain_lookup;` block opens with `infile datalines dsd dlm=','`.

**Lines 1711-1712:** The two cognitive rows (correct, no change needed):
```
COGNITIVE_SCORE,D3,instrument,named cognitive instrument score -- instrument membership overrides timing
COGNITIVE_CATEGORY,D3,instrument,named cognitive instrument category -- instrument membership overrides timing
```

Lines 1713-1716 continue the D3 block (CLOCK_SCORE, DCDT_SCORE, DCDT_COMMAND, DCDT_COPY).

### analysis_base_ext and D15_APPROVED gate

**Line 202-205:** `%macro gate_ext` checks `D15_APPROVED`:
```sas
%if &D15_APPROVED ne 1 %then %do;
  %fail_out(msg=PCM-D-15 awaiting approval -- review 18_gap_candidates.txt then set D15_APPROVED=1 in 00_config.sas);
```

**Line 1056-1059:** `/* D15 gate: blocks analysis_base_ext until PCM-D-15 is approved */` followed by `%gate_ext;` then `data work.analysis_base_ext;`. This gate blocks the MERGE step that adds extension columns from `g.master_data_merged`.

**`D15_APPROVED` is currently set to 1 in `00_config.sas` line 35:** `%let D15_APPROVED = 1;` — so the gate is already open. No change needed here.

**Program 17's two primary reads:**
- `g.analysis_base` (lines 234-274, 367, 399, 471, 478, 534, 604, 644, 650): the main base dataset; does NOT carry pecan_ID
- `g.master_data_merged` (lines 550+): extension column sweep; does NOT carry pecan_ID (PCM-D-05 — merged file untouched)

**pecan_ID:** Not in either input dataset. Program 17's GUARD 5 (identifier exclusion regex at lines 1602-1610) would catch `pecan_ID` if it appeared, but it does not. No DATALINES row needed (D-10 confirmed).

---

## Planning Implications

- **Q1 (g.analysis_base):** D-07a is a HARD BLOCKER for the RUN-01 acceptance test. The plan must include a wave-0 or pre-wave task that obtains Gerard's Option A/B decision. Program 17 cannot be end-to-end tested in the new runner until this is resolved. The planner should scaffold the driver with program 17 included but flag its acceptance test as pending D-07a resolution.

- **Q2 (program order):** The current `99_run_all.sas` covers only programs 1-8. The new `.cmd` driver must add programs 10b, 16b, 17, 18, 19, 20 in the order: 1-8, 19, 20, 10b, 16b, 17, 18. Phase 3 can be a single `sas.exe` call to `03_prep_all.sas` (matching the current single-call pattern), or atomized — planner decides. The planner should reuse the header comment block and log-path variable text from the existing `99_run_all.sas` for the driver's echo lines.

- **Q3 (%_set_pipeline_default):** The macro body at lines 51-56 of `00_config.sas` must be replaced with the `envlen(RUN_ALL)` check. The call at line 57 stays. Program 17's duplicate `init_pipeline_flag` macro needs no change (it fires after `00_config.sas` already set `in_pipeline`, so its guard prevents any overwrite).

- **Q4 (sas.exe path):** No existing `.bat`/`.cmd` to reference for path conventions. The driver must define `SAS_EXE` as a variable at the top using the path from CONTEXT.md D-02: `C:\Program Files\SASHome\SASFoundation\9.4\sas.exe`. Code path and log path are derivable from the patterns already in `00_config.sas` and the `99_run_all.sas` header — no new path conventions needed.

- **Q5 (program 17 gates):** FIX-01 is a one-line change at line 145 (`0` to `1`). The `D15_APPROVED` gate is already open (set to 1 in `00_config.sas`). The DATALINES rows at lines 1711-1712 are correct and need no change. The only code edit for FIX-01 is line 145, plus adding PCM-D-19 to `docs/DECISIONS.md`.

---

## RESEARCH COMPLETE

**Phase:** 21 - Runner Wiring & D3 Fix
**Confidence:** HIGH (all findings from direct file reads; no web search used)

| Area | Level | Reason |
|------|-------|--------|
| g.analysis_base producer | HIGH | Confirmed by absence: Glob of all .sas files + reading 99_run_all.sas |
| 99_run_all.sas program order | HIGH | Read directly from source file |
| %_set_pipeline_default location and logic | HIGH | Read lines 51-57 of 00_config.sas directly |
| sas.exe path | HIGH | Read from 99_run_all.sas header; confirmed no .bat/.cmd exists |
| Program 17 gates and DATALINES | HIGH | Read lines 145, 197-200, 1666-1712 directly |

**Open question not resolved by research (requires human input):**
- D-07a: Whether `g.analysis_base` is equivalent to `g.analytic_cohort` and which option (A or B) Gerard selects. This cannot be determined from code inspection alone.
