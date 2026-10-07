---
phase: 27-md8-row-count-correction
verified: 2026-10-07T00:00:00Z
status: human_needed
score: 9/10 must-haves verified
human_verification:
  - test: "Run sas/27_md8_count.sas in a clean SAS session and confirm log shows 'COUNT A ... = 22473 | COUNT B ... = 22473' and qc/27_md8_count.csv is written with both rows showing pass_fail=PASS"
    expected: "Log ends with '==== 27_md8_count complete -- dual count 22473 confirmed, three checks passed ====' and qc/27_md8_count.csv contains two data rows both marked PASS"
    why_human: "SAS runs against P: drive and cannot be invoked from the git sandbox; qc/27_md8_count.csv is gitignored (runtime artifact on P:) so its content cannot be read here"
  - test: "Run sas/03_prep_md8.sas (or 99_run_all.sas) in a clean SAS session after the Phase 27 edits and confirm the log shows the md8 row count assertion passes at 22,473"
    expected: "Log contains 'NOTE: OK -- md8 row count 22473 matches expected 22473' (or equivalent from %assert_row_count) with no ERROR or ABORT"
    why_human: "SAS execution against P: drive cannot be invoked from the sandbox; the cmiss drop and assertion can only be confirmed by actually running the pipeline"
---

# Phase 27: md8 Row-Count Correction Verification Report

**Phase Goal:** Make the 22,473 md8 row-count correction permanent and documented -- patch 03_prep_md8.sas to drop all-missing rows and assert 22,473, document the dual-count finding as PCM-D-31 in DECISIONS.md.
**Verified:** 2026-10-07
**Status:** human_needed (all automated checks pass; two SAS-execution checks require human confirmation)
**Re-verification:** No -- initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A standalone SAS program reports two independently derived counts of md8 non-missing rows | VERIFIED | sas/27_md8_count.sas exists, 377 lines (> min 120); contains "libname rawaim xlsx" (Count B) and the any-column sweep |
| 2 | Count A branches on src_nobs -- reads raw XLSX when src already has 22,473 rows | VERIFIED | "dictionary.tables" and "src_nobs" found in 27_md8_count.sas; branching logic confirmed |
| 3 | Count B is an independent any-column non-missing sweep via XLSX libname on the raw workbook | VERIFIED | "libname rawaim xlsx" present (1 hit); "ALL_AIM2_MASTER_DATASET_20210917.xlsx" present (9 hits) |
| 4 | SHA-256 difference pre-condition reads 19_raw_files.csv by path (not file_id) and aborts on absent master | VERIFIED | "infile" + "19_raw_files.csv" present; "index(full_path" present (4 hits); "sha_master ne ''" present; file_id=19/30 selection: 0 hits |
| 5 | Both counts equal 22,473 and the program aborts if they disagree | ? HUMAN NEEDED | 22473 string appears 15 times and %assert_eq_local with %abort cancel confirmed (11 hits); actual SAS execution result not verifiable from sandbox |
| 6 | 03_prep_md8.sas drops all-missing trailing rows before promoting g.prep_md8 | VERIFIED | "cmiss(of &md8_vars)" present; "dictionary.columns" + "md8_vars" + "n_md8_vars" present; no "_n_nonmiss" self-reference; no "data g.prep_md8; set g.prep_md8" |
| 7 | 03_prep_md8.sas asserts N = 22,473 on every pipeline run | VERIFIED | "%let expected_nobs = 22473" and "%assert_row_count(actual=&n_prep, expected=&expected_nobs, src=md8)" both confirmed present; assertion fires after drop |
| 8 | docs/DECISIONS.md contains PCM-D-31 stating trailing padding, not lost data; raw copy reference-only with different encryption | VERIFIED | "## PCM-D-31" present; "Trailing Padding, Not Truncation" present; "ROW-COUNT REFERENCE ONLY" present; "different encryption" present; "PCM-D-16" cited; "27_md8_count.csv" cited; "22,473" appears 7 times in DECISIONS.md |
| 9 | 00_ownership_rule.sas cites Phase 27 as the verified source of 22,473 (comment only, logic unchanged) | VERIFIED | "27_md8_count.sas" + "PCM-D-31" both present (1 hit each); "else if index(sources_present,'md8')" ownership logic unchanged (1 hit) |
| 10 | STATE.md performance metric reads 22,473 (not TBD) | VERIFIED | Line 123: "md8 non-missing rows | 22,473 | **22,473** | Phase 27 (MD8-01); dual count + contiguity, PCM-D-31"; no "TBD | TBD" on that row |

**Score:** 9/10 truths verified automatically; Truth 5 requires human SAS execution.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `sas/27_md8_count.sas` | Standalone dual-count + contiguity + ID-agreement verification (MD8-01) | VERIFIED | 377 lines (min 120 required); all 20 acceptance criteria pass; no PROC IMPORT; no open-code %if; ASCII only per grep checks |
| `qc/27_md8_count.csv` | Committed dual-count result (runtime artifact) | NOT IN REPO -- EXPECTED | Gitignored per `*.csv` rule; lives on P: drive; must be confirmed via human SAS run |
| `sas/03_prep_md8.sas` | Permanent all-missing-row drop + 22,473 assertion on every run (MD8-02) | VERIFIED | cmiss(of &md8_vars) drop present; dictionary.columns column list present; existing %assert_row_count and %let expected_nobs = 22473 unchanged |
| `docs/DECISIONS.md` | PCM-D-31 dual-count finding, contiguity, raw-copy-reference-only + encryption note | VERIFIED | Full PCM-D-31 block at line 946; follows PCM-D-30 heading/field format exactly |
| `sas/00_ownership_rule.sas` | Updated comment citing Phase 27 verification as source of 22,473 | VERIFIED | Parenthetical citing sas/27_md8_count.sas, Phase 27, PCM-D-31 added; no logic change |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| sas/27_md8_count.sas | src.master_data_8 | any-column non-missing sweep reusing NULL-sentinel logic | VERIFIED | "upcase(strip(" + "'NULL'" present (3 hits); "dictionary.tables" + "src_nobs" branch logic present |
| sas/27_md8_count.sas | raw\ALL_AIM2_MASTER_DATASET_20210917.xlsx | XLSX libname + same any-column sweep as Count A | VERIFIED | "libname rawaim xlsx" present; "ALL_AIM2_MASTER_DATASET_20210917.xlsx" present (9 hits) |
| sas/27_md8_count.sas | qc/19_raw_files.csv | DATA step infile, path-based row selection, SHA-256 difference pre-condition only | VERIFIED | "infile" + "19_raw_files.csv" present; "index(full_path" path-based selection (4 hits); "sha_master ne ''" abort on absent master confirmed |
| sas/03_prep_md8.sas | g.prep_md8 | drop all-missing rows then %assert_row_count against 22473 | VERIFIED | "cmiss(of &md8_vars) = &n_md8_vars then delete" present; "%assert_row_count" present |
| docs/DECISIONS.md PCM-D-31 | qc/27_md8_count.csv | cites committed dual-count result from Plan 01 | VERIFIED | "27_md8_count.csv" cited twice in DECISIONS.md (within PCM-D-31 block) |

---

### Data-Flow Trace (Level 4)

Not applicable -- phase produces SAS programs and documentation files, not web components or UI rendering dynamic data. Data flow is validated at SAS execution time (human verification item).

---

### Behavioral Spot-Checks

Step 7b: SKIPPED -- SAS programs run against P: drive and cannot be invoked from the sandbox. Behavioral confirmation is routed to human verification.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MD8-01 | 27-01-PLAN.md | Dual independent count confirming md8 true N = 22,473 | VERIFIED (code) / HUMAN (execution) | sas/27_md8_count.sas complete with all structural checks passing; SAS execution result requires human confirmation |
| MD8-02 | 27-02-PLAN.md | Permanent all-missing-row drop + per-run 22,473 assertion in 03_prep_md8.sas | VERIFIED (code) / HUMAN (execution) | cmiss drop and %assert_row_count confirmed in code; pipeline run result requires human confirmation |

---

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| None | -- | -- | No TODO/FIXME/placeholder/return null patterns found in any modified file |

---

### Human Verification Required

#### 1. Run sas/27_md8_count.sas -- Confirm dual-count PASS result

**Test:** In a clean SAS session, run `sas/27_md8_count.sas`. Inspect the log.
**Expected:** Log shows the side-by-side line "NOTE: md8 COUNT A ... = 22473 | COUNT B (raw XLSX) = 22473", all four %assert_eq_local calls emit "NOTE: OK", and the final line reads "NOTE: ==== 27_md8_count complete -- dual count 22473 confirmed, three checks passed ====". Also confirm `qc/27_md8_count.csv` is written on P: drive with two data rows both showing `pass_fail=PASS`.
**Why human:** SAS runs against P: drive and cannot be invoked from the git sandbox. `qc/27_md8_count.csv` is gitignored (`*.csv`) so its content is not available in the repo.

#### 2. Run 03_prep_md8.sas (or 99_run_all.sas) -- Confirm cmiss drop + assertion pass

**Test:** In a clean SAS session, run `sas/03_prep_md8.sas` (or the full `99_run_all.sas`). Inspect the log around the md8 section.
**Expected:** Log confirms the PROC SQL column list runs without error, the `cmiss(of &md8_vars) = &n_md8_vars then delete` step executes inside the `data g.prep_md8` step, and `%assert_row_count` emits "NOTE: OK -- md8 row count 22473 matches expected 22473" (or equivalent). No ABORT or ERROR lines in the md8 section.
**Why human:** SAS pipeline execution against P: drive cannot be invoked from the sandbox. The cmiss drop correctness (that no real data rows are deleted) can only be confirmed by actually running the program against `src.master_data_8`.

---

### Gaps Summary

No automated gaps. All code-level checks pass: sas/27_md8_count.sas is complete (377 lines, all 20 acceptance criteria verified), sas/03_prep_md8.sas has the cmiss drop and unchanged assertion, docs/DECISIONS.md has the full PCM-D-31 block, sas/00_ownership_rule.sas has the comment citation, and .planning/STATE.md has the metric updated.

The only outstanding items require SAS execution on P: drive to confirm the programs actually run cleanly and produce the expected counts. The 27-02-SUMMARY.md notes the gate (qc/27_md8_count.csv must show PASS before PCM-D-31 is finalized) was assumed-complete based on the user's review commit prior to Plan 02 execution. If the SAS run has not been performed, it must be done before Phase 27 is considered fully closed.

---

_Verified: 2026-10-07_
_Verifier: Claude (gsd-verifier)_
