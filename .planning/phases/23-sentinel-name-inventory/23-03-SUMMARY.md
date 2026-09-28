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
  - "PCM-D-25 RESOLVED 2026-09-28: companion-column (reason-preservation) question; no companion columns in v2.1; Declined/Refused/Not applicable become MISSING per sentinel_decisions.csv"
  - "PCM-D-27 RESOLVED 2026-09-28: column-scope (demographic + count/score lists for AMBIGUOUS treatment); Gerard, 2026-09-28; renumbered from planning-artifact D-25 to avoid conflict with REQUIREMENTS.md"
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

**PCM-D-25 -- Declined/Refused Companion-Column Reason Preservation: RESOLVED**
- Decision: No companion reason column in v2.1; values become MISSING per sentinel_decisions.csv
- Gerard, 2026-09-28
- Conflict with CONTEXT.md planning ID now resolved: column-scope question reassigned PCM-D-27

**PCM-D-27 -- Ambiguous-Value Column Scope: RESOLVED**
- Decision: Two hardcoded lists (demographic + score/count) confirmed at Phase 23 checkpoint
- Gerard, 2026-09-28; renumbered from PCM-D-25 as used in Phase 23 planning artifacts
- Lists hardcoded in sas/23_pcnr_inventory.sas header (%let demog_cols, %let score_cols)

---

## D-Number Reconciliation Results

| ID | DECISIONS.md (before) | REQUIREMENTS.md | CONTEXT.md | Verdict |
|----|----------------------|-----------------|------------|---------|
| PCM-D-21 | Absent | Same question (which values -> MISSING) | Sentinel seed + rules | Same question, different wording -- WRITTEN |
| PCM-D-22 | Absent | Same question (prefix scope / key columns) | KEY columns unprefixed | Same question, different wording -- WRITTEN |
| PCM-D-23 | Absent | Same question (shortening rule) | h_-strip + truncation | Same question, different wording -- WRITTEN |
| PCM-D-24 | Absent | Same question (numeric sentinels in scope) | Numeric approval gate | Same question, different wording -- WRITTEN |
| PCM-D-25 | Written | Companion-column question (Declined/Refused) | (planning artifact; D-25=companion per REQUIREMENTS.md) | RESOLVED 2026-09-28; Gerard |
| PCM-D-27 | Written | N/A (new ID) | Column scope (demog + score lists) | RESOLVED 2026-09-28; Gerard; renumbered from planning D-25 |

---

## Deviations from Plan

### PCM-D-25 / PCM-D-27 Conflict Resolved (2026-09-28 -- Gerard)

Option B selected: PCM-D-25 = companion-column question (REQUIREMENTS.md meaning, now RESOLVED
as "no companion columns in v2.1"); PCM-D-27 = column-scope question (hardcoded demographic +
score/count lists, RESOLVED and in effect in program 23).

PCM-D-26 was already taken (program 17 input redirect in REQUIREMENTS.md), so column-scope
was assigned PCM-D-27. DECISIONS.md conflict placeholder replaced with two proper entries.
Phase 23 planning artifacts (CONTEXT.md, RESEARCH.md, 23-01-PLAN.md) updated to reference
PCM-D-27 for column scope. REQUIREMENTS.md and STATE.md retain PCM-D-25 = companion-column.

**Impact on Phase 24:** No block. Column-scope behavior (AMBIGUOUS for demographic UNKNOWN
and score 0) was already implemented in program 23. Both IDs are now attributed in DECISIONS.md.

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
