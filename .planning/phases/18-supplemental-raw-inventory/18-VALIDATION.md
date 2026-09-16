---
phase: 18
slug: supplemental-raw-inventory
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-16
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS log inspection + file-existence checks (no automated test runner) |
| **Config file** | sas/00_config.sas |
| **Quick run command** | `grep -i "ERROR\|ABORT" logs/18_supplemental_raw_gap.log` |
| **Full suite command** | Manual SAS run + grep checks on qc/ outputs |
| **Estimated runtime** | ~5-15 minutes (SAS session) |

---

## Sampling Rate

- **After every task commit:** Verify no SAS ERROR/ABORT in log excerpt, file written
- **After every plan wave:** Full grep check on all qc/18_*.txt outputs
- **Before `/gsd:verify-work`:** All outputs present, D15_APPROVED gate in place
- **Max feedback latency:** Manual SAS run only — no continuous runner

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-01 | 01 | 0 | raw_path in 00_config.sas | grep | `grep "raw_path" sas/00_config.sas` | ✅ W0 creates | ⬜ pending |
| 18-01-02 | 01 | 1 | qc/18_id_diagnostic.txt written | file | `test -f qc/18_id_diagnostic.txt` | ✅ runtime | ⬜ pending |
| 18-01-03 | 01 | 2 | qc/18_gap_candidates.txt written | file | `test -f qc/18_gap_candidates.txt` | ✅ runtime | ⬜ pending |
| 18-01-04 | 01 | 3 | D15_APPROVED gate present | grep | `grep "D15_APPROVED" sas/18_supplemental_raw_gap.sas` | ✅ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `sas/00_config.sas` — add `%let raw_path=...;` (confirm value from disk or Phase 16 log)
- [ ] Confirm `sas/16_raw_inventory.sas` exists on disk; extract `%import_csv` / `%import_xlsx` macros for reuse
- [ ] Scaffold `sas/18_supplemental_raw_gap.sas` with `%include`, `libname g`, `%assert_base`, and `%let D15_APPROVED=0` gate

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 5 base IDs vs 5 r9 IDs with lengths printed in diagnostic | PCM-D-16 | Requires SAS run and human review | Open qc/18_id_diagnostic.txt, confirm two ID lists with length values |
| Gap candidates sorted by n_fillable desc (IN_BASE) then n_raw_populated desc (NEW) | D-04 | Sort order requires visual inspection | Open qc/18_gap_candidates.txt, verify IN_BASE block sorted by n_fillable, NEW block by n_raw_populated |
| r2 dCDT/LINUS families reported as rollups | D-02 | Rollup structure not grep-verifiable | Confirm dCDT (3,341 cols) and LINUS (251 cols) appear as family summary rows in output |
| D15_APPROVED gate blocks re-run until flag set | D-03 | Behavioral — requires SAS session test | With D15_APPROVED=0, verify %abort cancel fires; set to 1, verify program completes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency manual SAS run (~10 min acceptable for SAS pipeline)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
