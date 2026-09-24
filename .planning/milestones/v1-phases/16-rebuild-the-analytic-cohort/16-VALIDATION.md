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
| **Config file** | sas/00_config.sas (paths only; assertions live inside 16b_cohort_rebuild.sas) |
| **Quick run command** | `%include "C:\Master_Renamed_same_format_accross\sas\16b_cohort_rebuild.sas";` in a fresh SAS session |
| **Full suite command** | Same as quick run. Per D-04, 16b is NOT registered in 99_run_all.sas (Phase 8's job), so 99_run_all cannot exercise this phase. |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run 16b_cohort_rebuild.sas in a fresh session and confirm 0 lines matching `^ERROR` in the P: log
- **After every plan wave:** Inspect 16b_cohort_missingness.txt for admitted_n, cohort_cols, bmi_rationale_asserted=PASS, and the measured baselines
- **Before `/gsd:verify-work`:** Standalone 16b run completes with 0 ERRORs, all four assertions pass (3 full-file + BMI rationale), harmonized confirmed unmodified. (99_run_all coverage is deferred to Phase 8.)
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | HARM-10 | log-check | `grep -c "^ERROR" "<logs_path>\16b_cohort_rebuild.log"` returns 0 (log is on P:, not in sas/) | ❌ W0 | ⬜ pending |
| 16-01-02 | 01 | 1 | HARM-10 | row-count | QC file: admitted_n=13890 and admitted_n_matches_reference=YES | ❌ W0 | ⬜ pending |
| 16-01-03 | 01 | 1 | HARM-10 | col-check | QC file: cohort_cols=174; all 12 h_within_cohort_* lines present | ❌ W0 | ⬜ pending |
| 16-01-04 | 01 | 1 | PCM-D-05 | assertion | QC file: bmi_rationale_asserted=PASS; three *_n_harmonized lines equal 12726/20540/23311 | ❌ W0 | ⬜ pending |
| 16-01-05 | 01 | 1 | HARM-10 | ordering | `grep -n "gate_on_status\|data g.analytic_cohort" sas/16b_cohort_rebuild.sas` -- gate call precedes promote | ❌ W0 | ⬜ pending |
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
| PCM-D-05 attribution (Price's status) | PCM-D-05 | Requires human knowledge of who was consulted | Gerard answers the Plan 02 blocking checkpoint (consulted / informed) before Task 1 writes DECISIONS.md |
| PCM-D-05 entry prose | PCM-D-05 | Rationale wording (BMI forces restriction; PCM-F-12 void; population shift, not missingness filter) needs a human read | Read the DECISIONS.md entry; the five figures and 13,890 are covered by Plan 02 automated greps. (No methods section exists in Phase 16 -- that is a downstream manuscript concern.) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
