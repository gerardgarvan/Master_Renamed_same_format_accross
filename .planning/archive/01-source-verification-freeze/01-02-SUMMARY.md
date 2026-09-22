---
phase: 01-source-verification-freeze
plan: "02"
subsystem: source-verification
tags: [SAS, assertions, freeze, SRC-05, SRC-01, SRC-02, PCM-F-01, PCM-F-02]
dependency_graph:
  requires: ["01-01"]
  provides: ["SRC-05", "SRC-01/PCM-F-01", "SRC-02/PCM-F-02"]
  affects: ["Phase 4 merge safety — blank keys, duplicates, orphan IDs all aborted before mutation"]
tech_stack:
  added: []
  patterns:
    - "PROC SQL COUNT(*) into :macvar trimmed — explicit counting, never &SQLOBS"
    - "%abort cancel with labeled %put ERROR — abort names requirement and source"
    - "Anti-join via NOT IN subselect with UNION ALL across non-spine sources"
key_files:
  modified:
    - sas/01_verify_sources.sas
decisions:
  - "SRC-05 runs before SRC-01: a blank key is 'unique' when it occurs once and survives uniqueness; must be caught first"
  - "&SQLOBS not used anywhere — CREATE TABLE AS SELECT behavior is version- and context-dependent; all counts use explicit SELECT COUNT(*)"
  - "SRC-02 anti-join covers md1,md2,md4-md8 only — md3 is the spine, self-check would be meaningless"
  - "Offender tables retained in WORK (work._dups_*, work._not_in_md3) for diagnosis on failure"
metrics:
  duration: ~5 minutes
  completed: "2026-08-25"
  tasks_completed: 3
  files_modified: 1
---

# Phase 01 Plan 02: Structural Assertion Blocks Summary

**One-liner:** Three ordered abort-on-violation SAS macros (blank key, duplicate key, orphan ID anti-join) appended to `01_verify_sources.sas` as freeze guarantees for the Phase 4 md3-spine merge.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SRC-05 — blank key assertion | 2ce3866 | sas/01_verify_sources.sas |
| 2 | SRC-01/PCM-F-01 — uniqueness assertion | 2ce3866 | sas/01_verify_sources.sas |
| 3 | SRC-02/PCM-F-02 — md3 superset anti-join | 2ce3866 | sas/01_verify_sources.sas |

All three tasks committed atomically in a single file change (all appended in one edit pass in dependency order).

---

## What Was Built

Appended to `sas/01_verify_sources.sas` below the plan-02 marker, in this exact order:

**SRC-05 block** (`assert_no_blank_id` macro, called 8 times):
- Uses `sum(missing(PRECEDE_STUDY_ID))` counted into `:n_blank trimmed`
- Aborts with labeled ERROR naming the dataset and explaining the Phase 4 risk
- Runs before SRC-01 to prevent a blank from masquerading as a uniqueness problem

**SRC-01/PCM-F-01 block** (`assert_unique_id` macro, called 8 times):
- Creates `work._dups_<ds>` via `GROUP BY ... HAVING count(*) > 1` for diagnosis
- Counts offenders explicitly: `select count(*) into :n_dups trimmed from work._dups_<ds>`
- Aborts with labeled ERROR naming the dataset and duplicate count

**SRC-02/PCM-F-02 block** (inline PROC SQL with UNION ALL anti-join):
- Builds `work._not_in_md3` unioning orphan IDs from md1, md2, md4, md5, md6, md7, md8
- Counts result: `select count(*) into :n_orphan trimmed from work._not_in_md3`
- Aborts with labeled ERROR; clean data produces a PCM-F-02 OK note
- Closes with `libname src clear;`

---

## Acceptance Criteria Verification

| Criterion | Result |
|-----------|--------|
| `sum(missing(PRECEDE_STUDY_ID))` present | PASS (1 occurrence) |
| `SRC-05 VIOLATION` present | PASS |
| `%abort cancel` in assert_no_blank_id body | PASS |
| 8 `%assert_no_blank_id(ds=master_data_` invocations | PASS |
| `having count(*) > 1` present | PASS |
| `select count(*) into :n_dups trimmed` present | PASS |
| `PCM-F-01 VIOLATION` present | PASS |
| `%abort cancel` in assert_unique_id body | PASS |
| 8 `%assert_unique_id(ds=master_data_` invocations | PASS |
| `PCM-F-02 VIOLATION` present | PASS |
| 7 `not in (select PRECEDE_STUDY_ID from src.master_data_3)` occurrences | PASS |
| `select count(*) into :n_orphan trimmed` present | PASS |
| `&SQLOBS` absent from entire file | PASS (0 occurrences) |
| No bare `%abort;` | PASS (0 occurrences) |
| No `ENDSAS` | PASS (0 occurrences) |
| Block order: SRC-05 before SRC-01 before SRC-02 | PASS |

---

## Deviations from Plan

None — plan executed exactly as written. All three tasks appended in a single edit in dependency order; each acceptance criterion verified by grep.

---

## Known Stubs

None — all assertion logic is fully wired. Runtime verification (clean data yields OK notes; injected violations abort) is gated on Wave 0 (P: drive + SAS session availability) per plan frontmatter.

---

## Self-Check: PASSED

- `sas/01_verify_sources.sas` — FOUND
- Commit 2ce3866 — FOUND (`git log --oneline -1` confirms)
