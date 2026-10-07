# Phase 29: Gap-Fill Wiring (r1-r6) — Context

**Gathered:** 2026-10-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the D15_APPROVED extension columns from supplemental raw files r1–r6 into `g.master_data_merged`, extend `docs/pcnr_name_map.csv` and `docs/sentinel_decisions.csv` to cover the new columns, and verify via PROC COMPARE that no existing rows or columns changed. r7/r8/r9 are explicitly excluded per PCM-D-28.

No new dataset names are introduced. `g.master_data_merged` and `g.master_data_harmonized` retain their names; downstream programs are untouched except for updated column-count assertions in programs 23 and 24.

</domain>

<decisions>
## Implementation Decisions

### D-01 — Column Selection (two-stage)

**Do not select by fill rate alone.** `2018_2019_Precede_Database.xlsx` (r2) alone has ~3,987 columns; a fill-rate cutoff without a secondary gate would pull in thousands of clock and neuropsych columns.

Two-stage rule:
1. **Automatic prefilter** — a column passes if ALL of the following hold:
   - Not already present in `g.master_data_merged` under any name or harmonized concept (IN_BASE = no)
   - Fill rate (n_fillable / n_matched) ≥ chosen threshold (e.g., 5%) — planner may propose the threshold, but it is advisory only
   - Not an ID or key column (PRECEDE_STUDY_ID, ENCRYPTED_MRN, ENCRYPTED_ENCOUNTER, studyid)
2. **Human allowlist** — Gerard reviews the filtered list and approves the final column set before wiring

**Reuse check before re-review:** If `D15_APPROVED = 1` was set against an existing `qc/18_gap_candidates.txt` that has not changed since it was generated, check whether an approved column list was already recorded (in `docs/`, a planning artifact, or git history). If one exists and the source file sizes/SHAs match, reuse it rather than re-reviewing from scratch.

Source files for r1–r6 (by canonical file path on P: drive):
- r1: `P:\PeCAN Master Data\Gerard\raw\2018_2019_2020_Induction_Emergent20231121.csv`
- r2: `P:\PeCAN Master Data\Gerard\raw\2018_2019_Precede_Database.xlsx` (14,807 rows)
- r3: `P:\PeCAN Master Data\Gerard\raw\2018_2022_COLONOSCOPY_20240118.xlsx`
- r4: `P:\PeCAN Master Data\Gerard\raw\2020_Precede_Database_Edu.xlsx` (7,696 rows)
- r5: `P:\PeCAN Master Data\Gerard\raw\2021_Education_20240124.csv`
- r6: `P:\PeCAN Master Data\Gerard\raw\2021_Frailty_20240123.csv`
- (Also mentioned: `2018-2022_PACU_STAY` at 41,423 rows — confirm whether this is a candidate file in program 18's gap_file calls; it does not appear in the current Section B call list)

### D-02 — Fan-Out Risk and Duplicate ID Resolution (BLOCKER)

Several r1–r6 source files have MORE rows than the cohort they describe, indicating duplicate PRECEDE_STUDY_IDs:

| File | Rows | Cohort comparison |
|---|---|---|
| `2018_2019_Precede_Database.xlsx` (r2) | 14,807 | 2018–19 cohort: 14,778 |
| `2018_2019_2020_Induction_Emergent` (r1) | 22,476 | md8: 22,473 |
| `2020_Precede_Database_Edu.xlsx` (r4) | 7,696 | 2020 cohort: 7,695 |

A plain left join against `g.master_data_merged` on PRECEDE_STUDY_ID would fan out rows (adding rows to a 41,150-row dataset). This is PROHIBITED — GAP-03 requires the row count to be unchanged after wiring.

**Required resolution for each duplicate:** The prep program must detect duplicates and abort (`%abort cancel` inside a named macro) if a source file has any duplicate PRECEDE_STUDY_ID. Before running, each duplicate must be assigned one of:
- **De-dup rule recorded in DECISIONS.md:** e.g., "keep first occurrence by sort order" or "keep the row where column X is non-missing" — chosen per file based on domain knowledge
- **Documented exclusion:** the extra row(s) represent true duplicates (re-entries, split encounters) and are legitimately dropped

The planner must surface the specific duplicate IDs for each affected file and propose a de-dup rule for Gerard to approve before the wiring program runs. A gate flag or checkpoint should block the merge block until duplicates are resolved.

### D-03 — Wiring Architecture

Follow the md8 gap-fill pattern (MRG-06 in `04_merge.sas`):

**Step 1 — Prep program: `sas/03r_prep_gapfill.sas`**
- Reads each r1–r6 source file (CSV via DATA step infile; XLSX via `%import_xlsx` from `macros_raw_import.sas`)
- Normalizes PRECEDE_STUDY_ID type (character $12 for r1, r2, r3, r5, r6; numeric with `strip(put(..., best32.))` for r4)
- Applies the approved de-dup rule per file (D-02 above) — ABORTS if duplicates found before rule is applied
- Produces one work dataset per file, keeping only PRECEDE_STUDY_ID + approved extension columns (D-01 allowlist)
- Is NOT added to `run_pipeline.cmd` until duplicates are resolved and the allowlist is approved

**Step 2 — Merge block in `04_merge.sas`**
- A new gap-fill block adjacent to MRG-06 (the existing md8 gap-fill)
- Performs a left join from `g.master_data_merged` to each prepared r1–r6 work dataset
- Gap-fill only: new columns are ADDED, existing column values are NEVER overwritten (COALESCE or conditional assignment)
- Row-count assertion after each join: the dataset must remain at 41,150 rows
- r7, r8, r9 are explicitly skipped with a comment citing PCM-D-28

**Why not a post-merge program:** A separate downstream program would either require a new dataset name (rippling through 16b, 17, 24, 25) or a `data X; set X;` rewrite, which PCM-T-02 forbids.

### D-04 — pcnr Map and Sentinel Entries for New Columns

Auto-generate candidate rows; do not hand-write entries.

**Workflow:**
1. A step (added to or run after program 23) writes proposed rows for each new column into:
   - A draft `pcnr_name_map.csv` extension (same schema as existing file: original_name → pcnr_name, with PCNR_APPROVED = 0 initially)
   - A draft `sentinel_decisions.csv` extension (same schema: variable, raw_value, action, rationale, PCNR_APPROVED = 0 initially)
2. Gerard reviews and sets PCNR_APPROVED = 1 for approved rows
3. A gate flag (same pattern as `PCNR_APPROVED` in `00_config.sas`) blocks program 24 from running if any wired column lacks a map entry with PCNR_APPROVED = 1
4. Column-count assertions in programs 23 and 24 (currently 175 and 163) are updated to match the new totals after approval

The pipeline fails if any wired column reaches program 24 without a map entry.

### D-05 — Pre-Change Snapshot and PROC COMPARE (GAP-03)

**Snapshot approach:** PROC COPY into a separate `snap` libname on P: before the wiring program runs.

```sas
libname snap "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\snap";
proc copy in=g out=snap;
  select master_data_merged master_data_harmonized;
run;
```

Do NOT rename the existing dataset (leaves pipeline broken if run aborts mid-wiring). Do NOT copy within `g` (can be overwritten by next run).

**PROC COMPARE:**
- `base=snap.master_data_merged compare=g.master_data_merged`
- `id PRECEDE_STUDY_ID`
- Restrict the variable list to the original columns (columns present before wiring — derive from `snap.master_data_merged` column metadata)
- Assert: row count unchanged (41,150), ID set unchanged (no new or missing IDs)
- Assert: `&sysinfo` does not have the value-mismatch bit set (bit 12 = decimal 4096 means value differences exist; assert `%eval(&sysinfo & 4096) = 0`)
- New variables appearing only in the compare dataset (`g.master_data_merged`) are the expected result — PROC COMPARE will report them as "variables not in base"; this is not a failure
- Any value difference in an original column IS a failure — fails the phase

Repeat the comparison for `master_data_harmonized`.

### Claude's Discretion

- The exact fill-rate threshold for the D-01 prefilter (user suggested 5% as an example; planner may propose based on `qc/18_gap_candidates.txt` distribution)
- Macro layout and section numbering within `03r_prep_gapfill.sas`
- Whether the PROC COMPARE step lives in a standalone program or as a final section of the wiring program
- Exact de-dup rules for each affected file (r1, r2, r4) — planner surfaces the duplicates, but the rule is Gerard's to approve

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gap-fill evidence and approval
- `sas/18_supplemental_raw_gap.sas` — Sections B and C: the `%gap_file` macro, the r1–r6 call list (lines ~674–733), and the D15_APPROVED gate logic; the column list, key types, and file paths here are authoritative
- `sas/00_config.sas` — `D15_APPROVED = 1` flag (line ~48); path macros (`&raw_path`, `&qc_path`, `&source_path`, `&sas_path`)
- `qc/18_gap_candidates.txt` — (P: drive, gitignored) The gap-fill candidate table by file, bucket (IN_BASE vs NEW), fill rate, and conflict counts; primary input to the D-01 two-stage selection

### Existing merge pattern to follow
- `sas/04_merge.sas` lines ~374–516 (MRG-06 block) — md8 gap-fill pattern: prep work dataset, COALESCE join, row-count assertion; Phase 29 wiring follows the same structure
- `sas/macros_raw_import.sas` — `%import_csv` and `%import_xlsx` macros for DATA step reads (PCM-T-16 compliant)

### pcnr map and sentinel files
- `docs/pcnr_name_map.csv` — Current name map (175 variables); new columns extend this file
- `docs/sentinel_decisions.csv` — Current sentinel decisions; new columns extend this file
- `sas/23_pcnr_inventory.sas` — Program that regenerates candidates; the auto-generation step for new columns follows the same pattern
- `sas/24_pcnr_build.sas` — Contains PCNR_APPROVED gate and column-count assertion (currently 163); must be updated

### Decision record
- `docs/DECISIONS.md` — PCM-D-28 (r7-r9 exclusion and reopening condition); new decision(s) needed for approved column list and de-dup rules
- `.planning/phases/28-r7-r8-r9-linkage-investigation/28-CONTEXT.md` — Phase 28 exclusion rationale for r7/r8/r9

### Conventions
- `sas/00_config.sas` — `%assert_eq` macro, `%abort cancel` pattern (PCM-R-05); PCM-T-15 (no open-code `%IF`); PCM-T-02 (no in-place dataset rewrite)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/18_supplemental_raw_gap.sas` `%gap_file` macro: shows how to import each r1–r6 file, normalize the key, and run a match against the base — reuse key-normalization logic in `03r_prep_gapfill.sas`
- `sas/04_merge.sas` MRG-06 block: the COALESCE left-join pattern + row-count assertion is the direct template for the new merge block
- `sas/27_md8_count.sas` and `sas/19b_seed_hash_baseline.sas`: show the abort-if-already-exists gate pattern for one-time operations

### Established Patterns
- `%import_csv` / `%import_xlsx` from `macros_raw_import.sas` — PCM-T-16 compliant CSV and XLSX reads; no PROC IMPORT
- `%abort cancel` must be inside a named macro, never in open code (PCM-R-05)
- No `%local` in open code; no open-code `%IF`; `%let` variables declared globally at top of macro (PCM-T-15)
- qc/ output files are gitignored; committed artifacts go under `docs/`
- PROC COPY (not DATA step copy) for dataset duplication — avoids PCM-T-02 in-place-rewrite restriction
- Column-count assertions: current values are 175 (program 23) and 163 (program 24, pcnr columns) — both will increase after wiring

### Integration Points
- `sas/04_merge.sas`: receives the r1–r6 prep work datasets and adds the gap-fill merge block (next to MRG-06)
- `sas/23_pcnr_inventory.sas`: re-run after wiring to regenerate candidate rows for new columns
- `sas/24_pcnr_build.sas`: column-count assertion updated; gate blocks run if any new column lacks a map entry
- `sas/25_pcnr_cohort.sas`: row-count assertion (41,150 for full dataset; 13,890 for analytic cohort) must still pass unchanged — no modification expected if row counts hold

</code_context>

<specifics>
## Specific Requirements

- Fan-out is a BLOCKER: each r1–r6 source file must have no duplicate PRECEDE_STUDY_IDs (after de-dup rule is applied) before the merge block runs — `%abort cancel` enforces this
- The PACU_STAY file (41,423 rows) should be investigated: it is not in the current `%gap_file` call list in program 18; confirm whether it is a Phase 29 candidate before including it
- r7, r8, r9 are skipped in the merge block with an explicit comment citing PCM-D-28 and the reopening condition
- PROC COMPARE `&sysinfo` check: the value-mismatch bit is decimal 4096 (bit 12); assert `%eval(&sysinfo & 4096) = 0` — this is a hard gate, not a warning
- The `snap` libname points to a directory outside the `g` library path so the snapshot cannot be overwritten by a pipeline re-run
- De-dup rules must be documented in `docs/DECISIONS.md` before the prep program is considered complete

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 29-gap-fill-wiring-r1-r6*
*Context gathered: 2026-10-07*
