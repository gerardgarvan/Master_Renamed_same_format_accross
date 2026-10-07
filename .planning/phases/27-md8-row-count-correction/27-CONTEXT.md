# Phase 27: md8 Row-Count Correction — Context

**Gathered:** 2026-10-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a one-time dual-count verification confirming md8 has 22,473 non-missing rows, and
make the pipeline permanently drop all-missing trailing rows and assert the expected N on
every run. Update DECISIONS.md with the corrected finding (md8 "truncation" is actually
trailing padding, not data loss). No other programs or datasets change in this phase.

Two-part deliverable:
1. **Standalone verification program** (run once, like 19b) — dual count + contiguity checks,
   result committed to a QC CSV and a new DECISIONS entry (PCM-D-31).
2. **Permanent correction in the md8 import step** — drop all-missing rows, assert N = 22,473
   on every pipeline run.

</domain>

<decisions>
## Implementation Decisions

### D-01: Program Disposition (MD8-01)

Split into two programs:

- **Standalone verification program** (e.g., `27_md8_count.sas`): runs once manually (not
  added to `run_pipeline.cmd`). Performs the dual count, contiguity check, and PRECEDE_STUDY_ID
  agreement check. Writes results to a committed QC CSV (e.g., `qc/27_md8_count.csv`).
  Rationale: HARD-01/HARD-02 already locks md8's bytes — once the verification passes and
  hashes are committed, rechecking every run proves nothing new and adds ~20 seconds.

- **Permanent row-drop + assertion** in whichever program currently imports md8 (planner
  confirms which program — likely 08): drop all-missing rows before promoting to the library
  dataset, then assert `n_rows = 22473` via `%assert_eq` / `%abort cancel` (PCM-R-05).
  This assertion costs nothing per run and catches any future re-export that changes the row
  count.

### D-02: Second Count Source (MD8-01)

Use `raw\ALL_AIM2_MASTER_DATASET_20210917.xlsx` (file_id 19 in the raw directory inventory,
22,473 rows, 68 columns) as the independent second count.

- The `raw\master\` copy (file_id 30) has 1,048,575 rows — the Excel sheet maximum minus the
  header, indicating used-range stretching from padding/formatting, not real data.
- The `raw\` copy is already inventoried in `qc/19_raw_files.csv`; its row count is the
  correct reference. MRN encryption difference (PCM-D-16) is irrelevant for a row count.
- **Pre-condition:** Before relying on the raw\ copy, confirm that the SHA-256 values for the
  two copies in `qc/19_raw_files.csv` (or `docs/raw_hash_baseline.csv`) are different. If
  they matched, the 1,048,575 figure would be an engine artifact of the same file, not an
  independent observation.
- If counts do not reconcile → escalate to the extract producer before updating documentation.

The weaker cross-check (Induction_Emergent at 22,476 rows, 2018–2020) noted for context but
not used as a primary count source.

### D-03: Non-Missing Definition (MD8-01)

A row is non-missing if **any** of the 68 columns is non-missing, where non-missing is:
- **Numeric:** not SAS missing (`.`)
- **Character:** not blank/whitespace-only (after `strip`), and not the literal `NULL`
  (case-insensitive — md8's sentinel per PCM-F-05)

Reuse Program 19 SECTION 7 logic exactly (lines ~560–590):
- char: `if missing(_char{_i}) then ...` → blank; `else if upcase(strip(_char{_i})) = 'NULL' then ...` → sentinel
- num: `if missing(_num{_i}) then ...`

### D-04: Three Confirmation Checks (MD8-01)

The standalone verification program must pass all three before the finding is settled:

1. **Count check:** any-column non-missing count = 22,473
2. **Contiguity check:** the position of the last non-missing row = 22,473. This distinguishes
   trailing padding (contiguous) from scattered blank rows interspersed with real data.
3. **PRECEDE_STUDY_ID agreement:** count of non-missing PRECEDE_STUDY_ID values = 22,473.
   Secondary cross-check — if this disagrees, the all-column sweep and the ID sweep are
   measuring different things and the definition needs review.

If all three pass → finding is "trailing padding, not truncation"; md8's true N = 22,473.

### D-05: Documentation Updates (MD8-02)

- **`docs/DECISIONS.md`**: new entry PCM-D-31 recording the dual-count result, the
  contiguity finding, and the statement that the raw\ copy is a row-count reference only
  (its MRNs use a different encryption and the files are not interchangeable, per PCM-D-16).
- **`sas/00_ownership_rule.sas` comment** (line ~37): 22,473 is already correct; update the
  inline comment to note it is verified by the Phase 27 program, not assumed.
- **STATE.md performance metrics table**: fill in `md8 non-missing rows | TBD | TBD` → `22,473`.
- No changes to DATA_DICTIONARY.xlsx or pcnr dictionaries in this phase.

### Claude's Discretion

- Which program currently imports md8 (likely 08_merge.sas or similar) — planner confirms
  from the codebase before adding the drop + assertion.
- Exact output format for `qc/27_md8_count.csv` (columns: count_source, row_count,
  last_nonmissing_pos, precede_id_count, pass_fail — or similar).
- Whether the contiguity check reads row numbers via `_N_` in a DATA step or via a PROC SQL
  rownum equivalent — planner decides based on existing patterns.
- Decision number for DECISIONS.md entry: PCM-D-31 (next after PCM-D-30).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Non-missing logic (reuse directly)
- `sas/19_raw_dir_inventory.sas` §SECTION 7 (lines ~560–590) — character and numeric
  non-missing / sentinel classification logic; md8 uses the same NULL sentinel pattern

### Existing count and assertion patterns
- `sas/01_verify_sources.sas` — `%count_src` macro and row-count assertion pattern;
  replicate for md8-specific assertion
- `sas/00_ownership_rule.sas` line ~37 — embedded 22,473 reference; update comment here

### Abort and assertion convention
- `sas/03_prep_md8.sas` — `%assert_row_count` and `%check_libname` inline macros using
  `%abort cancel` (PCM-R-05); permanent assertion reuses this pattern. NOTE: `%assert_eq`
  and `%fail_out` are NOT defined in `00_config.sas`; the convention is an inline named
  macro per-program. `%fail_out` lives in `sas/19_raw_dir_inventory.sas`, not in config.

### Documentation targets
- `docs/DECISIONS.md` — append PCM-D-31 after the PCM-D-30 block (line ~950)
- `.planning/STATE.md` — update performance metrics table (md8 non-missing rows row)
- `.planning/REQUIREMENTS.md` — MD8-01 and MD8-02 requirement definitions

### Raw directory inventory (second count source)
- `qc/19_raw_files.csv` — SHA-256 and row counts for both AIM2 copies; confirm SHA-256
  values differ before treating the raw\ copy as an independent source
- `docs/raw_hash_baseline.csv` — HARD-01 baseline; contains raw\master\ SHA-256 for md8

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/19_raw_dir_inventory.sas` SECTION 7: per-column missing/sentinel classifier —
  array-based DATA step; reuse directly for the 68-column any-column sweep
- `%assert_eq` / `%fail_out` (00_config.sas): established abort macro; permanent assertion
  in the md8 import program uses this

### Established Patterns
- Standalone-only programs (19b, 19c): not in run_pipeline.cmd, run once manually,
  result committed to docs/ or qc/; verification program follows the same model
- `%count_src` in 01_verify_sources.sas: source-level row count reporting; md8-specific
  assertion mirrors this structure
- PCM-T-16: DATA step infile for reading CSV files — apply if the verification program
  reads the raw\ copy via an IMPORT step (switch to infile/input if needed)

### Integration Points
- The md8 import program (planner identifies exact program): add drop-missing step before
  promote; add `%assert_eq(n_md8_nonmissing, 22473, ...)` after drop
- `docs/DECISIONS.md`: append new entry; planner reads existing PCM-D-30 block for format

</code_context>

<specifics>
## Specific Ideas

- **AIM2 file_id disambiguation:** file_id 19 (`raw\`) = 22,473 rows; file_id 30
  (`raw\master\`) = 1,048,575 rows. The 1,048,575 figure is the Excel sheet maximum minus
  header — a used-range artifact. Verify SHA-256 difference before treating them as
  independent observations.
- **Contiguity proof:** last non-missing row position = non-missing count is the key
  diagnostic. If trailing rows are scattered rather than contiguous, the finding changes.
- **Weaker cross-check (informational):** Induction_Emergent (2018–2020) has 22,476 rows —
  3 more than md8. Note as context in DECISIONS entry but do not use as a count source.
- `sas/00_ownership_rule.sas` line ~37 already embeds 22,473; it's correct but currently
  undocumented — the Phase 27 verification gives it a traceable source.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 27-md8-row-count-correction*
*Context gathered: 2026-10-07*
