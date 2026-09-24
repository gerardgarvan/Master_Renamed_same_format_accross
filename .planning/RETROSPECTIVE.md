# RETROSPECTIVE.md — PeCAN Master Dataset Integration

---

## Milestone: v1 -- PeCAN Master Dataset Integration Pipeline

**Shipped:** 2026-09-22
**Phases:** 13 active phases (1-8, 14-18) | **Plans:** 23

### What Was Built

- Eight-source SAS merge pipeline on md3 spine with KEEP= ownership enforcement, provenance flags, and rt_envelope_flag (Phases 1-8)
- Operative timestamp integrity amendment: PREP-08 flag-dont-null, QC-06 unflagged containment assertion, full Phase 3->4->5 re-run (AMENDMENT-01)
- MRG-06 gap-fill: five md8-donated variables recovered with zero disagreements, resolving PCM-F-18
- COMPGED label-similarity sweep: found no new pairs beyond name-match, but established the structural capability (Phase 14)
- HARM-07 pipeline-column rule: twelve no-information columns (in_md3 + eleven h_*_src) dropped from g.master_data_harmonized (Phase 15)
- h_ssdi_death harmonized: 29,316 values (71.2% coverage) added to g.master_data_harmonized (Phase 15)
- g.analytic_cohort rebuilt from g.master_data_harmonized: 13,890 rows, 174 columns, PCM-D-05 resolved with five population-shift figures (Phase 16)
- Domain-stratified descriptive statistics: D1-D5 workbook with pooled and per-year blocks, sentinel recoding, small-cell suppression (Phase 17)
- Supplemental raw gap diagnostic: 2022 ID mismatch diagnosed; per-column gap-fill candidate table for r1-r9; D15 approved (Phase 18)

### What Worked

- **Assertion-first design:** The pattern of writing `%assert_eq`, `%assert_harm07`, and `assert_complete_case_n` macros before any data transformation made every new run self-documenting. Failures were loud and immediate.
- **PCM-D-XX numbering system:** Naming every decision with a sequential ID and requiring attribution to a person and date prevented any silent code choices across 28 days and 245 commits.
- **AMENDMENT-01 protocol:** When QC-05 aborted on rt_INCISE_to_DRESS_mins, the amendment was documented, plans were written (03-06, 05-03), and the re-run chain (03->04->05) was executed cleanly. No data was lost; the flag-dont-null resolution (PCM-D-08) was defensible.
- **Phase 14 label sweep before Phase 15 application:** The COMPGED sweep ran first and explicitly found nothing new to harmonize. The negative result was a clean record that Phase 15 did not need to guess.
- **Checkpoint-gated deliverables:** Checkpoint 2 in Phase 17 and the human-UAT pattern in Phase 18 meant Gerard reviewed workbook output before any plan was marked complete.

### What Was Inefficient

- **PCM-F-17 was false and was withdrawn:** The md3-owns cost check omitted md8, the largest non-spine source. The error required a Phase 4 re-run and partial Phase 5 re-run. A systematic sweep of all 578 owner/donor combinations upfront would have caught this without backtracking.
- **REQUIREMENTS.md staleness:** COH-01 through COH-04, DOC-02 through DOC-04, HARM-04, HARM-07 accumulated as unchecked [  ] entries for weeks after being satisfied. The final audit commit (3d2a83d) had to tick 12 checkboxes at once. A light per-plan checkbox pass would have prevented this accumulation.
- **Phase 14 VERIFICATION.md was gaps_found after Phase 15 proved the gap was closed:** The verification artifact was not re-run after Phase 15 confirmed the CSV files existed. This created unnecessary audit noise (eaf1c8e corrected it). A rule: re-verify any phase whose VERIFICATION.md references a downstream phase.
- **QC-04 target was wrong at first:** The original "exactly 22,473" target for md8-owned variables was incorrect; within-md8 population varies by design (monitoring equipment availability). The metric was changed to log-not-assert after Phase 5 re-analysis.

### Patterns Established

- `%assert_eq(actual, expected, label)` macro pattern for loud-abort assertions
- `qclib.ownership_map` as the single source of truth for variable ownership, read at merge-time (never hand-transcribed)
- `concept_decisions.csv` pattern: human confirms -> program applies exactly that -> FAILS on anything unmapped
- COMPGED threshold of <= 50 for label similarity candidates (human judgment still required for all pairs)
- `%abort cancel` returns exit code 3 on Windows batch (PCM-D-12); `-sasuser WORK` required in headless runs
- HARM-07: pipeline-derived columns (in_md3 + h_*_src) are categorically no-information and should be dropped after harmonization
- PCM-T-12: for ownership questions, enumerate every candidate -- spot checks answered wrong twice on the same question

### Key Lessons

1. **Sweep, do not sample.** PCM-T-12 states this explicitly: spot checks produced the wrong answer twice on md3-owns questions. Enumerate every candidate combination.
2. **Name findings when they emerge.** PCM-F-18 and PCM-F-19 were added mid-project and immediately prevented wrong decisions (PCM-D-05 re-decision). A finding left unnamed gets forgotten.
3. **Impossible VALUES and impossible COMBINATIONS require different remedies.** Nulling an impossible value is correct (PREP-08). Nulling an impossible combination destroys good values to punish an unidentifiable one -- flag instead (PCM-D-08, MRG-05).
4. **A bound that has never fired and cannot fire is not a check.** QC-07 removed three operative-interval ceilings that were tautologically satisfied. These were noise masking the signal of the five real assertions.
5. **Checkpoint approval locks scope.** Checkpoint 2 in Phase 17 acknowledged the D3 absence and approved the workbook anyway. That decision is now documented and attributed, not an ambiguous gap.

### Cost Observations

- Model: Claude Sonnet (claude-sonnet-4-6) throughout
- Sessions: ~20 agent sessions over 28 days
- Notable: The largest context cost was reading ROADMAP.md at session start for every phase; the v1 archive eliminates this overhead for v2

---

## Milestone: v2.0 -- pecan_ID + Raw Directory Inventory

**Shipped:** 2026-09-24
**Phases:** 3 (19, 20, 21) | **Plans:** 6 | **Tasks:** 15

### What Was Built

- Complete raw directory inventory: recursive file listing with SHA-256 checksums, variable-level profiling (pct_missing, pct_sentinel), key-column flags (PRECEDE_STUDY_ID/ENCRYPTED_MRN/ENCRYPTED_ENCOUNTER), reconciliation against known sources (Phase 19)
- pecan_ID derivation: source audit, append-only crosswalk (g.pecan_id_xwalk) per PCM-D-17, cardinality assertions, PID-07 linkage reach report for all MRN-carrying raw files including r7/r8/r9 (Phase 20)
- pecan_ID attached to g.master_data_harmonized and g.analytic_cohort (10b, 16b) with PID-05/PID-06 assertions; pecan_ID explicit row added to DATA_DICTIONARY.xlsx (Phase 20)
- D3 cognitive domain fix: DOMAIN_MAP_APPROVED=1 (PCM-D-19), program 17 redirected from P:-drive g.analysis_base to pipeline-produced g.analytic_cohort (PCM-D-20) (Phase 21)
- run_pipeline.cmd batch driver: 14 separate sas.exe invocations in order, exit-code gating (>=2 = STOP), in_pipeline=1 auto-detection via envlen(RUN_ALL) in 00_config.sas (Phase 21)
- Full end-to-end pipeline run on second machine confirmed PASSED (Phase 21 acceptance test)

### What Worked

- **certutil pipe pattern reuse:** The SHA-256 checksum method from Phase 19 was reused without modification in Phase 20 (PID-01). Establishing the pattern in one phase and citing it in the next eliminated design time.
- **PCM-D-17/D-18 resolved before execution:** Both open decisions were resolved at discussion time, not discovered mid-plan. Plans could be written with concrete crosswalk build and attachment logic rather than placeholders.
- **WORK-then-promote join pattern (10b):** Attaching pecan_ID in 10b required working around an opaque macro (%build_harmonized). The WORK-then-promote fallback (create work.harmonized_with_pid, then DATA g.master_data_harmonized; set work.harmonized_with_pid) was correct and well-documented.
- **run_pipeline.cmd stop-path test design:** The verification checkpoint asked for a stop-path test (scratch copy with single abort program) before the full run. This would have caught ERRORLEVEL handling failures early without needing to run 14 programs.
- **Cross-machine testing exposed the SAS_EXE path gap:** Running on a second machine immediately found the SASHome vs SAS94 install path difference. The fix was trivial once found; testing on the target machine before sign-off is now the pattern.

### What Was Inefficient

- **REQUIREMENTS.md not updated incrementally during Phase 20:** PID-01 through PID-08 were completed across Phase 20 Plans 01 and 02, but the checkboxes were never ticked in REQUIREMENTS.md. The milestone pre-flight had to reconcile 8 stale unchecked entries against SUMMARY.md evidence. Per-plan checkbox pass at plan completion would prevent this.
- **SAS_EXE hardcoded to SASHome in run_pipeline.cmd:** The batch driver was written and committed against the dev machine path. A cross-machine test immediately required a fix commit. Parameterizing SAS_EXE via an environment variable or prompting at first run would eliminate this fragility.
- **OBS=0 error in 16b cascaded from open-code %local/%if:** The root cause (invalid open-code macro statement setting OBS=0) produced a cascade of confusing secondary errors (%put ERROR 180-322, blank assert values) that looked unrelated. The pattern is now in the trap list: %LOCAL and %IF in open code are not valid in SAS; use %SYSFUNC(IFC()) instead.

### Patterns Established

- `certutil -hashfile INFILE SHA256 | PIPE | FILENAME fileref PIPE` pattern for in-SAS checksum via OS command
- `PROC APPEND` with two-way NOT EXISTS guard for append-only crosswalk (prevents duplicate assignment on re-run)
- ISO-dated backup naming with `%sysfunc(datetime(), B8601DT15.)` for chronologically sortable SAS dataset names
- `CALL EXECUTE` loop for per-file linkage reach processing when file count is dynamic
- `envlen(RUN_ALL)` check in 00_config.sas for automatic in_pipeline detection from batch driver
- `setlocal EnableDelayedExpansion` + `!ERRORLEVEL!` (not `%ERRORLEVEL%`) for reliable exit-code capture in Windows batch
- WORK-then-promote for joining into datasets produced by opaque macros (avoids the DATA step re-entry problem)

### Key Lessons

1. **Tick requirement checkboxes at plan completion, not milestone end.** REQUIREMENTS.md staleness created reconciliation work at milestone close. The executor should check the relevant requirement IDs from the plan frontmatter at SUMMARY.md creation time.
2. **Machine-specific paths belong in an env var, not in the committed file.** SAS_EXE in run_pipeline.cmd should be overridable without a code edit. A `set SAS_EXE` at the top with a comment ("edit if different") is not enough — a first-run prompt or `%~dp0config.cmd` include would be better.
3. **OBS=0 cascades hide the root cause.** When SAS sets OBS=0 due to an error, all subsequent errors are symptoms. Always search for the FIRST error in the log, not the most visible one.
4. **Test on the target machine before the checkpoint.** run_pipeline.cmd worked on the dev machine. The first cross-machine run found the path problem immediately. The checkpoint should have included "run on all target machines" as an explicit step.

### Cost Observations

- Model: Claude Sonnet (claude-sonnet-4-6) throughout
- Sessions: ~4 sessions over 2 days (2026-09-23 to 2026-09-24)
- Notable: v2.0 was substantially smaller than v1 (3 phases vs 13); the main complexity was the cross-machine batch driver verification and the 16b OBS=0 debug cycle

---

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Key Pattern |
|-----------|--------|-------|----------|-------------|
| v1 | 13 | 23 | 28 days | Assertion-first design; amendment protocol for mid-project corrections |
| v2.0 | 3 | 6 | 2 days | certutil checksum reuse; cross-machine batch driver testing |
