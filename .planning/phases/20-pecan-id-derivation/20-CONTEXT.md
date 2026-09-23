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

</domain>

<decisions>
## Implementation Decisions

### PCM-D-17: pecan_ID Derivation Method

- **D-01:** pecan_ID is a **surrogate sequential integer** (1, 2, 3...) assigned in
  PRECEDE_STUDY_ID order from `g.master_data_merged`. One row per distinct ENCRYPTED_MRN.
- **D-02:** `g.pecan_id_xwalk` (ENCRYPTED_MRN, pecan_ID) is **append-only**. On re-run,
  existing assignments are never renumbered; new MRNs get the next available integer.
- **D-03:** ENCRYPTED_MRN is **retained in all analysis outputs** (`g.master_data_harmonized`,
  `g.analytic_cohort`) alongside pecan_ID. No DROP statement; no schema change to
  existing columns.
- **Ruled out:** Unsalted SHA-256 hash (no privacy benefit over the MRN itself; awkward
  64-char key). Salted/keyed hash (requires managing a secret outside git). "Same names"
  rewrite from program 20 (violates PCM-T-02 and PCM-T-05 single-producer rule).

### PCM-D-18: Attach Point

- **D-04:** **Option 2 — programs 10b and 16b join the crosswalk at build time.**
  Each dataset has a single producer. If 10b or 16b is re-run, it re-attaches pecan_ID
  from the crosswalk; program 20 need not re-run. The merged file is not touched.
- **D-05:** **PID-05 attachment assertions move into 10b and 16b:**
  - Row count unchanged after join
  - Zero blank pecan_ID where ENCRYPTED_MRN is non-blank
  - Zero PRECEDE_STUDY_IDs gaining a second pecan_ID after attachment
- **D-06:** Column-count assertions and DATA_DICTIONARY variable totals are updated in
  10b and 16b (one KEEP list and one assertion each). Program 20 does not carry
  attachment assertions.

### Program 20 Scope (PID-01 through PID-04, PID-07, PID-08)

- **D-07:** Program 20 owns: checksum verification (PID-01), source audit (PID-02),
  cardinality assertions (PID-03), crosswalk build (PID-04), linkage reach test (PID-07),
  and documentation updates (PID-08).
- Program 20 does **not** own attachment (moved to 10b/16b) or post-attachment counts
  (moved to 16b).

### Source File Strategy (PID-01)

- **D-08:** Source file: `raw\master\2018_2022_X_MASTER_DATASET_20240402.csv` (under
  `raw\master`, not `raw\`). Phase 19 presence check requires it in that exact folder.
- **D-09:** Checksum lookup reads `qc/19_raw_files.csv` — the CSV handoff from Phase 19,
  not the styled xlsx workbook. Parsing the xlsx back in is fragile.
- **D-10:** ENCRYPTED_MRN type and length: read Phase 19 VARIABLES sheet output to
  determine the actual imported type and length for the md3 source before writing any
  informat. The pipeline reads it as `$40`; treat that as the working assumption.
- **D-11 (truncation guard):** Read the CSV's ENCRYPTED_MRN with informat `$64`
  (wider than the pipeline's `$40`). Assert that the maximum observed length is ≤ 40.
  If the source holds longer values, the `$40` in the merged file silently truncated
  them — a same-width read on the CSV would mask that.
- **D-12 (crosswalk source):** Build `g.pecan_id_xwalk` from `g.master_data_merged`
  (which already carries ENCRYPTED_MRN $40, 41,150 rows). The CSV is used only for:
  (1) checksum verification against `qc/19_raw_files.csv`, and (2) a mandatory
  cross-check against the merged dataset.
- **D-13 (cross-check logic):** Join the CSV to `g.master_data_merged` on
  PRECEDE_STUDY_ID. Assert:
  - ENCRYPTED_MRN values are equal on every matched row
  - Both sides contain the same set of PRECEDE_STUDY_IDs (no orphans on either side)
  - Any disagreement → `%abort cancel`. The merged file no longer reflects its source
    and the crosswalk cannot be built.

### PID-02: Source Audit

- **D-14:** Report: blank/placeholder MRN count, **distinct** MRN count (not row count —
  41,150 is rows/PRECEDE_STUDY_IDs; MRNs repeat across repeat enrollments), distinct
  PRECEDE_STUDY_ID count, PRECEDE→MRN cardinality, MRN→PRECEDE cardinality.
- **D-15:** PID-03 assertion: every PRECEDE_STUDY_ID maps to exactly one ENCRYPTED_MRN →
  abort if violated. MRN→many PRECEDE is expected and reported, not asserted.

### PID-06: pecan_ID Counts (in program 16b)

- **D-16:** PID-06 runs inside program 16b, which reads `g.master_data_harmonized`
  as its input and writes `g.analytic_cohort` — both datasets are in hand.
- **D-17:** Report distinct pecan_ID counts and the 1/2/3+ encounter distribution for
  **both** `g.master_data_harmonized` (41,150 rows) and `g.analytic_cohort` (13,890 rows),
  presented side by side.
- **D-18:** Output written to `qc/16b_pecan_id_counts.txt` as well as the SAS log.
  The log is overwritten on each run; the file in `qc/` keeps the counts for comparison
  across runs.

### PID-07: Linkage Reach Report

- **D-19:** Output: `qc/20_linkage_reach.txt` — plain text, one section per
  file + sheet + ENCRYPTED_MRN column combination. Matches Phase 18 pattern
  (`18_gap_candidates.txt`). Log echo summary at the end.
- **D-20:** **Scope: all raw files Phase 19 tagged with ENCRYPTED_MRN** (INV-04
  key-column flags). UNENC_MRN columns are excluded from comparison (comparing plain
  and encrypted values produces a meaningless match rate). Files with only UNENC_MRN
  columns appear in an **exclusions list** with a reason, so a missing file reads as
  deliberate rather than overlooked.
- **D-21:** Each section reports four numbers: matched rows / total rows (row-level match
  rate), matched distinct MRNs / total distinct MRNs (distinct-MRN match rate). Counts
  appear alongside percentages — 100% on 12 rows reads very differently from 100% on
  12,000.
- **D-22:** The md3 source CSV section is labeled **"reference (crosswalk source)"** —
  it matches 100% by construction and is not a result.
- **D-23:** r7/r8/r9 sections each include an explicit line:
  `Links on MRN (PCM-D-16 test): yes/no, rate: NN.N%`. That result drives the
  PCM-D-15 join-key decision for v2.1.
- **D-24 (targeted re-import):** Phase 19 deletes WORK copies after profiling. Phase 20
  re-imports only what is needed, using Phase 19's KEY_COLUMNS and SHEETS output to
  target the specific file, sheet, and MRN column. This avoids importing full workbooks
  (especially md8, which has ~1M rows).
- **D-25 (numeric MRN guard):** If Phase 19 recorded an ENCRYPTED_MRN column as numeric,
  do not silently convert it to character. List those columns as
  **"type mismatch: not compared"** in a separate block, like the exclusions list.
  Converting numeric to char can lose digits or leading zeros, making a type problem
  look like a linkage failure.

### Claude's Discretion

- Exact SAS macro structure inside program 20 (looping over KEY_COLUMNS, output PUT
  statements for the text report)
- Whether PID-08 updates DATA_DICTIONARY.xlsx via ODS or via a PROC SQL update to the
  existing file — consistent with whatever pattern programs 10b/16b use
- Format of crosswalk sort order (PRECEDE_STUDY_ID ascending is the stated basis;
  tie-breaking within a PRECEDE is at Claude's discretion since cardinality is 1:1)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 20 Requirements
- `.planning/REQUIREMENTS.md` §"pecan_ID Derivation (Phase 20)" — PID-01 through PID-08
  acceptance criteria (full text)

### Open Decisions Being Resolved Here
- `.planning/PROJECT.md` §"Open decisions: PCM-D-17, PCM-D-18" — resolved by this context

### Prior Phase Artifacts Phase 20 Reads
- `qc/19_raw_files.csv` — checksum lookup for PID-01 (D-09)
- Phase 19 KEY_COLUMNS sheet output (in `qc/19_raw_inventory.xlsx`) — INV-04 flags for
  PID-07 targeted import (D-24); also available as `.planning/phases/19-raw-directory-inventory/19-CONTEXT.md`
- Phase 19 VARIABLES sheet — actual imported type and length of ENCRYPTED_MRN in md3
  source (D-10)

### Programs This Phase Modifies
- `sas/10b_harmonize.sas` — add crosswalk join + PID-05 assertions + column-count update
- `sas/16b_cohort_rebuild.sas` — add crosswalk join + PID-05 assertions + PID-06 counts
  + column-count update
- `docs/DATA_DICTIONARY.xlsx` — add pecan_ID row with derivation note (PID-08)
- `docs/DECISIONS.md` — record PCM-D-17 and PCM-D-18, attributed and dated (PID-08)

### Constraint References
- PCM-T-02 (no dataset rewritten in place) — enforced by D-04 design choice
- PCM-T-05 (single producer per dataset) — enforced by D-04 design choice
- PCM-T-12 (enumerate expected items individually) — applies to presence checks in PID-01
- PCM-D-16 (2022 ID mismatch, diagnosed not fixed) — PID-07 r7/r8/r9 test is the
  follow-up diagnostic; result drives PCM-D-15 v2.1 gap-fill key decision

No external specs beyond those above. Requirements fully captured in decisions.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/macros_raw_import.sas` — `%import_csv` and `%import_xlsx` macros for re-importing
  raw files in PID-07; use SHEETS/KEY_COLUMNS output to drive targeted calls
- `sas/04_merge.sas` line 273 — ENCRYPTED_MRN defined as `$40` (md3 owns); this is the
  canonical length for the crosswalk column
- Phase 19 certutil + FILENAME PIPE pattern (from 19-CONTEXT.md D-01) — reuse for
  PID-01 checksum verification of the md3 source CSV

### Established Patterns
- QC text output via PUT to a FILENAME fileref (see `18_gap_candidates.txt` pattern in
  `sas/18_supplemental_raw_gap.sas`) — use same pattern for `qc/20_linkage_reach.txt`
  and `qc/16b_pecan_id_counts.txt`
- `%abort cancel` on assertion failure (Phase 18/19) — same pattern for D-13 cross-check
  and D-15 cardinality assertion
- `qc/` folder for deliverables outside the xlsx workbooks — consistent naming:
  `20_linkage_reach.txt`, `16b_pecan_id_counts.txt`

### Integration Points
- `sas/10b_harmonize.sas` — reads `g.master_data_merged`, writes `g.master_data_harmonized`;
  add a SQL join to `g.pecan_id_xwalk` on ENCRYPTED_MRN before the final write, then
  add PID-05 assertions and column-count update
- `sas/16b_cohort_rebuild.sas` — reads `g.master_data_harmonized`, writes `g.analytic_cohort`;
  same join pattern; add PID-05 assertions, PID-06 counts, and column-count update
- `docs/DATA_DICTIONARY.xlsx` — 176 variables currently; each attached dataset adds
  one pecan_ID row; dictionary totals in 10b and 16b must reflect the new column count

</code_context>

<specifics>
## Specific Requirements

- Crosswalk is append-only — existing pecan_ID assignments must never change on re-run
- Read CSV ENCRYPTED_MRN at `$64`; assert max length ≤ 40 before building crosswalk (D-11)
- Cross-check must join on PRECEDE_STUDY_ID and assert both value equality and set equality;
  any mismatch aborts (D-13)
- PID-06 counts go to `qc/16b_pecan_id_counts.txt` and log — not a workbook (D-18)
- PID-07 report: counts behind every rate (matched/total), section per file+sheet+column,
  exclusions list for UNENC_MRN-only files, numeric-MRN "type mismatch: not compared"
  block, explicit r7/r8/r9 PCM-D-16 yes/no line, md3 labeled "reference" (D-19 through D-25)

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
