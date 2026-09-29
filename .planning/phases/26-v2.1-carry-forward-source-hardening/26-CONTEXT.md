# Phase 26: v2.1 Carry-Forward & Source Hardening — Context

**Gathered:** 2026-09-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix two v2.1 carry-forward items (sentinel CONTAINS cleanup in program 23, two new QC assertions in program 24), and add a hash-guard to program 19 that fails the run immediately when any md1-md8 source file has changed since baseline was seeded. A new seed program (19b) creates the baseline once and refuses to overwrite it.

Scope is: program 23 (sentinel audit + cleanup), program 24 (two assertions), program 19 (hash guard), program 19b (seed), docs/DECISIONS.md (one documentation note), and docs/raw_hash_baseline.csv (new file). No other programs or datasets change in this phase.

</domain>

<decisions>
## Implementation Decisions

### FIX-03: Sentinel CONTAINS Cleanup (two-task process)

- **D-01:** FIX-03 is a two-task process with a human checkpoint between tasks.
- **D-02 (Task 1 — Diagnostic):** Before modifying program 23 or sentinel_decisions.csv, produce a diagnostic report `qc/23_contains_audit.csv` listing every distinct `(contains_fragment, variable, raw_value, n_rows)` tuple currently matched by the CONTAINS block, limited to non-freetext columns. This can be a standalone DATA step or an audit mode inside program 23.
- **D-03 (Task 2 — Apply, after human review of audit):** Narrow the CONTAINS block based on the audit:
  - DECLINED, REFUSED, NOT SPECIFIED: keep only if the audit shows exclusively sentinel-only matches for those fragments; otherwise drop.
  - UNKNOWN and N/A compound forms (e.g., "UNKNOWN/OTHER", "N/A - NOT APPLICABLE"): if the audit shows they appear only as full-value matches, promote those specific compound values to EXACT rules and remove the CONTAINS fragment.
  - Multi-word phrases with low false-positive risk (NOT DOCUMENTED, NOT RECORDED, NOT APPLICABLE, NOT ASSESSED, NOT PERFORMED, UNABLE TO OBTAIN): retain as CONTAINS unless the audit shows false positives.
  - Short words with high false-positive risk (NONE, OTHER, MISSING, PENDING): drop from CONTAINS unless the audit justifies them.
  - After narrowing program 23, enumerate which KEEP rows in `docs/sentinel_decisions.csv` no longer match any remaining rule; present the list for human approval before deletion.

### FIX-04: New QC Assertions in program 24

- **D-04:** Both assertions go into `24_pcnr_build.sas`, after the sentinel-handling step, on `g.pcnr_harmonized`.
- **D-05:** `Cognitive_Score = 0` is treated as a placeholder sentinel (not a valid score); the assertion is: count of `pcnr_Cognitive_Score = 0` rows in `g.pcnr_harmonized` must equal 0. Triggers `%abort cancel` on failure (PCM-R-05: inside a named macro).
- **D-06:** `rt_RM_START_to_AN_START_mins = -9` is a sentinel; the assertion is: count of `pcnr_rt_RM_START_to_AN_START_mins = -9` (or the pcnr-prefixed equivalent) in `g.pcnr_harmonized` must equal 0. Triggers `%abort cancel` on failure (PCM-R-05).
- **D-07:** Both use `%assert_eq` macro pattern (PCM-R-05), consistent with program 05.

### HARD: Hash Baseline File Design

- **D-08:** Baseline hash file: `docs/raw_hash_baseline.csv`, columns `file_name, sha256, byte_size, seeded_date`. Read with a DATA step `infile` in program 19 (PCM-T-16).
- **D-09:** Seed program: `19b_seed_hash_baseline.sas` — copies today's verified sha256 values from `19_raw_files.csv` for md1-md8, populates `seeded_date` with today's date, and **refuses to run (aborts) if `docs/raw_hash_baseline.csv` already exists**. Never run automatically by the pipeline.
- **D-10:** Program 19 reads the baseline file and compares each md1-md8 sha256 against the stored value. Any mismatch triggers `%abort cancel` with an explicit error message before any merge program executes. Program 19 never writes the baseline file.
- **D-11:** To update the baseline (e.g., when an extract is replaced), the operator manually deletes `docs/raw_hash_baseline.csv` and re-runs `19b_seed_hash_baseline.sas`.
- **D-12:** `run_pipeline.cmd` does NOT include `19b`. The seed program is a one-time manual step, not part of the automated pipeline run.

### HARD-03: DECISIONS.md Note

- **D-13:** Add a documentation-only note to `docs/DECISIONS.md` explaining that the read-only file attribute is insufficient on a network share (deletion is still possible) and that full source protection requires IT engagement to remove folder-level write and delete permissions.

### Claude's Discretion

- Exact variable name used for `pcnr_Cognitive_Score` and `pcnr_rt_RM_START_to_AN_START_mins` — planner should confirm the pcnr-prefixed names from `docs/pcnr_name_map.csv` before writing assertions.
- Whether the CONTAINS audit step is a standalone SAS program or an audit mode flag inside program 23 — planner decides based on least disruption to the existing program structure.
- The decision number for the HARD-03 DECISIONS.md entry (next available after PCM-D-27 if it exists, otherwise PCM-D-27).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Sentinel Rules
- `docs/DECISIONS.md` §PCM-D-21 — Approved sentinel seed list and matching rules (EXACT vs CONTAINS intent)
- `docs/sentinel_decisions.csv` — Current approved sentinel decisions; KEEP rows are what FIX-03 cleanup targets

### Relevant Programs
- `sas/23_pcnr_inventory.sas` — Program 23; contains the EXACT and CONTAINS sentinel matching block (lines ~381-407)
- `sas/24_pcnr_build.sas` — Program 24; FIX-04 assertions go here, post-sentinel step
- `sas/19_raw_dir_inventory.sas` — Program 19; hash guard goes here; already computes sha256 via certutil pipe
- `sas/00_config.sas` — Defines `%assert_eq` macro, `%abort cancel` patterns (PCM-R-05), path macros

### QC Outputs (read, do not modify)
- `qc/19_raw_files.csv` — Source of verified sha256 values for md1-md8; used to seed the baseline
- `docs/pcnr_name_map.csv` — Maps original column names to pcnr_ prefixed names; needed to confirm assertion variable names

### Technical Constraints
- PCM-T-16: baseline hash file must be read with a DATA step `infile` statement (not PROC IMPORT)
- PCM-R-05: `%abort cancel` must live inside a named macro definition
- PCM-C-05: programs run as separate sas.exe sessions via run_pipeline.cmd

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `%assert_eq` macro (defined in `sas/00_config.sas` and copied into `05_qc_merge.sas`): exact pattern to reuse for FIX-04 assertions in program 24
- sha256 computation via certutil pipe (lines ~187-197 in `19_raw_dir_inventory.sas`): same approach reusable in program 19 for comparison; baseline read uses `infile` on the CSV file
- freetext_cols exclusion logic in program 23 (line ~379): already implemented; CONTAINS audit should respect the same exclusion

### Established Patterns
- `%abort cancel` inside named macro: PCM-R-05; see program 05 for reference implementation
- DATA step `infile` for reading CSVs: PCM-T-16; already used throughout (e.g., `19_raw_dir_inventory.sas` lines ~695, ~778, ~941)
- Sentinel matching block: lines 381-407 in `23_pcnr_inventory.sas`; EXACT block first, CONTAINS block second

### Integration Points
- Program 19 is the first program in `run_pipeline.cmd`; the hash guard runs before any merge program
- Program 24 runs after program 23; FIX-04 assertions added after the sentinel-handling DATA step that sets values to missing
- `19b_seed_hash_baseline.sas` is NOT wired into `run_pipeline.cmd`; it is a standalone manual program

</code_context>

<specifics>
## Specific Ideas

- FIX-03 audit output file: `qc/23_contains_audit.csv` — columns `(contains_fragment, variable, raw_value, n_rows)`, sorted by fragment then variable then descending n_rows, so the human reviewer can quickly spot false positives.
- After the audit, UNKNOWN and N/A compound forms that appear only as full-value matches should be promoted to the EXACT list (added as additional `in()` values) rather than kept in the CONTAINS block.
- The baseline file guard in `19b`: use `fileexist()` or a DATA step `infile` existence check; if file exists, `%put ERROR:` and `%abort cancel` — do not overwrite silently.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 26-v2.1-carry-forward-source-hardening*
*Context gathered: 2026-09-29*
