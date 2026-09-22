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

## Cross-Milestone Trends

| Milestone | Phases | Plans | Duration | Key Pattern |
|-----------|--------|-------|----------|-------------|
| v1 | 13 | 23 | 28 days | Assertion-first design; amendment protocol for mid-project corrections |
