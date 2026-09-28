---
phase: 23-sentinel-name-inventory
plan: "03"
subsystem: decisions-capture
tags: [decisions, pcnr, sentinel, name-map, d-number-reconciliation]
dependency_graph:
  requires: [23-01, 23-02, human-verify-checkpoint-Task1, human-action-checkpoint-Task2]
  provides: [PCM-D-21, PCM-D-22, PCM-D-23, PCM-D-24, PCM-T-16 in docs/DECISIONS.md]
  affects: [Phase 24 (gate check reads sentinel_decisions.csv + pcnr_name_map.csv after PCNR_APPROVED flip)]
tech_stack:
  added: []
  patterns: ["D-number reconciliation before writing", "conflict-surface-not-write rule"]
key_files:
  created: []
  modified:
    - docs/DECISIONS.md
decisions:
  - "PCM-D-21 sentinel seed list and matching rules resolved; Gerard, 2026-09-28"
  - "PCM-D-22 KEY columns (pecan_ID, PRECEDE_STUDY_ID, ENCRYPTED_MRN, ENCRYPTED_ENCOUNTER) stay unprefixed; Gerard, 2026-09-28"
  - "PCM-D-23 h_-strip + middle-truncate algorithm with 10-name table confirmed; Gerard, 2026-09-28"
  - "PCM-D-24 numeric gate defaults to KEEP; no approvals at checkpoint; Gerard, 2026-09-28"
  - "PCM-T-16 trap added: never PROC IMPORT a gate file -- use DATA step infile with explicit $ informats"
  - "PCM-D-25 CONFLICT SURFACED: REQUIREMENTS.md+STATE.md assign to companion-column question; CONTEXT.md assigns to column-scope question; entry intentionally not written; human resolution required before Phase 24"
metrics:
  duration: "~10 minutes"
  completed: "2026-09-28"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 1
---

# Phase 23 Plan 03: D-Number Reconciliation and DECISIONS.md Update Summary

PCM-D-21 through PCM-D-24 and PCM-T-16 appended to docs/DECISIONS.md with Gerard as decided_by (2026-09-28); PCM-D-25 conflict surfaced and intentionally left unwritten pending human resolution.

---

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 3 | Reconcile D-numbers; record PCM-D-21..24 and PCM-T-16 in DECISIONS.md | fcf4f97 | docs/DECISIONS.md |

(Tasks 1 and 2 were completed in prior sessions: Task 1 checkpoint passed 2026-09-28; Task 2 commit b12d4e2 docs/sentinel_decisions.csv + docs/pcnr_name_map.csv git-tracked.)

---

## What Was Built

### docs/DECISIONS.md (modified -- 182 lines appended)

**PCM-D-21 -- Sentinel Seed List and Matching Rules: RESOLVED**
- Exact-match seed list (14 AUTO values after normalize: upcase, strip, compbl)
- Whitespace-only normalized tokens: <TAB>, <CRLF>, <NBSP>
- Contains-match -> REVIEW only; exact-match-only for AUTO
- Hex-key basis: (variable, raw_hex) via %hexkey macro from 00_config.sas
- Numeric candidates always REVIEW; numeric 0 in score_cols always AMBIGUOUS
- Attribution: Gerard, 2026-09-28

**PCM-D-22 -- Key Columns That Stay Unprefixed: RESOLVED**
- Four KEY columns: pecan_ID, PRECEDE_STUDY_ID, ENCRYPTED_MRN, ENCRYPTED_ENCOUNTER
- All remaining non-DROP columns receive pcnr_ prefix
- REQUIREMENTS.md wording reconciled (same question, different angle -- consistent)
- Attribution: Gerard, 2026-09-28

**PCM-D-23 -- pcnr_ Name Construction: h_ Stripping and Truncation Algorithm: RESOLVED**
- Rule A: h_ prefix stripped for KEEP-role h_ columns; raw column -> DROP
- Rule B: middle-truncate with final-token preservation; trailing _ stripped from head
  to avoid double-underscore; fallback to plain tail truncation when final_token empty
  or > 12 chars
- 10-name truncation table cited as confirmed at Task 1 checkpoint
- REQUIREMENTS.md wording reconciled (deterministic algorithm = same intent)
- Attribution: Gerard, 2026-09-28

**PCM-D-24 -- Numeric Sentinel Approval Gate: RESOLVED**
- Default: KEEP for all numeric candidates; no recode without per-variable approval
- No numeric wildcards (var_type = num rows cannot use variable = *)
- At checkpoint: Gerard confirmed no numeric candidate approved for MISSING
- REQUIREMENTS.md wording reconciled (consistent)
- Note on attribution: REQUIREMENTS.md flags analytic-facing decisions for Price; this
  entry records the default KEEP position which requires no analytic judgment; future
  per-variable MISSING approvals would be per the checkpoint process
- Attribution: Gerard, 2026-09-28

**PCM-T-16 -- Never PROC IMPORT a Gate File**
- Rule: use DATA step infile with explicit $ informats; PROC IMPORT mis-types hex strings
  (30, 39, 09) as integers, breaking key lookups
- Added alongside PCM-T-14 and PCM-T-15

**PCM-D-25 -- Conflict placeholder written in DECISIONS.md (not a decision entry)**
- REQUIREMENTS.md + STATE.md: PCM-D-25 = "Preserve reason when Declined/Refused/Not
  applicable set to missing?" (companion-column question)
- CONTEXT.md: PCM-D-25 = "Ambiguous-value column scope -- hardcoded demographic +
  count/score column lists"
- Per plan conflict rule: entry NOT written; conflict documented with three resolution options
- Column-scope behavior IS in effect in program 23 as implemented; it just lacks an
  attributed DECISIONS.md entry until the ID is resolved

---

## D-Number Reconciliation Results

| ID | DECISIONS.md (before) | REQUIREMENTS.md | CONTEXT.md | Verdict |
|----|----------------------|-----------------|------------|---------|
| PCM-D-21 | Absent | Same question (which values -> MISSING) | Sentinel seed + rules | Same question, different wording -- WRITTEN |
| PCM-D-22 | Absent | Same question (prefix scope / key columns) | KEY columns unprefixed | Same question, different wording -- WRITTEN |
| PCM-D-23 | Absent | Same question (shortening rule) | h_-strip + truncation | Same question, different wording -- WRITTEN |
| PCM-D-24 | Absent | Same question (numeric sentinels in scope) | Numeric approval gate | Same question, different wording -- WRITTEN |
| PCM-D-25 | Absent | Companion-column question (Declined/Refused) | Column scope (demog + score lists) | DIFFERENT QUESTION -- NOT WRITTEN; conflict surfaced |

---

## Deviations from Plan

### PCM-D-25 Not Written (Plan Rule Applied -- Not a Deviation)

The plan explicitly states: "DIFFERENT question under the same ID -> STOP and surface the
conflict for human resolution; do not write either entry."

PCM-D-25 in REQUIREMENTS.md and STATE.md is the companion-column (reason-preservation)
question. PCM-D-25 in CONTEXT.md is the ambiguous-value column-scope question. These are
different questions. Per the plan's conflict rule, no PCM-D-25 entry was written.

A placeholder section was added to DECISIONS.md with the conflict documented and three
resolution options provided for human review.

**Impact on Phase 24:** Phase 24 reads docs/sentinel_decisions.csv and docs/pcnr_name_map.csv.
The column-scope behavior (AMBIGUOUS for demographic UNKNOWN and score 0) is implemented in
program 23 and present in the candidates CSV. The absence of a DECISIONS.md entry for the
column-scope decision does not block Phase 24 execution, but the PCM-D-25 ID conflict should
be resolved before PCNR_APPROVED is flipped to 1.

---

## Known Stubs

None -- docs/sentinel_decisions.csv and docs/pcnr_name_map.csv are human-owned and
git-tracked (commit b12d4e2 from Task 2). PCNR_APPROVED remains 0 pending Phase 24.

---

## Self-Check: PASSED

- docs/DECISIONS.md: FOUND
- Commit fcf4f97: FOUND (feat(23-03): record PCM-D-21..24 + PCM-T-16)
- PCM-D-21 heading in DECISIONS.md: FOUND (line 661)
- PCM-D-22 heading in DECISIONS.md: FOUND (line 695)
- PCM-D-23 heading in DECISIONS.md: FOUND (line 717)
- PCM-D-24 heading in DECISIONS.md: FOUND (line 755)
- PCM-T-16 heading in DECISIONS.md: FOUND (line 818)
- PCNR_APPROVED = 0 in sas/00_config.sas: FOUND (line 40)
- PCNR_APPROVED = 1 in sas/00_config.sas: NOT FOUND (correct -- not flipped)
- PCNR-05 ticked in REQUIREMENTS.md: FOUND (already ticked before this plan)
- PCNR-06 ticked in REQUIREMENTS.md: FOUND (already ticked before this plan)
