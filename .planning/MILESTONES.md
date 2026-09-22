# MILESTONES.md — PeCAN Master Dataset Integration

---

## v1 — PeCAN Master Dataset Integration Pipeline

**Shipped:** 2026-09-22
**Phases:** 1-8, 14-18 (13 active phases; Phases 1-5 pre-archived)
**Plans:** 23 (active phases), ~38 total across all phases
**Timeline:** 2026-08-25 to 2026-09-22 (28 days, 245 commits)
**SAS programs:** 37 programs, 22,319 lines of code

### Delivered

A reproducible, provenance-tracked SAS pipeline that merges eight heterogeneous master
extracts into one analysis-ready patient-level dataset, passing all QC assertions,
producing a complete data dictionary, and resolving all 14 numbered project decisions
-- runnable start-to-finish in a clean SAS session with no manual steps.

### Key Accomplishments

1. **g.master_data_merged (41,150 rows, 176 columns)** -- Eight source files merged on md3 spine with provenance flags, KEEP= ownership enforcement, MRG-06 gap-fill (five md8-donated variables, zero disagreements), and rt_envelope_flag; all 14 assertions pass
2. **g.master_data_harmonized (41,150 rows, 174 columns)** -- Eleven h_* canonical columns added via COMPGED label-similarity sweep; twelve no-information pipeline columns dropped per HARM-07 rule; h_ssdi_death added (71.2% coverage); all assertions pass
3. **g.analytic_cohort (13,890 rows, 174 columns)** -- Rebuilt from harmonized file on INPATIENT+OBSERVATION restriction; PCM-D-05 resolved with BMI-forces-restriction rationale and five documented population-shift figures
4. **DATA_DICTIONARY.xlsx (176 variables)** -- KEY sheet leftmost, UF blue (#0021A5) headers, every variable with source, type, length, coverage, and derivation; produced by 08_dictionary.sas
5. **DECISIONS.md (PCM-D-01 through D-14 resolved)** -- All 14 numbered project decisions attributed and dated; no silent code choices; includes AMENDMENT-01 (operative timestamp integrity), MRG-06 (gap-fill), and PCM-D-15 (supplemental raw integration approved)
6. **Domain-stratified statistics workbook** -- qc/17_summary_stats_by_domain.xlsx covering D1-D5 clinical domains with pooled and per-year blocks, sentinel recoding, and small-cell suppression (<=11); plus supplemental raw gap diagnostic (qc/18_gap_candidates.txt) for future extension-column decisions

### Known Gaps at Archive

- **REC-05 (PCM-D-07):** Age_at_Encounter floor investigation deliberately deferred as not pursuing; QC-05 type-sanity guard at 18 retained
- **D3 cognitive domain absent from Phase 17 workbook:** COGNITIVE_SCORE and COGNITIVE_CATEGORY not assigned instrument stat_route; one-line DATALINES fix needed before next run
- **99_run_all.sas covers Phases 1-8 only:** v1.1 programs (10b, 16b, 17, 18) not wired into single runner; expected scope boundary between pipeline delivery and post-hoc analysis

### Archives

- .planning/milestones/v1-ROADMAP.md -- Full phase details
- .planning/milestones/v1-REQUIREMENTS.md -- All requirements with final outcomes
- .planning/milestones/v1-MILESTONE-AUDIT.md -- Audit report (gaps_found -> resolved before archive)
