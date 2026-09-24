# Phase 19: Raw Directory Inventory — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-23
**Phase:** 19-raw-directory-inventory
**Areas discussed:** raw\master scope, wide-file variable profiling

---

## SHA-256 mechanism (not discussed interactively — recommended approach accepted)

| Option | Description | Selected |
|--------|-------------|----------|
| certutil via FILENAME PIPE | Windows native, returns parseable output, handles any file type | ✓ |
| SAS sha256hex() | SAS 9.4M8 function works on strings not files — would require file-read loop | |

**User's choice:** certutil via FILENAME PIPE (recommended default)
**Notes:** Paths must be double-quoted for spaces. XCMD must be enabled — document in program header. This dependency is shared with RUN-01 (Phase 21).

---

## raw\master scope

| Option | Description | Selected |
|--------|-------------|----------|
| Just enumerate — no assertion | List what's on disk; new files appear as NEW | |
| Assert expected count | Abort if count differs from expected | |
| Per-file presence check on named expected files | Abort only if a known extract is absent or renamed; extra files appear as NEW | ✓ |

**User's choice:** Per-file presence check (neither listed option — user identified a third approach)
**Notes:**
- raw\master contains the original extracts (CSVs + one XLSX), not master_data_*.sas7bdat (those live in Master_Renamed_same_format_accross)
- Phase 1 checksums are of different files; no reuse — fresh checksum for everything under raw
- md3 source CSV matters most: PID-01 (Phase 20) depends on its checksum in the INV-01 record
- INV-01 covers only raw; Master_Renamed_same_format_accross is out of scope

---

## Wide-file variable profiling

| Option | Description | Selected |
|--------|-------------|----------|
| Every column individually | Full INV-03 compliance; 40,000+ rows in VARIABLES | ✓ |
| Family rollups for wide families | Summary only; fails INV-03 as written | |

**User's choice:** Every column individually, plus FAMILIES sheet as addition (not replacement)
**Notes:**
- Add FAMILIES sheet with DATALINES-defined prefix lookup (like concept_decisions.csv pattern)
- Columns matching no prefix go in "unassigned" row per file
- Assert FAMILIES column counts sum to VARIABLES row count per file (%abort cancel if diverge)
- Report min, median, max % missing per family (not just median — hides empty blocks)
- Compute missingness in one pass per file: PROC MEANS NMISS for numerics, single DATA step for char
- INV-07 must be updated to include FAMILIES sheet before planning locks

---

## Excel output approach (not discussed interactively — recommended approach accepted)

| Option | Description | Selected |
|--------|-------------|----------|
| ODS Excel | Established in Phase 17; UF colors; sheet_name= controls order; write KEY first | ✓ |
| XLSX libname engine | Simpler DATA step writes; less formatting control | |

**User's choice:** ODS Excel (recommended default)
**Notes:** If ODS Excel is slow on 40,000-row VARIABLES sheet, fall back to XLSX libname for VARIABLES data only — targeted fallback, not full redesign.

---

## Claude's Discretion

- Directory traversal implementation (PIPE/dir command parsing)
- Macro structure for import and checksum loops
- Whether SHA-256 PIPE call is wrapped in a macro or open-coded
- Report ordering within sheets
- SAS7BDAT handling if found under raw

## Deferred Ideas

- Runner wiring (99_run_all.sas) — Phase 21
- r7/r8 2022 gap-fill joins — gated on PCM-D-16 (Phase 20)
- PCM-D-15 extension wiring — v2.1
