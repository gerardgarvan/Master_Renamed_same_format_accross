---
phase: 18
slug: supplemental-raw-inventory
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-16
updated: 2026-09-16
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS log inspection + file-existence and grep checks (no automated test runner) |
| **Config file** | sas/00_config.sas |
| **Quick run command** | `grep -i "ERROR\|ABORT" "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\18_supplemental_raw_gap.log"` |
| **Full suite command** | Manual SAS run of 18_supplemental_raw_gap.sas + grep checks on qc\18_*.txt |
| **Estimated runtime** | ~10-20 minutes (r2 import dominates) |

---

## Sampling Rate

- **After every task commit:** the task's `<automated>` grep passes; no new `%abort cancel`
- **After every plan wave:** manual SAS run; both qc\18_*.txt present; log ERROR lines limited to the D15 gate
- **Before `/gsd:verify-work`:** all outputs present, D15 gate present in 18 and 17, D15_APPROVED only in config
- **Max feedback latency:** one manual SAS run per wave

---

## Wave 0 Requirements

- [ ] Locate `sas/16_raw_inventory.sas` on disk (C:\Master_Renamed_same_format_accross\sas\) and commit it (plan 01 Task 0)
- [ ] Move `%import_csv` / `%import_xlsx` verbatim into `sas/macros_raw_import.sas`; 16 and 18 both `%include` it (plan 01 Task 0)
- [ ] Add `%let raw_path` and `%let D15_APPROVED = 0` to `sas/00_config.sas`; remove local raw_path from 16 (plan 01 Task 1)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-00 | 01 | 0 | 16 committed; macros in one shared file | grep | `git ls-files sas/16_raw_inventory.sas; grep -c "%macro import_" sas/macros_raw_import.sas` | W0 creates | pending |
| 18-01-01 | 01 | 1 | raw_path + D15_APPROVED in config; none in 16 | grep | `grep -n "raw_path\|D15_APPROVED" sas/00_config.sas; grep -c "%let raw_path" sas/16_raw_inventory.sas` | W0 creates | pending |
| 18-01-02 | 01 | 1 | Scaffold: options, shared include, libname g, assert_base, one abort | grep | `grep -c "%abort cancel" sas/18_supplemental_raw_gap.sas; grep -n "validmemname=extend\|macros_raw_import\|libname g " sas/18_supplemental_raw_gap.sas` | W1 creates | pending |
| 18-01-03 | 01 | 1 | qc\18_id_diagnostic.txt: base/r9/r7 samples + 4 length tables | grep + file | `grep -n "id_best32\|matched_ids\|18_id_diagnostic.txt" sas/18_supplemental_raw_gap.sas`; runtime `test -f qc/18_id_diagnostic.txt` | runtime | pending |
| 18-02-01 | 02 | 2 | Section B small files: per-column keep=/rename= merge, sentinel rule, no r7/r8 | grep | `grep -n "rename=(\|-999\|'NULL'\|gap_file" sas/18_supplemental_raw_gap.sas; grep -c "2022_RES\|2022_Education" <(sed -n '/SECTION B/,$p' sas/18_supplemental_raw_gap.sas)` | W2 creates | pending |
| 18-02-02 | 02 | 2 | r2 rollups (4 families), COMP10 excluded, dividers appendix, qc\18_gap_candidates.txt | grep + file | `grep -n "COM_dCDT\|COPY_dCDT\|paper_neuropsych\|COMP10\|r2_dividers\|TYPE_DIFF\|18_gap_candidates.txt" sas/18_supplemental_raw_gap.sas`; runtime `test -f qc/18_gap_candidates.txt` | runtime | pending |
| 18-02-03 | 02 | 2 | D15 gate in 18 and 17; flag only in config | grep | `grep -c "%let D15_APPROVED" sas/18_supplemental_raw_gap.sas sas/17_summary_stats_by_domain.sas` (both 0); `grep -c "gate_d15" sas/18_supplemental_raw_gap.sas sas/17_summary_stats_by_domain.sas` (both >= 2) | W2 | pending |

*Status: pending / green / red / flaky*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Base / r9 / r7 sample IDs with lengths, plus four length tables | PCM-D-16 / RAW-08 | Requires SAS run and human review | Open qc\18_id_diagnostic.txt; confirm three 5-ID blocks and four LENGTH DISTRIBUTION blocks; the matched-IDs table should be all 12 |
| Gap candidates sorted (IN_BASE by pct_fillable desc, NEW by pct_raw_populated desc) | D-04 | Sort order requires visual inspection | Open qc\18_gap_candidates.txt; check the first rows of each block |
| TYPE_DIFF rows have conflict counts that are type artefacts, not data disagreements | D-02 | Interpretation | For each TYPE_DIFF row, confirm raw_type ne base_type explains n_conflict |
| Four r2 family rollup rows; COMP10 columns appear as individual NEW rows | RAW-10 | Rollup structure not grep-verifiable at runtime | Confirm COM_dCDT (~2,082), COPY_dCDT (~1,259), LINUS (~251), paper_neuropsych (~153) rows; confirm COMP10_T80..T88 are listed individually |
| Divider appendix: all 8 names present, none flagged REVIEW | RAW-10 | Runtime content | Any "on divider list but populated -- REVIEW" line is a finding to record |
| D15 gate blocks program 18 completion AND program 17 extension until config flag = 1 | RAW-11 / D-03 | Behavioral — requires SAS session test | With D15_APPROVED=0: 18 writes both QC files then aborts with the PCM-D-15 message; 17 aborts before analysis_base_ext. Set the config flag to 1: both complete |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (16_raw_inventory.sas, shared macros, config flags)
- [x] No watch-mode flags
- [x] Feedback latency: manual SAS run (~10-20 min acceptable for SAS pipeline)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
