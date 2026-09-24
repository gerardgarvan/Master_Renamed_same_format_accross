---
plan: 15-02
phase: 15-extend-the-harmonized-dataset
status: complete
completed: 2026-09-21
tasks_complete: 4
tasks_total: 4
key_decisions:
  - "PCM-D-14: HARM-07 pipeline-derived column rule recorded in DECISIONS.md (2026-09-14)"
human_verify: passed
sas_run_date: 2026-09-21T21:11:22
---

# Plan 15-02 Summary: HARM-07 Rule Enforcement + Fresh-Session Run

## What Was Built

Extended `sas/10b_concept_harmonize.sas` with the HARM-07 pipeline-derived column
rule: `in_md3` and all twelve `h_*_src` companions are dropped from
`g.master_data_harmonized` via dataset-option DROP. The drop is self-proving: a
`work.src_check` side output retains the companions so SECTION 6 can assert each is
single-valued before the run passes. Recorded the rule as PCM-D-14 in
`docs/DECISIONS.md`.

## Task Results

### Task 1: HARM-07 rule header, gate, and DATA statement

- Rule header added to program header (ASCII, states CARRY/DROP/ENFORCEMENT)
- `%let drop_pipeline_noinfo = 1;` gate added after `%let force_src = 1;`
- `data g.master_data_harmonized (drop=in_md3 H_DEATH_YN_src ... H_SSDI_DEATH_src)`
  with `work.src_check (keep= H_DEATH_YN_src ... H_SSDI_DEATH_src)` side output
- `%local _pi;` added to build_harmonized; `force_src` unchanged

### Task 2: Assertions

Four changes to SECTION 6, in order after `%assert_all`:
- `src_changed` WHERE clause extended with `and a.name ne 'IN_MD3'` under gate guard
- `%assert_src_single`: loops every `%scan(&hnames,&_pi)_src`, uses count(distinct)
  on work.src_check, fails if any companion has > 1 distinct non-missing value
- `%assert_harm07`: queries dictionary.columns for IN_MD3 + every `h_*_src`; fails
  if any remain when gate = 1
- `%assert_merged_unchanged`: re-queries dictionary.columns and dictionary.tables
  post-run; fails on cols != 176 OR rows != &n_rows

### Task 3: PCM-D-14 in DECISIONS.md

PCM-D-14 appears in pending table (marked resolved) and in a full resolution section
naming the CARRY list, DROP list, enforcement macros, and the premise-assertion design.
Committed: 59e920e.

### Task 4: Fresh-session SAS run (human-verify, 2026-09-21)

Submitted `sas/10b_concept_harmonize.sas` in a fresh SAS 9.4 session.

**Zero ERROR lines.**

**All 7 required NOTE lines confirmed:**

| NOTE | Confirmed |
|------|-----------|
| `decision file passed all thirteen validation gates` | ✅ |
| `39 confirmed mappings across 12 concepts` (n_con_yes = 12: 11 original + SSDI) | ✅ |
| `every observed value of every confirmed column is mapped` | ✅ |
| Redundancy NOTEs (13 secondaries, all 0 rows / 0 disagreements) | ✅ |
| `HARM-07 premise OK -- every h_*_src companion is single-valued` | ✅ |
| `HARM-07 OK -- in_md3 and every h_*_src companion dropped` | ✅ |
| `g.master_data_merged confirmed post-run -- 176 columns and 41150 rows -- unmodified` | ✅ |

**SSDI redundancy proofs (new in this run):**
- `SSDI_DEATH vs SSDI_DEATH_DATE_Y_N -- would add 0 rows, 0 disagreements`
- `SSDI_DEATH_Y_N vs SSDI_DEATH_DATE_Y_N -- would add 0 rows, 0 disagreements`

**DATA step output:**
- `g.master_data_harmonized`: 41,150 rows, **174 columns**
  - 176 merged - 13 proven-redundant aliases - 1 (in_md3) - 12 (h_*_src companions dropped)
    + 12 h_ columns = 174
- `work.src_check`: 41,150 rows, 12 variables (companions kept for premise proof)
- `g.master_data_merged`: confirmed 176 columns, 41,150 rows, unmodified

**Column arithmetic:**
- 176 merged − 13 redundant aliases − 1 in_md3 + 12 h_ columns − 12 h_*_src = **174**

**QC report:** `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc\10b_harmonize_report.txt`

Harmonized column coverage summary:

| Column | N Populated | Pct |
|--------|------------|-----|
| H_DEATH_YN | 22,917 | 55.7% |
| H_DIABETES | 5,983 | 14.5% |
| H_FRAILTY_ACTIVITY | 14,025 | 34.1% |
| H_FRAILTY_EXHAUST | 14,181 | 34.5% |
| H_FRAILTY_GRIP | 13,699 | 33.3% |
| H_FRAILTY_WALKING | 13,989 | 34.0% |
| H_FRAILTY_WEIGHT | 14,156 | 34.4% |
| H_HYPERLIPIDEMIA | 11,207 | 27.2% |
| H_HYPERTENSION | 12,546 | 30.5% |
| H_MOVEMENT_DISORDER | 1,357 | 3.3% |
| H_SLEEP_APNEA | 3,812 | 9.3% |
| H_SSDI_DEATH | 29,316 | 71.2% |

## Acceptance Criteria

- [x] SAS log shows zero ERROR lines
- [x] `decision file passed all thirteen validation gates`
- [x] `HARM-07 premise OK -- every h_*_src companion is single-valued`
- [x] `HARM-07 OK -- in_md3 and every h_*_src companion dropped`
- [x] `g.master_data_merged confirmed post-run -- 176 columns and 41150 rows -- unmodified`
- [x] All 13 redundancy NOTEs show "would add 0 rows, 0 disagreements"
- [x] g.master_data_harmonized: 174 columns, 41,150 rows; in_md3 absent; no *_src present; H_SSDI_DEATH present
- [x] g.master_data_merged: exactly 176 columns, 41,150 rows

## Key Files

- `sas/10b_concept_harmonize.sas` — HARM-07 rule enforced (drop= + 3 new assertions + src_changed fix)
- `docs/DECISIONS.md` — PCM-D-14 entry (commits 59e920e, 36488c0)
- `docs/concept_decisions.csv` — 39 YES rows across 12 concepts (from Plan 15-01)
- `P:\...\qc\10b_harmonize_report.txt` — regenerated QC report (on P: drive, not git-tracked)
