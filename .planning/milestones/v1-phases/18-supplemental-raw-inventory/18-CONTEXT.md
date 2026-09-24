# Phase 18: Supplemental Raw Gap Diagnostic — Context

**Gathered:** 2026-09-16
**Revised:** 2026-09-16 (accuracy pass against Phase 16 results and `16_raw_inventory.sas`)
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the two follow-on items from Phase 16 ("16b"):

1. **2022 ID mismatch diagnostic (PCM-D-16)** — Identify why r7/r8/r9 2022 IDs match 0 base rows. Print 5 base IDs not in r9 beside 5 r9 IDs not in base with their lengths, plus a length distribution of all base IDs not in r9 and all r9 IDs not in base, and write to `qc\18_id_diagnostic.txt`. The diagnostic does **not** abort; it writes its file and the program continues to item 2. Gerard decides the resolution; PCM-D-16 cannot be auto-closed.

2. **Gap-fill counts (PCM-D-15 input)** — On matched IDs only, for every file with >0 matched IDs (r1, r2, r3, r4, r5, r6, r9), report per column:
   - IN_BASE columns: three counts — base missing / raw populated (fillable), both populated and equal, both populated and different (conflict)
   - NEW columns: raw populated count among matched IDs
   
   r7 and r8 are excluded until PCM-D-16 is resolved. Write `qc\18_gap_candidates.txt`. Phase 18 ends with a `%gate_d15` call reading `&D15_APPROVED` from `00_config.sas`; Gerard reviews the output, records the decision in `docs/DECISIONS.md`, then sets the config flag to 1. Program 17 calls the same gate before building `work.analysis_base_ext`, which is what actually blocks Phase 17.

Read-only: nothing under `raw\` is written to and no `g.*` dataset is modified.

</domain>

<decisions>
## Implementation Decisions

### D-01: 2022 ID mismatch handling
- **D-01:** Program runs the diagnostic (5 base IDs not in r9 vs 5 r9 IDs not in base with lengths, plus `length()` frequency tables for both non-matching sets), writes `qc\18_id_diagnostic.txt`, and **continues**. The only `%abort cancel` in the program is the D15 gate at the end. Gerard inspects the diagnostic and decides whether a numeric-to-char cast or another fix applies. PCM-D-16 cannot be auto-closed in code — the cause may be a true ID-series difference, not a formatting artefact. Any 2022 fix is Phase 19+ work.

### D-02: Gap-fill scope and metrics
- **D-02:** Compute on **all files with matched IDs**: r1 (22,472 matched), r2 (14,778), r3 (2,688), r4 (7,695), r5 (9,462), r6 (9,462), r9 (31,935). r7 and r8 are excluded until PCM-D-16 is resolved (numeric key, 0 matches).
- Per the Phase 16 overlap table, the IN_BASE metric applies only where IN_BASE non-key columns exist: r1 (2), r2 (101), r3 (7), r5 (1), r9 (3). r4 (0 IN_BASE) and r6 (key only) contribute nothing under that metric.
- The columns most likely to be approved — r4 `Edu_Years` / `edu_categorical`, r6's five frailty components, and r2's 3,885 NEW columns — are all NEW, so the table must also carry the NEW-column metric (raw populated count on matched IDs). Without it the review file is silent on the main candidates.
- The conflict count on IN_BASE columns decides whether Phase 17 fills only where base is missing or overwrites; it is computed in the same pass.

### D-03: PCM-D-15 decision gate
- **D-03:** `%let D15_APPROVED = 0;` lives in `00_config.sas`, not in program 18 — a `%let` inside one program is invisible to another, so the Phase 17 `DOMAIN_MAP_APPROVED` pattern (which gated later sections of the same program) is replicated with the flag moved to config. `%gate_d15` is called at the end of program 18 and again in program 17 immediately before `work.analysis_base_ext` is built. Program 18 writes `qc\18_gap_candidates.txt`; Gerard reviews, records the approved columns in `docs/DECISIONS.md`, then sets the config flag to 1. Phase 17 cannot build its extension until then.
- Attribution: PCM-D-15 is recorded as **Gerard's decision for Phase 18 scope**; Price may be consulted before the flag is set. `16-supplemental-raw-inventory.md` currently lists PCM-D-15 as "open, Price" and must be amended to match.

### D-04: Program naming and outputs
- **D-04:** SAS program is `sas/18_supplemental_raw_gap.sas`. All outputs go to `qc\18_*.txt`:
  - `qc\18_id_diagnostic.txt` — 2022 ID comparison
  - `qc\18_gap_candidates.txt` — per column per file: bucket (IN_BASE / NEW), n_matched, n_fillable, n_equal, n_conflict, n_raw_populated; sorted by n_fillable descending within IN_BASE, then n_raw_populated descending within NEW
  - Log: `logs\18_supplemental_raw_gap.log`
  - Fits the phase-number-matches-program-number convention used throughout the pipeline.

### D-05: Phase ordering note
- **D-05:** Phase 17 (summary stats by domain) is numbered lower but is downstream of Phase 18, because its extension dataset `work.analysis_base_ext` takes the columns approved under PCM-D-15. The roadmap entry for Phase 17 should state this dependency explicitly so the numbering does not read as a mistake.

### Claude's Discretion
- Whether to produce a single combined gap table or one section per file
- Macro structure (one macro per file vs a generalized loop)
- Whether the ID diagnostic and the gap counts are two sections of one program or two programs (`18a`, `18b`); one program is acceptable now that the diagnostic does not abort
- Report layout details (column widths, block ordering within the constraints in D-04)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 16 completed spec (primary input)
- `16-supplemental-raw-inventory.md` — Phase 16 summary: 9-file inventory, key coverage table, column overlap table, r2 column families, 2022 ID mismatch description, PCM-D-15/D-16 open decisions. Read this first. Amend PCM-D-15 attribution per D-03.

### Pipeline configuration
- `sas/00_config.sas` — defines `g_path`, `qc_path`, `logs_path` and the `%include`d source paths. It does **not** issue `libname g`; each program assigns it. `raw_path` is currently a `%let` inside `sas/16_raw_inventory.sas`, not in config — move it to `00_config.sas` as part of this phase so both programs share one definition.
- `sas/16_raw_inventory.sas` — Phase 16 program; on disk at `C:\Master_Renamed_same_format_accross\sas\` but not yet committed (plan 01 Task 0 commits it). Its `%import_csv` (PROC IMPORT, `guessingrows=max`) and `%import_xlsx` (libname `xin` with the XLSX engine, sheets enumerated from `dictionary.tables` and copied via `call execute`, output `work.<rid>_sN`) move verbatim into `sas/macros_raw_import.sas`, which 16 and 18 both `%include`. Do not reconstruct them from prose.

### Decision log
- `docs/DECISIONS.md` — PCM-D-15 and PCM-D-16 must be recorded here; review current open-decision wording before writing new entries.

### Prior phase context
- `.planning/phases/17-summary-stats-by-domain-context/17-CONTEXT.md` — Phase 17 is downstream and gated on PCM-D-15 (see D-05).

### No external ADRs — requirements fully captured in decisions above and in `16-supplemental-raw-inventory.md`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/16_raw_inventory.sas` — `%import_csv`, `%import_xlsx`, key detection, IN_BASE bucketing, `%assert_base`; Phase 18 reuses these without rerunning the full inventory
- `sas/00_config.sas` — `g_path`, `qc_path`, `logs_path`; `raw_path` and `D15_APPROVED` added by plan 01
- `sas/17_summary_stats_by_domain.sas` — `DOMAIN_MAP_APPROVED` gate pattern to replicate as `%gate_d15` (flag in config); receives its own `%gate_d15` call in plan 02 Task 3

### Established Patterns
- All programs `%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas"` as first step, then `options validvarname=v7 validmemname=extend;` (sheet names starting with a digit need name literals; "PRECEDE Study ID" must import as `PRECEDE_Study_ID`), then `libname g "&g_path";` and `%assert_base` before any reference to `g.analysis_base` — the config does not assign the libname, and Phase 16's first run produced silent zero coverage for exactly this reason
- No bare open-code `%IF` — all conditional logic in named macros
- Every `%abort cancel` inside a named macro (PCM-R-05)
- No `%PUT` with apostrophes or embedded semicolons
- `g.&src_ds` never on the left of a DATA statement (read-only source protection)
- `%let FLAG=0` gate with `%macro gate_X; %if &FLAG=0 %then %abort cancel; %mend;` — see Phase 17 Checkpoint 1

### Integration Points
- Reads `g.analysis_base` — 41,150 rows, 125 columns at Phase 16 execution. (The program that builds it is not named in the Phase 16 record; confirm before referencing it in plans.)
- Reads raw files under `&raw_path` (files listed in `16-supplemental-raw-inventory.md` §Scope)
- Writes to `qc\` and `logs\` (paths via `00_config.sas`)
- `docs/DECISIONS.md` is updated by Gerard manually after reviewing `qc\18_gap_candidates.txt`

### Known Pitfalls (from Phase 16)
- `cats()` of a numeric ID may not match the char form — do NOT assume the cast explains the 2022 mismatch until the diagnostic confirms it. r9 is character and shows the same 9,215 mismatch, so a cast alone is unlikely to be the whole story.
- r2 `studyid` and r4 `studyid` are the patient keys (not `PRECEDE_STUDY_ID`) — key detection must handle alias names. r1's key is `$18` while the others are `$12`; it still matched 22,472, so compare on `strip(cats())`.
- r8 has one duplicated PRECEDE_Study_ID (9,484 distinct of 9,485) and 157 all-blank rows — excluded from this phase anyway (2022, 0 matches).
- r2 has 3,987 columns and 14,807 rows; the row-ceiling check was clear in Phase 16, re-assert on import. Several 100%-missing r2 columns are section dividers (`IDR Variables Only`, `Bloods`, `LINUS`, `garvan_added_variables`, `ron_extra_for_sabya`, `DigitalClockData`, `PeCANers`, `Other Variables`) and should be reported as such, not as candidates.
- `dictionary.columns.type` is CHARACTER (`'char'`/`'num'`), not numeric — PCM-T-13
- Comparing raw to base values for the conflict count requires type-aware comparison: cast both sides with `strip(cats())` for equality, and carry `raw_type` / `base_type` into the results — when they differ, every non-missing pair lands in conflict (a numeric date renders as 21550, a char date as 01JAN2019), so the reader must be able to see the conflict is a type artefact.
- Never merge a raw file wide with `g.analysis_base`: same-named columns are silently overwritten and every conflict count comes out zero. One merge per IN_BASE column with `keep=` and `rename=` on both sides.
- Two missing sentinels are not caught by `missing()`: `-999` in the clock/dCDT numerics and the literal string `NULL` in Excel-sourced character columns. Both are treated as missing in every count.
- The `COM` prefix rule for dCDT must exclude `COMP10_*` and `complication_sum` (complications, not clock features).

</code_context>

<specifics>
## Specific Ideas

- The Phase 16 spec contains the diagnostic instruction: "print 5 base IDs not in r9 beside 5 r9 IDs not in base with their lengths." Use this, plus the length frequency tables, as the acceptance criterion for the 2022 ID diagnostic task.
- Candidates most likely to matter (from Phase 16 findings): r1 induction/emergence times (IN_BASE, 40% missing in raw — is base sparser?), r2 `Frailty_Score` / `Admit_BMI` / comorbidity `_YN` flags / `Education` (IN_BASE), r2 `Edu_Years` / `edu_categorical` / MMSE 3-word / grip trials / labs (NEW), r4 education (NEW), r6 five frailty components (NEW), r9 lat/long for pre-2022 patients (IN_BASE). The output should let these be found without reading all 4,000 rows — a per-file summary block at the top, then the detail.
- r2's 3,341 dCDT feature columns and 251 LINUS columns will dominate the NEW listing; report them as family rollups (family, n_cols, median n_raw_populated) rather than 3,592 individual rows, with the individual rows in an appendix section.

</specifics>

<deferred>
## Deferred Ideas

- Actual gap-fill joins (merging raw values into `g.analysis_base`) — Phase 17+ work, gated on PCM-D-15 approval
- 2022 ID format fix / cast application — gated on PCM-D-16 resolution; Phase 18 only diagnoses
- r7/r8 gap-fill (2022 files) — deferred until PCM-D-16 is resolved

</deferred>

---

*Phase: 18-supplemental-raw-gap-diagnostic*
*Context gathered: 2026-09-16*
