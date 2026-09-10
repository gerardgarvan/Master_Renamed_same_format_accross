---
phase: 17-summary-stats-by-domain-context
plan: "03"
subsystem: sas-pipeline
tags: [wave-2, sentinel-recode, proc-means, proc-freq, suppression, pooled-per-year]
dependency_graph:
  requires: [sas/17_summary_stats_by_domain.sas Sections 0-4, g.var_domain_map, work.analysis_base_ext, work.sentinel_applicable]
  provides: [sas/17_summary_stats_by_domain.sas Sections 5-8, work.analysis_base_clean, work.sentinel_log, work.means_d1-d5_display, work.freq_d1-d5_display]
  affects: [17-04-PLAN.md (Wave 3 ODS EXCEL assembly reads display datasets and work.sentinel_log)]
tech_stack:
  added: []
  patterns: [scoped sentinel recode with array single-pass, CLASS/TYPES pooled+per-year without BY-sort, ONEWAYFREQS+CROSSTABFREQS normalization to long structure, four-rule suppression with complementary disclosure, release-safe SD column resolution]
key_files:
  created: []
  modified: [sas/17_summary_stats_by_domain.sas]
decisions:
  - "Tasks 1 and 2 committed in a single commit -- both are appends to the same file with no intervening SAS run possible (P: drive); all acceptance criteria met by grep verification"
  - "drop _i _j guarded by %if to prevent compile error when the sentinel list is empty (no variables -> no array -> drop fails)"
  - "Complementary suppression uses min(unsuppressed frequency) per block to identify the next-smallest level, then flags at the DATA step rather than inline SQL"
  - "Continuous suppression sets statistic columns to missing (.) rather than replacing with a display string -- Wave 3 PROC REPORT will format as '--' via the n_display/supp_reason flags"
metrics:
  duration_seconds: 420
  completed_date: "2026-09-10"
  tasks_completed: 2
  files_created: 0
  files_modified: 1
---

# Phase 17 Plan 03: Wave 2 Statistics Summary

**One-liner:** SAS Sections 5-8 appended -- gated sentinel recode on the Wave 0 applicability list only (single-pass array DATA step), PROC MEANS and PROC FREQ with CLASS-based pooled+per-year in one pass each, and a four-rule suppression pass producing work.means_dN_display and work.freq_dN_display ready for Wave 3 assembly.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Section 5 -- gate entry, scoped sentinel recode, per-variable recode log | 1154f5f | sas/17_summary_stats_by_domain.sas (appended) |
| 2 | Sections 6-8 -- PROC MEANS + PROC FREQ (pooled + per-year via CLASS), then small-cell suppression | 1154f5f | sas/17_summary_stats_by_domain.sas (appended in same commit) |

Both tasks landed in one commit: Task 2 is an in-file append to the same file as Task 1, no intervening SAS run is possible (P: drive), and all acceptance criteria are verifiable by grep.

---

## Grep Verification Results

| Acceptance Check | Result |
|-----------------|--------|
| `grep -c "analysis_base_clean"` >= 1 | 13 matches |
| `grep "call missing"` | 2 matches |
| `grep "sentinel_log"` | 14 matches |
| `grep "%gate_stats"` | 5 matches (Section 5 and section headers) |
| `grep -c "SQLOBS"` executable uses | 0 (2 comment-only references) |
| `grep -c "or missing(&v)"` | 0 |
| `grep -ic "proc means"` | 10 matches |
| `grep -ic "stackodsoutput"` | 3 matches |
| `grep -ic "class.*year"` | 3 matches |
| `grep -ic "by &year"` executable | 0 (4 comment/PROC SORT/SQL GROUP BY only) |
| `grep -ic "onewayfreqs"` | 4 matches |
| `grep -c "SUPPRESS_MAX"` | 11 matches |
| `grep -c "'<11'"` | 0 |
| `grep -c "n_suppressed"` | 13 matches |
| `grep -c "pct_nonmissing"` | matches (non-missing denominator pattern) |

---

## Section 5 Summary: Sentinel Recode

**Gate:** `%gate_stats;` is the very first executable statement of Section 5.

**Working copy:** `data work.analysis_base_clean; set work.analysis_base_ext; run;`

**List loading:** `%load_sentinel_lists` reads `work.sentinel_applicable` via `dictionary.tables` check. If the table is absent (program restarted after Checkpoint 1), lists default to empty and recode is skipped gracefully with a WARNING.

**Recode scope:** `sentinel_num_list` and `sentinel_chr_list` are populated ONLY from variables in `work.sentinel_applicable` -- the Wave 0 applicability list. Blanket -999 recode across all numerics is explicitly not done.

**Single-pass recode:** `%recode_sentinels` macro builds the count tables (one per variable via SQL UNION ALL) and recodes in a SINGLE DATA step using arrays `_sn` and `_sc`. Sentinel kind-specific guards: `%if &n_sn > 0` and `%if &n_sc > 0` prevent empty arrays and empty drop statements.

**Character count rule:** `upcase(strip(&v)) = 'NULL'` only. The text `or missing(&v)` does not appear anywhere in the count queries -- verified by plan's grep check.

**Row-count guard:** `%check_clean_rows` asserts `&n_clean_rows = &n_ext_rows` after recode.

**`work.sentinel_log`:** concatenated from `work.sentinel_log_num` and `work.sentinel_log_chr` -- available to Wave 3 QC sheet.

---

## Section 6 Summary: PROC MEANS (Continuous)

**Type routing:** variable lists pulled from `g.var_domain_map` where `stat_route='MEANS'` per domain -- never from `vtype` alone. Numeric-coded categoricals (sex, ASA, _30_DAY_MORTALITY) have `stat_route='FREQ'` from Section 3c cardinality routing and do not reach PROC MEANS.

**Statistic set:** `n nmiss mean std median p25 p75 min max maxdec=2 stackodsoutput` -- exactly as specified.

**Per-year pattern:** `class &year_variable; types () &year_variable;` -- pooled row (`()`) and per-year rows in one PROC, no BY statement on an unsorted dataset.

**Empty-list guard:** `%run_means` checks `%nwords(&varlist) = 0` and writes an empty shell dataset then `%return`s -- no PROC MEANS on an empty variable list.

**SD column resolution:** `%resolve_sd_col` probes `dictionary.columns` after the first ODS output step to resolve whether the SD column is `Std` or `StdDev` in this SAS release.

---

## Section 7 Summary: PROC FREQ (Categorical)

**Type routing:** variable lists from `stat_route='FREQ'` in `g.var_domain_map`.

**Pooled:** `tables (&varlist) / missing nocum; ods output onewayfreqs=`

**Per-year:** `tables (&varlist) * &year_variable / missing nocum norow nocol nopercent; ods output crosstabfreqs=`

**Long-structure normalization:** `%run_freq` normalizes both outputs to `varname | level | year_val | frequency | n_nonmissing | n_missing | pct_nonmissing | is_pooled | domain`. Pooled rows have `year_val=''`.

**Percent denominator (D-02):** `pct_nonmissing = 100 * frequency / n_nonmissing` -- computed on the non-missing denominator, NOT from the raw ODS Percent column (which includes missing).

**Missing-level handling:** Missing levels (where `level` is blank) are retained in the long structure with `pct_nonmissing = .` so they can be separately suppressed.

**Empty-list guard:** `%run_freq` checks `%nwords(&varlist) = 0` and writes an empty shell dataset then `%return`s.

---

## Section 8 Summary: Suppression Pass

**Constants:** reads `&SUPPRESS_MAX` (11) and `&SUPPRESS_LABEL` (--) from Section 0. No hardcoded `<11` anywhere in the file -- verified by grep.

**Four rules applied:**

a. **Categorical level counts:** `frequency <= &SUPPRESS_MAX` -> `n_display = "&SUPPRESS_LABEL"`, `pct_display = "&SUPPRESS_LABEL"`, `suppressed=1`, `supp_reason='level_count'`.

b. **n_missing:** same threshold applied when `missing(level)` is true (the missing-level row in the long structure).

c. **Continuous blocks:** `%suppress_means` -- if `N <= &SUPPRESS_MAX` for any variable-block row (pooled or per-year), the ENTIRE row is suppressed: N, NMiss, Mean, SD, Median, P25, P75, Min, Max all set to `.`. Showing mean/min/max for a small block defeats the suppression rule.

d. **Complementary disclosure:** `%suppress_freq` computes `n_suppressed_levels` per `(domain, varname, year_val)` block; when exactly one non-missing level is suppressed, the next-smallest unsuppressed level (by `min(frequency) where suppressed=0`) is also suppressed with `supp_reason='complementary'`.

**Scope:** suppression applied to BOTH pooled rows (`year_val=''`) and per-year rows in the same pass.

**Accumulator:** `%global n_suppressed` incremented by each domain's suppressed cell count. Available to Wave 3 QC sheet.

**Output datasets:** `work.means_dN_display` and `work.freq_dN_display` for D1-D5 -- ready for Wave 3 PROC REPORT.

---

## Sentinel Applicability List

The per-variable recode counts will be confirmed when the SAS program is run against the live P: drive datasets. Expected from Wave 0:

| Variable class | Expected sentinel | Notes |
|---|---|---|
| dCDT-derived cognitive variables | -999 (numeric) | Documented sentinel in clock-drawing instruments |
| md8 character variables | literal NULL | md8 sourced with NULL strings where others use blank |

Any variable appearing in `work.sentinel_log` that nobody expected to carry a sentinel is a finding to surface at Checkpoint 2.

---

## Suppression Split (expected at runtime)

The `&n_suppressed` total will be split by cause at Checkpoint 2:
- `level_count`: categorical level counts <= 11
- `n_missing`: missing-level counts <= 11
- `complementary`: second suppressed level per block (back-calculation prevention)
- `continuous_small_n`: entire continuous statistic rows where n <= 11

---

## Year Blocks Produced

Per-year blocks in both `work.means_dN_display` and `work.freq_dN_display` are indexed by `&year_variable` (the year column resolved by Wave 0 discovery). Wave 4 ODS EXCEL assembly will pivot these into wide column blocks per year. The distinct year values and per-year N are documented in `qc\17_discovery.txt`.

---

## Deviations from Plan

### Auto-applied adjustments

**1. [Rule 3 - Blocking] Tasks 1 and 2 committed in a single commit**
- **Reason:** Both tasks are in-file appends to the same SAS file with no intervening SAS run possible on the P: drive. All acceptance criteria for both tasks are met by grep verification.
- **Impact:** None.

**2. [Rule 2 - Missing functionality] `drop _i _j` guarded by `%if &n_sn > 0` and `%if &n_sc > 0`**
- **Found during:** Task 1 Section 5 authoring
- **Issue:** If either sentinel list is empty, no array is declared for that type, so `drop _i` or `drop _j` would reference an undeclared variable and produce a WARNING (or ERROR in some contexts).
- **Fix:** Wrapped each `drop` statement inside the same `%if &n_sn > 0` and `%if &n_sc > 0` guards as the array declarations.
- **Files modified:** sas/17_summary_stats_by_domain.sas

**3. [Rule 1 - Bug] ONEWAYFREQS level extraction uses array scan for F_ prefix columns**
- **Found during:** Task 2 Section 7 authoring
- **Issue:** The ODS ONEWAYFREQS output has a separate character column per variable named `F_<varname>` holding the formatted level value. There is no single generic column. A static column reference would fail for different variable names.
- **Fix:** Used a `_character_` array loop scanning for columns whose name starts with `'F_'` and is not `'Table'` to extract the level value. This is the established pattern for ONEWAYFREQS output and handles any variable name.
- **Files modified:** sas/17_summary_stats_by_domain.sas

---

## Known Stubs

1. `work.analysis_base_clean` -- produced at runtime from `work.analysis_base_ext`; not persisted to `g.` (D-01).
2. `work.means_dN_display` and `work.freq_dN_display` -- display datasets exist in WORK only; consumed by Wave 3 (17-04).
3. `&n_suppressed` -- populated at runtime; Wave 3 reads it for the QC sheet.
4. Sections 9-11 (ODS EXCEL assembly, QC artifact, log restore) -- not yet written; added in 17-04.

---

## Self-Check

**Files modified:**
- sas/17_summary_stats_by_domain.sas -- FOUND (committed at 1154f5f, 710 insertions)

**Commits:**
- 1154f5f -- FOUND (feat(17-03): Section 5 -- gated sentinel recode)

## Self-Check: PASSED
