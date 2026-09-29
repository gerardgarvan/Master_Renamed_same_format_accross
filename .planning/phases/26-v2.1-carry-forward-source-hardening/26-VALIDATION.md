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
| 26-01-01 | 01 | 1 | FIX-03 audit | manual inspect | run program 23 → qc/23_contains_audit.csv (with current_action) | ❌ W0 | ⬜ pending |
| 26-01-03 | 01 | 1 | FIX-03 narrowing | automated | run program 23 → qc/26_fix03_orphans.csv has 0 MISSING rows; AMBIG_EXACT branch present | ❌ W0 | ⬜ pending |
| 26-01-04 | 01 | 1 | FIX-03 reconcile | automated | after approved deletion, program 24 log shows gate Check 5 and Check 7 passed; MISSING row count unchanged | ❌ W0 | ⬜ pending |
| 26-02-00 | 02 | 2 | FIX-04 decisions | manual | two rows KEEP → MISSING in docs/sentinel_decisions.csv (git diff = 2 rows) | ❌ W0 | ⬜ pending |
| 26-02-01 | 02 | 2 | FIX-04 assertions | automated | run program 24 → both `QC ASSERTION OK -- FIX-04` NOTEs, PCNR-11 PASS; then program 25 clean | ❌ W0 | ⬜ pending |
| 26-03-01 | 03 | 1 | HARD seed program | manual | run seed program → baseline CSV (8 rows); re-run → `SEED ABORTED` | ❌ W0 | ⬜ pending |
| 26-03-02 | 03 | 1 | HARD hash guard | automated | run program 19 → `HARD-01 hash guard passed`, 0 ERROR lines | ❌ W0 | ⬜ pending |
| 26-03-2b | 03 | 1 | HARD ordering | automated | first `call :run_program` in run_pipeline.cmd is program 19 | ❌ W0 | ⬜ pending |
| 26-04-01 | 04 | 3 | HARD-03 docs + D-24 amendment | manual inspect | docs/DECISIONS.md has PCM-D-29 and the PCM-D-24 amendment; each heading once | ❌ W0 | ⬜ pending |

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
| Hash guard triggers on drift | HARD D-10 | Must see the guard fail once | Change ONE sha256 in docs/raw_hash_baseline.csv to a wrong 64-hex value (never edit a source extract), run program 19 → `HARD-01 HASH GUARD FAILED`; restore the value → passes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 900s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
