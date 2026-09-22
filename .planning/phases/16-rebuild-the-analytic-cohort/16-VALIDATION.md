---
phase: 16
slug: rebuild-the-analytic-cohort
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-21
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4M8 — ODS log inspection + PROC COMPARE + macro %assert_complete_case_n |
| **Config file** | sas/99_run_all.sas |
| **Quick run command** | `%include "sas/16b_cohort_rebuild.sas";` |
| **Full suite command** | `%include "sas/99_run_all.sas";` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `%include "sas/16b_cohort_rebuild.sas";` and confirm 0 ERRORs in log
- **After every plan wave:** Inspect ODS output for row counts and %assert_ macro results
- **Before `/gsd:verify-work`:** Full 99_run_all.sas must complete with 0 ERRORs and correct Ns
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | HARM-10 | log-check | `grep -c "ERROR" sas/16b_cohort_rebuild.log` returns 0 | ❌ W0 | ⬜ pending |
| 16-01-02 | 01 | 1 | HARM-10 | row-count | `g.analytic_cohort` obs = 13,890 | ❌ W0 | ⬜ pending |
| 16-01-03 | 01 | 1 | HARM-10 | col-check | h_ columns present in analytic_cohort | ❌ W0 | ⬜ pending |
| 16-02-01 | 02 | 2 | PCM-D-05 | manual | DECISIONS.md entry reviewed with attribution | manual | ⬜ pending |
| 16-02-02 | 02 | 2 | PCM-D-05 | doc-check | DECISIONS.md contains racial composition shift stats | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `sas/16b_cohort_rebuild.sas` — main program stub
- [ ] Confirm existing `%assert_complete_case_n` macro is accessible from 16b program

*Existing SAS infrastructure covers most validation; Wave 0 installs the program stub.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| PCM-D-05 attribution (Price's status) | PCM-D-05 | Requires human knowledge of who was consulted | Confirm with PI before writing DECISIONS.md entry |
| Racial composition shift language in methods section | PCM-D-05 | Prose review for accuracy and generalisability framing | Read methods section, verify 79.8%→87.1% WHITE stat is present |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
