# Phase 20: pecan_ID Derivation — Context

**Gathered:** 2026-09-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the patient-level linkage key (pecan_ID) from ENCRYPTED_MRN, assert cardinality,
produce the append-only crosswalk `g.pecan_id_xwalk`, test linkage reach of all
ENCRYPTED_MRN-carrying raw files, and update DATA_DICTIONARY.xlsx and DECISIONS.md.

**Attach point:** pecan_ID is attached by programs 10b and 16b (not program 20).
Program 20 builds the crosswalk and runs audits only.
`g.master_data_merged` is untouched — no pecan_ID column is added to it.

**Datasets that receive pecan_ID:**
- `g.master_data_harmonized` — attached by program 10b (41,150 rows)
- `g.analytic_cohort` — attached by program 16b (13,890 rows)

**Runner order implied by this design:**
1–8 → 19 → 20 → 10b → 16b → 17 → 18

**Pre-condition (Phase 19 plan amendment required):**
Program 19 Plan 01 must be amended before it executes to also write:
- `qc/19_raw_key_columns.csv` — the KEY_COLUMNS sheet content as CSV
- `qc/19_raw_sheets.csv` — the SHEETS sheet content as CSV
- `qc/19_raw_variables_md3.csv` — VARIABLES rows for the md3 source file only
  (needed by Phase 20 to determine ENCRYPTED_MRN's imported type and length
  without parsing the styled xlsx)
These sit next to `qc/19_raw_files.csv` and follow the same anti-fragile pattern
(D-09). This is a small addition to program 19; cheaper to make now than mid-Phase 20.

</domain>

<decisions>
## Implementation Decisions

### PCM-D-17: pecan_ID Derivation Method

- **D-01:** pecan_ID is a **surrogate sequential integer** (1, 2, 3...). Distinct
  ENCRYPTED_MRN values are numbered 1, 2, 3... in **ascending order of each MRN's
  smallest PRECEDE_STUDY_ID** in `g.master_data_merged` (pecan_ID is a rank, not the
  PRECEDE_STUDY_ID value itself). If PRECEDE_STUDY_ID is stored as character, order
  it numerically, since character sorting puts "10" before "9". MRNs added on later
  runs are appended in the same order after the existing maximum. Blank MRNs (empty after
  `strip()`) and placeholder MRNs (literal string `'NULL'` after `strip(upcase())`)
  receive **no pecan_ID** — they are excluded from the crosswalk entirely.
- **D-02:** `g.pecan_id_xwalk` (ENCRYPTED_MRN, pecan_ID) is **append-only**:
  - The reference for "unchanged" is the **latest dated backup** (D-04), not the
    crosswalk itself — comparing the table to itself always passes. Sequence on re-run:
    1. Before appending, assert the current `g.pecan_id_xwalk` equals the latest
       backup (same rows, same ENCRYPTED_MRN ↔ pecan_ID pairings). Any difference
       aborts — the crosswalk was corrupted or edited outside program 20.
    2. Add new MRNs via PROC APPEND (new rows only); the table is never fully
       rewritten. The next available integer is `max(pecan_ID) + 1`.
    3. After appending, assert every backup row is still present and unchanged.
    4. Only then write the new dated backup.
  - First run (no crosswalk and no backup exists): skip steps 1 and 3, build the
    crosswalk, write the first backup, and log the run as the initial build.
- **D-03:** ENCRYPTED_MRN is **retained in all analysis outputs**
  (`g.master_data_harmonized`, `g.analytic_cohort`) alongside pecan_ID. No DROP
  statement; no schema change to existing columns.
- **D-04 (crosswalk backup):** `g.pecan_id_xwalk` is a `.sas7bdat` file excluded
  from git. It is the only persistent record of pecan_ID assignments. Program 20
  must write a **dated backup copy** to a protected location outside `qc/` and
  outside git (ENCRYPTED_MRN values must not appear in `qc/` or git). Document
  the backup path in `00_config.sas` as a macro variable. If the crosswalk is
  ever deleted, the next run would renumber every patient and violate the
  append-only guarantee.
- **Ruled out:** Unsalted SHA-256 hash (no privacy benefit over the MRN itself;
  awkward 64-char key in analysis). Salted/keyed hash (requires managing a secret
  outside git). Program 20 rewriting 10b/16b output datasets (violates PCM-T-02
  and PCM-T-05 single-producer rule).

### PCM-D-18: Attach Point

- **D-05:** **Programs 10b and 16b join the crosswalk at build time** (option 2).
  Each dataset has a single producer. The merged file is not touched.
- **D-06:** **PID-05 attachment assertions move into 10b and 16b:**
  - Row count unchanged after join
  - Zero blank pecan_ID where ENCRYPTED_MRN is non-blank and non-placeholder
  - Zero PRECEDE_STUDY_IDs gaining a second pecan_ID after attachment
- **D-07:** Column-count assertions are updated in 10b and 16b (one KEEP list and
  one assertion each): `g.master_data_harmonized` and `g.analytic_cohort` each go
  from 174 to 175 columns. DATA_DICTIONARY variable totals are **not** handled in
  10b/16b — the dictionary is produced only by `08_dictionary.sas` (D-27).

### Program 20 Scope (PID-01 through PID-04, PID-07, PID-08)

- **D-08:** Program 20 owns: checksum verification (PID-01), source audit (PID-02),
  cardinality assertions (PID-03), crosswalk build (PID-04), linkage reach test
  (PID-07), and documentation updates (PID-08).
- Program 20 does **not** own attachment or post-attachment counts.

### Source File Strategy (PID-01)

- **D-09:** Source file: `raw\master\2018_2022_X_MASTER_DATASET_20240402.csv`
  (under `raw\master`, not `raw\`). Phase 19 presence check requires it in that
  exact folder.
- **D-10:** Checksum lookup reads `qc/19_raw_files.csv` — the CSV handoff from
  Phase 19, not the styled xlsx workbook. All other Phase 19 structured outputs
  consumed by Phase 20 (`qc/19_raw_key_columns.csv`, `qc/19_raw_sheets.csv`,
  `qc/19_raw_variables_md3.csv`) are also plain CSV for the same reason.
- **D-11:** ENCRYPTED_MRN type and length: read `qc/19_raw_variables_md3.csv`
  to determine the actual imported type and length before writing any informat.
  The pipeline reads it as `$40`; treat that as the working assumption only
  until the CSV confirms it.
- **D-12 (truncation guard):** Read the CSV's ENCRYPTED_MRN with informat `$64`
  (wider than the pipeline's `$40`). Assert that the maximum observed length is
  ≤ 40. If the source holds longer values, the `$40` in the merged file silently
  truncated them — a same-width read on the CSV would mask that failure.
- **D-13 (crosswalk source):** Build `g.pecan_id_xwalk` from `g.master_data_merged`
  (which already carries ENCRYPTED_MRN `$40`, 41,150 rows). The CSV is used only
  for: (1) checksum verification against `qc/19_raw_files.csv`, and (2) the
  mandatory cross-check below.
- **D-14 (cross-check logic):** Join the CSV to `g.master_data_merged` on
  PRECEDE_STUDY_ID. Before comparing:
  - Apply to the CSV side **exactly the transformations the md3 prep program
    applies** to ENCRYPTED_MRN and PRECEDE_STUDY_ID. The planner must read the md3
    prep program and copy its rules; do not assume them. The expected rules are
    `strip()` whitespace and treating `strip(upcase(ENCRYPTED_MRN)) = 'NULL'` as
    blank (PREP-02), but the prep program is authoritative. Any transformation the
    cross-check misses shows up as a false mismatch and aborts the run.
  - Cast PRECEDE_STUDY_ID to the same type on both sides before joining (CSV import
    may read it as numeric).
  Assert:
  - ENCRYPTED_MRN values are equal on every matched row (after normalization)
  - Both sides contain the same set of PRECEDE_STUDY_IDs (no orphans on either side)
  - Any disagreement → `%abort cancel`. The merged file no longer reflects its
    source and the crosswalk cannot be safely built.

### PID-02: Source Audit

- **D-15:** "Blank or placeholder" is testable: a row is excluded from the crosswalk
  if `missing(ENCRYPTED_MRN)` (SAS missing char = all-blank) OR
  `strip(upcase(ENCRYPTED_MRN)) = 'NULL'` (literal sentinel surviving CSV import).
  Report: count of excluded rows (blank + placeholder separately), count of included
  distinct MRNs, count of distinct PRECEDE_STUDY_IDs, PRECEDE→MRN cardinality,
  MRN→PRECEDE cardinality.
- **D-16:** PID-03 assertion: every PRECEDE_STUDY_ID maps to exactly one
  ENCRYPTED_MRN → abort if violated. MRN→many PRECEDE is expected (repeat
  enrollments) and reported, not asserted.
- **Note:** 41,150 is the row/PRECEDE count. Distinct MRN count is lower and is
  what PID-02 reports.

### PID-06: pecan_ID Counts (in program 16b)

- **D-17:** PID-06 runs inside program 16b, which reads `g.master_data_harmonized`
  as its input and writes `g.analytic_cohort` — both datasets are in hand.
- **D-18:** Report distinct pecan_ID counts and the 1/2/3+ encounter distribution
  for **both** `g.master_data_harmonized` (41,150 rows) and `g.analytic_cohort`
  (13,890 rows), presented side by side.
- **D-19:** Output written to `qc/16b_pecan_id_counts.txt` and the SAS log.

### PID-07: Linkage Reach Report

- **D-20:** Output: `qc/20_linkage_reach.txt` — plain text, one section per
  file + sheet + ENCRYPTED_MRN column combination. Matches Phase 18 pattern
  (`18_gap_candidates.txt`). Log echo summary at the end.
  Reader is **Gerard**, deciding PCM-D-15's join key for v2.1.
- **D-21:** **Scope: all raw files Phase 19 tagged with ENCRYPTED_MRN** (from
  `qc/19_raw_key_columns.csv`). UNENC_MRN columns are excluded from comparison.
  Files with only UNENC_MRN columns appear in an **exclusions list** with reason.
- **D-22:** Each section reports: matched rows / total rows (row-level match rate),
  matched distinct MRNs / total distinct MRNs (distinct-MRN match rate). Counts
  appear alongside percentages — 100% on 12 rows reads differently from 100% on
  12,000.
- **D-23:** The md3 source CSV section is labeled **"reference (crosswalk source)"**
  — it matches 100% by construction and is not a result.
- **D-24:** r7/r8/r9 sections each include an explicit line:
  `Links on MRN (PCM-D-16 test): YES / NO`.
  **"YES"** = at least one distinct ENCRYPTED_MRN in the file matches a row in
  `g.pecan_id_xwalk`. Report the exact distinct-MRN match rate alongside. If the
  rate is 0% the answer is NO; any positive rate is YES. Gerard decides whether
  the rate is actionable for PCM-D-15 — program 20 does not apply a threshold.
- **D-25 (targeted re-import):** Phase 19 deletes WORK copies after profiling.
  Phase 20 re-imports only what is needed, using `qc/19_raw_key_columns.csv` and
  `qc/19_raw_sheets.csv` to identify the target file, sheet, and column. Use
  `FILENAME` / `LIBNAME` (or `PROC IMPORT` with explicit SHEET=) — not
  `%import_csv` / `%import_xlsx`, which take source IDs and are not designed for
  targeted column reads. This matters especially for md8 (~1M rows).
- **D-26 (numeric MRN guard):** If `qc/19_raw_key_columns.csv` records an
  ENCRYPTED_MRN column as numeric in any file, do not silently convert it to
  character. List those columns as **"type mismatch: not compared"** in a
  separate block analogous to the exclusions list. A silent numeric-to-char
  conversion can lose digits or leading zeros, making a type problem look like
  a linkage failure.

### PID-08: Documentation Updates

- **D-27 (DATA_DICTIONARY.xlsx):** `08_dictionary.sas` generates the dictionary
  from `g.master_data_merged` and already has a static-entry block for
  merge-derived variables (lines 234–244, variables like `RT_ENVELOPE_FLAG`,
  `N_SOURCES`). Add pecan_ID as a static entry in that same block with a
  derivation note: "surrogate patient key derived from ENCRYPTED_MRN in Phase 20;
  attached to g.master_data_harmonized and g.analytic_cohort by programs 10b and 16b."
  One dictionary row for the variable; the note names the datasets that carry it.
  This is the correct pattern because pecan_ID is not in `g.master_data_merged`
  (which 08 reads), and any row added elsewhere would be overwritten the next time
  08 runs.
  **Verify before planning the edit:** `RT_ENVELOPE_FLAG` and `N_SOURCES` already
  exist in `g.master_data_merged`, so the block at lines 234–244 may only supply
  derivation text for columns 08 finds there. If it annotates existing columns
  rather than adding rows, a pecan_ID entry will be silently dropped; in that case
  the pecan_ID row needs an explicit output of its own. Also check whether 08
  asserts a variable count (176) that the new row would change, and update that
  assertion if so.
  **Do not use PROC SQL UPDATE or xlsx manipulation** — PCM-T-01 bans PROC SQL UPDATE;
  you cannot SQL-update an xlsx file.
- **D-28 (DECISIONS.md):** Record PCM-D-17 and PCM-D-18, attributed to Gerard
  Garvan, dated 2026-09-23.

### Claude's Discretion

- Exact SAS macro structure inside program 20 (looping over `qc/19_raw_key_columns.csv`
  rows for PID-07, PUT statement layout for text report files)
- Backup location path for the crosswalk (macro variable in `00_config.sas`; must
  be outside `qc/` and outside git)
- Whether the static pecan_ID entry in `08_dictionary.sas` uses the existing
  `varname = "..."; derivation = "..."; output;` pattern or a separate hardcoded
  dataset — use whichever matches the existing block style

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 20 Requirements
- `.planning/REQUIREMENTS.md` §"pecan_ID Derivation (Phase 20)" — PID-01 through PID-08

### Open Decisions Resolved Here
- `.planning/PROJECT.md` §"Open decisions: PCM-D-17, PCM-D-18"

### Phase 19 CSV Handoffs (Phase 20 reads these — NOT the xlsx)
- `qc/19_raw_files.csv` — checksum records (PID-01)
- `qc/19_raw_key_columns.csv` — INV-04 key-column flags (PID-07 scope + D-25)
- `qc/19_raw_sheets.csv` — sheet metadata (PID-07 targeted import + D-25)
- `qc/19_raw_variables_md3.csv` — ENCRYPTED_MRN type/length for md3 (D-11)
  *(These files are written by the Phase 19 Plan 01 amendment. They do not exist
  until program 19 runs, so their presence is checked at the start of Phase 20
  execution (program 20 aborts if any is missing), not during planning.)*

### Programs Phase 20 Creates or Modifies
- `sas/20_pecan_id.sas` — new program (PID-01 through PID-04, PID-07, PID-08)
- `sas/10b_harmonize.sas` — add crosswalk join + PID-05 assertions + column-count update
- `sas/16b_cohort_rebuild.sas` — add crosswalk join + PID-05/PID-06 + column-count update
- `sas/08_dictionary.sas` lines 234–244 — add pecan_ID static entry
- `docs/DATA_DICTIONARY.xlsx` — regenerated by 08 after the static entry is added
- `docs/DECISIONS.md` — PCM-D-17 and PCM-D-18 entries

### Constraint References
- PCM-T-01 (no PROC SQL UPDATE) — rules out SQL-patching the dictionary xlsx (D-27)
- PCM-T-02 (no dataset rewritten in place) — enforced by D-05 design
- PCM-T-05 (single producer per dataset) — enforced by D-05 design
- PCM-T-12 (enumerate expected items individually) — applies to PID-01 presence checks
- PCM-D-16 (2022 ID mismatch, diagnosed not fixed) — PID-07 r7/r8/r9 test is the
  follow-up; result drives PCM-D-15 v2.1 gap-fill key decision

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/08_dictionary.sas` lines 234–244 — static-entry block for derived variables;
  pecan_ID fits this exact slot (D-27)
- `sas/04_merge.sas` line 273 — ENCRYPTED_MRN defined as `$40` (md3 owns); canonical
  crosswalk column length
- Phase 19 certutil + `FILENAME ... PIPE` checksum pattern (19-CONTEXT.md D-01) —
  reuse for PID-01 checksum of md3 source CSV
- Phase 18 PUT-to-fileref text output pattern (`18_gap_candidates.txt`) — reuse for
  `qc/20_linkage_reach.txt` and `qc/16b_pecan_id_counts.txt`

### Established Patterns
- `%abort cancel` on assertion failure — same pattern for D-14 cross-check, D-16
  cardinality assertion, D-02 crosswalk-unchanged assertion
- NULL sentinel test: `strip(upcase(col)) = 'NULL'` — from prep programs (PREP-02);
  apply same normalization in D-14 before cross-checking the CSV
- `qc/` folder for deliverables outside xlsx workbooks

### Integration Points
- `sas/10b_harmonize.sas` — reads `g.master_data_merged`, writes
  `g.master_data_harmonized`; add SQL join to `g.pecan_id_xwalk` on ENCRYPTED_MRN
  before final write, then PID-05 assertions and column-count update
- `sas/16b_cohort_rebuild.sas` — reads `g.master_data_harmonized`, writes
  `g.analytic_cohort`; same join + PID-05 assertions + PID-06 counts + column-count
  update
- `sas/08_dictionary.sas` — pecan_ID added as static entry in existing derived-vars
  block; triggers dictionary regeneration

</code_context>

<specifics>
## Specific Requirements

- Crosswalk append-only: compare against the latest dated backup before and after
  appending; PROC APPEND new rows only; first run logged as initial build (D-02)
- Dated backup of crosswalk in protected location outside qc/ and git (D-04)
- CSV ENCRYPTED_MRN read at `$64`; assert max length ≤ 40 (D-12)
- Cross-check: apply the md3 prep program's own rules to the CSV side, plus the same
  PRECEDE type on both sides, before asserting
  equality and set membership; any mismatch aborts (D-14)
- Placeholder values are testable: `missing()` OR `strip(upcase()) = 'NULL'` (D-15)
- PID-07: counts behind every rate; section per file+sheet+column; exclusions list for
  UNENC_MRN-only files; numeric-MRN "type mismatch: not compared" block; explicit
  r7/r8/r9 PCM-D-16 YES/NO line where YES = any distinct MRN matches (D-20 through D-26)
- PID-08: pecan_ID as static entry in 08_dictionary.sas derived-vars block; one row,
  note names datasets that carry it; verify the block adds rows (not only annotates)
  and update any 176-variable assertion; no PROC SQL UPDATE, no xlsx manipulation (D-27)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

PCM-D-15 gap-fill wiring (extension-column join key decision) remains deferred to v2.1
pending the r7/r8/r9 linkage result from PID-07.

</deferred>

---

*Phase: 20-pecan-id-derivation*
*Context gathered: 2026-09-23*
