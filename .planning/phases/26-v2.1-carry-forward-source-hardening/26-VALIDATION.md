---
phase: 26
slug: v2-1-carry-forward-source-hardening
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-29
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4M8 — programs run via `sas.exe` subprocess; QC assertions via `%assert_eq` macro |
| **Config file** | `sas/00_config.sas` (defines `%assert_eq`, path macros) |
| **Quick run command** | `sas -sysin sas/23_pcnr_inventory.sas` (audit mode) |
| **Full suite command** | `run_pipeline.cmd` (full pipeline, programs 19→99) |
| **Estimated runtime** | ~5–15 minutes (full pipeline) |

---

## Sampling Rate

- **After every task commit:** Inspect QC output CSV / SAS log for ERROR/WARNING lines
- **After every plan wave:** Run affected program(s) and verify QC outputs
- **Before `/gsd:verify-work`:** Full pipeline must complete without `%abort cancel`
- **Max feedback latency:** 15 minutes (SAS runtime)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 26-01-01 | 01 | 1 | FIX-03 audit | manual inspect | `sas -sysin sas/23_pcnr_inventory.sas` → check qc/23_contains_audit.csv | ❌ W0 | ⬜ pending |
| 26-01-02 | 01 | 2 | FIX-03 cleanup | manual inspect | `sas -sysin sas/23_pcnr_inventory.sas` → check log for ERROR | ❌ W0 | ⬜ pending |
| 26-02-01 | 02 | 1 | FIX-04 assertions | automated | `sas -sysin sas/24_pcnr_build.sas` → 0 ERROR lines in log | ❌ W0 | ⬜ pending |
| 26-03-01 | 03 | 1 | HARD seed program | manual | run `19b_seed_hash_baseline.sas` → baseline CSV created; re-run → aborts | ❌ W0 | ⬜ pending |
| 26-03-02 | 03 | 2 | HARD hash guard | automated | `sas -sysin sas/19_raw_dir_inventory.sas` → 0 ERROR lines (hashes match) | ❌ W0 | ⬜ pending |
| 26-04-01 | 04 | 1 | HARD-03 docs | manual inspect | Read docs/DECISIONS.md → new PCM-D-XX entry exists | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- No new test framework installation needed — SAS is already available
- QC outputs inspected manually via CSV review and SAS log grep

*All phase verification is manual SAS log / CSV inspection — no automated test harness exists for this project.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| FIX-03 audit CSV accuracy | FIX-03 D-02 | Requires human domain review of fragment false-positives | Open qc/23_contains_audit.csv; verify each fragment listed matches expected semantics |
| FIX-03 cleanup correctness | FIX-03 D-03 | Requires human approval of which CONTAINS rules to drop | Review narrowed CONTAINS block; compare removed rows to audit findings |
| 19b refuses to overwrite baseline | HARD D-09 | Interactive test — run 19b twice, confirm abort on 2nd run | Run 19b → baseline created; run 19b again → SAS log shows `%abort cancel` |
| Hash guard triggers on tampered file | HARD D-10 | Requires temporarily altering a source file | Edit md1 byte, run program 19 → SAS log shows mismatch abort; restore file |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 900s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
