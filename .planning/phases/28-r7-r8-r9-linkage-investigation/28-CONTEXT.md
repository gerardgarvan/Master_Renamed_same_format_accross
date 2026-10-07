# Phase 28: r7/r8/r9 Linkage Investigation — Context

**Gathered:** 2026-10-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Read the existing linkage reach report (`qc/20_linkage_reach.txt`) and raw-directory evidence, run a standalone one-time SAS program that profiles PRECEDE_STUDY_ID formats and derives documented match rates, then write PCM-D-28 in `docs/DECISIONS.md`.

No pipeline programs are added or modified. `run_pipeline.cmd` is not touched.

</domain>

<decisions>
## Implementation Decisions

### D-01 — SAS Program (standalone, one-time, like 27_md8_count.sas)

Write `sas/28_linkage_investigation.sas`. It is NOT added to `run_pipeline.cmd`. Run once manually on P: drive after `src.master_data_*` are available. Three investigation blocks:

**Block 1 — SHA comparison of raw\ / raw\master pairs**

For each filename that appears in both `raw\` and `raw\master` rows of `qc/19_raw_files.csv`, compare the sha256 values and emit one row to `qc/28_linkage_investigation.csv` with `sha_identical_flag = YES/NO`.

Pre-established finding from 19_raw_files.csv (program may verify, not re-derive from scratch):
- 2018_2019_X_MASTER_DATASET_20200801.csv: raw\ 8,756,318 bytes (17 Aug 2026), raw\master 8,836,551 bytes (28 Apr 2026) — 80,233-byte difference, unexplained, file-level
- 2018_2019_CPT_ROLLUP_X_MASTER_DATASET_20200801.csv: raw\ 9,182,718 bytes, raw\master 9,262,951 bytes — same 80,233-byte difference
- 2018_2022_X_MASTER_DATASET_20240402.csv: raw\ 25,679,210 bytes, raw\master 25,759,443 bytes — same 80,233-byte difference
- The constant gap across files of very different row counts (14,778 vs 41,150) rules out a per-row-per-column explanation; record as an observed, unexplained finding
- 2020_X_MASTER_DATASET_20210519.csv, 2020_CPT_ROLLUP_X_MASTER_DATASET_20210609.csv, 2021_X_MASTER_DATASET_20230512.csv, 2022_MASTER_DATASET_20231024.csv: same byte sizes in both directories but sha256 values differ — NOT byte-identical

**Block 2 — ID-format profile**

Profile PRECEDE_STUDY_ID for the following, reporting type, width, and count of non-missing values. r7/r8/r9 have no ENCRYPTED_MRN column; the PHI guard applies to ENCRYPTED_MRN in the Crypto files and md3/md7 only (width and count only — no min/max, no sample values).

Files to profile:
- r7: `P:\PeCAN Master Data\Gerard\raw\2022_Education_20240124.csv` — 9,215 rows, 2 cols (PRECEDE_Study_ID numeric, Education)
- r8: `P:\PeCAN Master Data\Gerard\raw\2022_RES_20230927.csv` — 9,485 rows, 4 cols (PRECEDE_Study_ID numeric, Race, Ethnicity, Sex)
- r9: `P:\PeCAN Master Data\Gerard\raw\All_YEARS_LAT_LONG_20231127.csv` — 41,150 rows across all years; PRECEDE_STUDY_ID is character $12, YEAR is character $9. Profile distinct YEAR values before subsetting — YEAR may not hold the plain string "2022"
- md3's 2022 rows: read `P:\PeCAN Master Data\Gerard\raw\master\2018_2022_X_MASTER_DATASET_20240402.csv` (raw\master copy — the one the pipeline's md3 came from) and subset where YEAR = 2022; optionally also run against the raw\ copy as a second row to document the difference
- md7: `src.master_data_7` (SAS dataset on P: drive, read via libname src) — this is 2022_MASTER_DATASET, a different file from r7; profile PRECEDE_STUDY_ID type/width/count

r7 and r8 have numeric PRECEDE_STUDY_ID; r9 is character $12; md7 is numeric. Profile each independently and document the actual type found. Block 3 normalizations are derived from the Block 2 profile — do not assume before profiling. A safe default for numeric-vs-character comparison: `input(compress(id,,'kd'), best32.)` (digits only on both sides).

**Block 3 — Normalized ID match**

Each comparison gets its own documented normalization derived from Block 2 profile results. Report both directions: match_rate_left = n_matched / n_left, match_rate_right = n_matched / n_right. Guard against division by zero: if n_left = 0 or n_right = 0, set the corresponding rate to `.` (SAS missing).

md3-2022 source (decisive): `&raw_path.\master\2018_2022_X_MASTER_DATASET_20240402.csv` — the raw\master copy, which is what the pipeline's md3 (and PCM-D-16's mismatch count) came from. Optionally add a second row using the raw\ copy for comparison.

Profile r9's distinct YEAR values in Block 2 first; subset r9 to 2022 rows using the label found (YEAR is $9, may not be plain "2022"). A full-file r9 comparison makes match_rate_left meaningless.

Comparisons and normalizations:
- r7_vs_md3_2022: r7 numeric vs md3-2022 character $12 — digits-only comparison; document normalization
- r8_vs_md3_2022: same normalization as r7
- r9_vs_md3_2022: subset r9 to 2022 rows; r9 is character $12 — try direct match first, then digits-only; document
- md7_vs_md3_2022: md7 numeric vs md3-2022 character $12 — root question: do md3's 2022 IDs and md7's 2022 IDs share an ID space? Same normalization as r7. If about 0%, the PCM-D-16 mismatch implicates md3 vs md7 more broadly, not just r7-r9
- r7_vs_md7: both numeric — direct numeric match. If ~100% while md7_vs_md3_2022 is ~0%, the PCM-D-16 mismatch is an md3-vs-md7 problem, not specific to r7-r9
- r8_vs_md7: both numeric — direct numeric match; same diagnostic purpose as r7_vs_md7
- 2018_2019_MRN_Crypto_Data20260814.csv (14,781 rows, 2 cols) vs 2018_2019_X_MASTER (raw\master copy): PRECEDE_Study_ID is $18 in Crypto vs $12 in master — digits-only normalization; additionally run a count-only ENCRYPTED_MRN equality match (Crypto $41 vs master $40) — output n_matched only (PHI-safe), this settles which encryption the Crypto files share with which master copy; also run against the raw\ copy as a second row
- 2018_2019_ENCOUNTER_Crypto_Data_20260814.csv (14,781 rows, 2 cols) vs 2018_2019_X_MASTER: same normalization as MRN Crypto

Before re-deriving the 14.5% / 64% / 41% rates from PROJECT.md, check the git log, Phase 20 SUMMARY, and Phase 21 SUMMARY to establish their provenance (which files, which key, whether IDs were normalized, what the denominator was). If the program reproduces them with documented denominators and both-direction rates, PCM-D-28 may cite those values. If not, do not include the unprovenanced figures in the decision record.

**PHI guard (all blocks):** Value ranges and sample values for PRECEDE_STUDY_ID are acceptable in logs and the CSV. For ENCRYPTED_MRN, report widths and counts only — no min/max, no sample values — in any log line, PUT statement, or CSV row.

### D-02 — v2.3 Scope Statement in PCM-D-28

The determination is "MRN linking infeasible with the current extracts because r7/r8/r9 have no ENCRYPTED_MRN column" — this is positive evidence about the extract format, not an unexplained mismatch. Recovery is still possible. PCM-D-28 must state the specific condition for reopening r7-r9 linkage in v2.3 — for example: a re-extract of r7/r8/r9 that includes ENCRYPTED_MRN, or an ID crosswalk mapping r7-r9 PRECEDE_STUDY_IDs to the base cohort.

Phase 29 excludes r7-r9 tentatively, with a reference to PCM-D-28 and the stated reopening condition. A permanent exclusion requires positive evidence, not just unexplained mismatches.

### D-03 — Evidence Sufficiency for PCM-D-28

The 14.5% / 64% / 41% match rates in PROJECT.md are not sufficient as-is — their provenance is unrecorded. The program must:
1. First check git log, Phase 20 SUMMARY, Phase 21 SUMMARY, and PROJECT.md history for where these figures came from
2. Reproduce them with documented source pair, key column, normalization applied, n_left, n_right
3. Report both match_rate_left and match_rate_right — a single rate hides which side failed to match
4. Only include reproduced, documented rates in PCM-D-28; do not cite the PROJECT.md figures directly

### D-04 — Output Artifact

Commit `qc/28_linkage_investigation.csv` to P: drive (gitignored). Columns:

```
source_pair, key_used, normalization_applied, n_left, n_right,
n_matched, match_rate_left, match_rate_right, sha_identical_flag
```

One row per comparison. Counts only, no PHI. PCM-D-28 cites this file the same way PCM-D-31 cites `qc/27_md8_count.csv`.

### Pre-Established Findings (for program design)

These are known from existing evidence; the program confirms or elaborates, not re-discovers:
- r7 (`2022_Education_20240124.csv`), r8 (`2022_RES_20230927.csv`), r9 (`All_YEARS_LAT_LONG_20231127.csv`) do NOT carry ENCRYPTED_MRN; they have only PRECEDE_STUDY_ID (numeric for r7/r8, character $12 for r9) plus their domain columns. MRN-based linking is therefore infeasible with the current extracts. They match 0 rows in pecan_id_xwalk on PRECEDE_STUDY_ID (PCM-F-20, PCM-D-16)
- The 2018-2019 Crypto files cover 2018–2019 only (14,781 rows each); they cannot speak to 2022 linkage
- 2020–2022 raw\ / raw\master pairs are same byte size — whether SHA-256 values differ is to be confirmed by Block 1
- The 80,233-byte constant difference for the three 2018-2019 and 2018-2022 file pairs is an observed, unexplained finding; the raw\ copies bear an August 2026 modification date

### Claude's Discretion

- Internal structure of `28_linkage_investigation.sas` (macro layout, section numbering)
- Whether Block 1 reads 19_raw_files.csv via DATA step infile or processes the sha256 values already in scope from a prior PROC SQL; consistent with PCM-T-16 (no PROC IMPORT)
- Whether to attempt additional normalizations beyond those listed if the primary ones produce a match rate of 0

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing evidence files
- `qc/19_raw_files.csv` — Raw directory inventory with sha256, byte sizes, file dates, nobs, file_id for all raw\ and raw\master files; primary source for Block 1
- `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc\20_linkage_reach.txt` — PID-07 linkage reach report produced by program 20; must be read at phase start to establish what is already known about r7-r9 ENCRYPTED_MRN coverage

### Source program (read for patterns, do not modify)
- `sas/20_pecan_id.sas` — Contains the r7/r8/r9 file list (lines ~583-595), the linkage reach logic, and the %abort cancel / assert patterns to reuse; confirms r7=2022_Education, r8=2022_RES, r9=All_YEARS_LAT_LONG
- `sas/27_md8_count.sas` — Structural template for a standalone one-time investigation program

### Decision record
- `docs/DECISIONS.md` — PCM-D-16 (2022 ID mismatch), PCM-D-31 (md8 trailing-padding finding); PCM-D-28 entry is the primary output of this phase

### Prior phase context
- `.planning/phases/27-md8-row-count-correction/27-CONTEXT.md` — Template for how a one-time investigation phase is structured
- `.planning/phases/27-md8-row-count-correction/27-01-SUMMARY.md` — Shows how to document a SAS investigation finding

### Conventions
- `sas/00_config.sas` — Path macros (`&raw_path`, `&qc_path`, `&source_path`), `%assert_eq` macro, `%abort cancel` patterns (PCM-R-05)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/20_pecan_id.sas` lines ~583-595: r7/r8/r9 DATALINES block — copy as the authoritative file list; do not re-derive
- `sas/20_pecan_id.sas` linkage loop: shows how to iterate over r1-r9 files and run match comparisons
- `sas/27_md8_count.sas`: SHA pre-condition pattern, `%assert_eq_local` macro, DATA step infile for CSV, qc CSV output via DATA step PUT

### Established Patterns
- Standalone one-time programs: NOT added to `run_pipeline.cmd`; run manually; produce a qc/ CSV cited by a DECISIONS.md entry
- DATA step `infile` for all CSV reads (PCM-T-16 — never PROC IMPORT)
- `%abort cancel` inside named macros only (PCM-R-05)
- No open-code `%IF`; no `%local` in open code (PCM-T-15)
- qc/ files are gitignored (runtime artifacts on P: drive)

### Integration Points
- `qc/19_raw_files.csv` (P: drive): read at program start via DATA step infile to get sha256 pairs for Block 1
- `src` libname (assigned in `00_config.sas`): read-only access to master_data_*.sas7bdat
- `raw_path` macro (from `00_config.sas`): resolves to `P:\PeCAN Master Data\Gerard\raw`

</code_context>

<specifics>
## Specific Requirements

- Normalization in `qc/28_linkage_investigation.csv` is documented per comparison row, not as a single field — each row names what normalization was applied for that specific comparison
- Match rates reported in both directions: match_rate_left = n_matched / n_left, match_rate_right = n_matched / n_right
- The 80,233-byte constant difference is recorded as an observed finding, not attributed to any cause
- "md3's 2022 rows" defined as: rows in `raw\2018_2022_X_MASTER_DATASET_20240402.csv` where `YEAR = 2022`
- PCM-D-28 v2.3 scope statement must name a specific condition for reopening (e.g., "a 2022 Crypto file from the extract producer"), not just "investigate later"

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 28-r7-r8-r9-linkage-investigation*
*Context gathered: 2026-10-07*
