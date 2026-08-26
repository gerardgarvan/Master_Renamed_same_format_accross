---
phase: 4
slug: merge
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-26
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4M8 — PROC SQL assertions + %abort cancel macros (no external test runner) |
| **Config file** | none — assertions embedded in 04_merge.sas |
| **Quick run command** | Submit 04_merge.sas in SAS and verify zero ERRORs in log |
| **Full suite command** | Submit 04_merge.sas; inspect qc/04_merge_provenance.txt and log for assertion failures |
| **Estimated runtime** | ~30–60 seconds |

---

## Sampling Rate

- **After every task commit:** Check SAS log for ERROR/WARNING lines: `grep -i "ERROR\|WARNING" logs/04_merge.log`
- **After every plan wave:** Run full 04_merge.sas; verify qc/ artifacts exist
- **Before `/gsd:verify-work`:** Full run must be clean; all qc/ provenance artifacts present
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | MRG-01, MRG-04 | macro assertion | `%assert_row_count(g.master_data_merged, 41150)` in 04_merge.sas | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | MRG-02 | macro assertion | `%assert_no_blank_key(g.master_data_merged)` in 04_merge.sas | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | MRG-03 | qc artifact | `qc/04_merge_provenance.txt` present + row counts match src_counts | ❌ W0 | ⬜ pending |
| 04-01-04 | 01 | 1 | MRG-04 | log check | grep -c "ERROR" logs/04_merge.log = 0 | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `sas/04_merge.sas` — program stub with libname block, %macro wrappers for assertions
- [ ] `qc/` directory confirmed writable
- [ ] `logs/` directory confirmed writable

*Existing assertion macro patterns from Phases 1–3 cover all requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Ownership assignment for 135 CONFLICT variables is correct | MRG-04 | Requires human review of qc/02_ownership_map.txt against 04_merge.sas assignments | Compare each CONFLICT variable's IF-THEN assignment in 04_merge.sas against the owner column in qc/02_ownership_map.txt |
| No last-wins overwrite possible for any variable | MRG-04 | Structural review — no automated check can prove absence | Code review: every variable in the DATA step has either (a) unique source, (b) explicit owner assignment, or (c) is PRECEDE_STUDY_ID |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
