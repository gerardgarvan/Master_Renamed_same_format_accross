# Phase 20: pecan_ID Derivation — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-23
**Phase:** 20-pecan-id-derivation
**Areas discussed:** Source file read strategy (PID-01), PCM-D-17 derivation method,
PCM-D-18 attach point, PID-07 linkage reach output

---

## Source File Read Strategy (PID-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Checksum + cross-check only | Build crosswalk from g.master_data_merged; use CSV for checksum verification and mandatory cross-check on PRECEDE_STUDY_ID | ✓ |
| CSV as primary source | Import CSV, build crosswalk from it; merged dataset used only for attachment | |

**User's choice:** Option 1 — checksum + cross-check only.

**Notes:**
- Path corrected: `raw\master\2018_2022_X_MASTER_DATASET_20240402.csv` (not `raw\`)
- Checksum lookup: `qc/19_raw_files.csv`, not the xlsx workbook
- Cross-check: join CSV to g.master_data_merged on PRECEDE_STUDY_ID; assert MRN value
  equality on every matched row AND same set of PRECEDE_STUDY_IDs on both sides; any
  disagreement aborts
- Read CSV ENCRYPTED_MRN at `$64` (wider than pipeline's `$40`); assert max length ≤ 40
  to catch any truncation that $40 would mask
- Type/length: determined from Phase 19 VARIABLES sheet; pipeline already uses `$40`
- "All 41,150 distinct MRNs" is wrong — 41,150 is the row/PRECEDE count; distinct MRN
  count is lower and is reported by PID-02

---

## PCM-D-17: pecan_ID Derivation Method

| Option | Description | Selected |
|--------|-------------|----------|
| Surrogate sequential integer | 1, 2, 3... in PRECEDE_STUDY_ID order; append-only crosswalk | ✓ |
| Unsalted SHA-256 hash | Hash of ENCRYPTED_MRN; no secret to manage | |
| Salted/keyed hash | Adds genuine privacy but requires secret management | |

**User's choice:** Surrogate sequential integer.

**Notes:**
- Unsalted hash ruled out: no privacy benefit over the MRN itself (anyone holding the
  encrypted MRN can recompute it); 64-char key is awkward in analysis
- Salted hash ruled out: adds a secret to manage and keep out of git
- ENCRYPTED_MRN retained in all analysis outputs alongside pecan_ID (no DROP)
- g.master_data_merged untouched — no pecan_ID column added

| MRN Retention Option | Description | Selected |
|----------------------|-------------|----------|
| Retain in all outputs | Keep ENCRYPTED_MRN in harmonized + cohort datasets | ✓ |
| Retain only in crosswalk | Drop from analysis outputs after attachment | |

---

## PCM-D-18: Attach Point

| Option | Description | Selected |
|--------|-------------|----------|
| Program 20 writes new datasets | 20 reads all three outputs and writes pecan_ID-enhanced versions | |
| Programs 10b/16b join at build time | Crosswalk exists before 10b/16b run; each attaches at their own write step | ✓ |

**User's choice:** Option 2 — 10b and 16b join at build time.

**Notes (user-supplied rationale):**
- "Same names" in option 1 means one program overwriting another program's output —
  violates PCM-T-05 single-producer rule. If 10b/16b are re-run alone, pecan_ID
  silently disappears.
- "Versioned names" in option 1 creates parallel datasets; downstream programs (17,
  analysts) would have to switch names.
- Writing a table back over itself is the PCM-T-02 pattern: fails in PROC SQL
  (`create table g.x from g.x` errors), risks destruction on interruption in DATA step.
- Option 2: every dataset has a single producer; dependency chain is natural
  (20 before 10b); merged file untouched.

**Consequences recorded:**
- Runner order: 1–8 → 19 → 20 → 10b → 16b → 17 → 18
- PID-05 assertions move into 10b and 16b
- Program 20 scope: PID-01 through PID-04, PID-07, PID-08
- PID-06 counts: inline in 16b (covers both g.master_data_harmonized and g.analytic_cohort),
  output to qc/16b_pecan_id_counts.txt and log

| PID-06 Home Option | Description | Selected |
|--------------------|-------------|----------|
| Inline in 16b | Counts run after 16b writes the cohort; both datasets in hand | ✓ |
| Standalone program 20b | Separate program after 16b | |

**PID-06 notes:**
- Must cover both g.master_data_harmonized (41,150 rows) and g.analytic_cohort (13,890),
  side by side — not cohort only
- Write to qc/16b_pecan_id_counts.txt as well as log (log is overwritten on each run)

---

## PID-07: Linkage Reach Report

| Format Option | Description | Selected |
|---------------|-------------|----------|
| Plain text (.txt) with log echo | qc/20_linkage_reach.txt; matches Phase 18 pattern | ✓ |
| CSV with log echo | Machine-readable; more setup | |

**User's choice:** Plain text.

**Notes:** Reader is Claude (deciding PCM-D-15 join key for v2.1), not a downstream
program; CSV doesn't buy much. Matches Phase 18 pattern for qc/ folder consistency.

| Scope Option | Description | Selected |
|--------------|-------------|----------|
| All ENCRYPTED_MRN-tagged raw files | Every file Phase 19 flagged in INV-04 | ✓ |
| r7/r8/r9 only | Only the three 2022 files | |

**User's choice:** All ENCRYPTED_MRN-tagged files.

**Rationale:** Other files provide a comparison basis when reading r7/r8/r9 results.

**Detail additions (user-supplied):**
- Section per file+sheet+MRN column (not per file alone)
- Each section: matched rows / total rows + rate, matched distinct MRNs / total distinct MRNs + rate
- Exclusions list: files with only UNENC_MRN (deliberate skip, not overlooked)
- md3 labeled "reference (crosswalk source)" — 100% by construction
- r7/r8/r9: explicit line "Links on MRN (PCM-D-16 test): yes/no, rate: NN.N%"
- Targeted re-import using Phase 19 KEY_COLUMNS + SHEETS output (avoid full workbook imports)
- Numeric ENCRYPTED_MRN columns: "type mismatch: not compared" block (not silently converted)

---

## Claude's Discretion

- SAS macro structure for looping over KEY_COLUMNS in PID-07
- PUT statement layout for the text report files
- Whether PID-08 DATA_DICTIONARY update uses ODS or PROC SQL (follow 10b/16b pattern)
- Crosswalk sort tie-breaking within a PRECEDE_STUDY_ID (cardinality is 1:1, so no tie)

## Deferred Ideas

None surfaced during discussion. PCM-D-15 gap-fill wiring remains v2.1 pending PID-07 result.
