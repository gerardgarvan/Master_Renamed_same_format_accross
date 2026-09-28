---
phase: 23
slug: sentinel-name-inventory
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-28
---

# Phase 23 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4 — ODS CSV + PROC PRINT output file checks |
| **Config file** | none — outputs are file-based CSV/log checks |
| **Quick run command** | `dir qc\23_sentinel_candidates.csv` |
| **Full suite command** | `sas sas/23_pcnr_inventory.sas` + check all four output files exist |
| **Estimated runtime** | ~30–120 seconds (depends on `g.master_data_harmonized` size) |

---

## Sampling Rate

- **After every task commit:** Verify target output file exists and has expected row structure
- **After every plan wave:** Run full SAS program; check all CSV/log outputs
- **Before `/gsd:verify-work`:** All four output files present + `PCNR_APPROVED=1` in `sentinel_decisions.csv`
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 23-01-01 | 01 | 1 | Sentinel char scan | file-check | `dir qc\23_sentinel_candidates.csv` | ❌ W0 | ⬜ pending |
| 23-01-02 | 01 | 1 | Numeric sentinel scan | file-check | `dir qc\23_ambiguous_values.csv` | ❌ W0 | ⬜ pending |
| 23-01-03 | 01 | 2 | Name map complete | file-check | `dir docs\pcnr_name_map.csv` | ❌ W0 | ⬜ pending |
| 23-01-04 | 01 | 2 | Decision table | file-check | `dir docs\sentinel_decisions.csv` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- No new test framework needed — SAS program outputs are verified by file existence and row-count checks via `dir` / `proc contents` in QC log.

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Human review of sentinel_candidates.csv | PCM-D-21..D-25 resolution | Requires human judgement on placeholder values | Gerard opens `qc/23_sentinel_candidates.csv`, reviews each row, marks decision in `docs/sentinel_decisions.csv` |
| PCM-D-25 demographic column list approval | Numeric sentinel columns | Price must approve column list | Share `qc/23_ambiguous_values.csv` with Price; receive sign-off before phase 24 |
| Name truncation review | PCM-D-23 | 10 names hit 32-char limit; human picks truncation pattern | Gerard reviews `docs/pcnr_name_map.csv` truncated entries against worked example |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
