# Phase 24: Build g.pcnr_harmonized - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-28
**Phase:** 24-build-g-pcnr-harmonized
**Areas discussed:** Recode loop structure, Full-comparison assertion, Column rename approach, Recode counts CSV format

---

## Recode Loop Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Macro-indexed loop (10b pattern) | Load rules into indexed macro variables; loop generates `if` statements inside DATA step | |
| Code generation + %include | Resolve rules into explicit table; write `qc/24_recode_rules_generated.sas`; `%include` inside single DATA step | ✓ |
| Infile-driven DATA step logic | Read decisions CSV inside the recode DATA step and apply rules dynamically | |

**User's choice:** Code generation — write `qc/24_recode_rules_generated.sas`, `%include` it inside one DATA step.

**Notes:** User specified the exact structure: `select (%hexkey(col)); when ('hex') call missing(col); otherwise; end;` blocks per character column; direct `if var = value` for numerics. Motivated by: matches gate's hex keys byte-for-byte, one pass, readable audit trail, avoids open-code `%if` traps that `%emit_rules` invites (PCM-T-15). Wildcard rows expanded into per-variable explicit rules before code generation; generated file is not a full program (no `options`, no `run;`).

---

## Full-Comparison Assertion

| Option | Description | Selected |
|--------|-------------|----------|
| PROC COMPARE | Standard SAS comparison tool; reports differing cells | |
| Two-SET parallel DATA step | Read source and recoded in parallel by row position; check each cell; verify each difference is authorized | ✓ |
| Sample-based check | Compare a random sample of rows for performance | |

**User's choice:** Two-SET DATA step with cell-by-cell authorization check.

**Notes:** User explained PROC COMPARE only reports differences — it cannot verify each difference was authorized. The parallel-set approach reads both datasets by position (requires equal row counts, which PCNR-11 asserts), uses separate character and numeric arrays (SAS 9.4 constraint), and outputs one row per authorized change. Authorized = recoded cell is missing AND source hex key is in MISSING rule set for that column. Two cross-checks added: (1) comparison count equals recode-step count; (2) per-rule count equals `n_rows` from candidates CSV (source-drift check beyond fingerprint).

---

## Column Rename Approach

| Option | Description | Selected |
|--------|-------------|----------|
| RENAME= in final DATA step | Generate rename list from name map; apply in DATA step that also handles drop and labels | ✓ |
| PROC DATASETS MODIFY | In-place rename without DATA step | |
| Rename during recode step | Apply pcnr_ names at recode time | |

**User's choice:** Separate final DATA step after comparison passes; rename, drop (DROP-role columns), and labels in one step.

**Notes:** Keeping rename last makes the comparison step straightforward — source and recoded share the same column names. User confirmed: KEY columns stay unprefixed; each renamed column gets its original name as its label for traceability; assert variable set after rename equals KEY names + KEEP final_names exactly. PROC DATASETS MODIFY not used — DATA step does everything in one place.

---

## Recode Counts CSV Format

| Option | Description | Selected |
|--------|-------------|----------|
| Single CSV with TOTAL rows | Detail + totals in one file; TOTAL sentinel in raw_value column | |
| Two CSVs: detail + totals | `24_pcnr_recode_counts.csv` (detail) + `24_pcnr_recode_totals.csv` (per-variable) | ✓ |
| Single detail CSV only | No per-variable totals | |

**User's choice:** Two tidy CSVs with no TOTAL sentinel rows.

**Notes:** User's specific reason for rejecting TOTAL rows: "it's literally a sentinel in a file about sentinels." Detail file includes zero-hit rules (n_recoded = 0) so gaps are visible. Both files machine-readable: fixed headers, ASCII, read with DATA step `infile` + `$` informats (PCM-T-16). Totals file includes all KEEP and KEY columns with 0 for untouched ones. Phase 25 dictionary will want "n set to missing" per variable — both files designed for that consumption.

---

## Claude's Discretion

- Exact character array syntax for parallel-set comparison (planner confirms working SAS 9.4 pattern)
- Whether `work._recode_rules` is a SAS dataset or indexed macro variables
- Log verbosity and `%put NOTE:` section transitions
- Whether generated `.sas` omits columns with zero MISSING rules (user preference: omit — cleaner file)

## Deferred Ideas

None.
