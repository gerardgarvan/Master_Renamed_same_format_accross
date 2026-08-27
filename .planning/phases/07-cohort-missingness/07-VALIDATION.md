---
phase: 7
slug: cohort-missingness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-27
revised: 2026-08-27
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Revision Notes

**R1 — QC artifact filename corrected.** This document previously referenced
`qc/07_cohort_summary.txt` in five places. Every other Phase 7 artifact
(07-RESEARCH.md, 07-01-PLAN.md, 07-02-PLAN.md) uses
`qc/07_cohort_missingness.txt`. The gate would have grepped a file that never
gets created. All references now use the correct name.

**R2 — Task map realigned to the actual plans.** The map listed three tasks under
Plan 01 across waves 1 and 2, including a DECISIONS.md check. Plan 01 is entirely
Wave 1 and now has two tasks (write, then run). The DECISIONS.md edit belongs to
Plan 02, Wave 2. IDs now follow `7-<plan>-<task>` and match one-to-one.

**R3 — Run command corrected.** `sas sas/07_cohort.sas` assumed a command-line
executable. There is no confirmed `sas` CLI on this Windows workstation; the
program is submitted interactively. The latency budget is restated accordingly —
a claim of 60-second automated feedback was not achievable for a manually
submitted program.

**R4 — Approval status made explicit.** `nyquist_compliant` and `wave_0_complete`
are both false and approval is pending, while 07-01-PLAN is `autonomous: true`.
See Gating below for what that means in practice.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS `%abort cancel` assertions inside named macros + log inspection |
| **Config file** | none — inline macro assertions |
| **Invocation** | Submit `sas/07_cohort.sas` interactively in SAS 9.4M8 (Display Manager, Enterprise Guide, or SAS Studio). No `sas` CLI is confirmed on this workstation; do not script a batch call without verifying one exists. |
| **Quick run** | Same as full — a single program covers all checks |
| **Estimated runtime** | ~30 seconds of compute, plus manual submit and log review |

---

## Sampling Rate

- **After the file-writing task (7-01-01):** run the static greps in the plan's
  acceptance criteria. These are cheap and catch the path-separator, ACCESS=READONLY,
  and double-ODS-open defects before SAS is ever opened.
- **After the run task (7-01-02):** inspect the SAS log for `ERROR:` and `WARNING:`
  lines, and confirm all four `(assertion passed)` NOTEs.
- **Before `/gsd:verify-work`:** full run must be clean and
  `qc/07_cohort_missingness.txt` must exist with procedure output intact.
- **Max feedback latency:** static greps under 10 seconds; SAS run feedback is
  bounded by manual submission, so budget a few minutes rather than 60 seconds.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Verification | File Exists | Status |
|---------|------|------|-------------|-----------|--------------|-------------|--------|
| 7-01-01 | 01 | 1 | PCM-F-11, PCM-F-12 | static grep | acceptance-criteria greps on `sas/07_cohort.sas` | ❌ W0 | ⬜ pending |
| 7-01-02 | 01 | 1 | COH-01, COH-03 | `%abort cancel` + log | submit in SAS; zero `ERROR:`; four `(assertion passed)` NOTEs | ❌ W0 | ⬜ pending |
| 7-02-01 | 02 | 2 | COH-02 | human verify | review `qc/07_cohort_missingness.txt` and the SAS log; capture the eight key=value figures | ❌ W0 | ⬜ pending |
| 7-02-02 | 02 | 2 | PCM-D-05, COH-04 | manual + grep | `grep "PCM-D-05 -- Analytic cohort" docs/DECISIONS.md`; no unfilled placeholders | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Note on ordering: 7-02-01 (human verify) precedes 7-02-02 (DECISIONS.md edit).
The edit transcribes measured values out of the QC file, so the file must exist and
have been reviewed first.

---

## Wave 0 Requirements

- [ ] `sas/07_cohort.sas` — program file (created in task 7-01-01)
- [ ] `qc/07_cohort_missingness.txt` — output artifact (created during the SAS run, 7-01-02)
- [ ] `.planning/phases/07-cohort-missingness/07-01-SUMMARY.md` — carries the measured
      admitted N, within-cohort Ns, and both BMI percentages into Plan 02

*Existing infrastructure covers all SAS assertion patterns from prior phases.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| PCM-D-05 closure documented | PCM-D-05 | docs/DECISIONS.md edit | `grep "PCM-D-05 -- Analytic cohort" docs/DECISIONS.md` shows the resolution entry |
| md3-owns missingness trade-off recorded | PCM-F-11 | prose documentation | `grep "md3-owns" qc/07_cohort_missingness.txt` or `docs/data_dictionary_notes.txt` |
| BMI availability stated with explicit direction | PCM-F-11 | measured value must be human-verified, and the direction was previously stated backwards | Check `qc/07_cohort_missingness.txt` for `pct_admitted_HAVE_bmi=` and `pct_admitted_LACK_bmi=`; confirm they sum to ~100 and that HAVE is the larger of the two (~53 vs ~47) |
| Within-cohort Ns reported separately from full-file Ns | PCM-F-11 | denominator confusion is the documented Pitfall 2 | Check the QC file has both `*_n_merged=` and `*_n_cohort=` lines |
| Patient_Type distribution reviewed before filtering | PCM-D-05 | unexpected categories require human judgement | Read the PROC FREQ table at the top of `qc/07_cohort_missingness.txt` |
| QC file not truncated by a second ODS open | COH-02 | silent failure; greps still pass | Confirm PROC FREQ and PROC MEANS output appear ABOVE the summary key=value lines |

---

## Known Failure Modes to Watch For

These were found during plan review and are the specific things most likely to go
wrong in this phase. Each is cheap to check and silent if missed.

| Failure | Symptom | Check |
|---------|---------|-------|
| `ACCESS=READONLY` on the `g` library | "Library G is read only" on the `data g.analytic_cohort` step | `grep -i "access=readonly" sas/07_cohort.sas` returns nothing |
| Missing path separator | Output lands at `...\merge\qc07_cohort_missingness.txt` instead of `...\merge\qc\07_cohort_missingness.txt` | File exists in the `qc` directory; no stray file one level up |
| Second `ods listing file=` truncates the QC file | File exists, greps pass, procedure output gone | Procedure output appears above the summary lines |
| Percentage direction inverted | "53% lack Admit_BMI" instead of "53% HAVE" | HAVE is the larger figure; both labelled; sum ≈ 100 |
| Filter matched nothing or everything | admitted N is 0 or 41,150 | WARNING lines from the degenerate-N guard |
| Stale macro value passes an assertion | assertion "passes" after a failed PROC SQL | `%local` present in the assertion macro |
| `%abort cancel` in open code | Next submit silently swallowed (PCM-R-05) | Every abort sits inside a `%macro`/`%mend` block |

---

## Gating

`nyquist_compliant: false` and `wave_0_complete: false` reflect that no automated
test framework exists for this SAS pipeline — validation is assertion-and-log based,
which is the established project pattern and is not going to change in Phase 7.

07-01-PLAN is `autonomous: true`, meaning the executor may write and run the program
without a checkpoint. That is appropriate: the program is read-only toward
`g.master_data_merged` and its only write is a new dataset. The blocking human
checkpoint sits at 7-02-01, before anything reaches `docs/DECISIONS.md`, which is the
permanent record and the only irreversible step in the phase.

Approval of this contract is therefore not a prerequisite for starting 07-01, but IS
a prerequisite for 07-02-02.

---

## Validation Sign-Off

- [ ] All tasks have a stated verification or Wave 0 dependency
- [ ] Sampling continuity: no 3 consecutive tasks without a verification step
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] QC artifact filename consistent across all four Phase 7 documents
      (`07_cohort_missingness.txt`)
- [ ] Task IDs map one-to-one to plan tasks
- [ ] Feedback latency documented honestly (static greps fast; SAS run is manual)
- [ ] `nyquist_compliant` left false with a stated reason (no test framework in a
      SAS 9.4 batch pipeline)

**Approval:** pending
