---
phase: 22
slug: pipeline-green-hardening
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-24
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual + PowerShell script (no unit test framework — SAS pipeline) |
| **Config file** | `qc/22_pipeline_scan.ps1` (Wave 1 creates this) |
| **Quick run command** | `powershell -File qc/22_pipeline_scan.ps1` |
| **Full suite command** | `powershell -File qc/22_pipeline_scan.ps1` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Verify file changes match acceptance criteria (grep/read)
- **After every plan wave:** Run `powershell -File qc/22_pipeline_scan.ps1` (after pipeline run)
- **Before `/gsd:verify-work`:** Human pipeline run completed + scan passes
- **Max feedback latency:** 30 seconds for code tasks; pipeline run is human-gated

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| RUN-02 | 01 | 1 | RUN-02 | grep | `grep -c "findstr /b /c" run_pipeline.cmd` | ✅ | ⬜ pending |
| RUN-03 | 01 | 1 | RUN-03 | grep | `grep -c "config.local.cmd" run_pipeline.cmd` | ✅ | ⬜ pending |
| INV-07 | 02 | 1 | INV-07 | file-exists | `test -f sas/19b_raw_inventory_xlsx.sas` | ❌ W0 | ⬜ pending |
| Scan script | 01 | 1 | D-11 | file-exists | `test -f qc/22_pipeline_scan.ps1` | ❌ W0 | ⬜ pending |
| DOC-05 | 03 | 2 | DOC-05 | grep | `grep -l "PCM-T-14" PROJECT.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `sas/19b_raw_inventory_xlsx.sas` — stub (created in Wave 1, not Wave 0; no test framework to scaffold)
- [ ] `qc/22_pipeline_scan.ps1` — log-scan script (Wave 1 deliverable)

*Existing infrastructure (run_pipeline.cmd, sas/) covers structural patterns. No test framework needed — validation is via grep, file-exists, and human pipeline run.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full pipeline exits clean | D-14 | Requires P: drive access; Claude Code cannot execute against P: drive | Run `run_pipeline.cmd`; confirm exit 0 and no ERROR lines in logs |
| 10b reports 0 warnings in runner | RUN-02 | Requires actual pipeline run | Check runner output: "10b: N warnings" should show 0 after RUN-02 fix |
| `SAS_EXE` override works on second machine | RUN-03 | Second machine test | Copy repo, set `config.local.cmd`, run pipeline; confirm correct SAS exe used |
| `qc/19_raw_inventory.xlsx` KEY sheet leftmost | INV-07 | Excel sheet order is visual | Open file; KEY tab must be first (leftmost) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s for code tasks
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
