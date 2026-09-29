# Phase 26: v2.1 Carry-Forward & Source Hardening — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-29
**Phase:** 26-v2.1-carry-forward-source-hardening
**Areas discussed:** FIX-03 (Sentinel CONTAINS cleanup), FIX-04 (QC assertion placement and semantics), HARD (Hash baseline file design)

---

## FIX-03: Sentinel CONTAINS Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Simple drop: remove short-word fragments up front | Drop NONE/OTHER/MISSING/PENDING/N/A/UNKNOWN from CONTAINS without audit | |
| Audit-first: generate diagnostic report, decide after review | Produce qc/23_contains_audit.csv listing all (fragment × column × value × count) matches; review before narrowing | ✓ |

**User's choice:** Audit-first — two-task process with human checkpoint.

**Notes:** User specified: DECLINED/REFUSED/NOT SPECIFIED must be justified by the audit report before being kept. UNKNOWN and N/A compound forms that appear only as full-value matches should be promoted to EXACT rules (not kept in CONTAINS). Multi-word phrases (NOT DOCUMENTED, NOT RECORDED, etc.) are presumed keepers unless the audit shows false positives. Short words (NONE, OTHER, MISSING, PENDING) are presumed drops unless the audit justifies them.

---

## FIX-04: QC Assertion Placement and Semantics

### Cognitive_Score = 0

| Option | Description | Selected |
|--------|-------------|----------|
| Placeholder sentinel — assert count = 0 | 0 is not a real score; assertion fails run if any remain in g.pcnr_harmonized | ✓ |
| Valid score — count and report only | 0 is real; assertion just logs count, does not fail | |

**User's choice:** Placeholder sentinel — assert zero rows remain after sentinel handling in program 24.

### rt_RM_START_to_AN_START_mins = -9

| Option | Description | Selected |
|--------|-------------|----------|
| Assert count = 0 in pcnr output (Recommended) | -9 is a sentinel; program 24 should have set it missing; abort if any remain | ✓ |
| Count and report only | Informational only | |

**User's choice:** Assert count = 0; abort on failure. Lives in 24_pcnr_build.sas post-sentinel step.

---

## HARD: Hash Baseline File Design

Presented as a default by Claude; user accepted without modification.

| Decision | Choice |
|----------|--------|
| Baseline filename | `docs/raw_hash_baseline.csv` |
| Columns | `file_name, sha256, byte_size, seeded_date` |
| Read method | DATA step infile (PCM-T-16) |
| Seed program | `19b_seed_hash_baseline.sas` — refuses to run if baseline already exists |
| Program 19 role | Read only; never writes baseline |
| Pipeline wiring | 19b NOT in run_pipeline.cmd; manual one-time step |
| Update procedure | Delete baseline file, re-run 19b intentionally |

---

## Claude's Discretion

- Exact pcnr-prefixed variable names for assertions (confirm from pcnr_name_map.csv)
- Whether CONTAINS audit is a standalone program or an audit-mode flag inside program 23
- DECISIONS.md entry number for HARD-03 note (next available after existing entries)

## Deferred Ideas

None.
