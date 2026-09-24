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
| **Config file** | `scan_pipeline_logs.ps1` (repo root; Wave 1 creates this) |
| **Quick run command** | `powershell -ExecutionPolicy Bypass -File scan_pipeline_logs.ps1` |
| **Full suite command** | `powershell -ExecutionPolicy Bypass -File scan_pipeline_logs.ps1` |
| **Estimated runtime** | ~5 seconds |

*Note: the scanner lives at the repo root as `scan_pipeline_logs.ps1`. It is NOT under `qc/` — that tree is on the P: drive and is never committed. Its output (`22_pipeline_scan.txt`) is written to the P: `qc\` directory.*

---

## Sampling Rate

- **After every task commit:** Verify file changes match acceptance criteria (grep/read)
- **After every plan wave:** Run `powershell -ExecutionPolicy Bypass -File scan_pipeline_logs.ps1` (after pipeline run)
- **Before `/gsd:verify-work`:** Human pipeline run completed + scan passes
- **Max feedback latency:** 30 seconds for code tasks; pipeline run is human-gated

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| RUN-02 | 01 | 1 | RUN-02 | grep | `grep -c 'findstr /b /c:"WARNING"' run_pipeline.cmd` | ✅ | ⬜ pending |
| RUN-03 | 01 | 1 | RUN-03 | grep | `grep -c "config.local.cmd" run_pipeline.cmd` | ✅ | ⬜ pending |
| INV-07 | 02 | 1 | INV-07 | grep | `grep -n "sheet_name='" sas/19_raw_dir_inventory.sas` (FAMILIES second) | ✅ | ⬜ pending |
| Scan script | 01 | 1 | D-11 | file-exists | `test -f scan_pipeline_logs.ps1` | ❌ W1 | ⬜ pending |
| DOC-05 | 03 | 2 | DOC-05 | grep | `grep -l "PCM-T-14" .planning/PROJECT.md` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `scan_pipeline_logs.ps1` — log-scan script at repo root (Wave 1 deliverable)
- [ ] `sas/19_raw_dir_inventory.sas` SECTION 13 reorder (Wave 1; existing file, edited in place)

*Existing infrastructure (run_pipeline.cmd, sas/) covers structural patterns. No test framework needed — validation is via grep, file-exists, and human pipeline run. Note: no 19b program is created — INV-07 is delivered by reordering program 19 SECTION 13.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full pipeline exits clean | D-14 | Requires P: drive access; Claude Code cannot execute against P: drive | Run `run_pipeline.cmd`; confirm exit 0 and no ERROR lines in logs |
| RUN-03 override guard stops on bogus path | RUN-03 | Requires running the batch driver | Set `config.local.cmd` to a bogus SAS_EXE; run `run_pipeline.cmd`; confirm it prints `SAS_EXE not found` and stops before launching SAS |
| 10b reports 0 warnings in runner | RUN-02 | Requires actual pipeline run | Check runner output: "10b: N warnings" should show 0 after RUN-02 fix |
| `qc/19_raw_inventory.xlsx` sheet order | INV-07 | Excel sheet order is visual | Open file; tabs must read KEY (leftmost), FAMILIES (second), then data sheets |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s for code tasks
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
