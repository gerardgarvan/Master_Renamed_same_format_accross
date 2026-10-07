# Phase 27: md8 Row-Count Correction — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-07
**Phase:** 27-md8-row-count-correction
**Areas discussed:** Program disposition, Second count source, Non-missing definition

---

## Program Disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Permanent pipeline program | Added to run_pipeline.cmd; re-verifies md8 on every run | |
| Standalone + permanent split | One-time verification program (like 19b) + permanent drop/assert in import step | ✓ |

**User's choice:** Split approach — standalone verification (27_md8_count.sas, run once,
result committed to QC CSV + DECISIONS entry) plus permanent drop-all-missing + assert N=22473
in whichever program imports md8.

**Notes:** HARD-01/HARD-02 already lock md8's bytes via the hash guard — once verification
passes and hashes are committed, rechecking the count every run adds ~20 seconds and proves
nothing new. The permanent assertion in the import program catches future re-exports.

---

## Second Count Source

| Option | Description | Selected |
|--------|-------------|----------|
| raw\master\ copy | 1,048,575 rows — Excel sheet maximum minus header; padding artifact | |
| raw\ copy (file_id 19) | 22,473 rows, 68 columns; already inventoried in 19_raw_files.csv | ✓ |
| Generating query | Not accessible | |

**User's choice:** `raw\ALL_AIM2_MASTER_DATASET_20210917.xlsx` (file_id 19, raw\ directory),
22,473 rows. MRN encryption difference (PCM-D-16) is irrelevant for row count.

**Notes:**
- Pre-condition: confirm SHA-256 of the two AIM2 copies differ in 19_raw_files.csv; if they
  match, the 1,048,575 row count would be an engine artifact of the same underlying file.
- If counts don't reconcile → escalate to extract producer before updating documentation.
- Induction_Emergent (2018–2020, 22,476 rows) noted as a weaker cross-check but not used as
  a primary source.

---

## Non-Missing Definition

| Option | Description | Selected |
|--------|-------------|----------|
| PRECEDE_STUDY_ID-based only | Count rows where ID is non-missing | |
| Any of 68 columns, reuse Program 19 SECTION 7 logic | Char: not blank, not NULL literal; Num: not . | ✓ |

**User's choice:** Any of the 68 columns, using Program 19 SECTION 7 logic exactly. Three
confirmation checks required:
1. Any-column non-missing count = 22,473
2. Last non-missing row position = 22,473 (contiguity — distinguishes trailing padding from
   scattered blanks)
3. PRECEDE_STUDY_ID non-missing count = 22,473 (secondary agreement check)

**Notes:** If all three pass, the "truncation" finding is reclassified as "trailing padding"
and md8's true N is settled at 22,473.

---

## Claude's Discretion

- Which program currently imports md8 (planner confirms from codebase — likely 08)
- Exact columns for qc/27_md8_count.csv
- Implementation of the contiguity check (_N_ vs. PROC SQL rownum)
- Decision number PCM-D-31 (next after PCM-D-30)

## Deferred Ideas

None.
