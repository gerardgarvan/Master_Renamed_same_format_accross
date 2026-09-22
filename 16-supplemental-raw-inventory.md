---
phase: 16
slug: supplemental-raw-inventory
status: complete
depends_on: 15
requirements: [RAW-01, RAW-02, RAW-03, RAW-04, RAW-05, RAW-06, RAW-07]
program: sas/16_raw_inventory.sas
executed: 2026-09-16
---

# Phase 16 — Supplemental Raw Source Inventory

## Goal

Profile the 9 non-master files in `P:\PeCAN Master Data\Gerard\raw` and report, for each one, what it is, what grain it sits at, which ID it carries, how many `g.analysis_base` patients it reaches, and which of its columns already exist in the base. Every column is inventoried regardless of whether it appears in the PRECEDE data dictionary. Read-only: nothing under `raw\` is written to and no `g.*` dataset is modified.

## Scope

| rid | File | Rows | Cols | Sheet |
|---|---|---|---|---|
| r1 | 2018_2019_2020_Induction_Emergent20231121.csv | 22,476 | 3 | csv |
| r2 | 2018_2019_Precede_Database.xlsx | 14,807 | 3,987 | 2018_2019_PRECEDE_DATABASE |
| r3 | 2018_2022_COLONOSCOPY_20240118.xlsx | 3,456 | 8 | Sheet1 |
| r4 | 2020_Precede_Database_Edu.xlsx | 7,696 | 3 | 2020_PRECEDE_DATABASE_EDU |
| r5 | 2021_Education_20240124.csv | 9,462 | 2 | csv |
| r6 | 2021_Frailty_20240123.csv | 9,462 | 6 | csv |
| r7 | 2022_Education_20240124.csv | 9,215 | 2 | csv |
| r8 | 2022_RES_20230927.csv | 9,485 | 4 | csv |
| r9 | All_YEARS_LAT_LONG_20231127.csv | 41,150 | 4 | csv |

Base spine at execution: `g.analysis_base`, 41,150 rows, 125 columns.

## Requirements

- **RAW-01** Inventory program `16_raw_inventory.sas` imports each file read-only, ASCII only, no semicolons in `%let` text, paths from `00_config.sas` plus one new `raw_path` macro variable.
- **RAW-02** Per-sheet handling for the three workbooks (r2, r3, r4); every sheet enumerated and imported separately; Excel row-ceiling flag on every dataset.
- **RAW-03** Key presence, uniqueness and coverage vs the `g.analysis_base` PRECEDE_STUDY_ID spine for every file.
- **RAW-04** Grain classification (PATIENT / ENCOUNTER / MULTI_PER_PT / NO_KEY_FOUND) derived from the uniqueness test, not from the filename.
- **RAW-05** Every raw column bucketed IN_BASE / NEW against the 125 base columns, matching on normalized SAS name or source label.
- **RAW-06** r8 (RES) characterized from its values rather than its name.
- **RAW-07** Transcoding warnings captured in `logs\16_raw_inventory.log`.

## Outputs (qc_path, not version-controlled)

- `16_raw_inventory.txt` — dataset inventory, grain table, r2 column-family summary
- `16_raw_columns.txt` — every variable in every file (4,019 rows): source name, SAS name, type, length, % missing
- `16_raw_keys.txt` — key columns, uniqueness, coverage vs base
- `16_raw_overlap.txt` — IN_BASE / NEW bucketing, r8 value distributions

## Success criteria

| # | Criterion | Result |
|---|---|---|
| 1 | Per file/sheet: rows, cols, all column names, SAS type/length, positional-name flag | Met — no VARn names assigned |
| 2 | Key presence, uniqueness, coverage vs base per file | Met |
| 3 | Every raw column bucketed vs base | Met (IN_BASE/NEW only; "sparser in base" deferred to 16b) |
| 4 | r2 confirmed not truncated | Met — 14,807 rows, single sheet, well under 1,048,575 |
| 5 | Read-only on `raw\` | Met |
| 6 | Scope decision recorded (PCM-D-15) | **Open** — see Decisions |

## Findings

### Keys and coverage

| rid | Key column | Type | Distinct / non-missing | Grain | Match base | Raw-only | Base-only |
|---|---|---|---|---|---|---|---|
| r1 | PRECEDE_Study_ID | char $18 | 22,476 / 22,476 | PATIENT | 22,472 | 4 | 18,678 |
| r2 | studyid | char $12 | 14,807 / 14,807 | PATIENT | 14,778 | 29 | 26,372 |
| r3 | PRECEDE Study ID | char $12 | 3,456 / 3,456 | PATIENT | 2,688 | 768 | 38,462 |
| r4 | studyid | char $12 | 7,696 / 7,696 | PATIENT | 7,695 | 1 | 33,455 |
| r5 | PRECEDE_Study_ID | char $12 | 9,462 / 9,462 | PATIENT | 9,462 | 0 | 31,688 |
| r6 | PRECEDE_Study_ID | char $12 | 9,462 / 9,462 | PATIENT | 9,462 | 0 | 31,688 |
| r7 | PRECEDE_Study_ID | **num** | 9,215 / 9,215 | PATIENT | **0** | 9,215 | 41,150 |
| r8 | PRECEDE_Study_ID | **num** | 9,484 / 9,485 | MULTI_PER_PT | **0** | 9,484 | 41,150 |
| r9 | PRECEDE_Study_ID | char $12 | 41,150 / 41,150 | PATIENT | 31,935 | **9,215** | **9,215** |

Coverage counts align with year cohorts: r2 matches exactly the 2018–2019 master row count (14,778), r4 the 2020 master (7,695), r5/r6 the 2021 master (9,462). r1 covers 2018–2020 with 4 unmatched IDs. r3 has 768 colonoscopy patients outside the cohort.

r2 also carries ENCRYPTED_MRN (13,044 distinct of 14,778 — repeated) and ENCRYPTED_ENCOUNTER (14,348 distinct of 14,560 — repeated); `studyid` is the patient-grain key.

r8 has one duplicated PRECEDE_Study_ID (9,484 distinct of 9,485) and 157 rows with Race, Ethnicity and Sex all blank.

### 2022 ID mismatch (blocker for Phase 17)

The 2022 cohort does not join. r7 and r8 match 0 base IDs; r9 (character, all years) has exactly 9,215 raw-only and 9,215 base-only IDs, which is the 2022 master row count. Because r9 is character, this is not a `cats()` numeric-rendering artefact — the 2022 ID values in `g.analysis_base` differ from the 2022 ID values in every raw file. This is consistent with master_data_7 (2022) having carried PRECEDE_STUDY_ID as NUM8 while the other masters were `$12`. Cause not yet established (leading zeros, scientific notation, or different ID series). Diagnostic: print 5 base IDs not in r9 beside 5 r9 IDs not in base with their lengths.

### Column overlap

| rid | IN_BASE | NEW | Note |
|---|---|---|---|
| r1 | 3 | 0 | rt_RM_START_to_INDUCTION / EMERGENCE already in base |
| r2 | 102 | 3,885 | |
| r3 | 8 | 0 | CPT1_Class, CPT1_Label already in base |
| r4 | 0 | 3 | Edu_Years, edu_categorical |
| r5 | 2 | 0 | Education already in base (98% missing here) |
| r6 | 1 | 5 | five frailty components |
| r7 | 2 | 0 | Education already in base (99% missing here) |
| r8 | 4 | 0 | Race, Ethnicity, Sex already in base |
| r9 | 4 | 0 | Latitude, Longitude, YEAR already in base |

Six of nine files add no columns. Whether they add *values* (base missing where raw is populated) is not yet measured — see 16b.

### r2 structure (3,987 columns)

| Family | Cols | All-missing | Median % missing |
|---|---|---|---|
| COM_dCDT (command clock features) | 2,082 | 12 | 22.5 |
| COPY_dCDT (copy clock features) | 1,259 | 2 | 22.5 |
| LINUS (derived clock scores) | 251 | 1 | 22.9 |
| paper_neuropsych (Aim 3 battery) | 153 | 0 | 90.1 |
| idr_other | 108 | 30 | 22.5 |
| anesthetic_opioid | 30 | 0 | 0.2 |
| precede_admin | 27 | 8 | 95.4 |
| rt_times | 18 | 0 | 11.9 |
| blood_labs | 17 | 0 | 49.5 |
| billing_dx | 15 | 3 | 99.9 |
| ron (CPT/BPC digit splits) | 11 | 1 | 8.1 |
| COMP10 | 10 | 0 | 0.2 |
| garvan | 6 | 1 | 62.4 |

Several 100%-missing columns are section dividers, not data: `IDR Variables Only`, `Bloods`, `LINUS`, `garvan_added_variables`, `ron_extra_for_sabya`, `DigitalClockData`, `PeCANers`, `Other Variables`.

Genuinely new clinical content in r2 (2018–2019 patients only): `Edu_Years`, `edu_categorical`, `Frailty_Score`, `frailty_score_category`, `mmse_3word_repeat`, `mmse_3word_recall`, `GripStrength_trial_1..3`, `handedness`, `age`, `Primary_Payer`, `Insurance`, `Payer_categ`, `SSDI_Death_Y_N`, `average_pain`, `Death_Indicator`, 17 pre-op lab columns (`blood_*`), plus the dCDT / LINUS feature blocks.

### r8 (RES) content

Race (WHITE 83%, BLACK 8.5%, OTHER 3.6%, PATIENT REFUSED 1.1%, ASIAN 1.0%, MULTIRACIAL 0.5%, UNKNOWN 0.5%, AMERICAN INDIAN 0.2%), Ethnicity (NOT HISPANIC 93%, HISPANIC 3.5%, PATIENT REFUSED 1.4%, UNKNOWN 0.5%, two rows of `?`), Sex (MALE 49.9%, FEMALE 48.5%). "RES" is a race/ethnicity/sex extract for 2022.

## Execution notes

- First run produced zero coverage and 0 IN_BASE everywhere because `00_config.sas` defines `&g_path` but does not issue `libname g`. The program now assigns the libname itself and `%assert_base` aborts if `g.analysis_base` is unreachable, so an empty base can no longer produce silent zeros.
- Key detector extended: `studyid` (r2, r4) is a PRECEDE_ID key; ENCOUNTER detection requires ENCRYPTEDENCOUNTER or ENCOUNTERID so `Age_at_Encounter` is no longer misread as a key.
- No positional (VARn) names were assigned on import; no Excel row-ceiling flags.
- RAW-07 log check (`character data was lost`, `Transcod`) to be run in PowerShell against `logs\16_raw_inventory.log`.

## Decisions

- **PCM-D-15 (open, Price):** which raw columns, if any, are approved for Phase 17 gap fill. The inventory covers every column; the dictionary question applies only to what gets joined.
- **PCM-D-16 (proposed, open):** 2022 PRECEDE_STUDY_ID format. Until the base and raw 2022 IDs are reconciled, no 2022 join is possible in Phase 17 or any later phase.

## Next

- **16b** — resolve the 2022 ID format, then for every IN_BASE column compute base-missing-but-raw-populated counts on matched IDs. This is the table PCM-D-15 needs; the candidates most likely to matter are r1 (induction/emergence times), r8 (race/ethnicity/sex for 2022), r2 (Frailty_Score, Education, Admit_BMI, comorbidity flags, labs).
- **Phase 17** — gated on PCM-D-15 and PCM-D-16.
