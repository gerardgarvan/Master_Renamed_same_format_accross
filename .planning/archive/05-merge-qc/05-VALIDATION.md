---
phase: 5
slug: merge-qc
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-26
updated: 2026-08-26
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4M8 — `%assert_eq` macro emitting `NOTE: QC ASSERTION OK -- <label> = <value>` on pass, `ERROR: QC ASSERTION FAILED` + `%abort cancel` on failure |
| **Config file** | none — SAS session paths set in SECTION 0 libnames |
| **Quick run command** | `sas -sysin "C:\Master_Renamed_same_format_accross\sas\05_qc_merge.sas" -log "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\05_qc_merge.log"` (full program is the test) |
| **Full suite command** | same as quick run — the program IS the suite |
| **Log path** | `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\05_qc_merge.log` — matches `%let logs_path` in Plan 01 SECTION 0 and the RESEARCH quick-run command. An earlier draft of this contract pointed at a `C:` path that no program writes |
| **Estimated runtime** | ~30–60 seconds |

---

## Sampling Rate

- **After every task commit (Plan 01, static):** run the Task `<automated>` grep checks against sas/05_qc_merge.sas (no SAS run — the program is not yet executed)
- **After Plan 01 both tasks:** full static verification block (section count, assert_eq count, values() >= 40, PCM checks)
- **After Plan 02 SAS run:** `QC ASSERTION FAILED` count = 0 AND `^ERROR` count = 0 AND `QC ASSERTION OK` count = 12 + the `&n_md8_only` figure reported in the QC-04 NOTE (do NOT gate on a fixed 20 — QC-04 issues one assertion per md8-owned variable, derived at run time)
- **Before `/gsd:verify-work`:** SAS log has 0 `ERROR:` lines, 0 `QC ASSERTION FAILED`, and a `QC ASSERTION OK` count matching 12 + n_md8_only
- **Max feedback latency:** 60 seconds (SAS run) / instant (static greps)

---

## Per-Task Verification Map

Signal patterns below match the actual `%assert_eq` output format
(`NOTE: QC ASSERTION OK -- <label> = <value>`), not a placeholder `QC-NN PASSED` string.

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 5-01-01 | 01 | 1 | QC-01, QC-02, QC-03 | static grep | `grep -c "SECTION"` >= 4 AND `grep -q "%macro assert_eq"` AND `grep -q "expected=41150"` AND `grep -q "_CHARACTER_"` AND the QC-02 reference uses `create table ... ; insert into ... values` (NOT `select * from (values ...)`, which is not SAS syntax) | ⬜ W1 | ⬜ pending |
| 5-01-02 | 01 | 1 | QC-04, QC-05 | static grep | `grep -q "qc04_partB"` AND `grep -q "md8_only"` AND `grep -q "in_md8 = 0 and Admit_BMI"` returns NO match AND `grep -c "is not missing and ("` = 8 (QC-05 only) | ⬜ W1 | ⬜ pending |
| 5-01-03 | 01 | 1 | QC-05 | static grep | `grep -q "Cognitive_Score > 30"` returns NO match (bound is 0-3) AND `grep -q "Admit_BMI > 80"` returns NO match (observed max 88.32; ceiling 100) | ⬜ W1 | ⬜ pending |
| 5-02-01 | 02 | 2 | QC-01..05 | static grep | all Plan 01 static checks pass; `grep -in "&SQLOBS"` = 0; multi-line PCM-T-01/T-02 checks return no match | ⬜ W2 | ⬜ pending |
| 5-02-02 | 02 | 2 | QC-01 | assertion (SAS run) | `QC ASSERTION OK -- QC-01 merged row count = 41150` = 1 match | ⬜ W2 | ⬜ pending |
| 5-02-03 | 02 | 2 | QC-02 | assertion (SAS run) | `grep -c "QC ASSERTION OK -- QC-02"` = 2 (truncated + missing-from-reference) | ⬜ W2 | ⬜ pending |
| 5-02-04 | 02 | 2 | QC-03 | assertion (SAS run) | `QC ASSERTION OK -- QC-03 NULL strings in any character variable = 0` = 1 match | ⬜ W2 | ⬜ pending |
| 5-02-05 | 02 | 2 | QC-04 | assertion + log (SAS run) | `grep -c "QC ASSERTION OK -- QC-04"` equals the `&n_md8_only` figure in the QC-04 NOTE (~20). No QC-04 line names Admit_BMI, Age_at_Encounter, Cognitive_Score, Frailty_Score, ASA__Anesth_Record_ or any rt_* variable — those are md3-owned. Part A counts logged, not asserted | ⬜ W2 | ⬜ pending |
| 5-02-06 | 02 | 2 | QC-05 | assertion (SAS run) | `grep -c "QC ASSERTION OK -- QC-05"` = 8 | ⬜ W2 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Aggregate SAS-run signal: `QC ASSERTION FAILED` = 0, `^ERROR` = 0, and `QC ASSERTION OK` =
12 + n_md8_only. The earlier fixed target of 20 assumed QC-04 covered eight hardcoded variables;
it now covers every md8-owned variable, derived from the ownership map at run time.

---

## Wave 0 Requirements

- Existing infrastructure covers all phase requirements (SAS programs are self-contained; no test framework install needed). The `%assert_eq` macro is defined inline in SECTION 0 of sas/05_qc_merge.sas — no external test scaffold to create.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| QC-04 Part A: within-md8 population counts | QC-04 | Interpreting sparsity needs domain context, not a threshold | Review the Part A block in `qc/05_qc_merge_report.txt`. Monitoring-derived columns (`ABP_*`, `NIBP_*`, `BIS_*`, `SD_*`, `AVG_*`) are expected at roughly **16–18%** of the 22,473 md8 rows — arterial-line and BIS monitoring are not used on most cases. Only the pressor/medication `Total_*` columns approach 22,473 (`Total_Midazolam_mg` = 22,473). A low count on a monitoring column is NORMAL, not a conversion failure. An earlier version of this row told the reviewer to treat any shortfall from 22,473 as needing explanation, which would send them chasing clinically routine sparsity |
| QC-05 range bounds remain appropriate | QC-05 | Bounds are calibrated to the current data; a future re-merge could shift them | Confirm the observed min/max still sit inside the bounds: `Admit_BMI` 12.84–88.32 (bound 10–100), `Age_at_Encounter` 64–100 (bound 18–120, floor cannot fire), `Cognitive_Score` 0–3 (bound 0–3 — NOT MMSE 0–30), `Frailty_Score` 0–5, `ASA__Anesth_Record_` 1–5 (bound 1–6). If a bound fires, inspect the rows before widening it |
| PCM-D-07 age floor | QC-05 | Open cohort question, not a data defect | The observed minimum age is 64. Do NOT tighten the QC-05 floor to 64 — that converts an open question into a pipeline abort. Resolve D-07 with Erin first |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (none — assert_eq defined inline)
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** signals aligned to `%assert_eq` output format. QC-04 retargeted to the md8-OWNED
single-source block (the PREP-03 conversion targets are md3-owned and would fail every
assertion); QC-05 bounds recalibrated to observed data; log path corrected to the P: location
the programs actually write to.
