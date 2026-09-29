# Phase 25: pcnr Cohort, Dictionary & Wiring - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Subset `g.pcnr_harmonized` → `g.pcnr_analytic_cohort` (PCM-D-05 restriction);
produce `PCNR_DICTIONARY.xlsx`; wire programs 23/24/25 into `run_pipeline.cmd`;
record PCM-D-26 resolution; update `docs/DECISIONS.md`.

Programs: `sas/25_pcnr_cohort.sas` (cohort + dictionary + QC N table); runner edits to
`run_pipeline.cmd`.

Deliverables:
- `g.pcnr_analytic_cohort` — 13,890 rows; PRECEDE_STUDY_ID set identical to `g.analytic_cohort`
- `qc/25_complete_case_n.csv` — before/after complete-case Ns for BMI/Cognitive/Frailty/all-three
- `qc/PCNR_DICTIONARY.xlsx` — KEY + VARIABLES + RECODES + COHORT_N sheets; UF blue headers
- `qc/25_pcnr_variables.csv` — machine-readable copy of the VARIABLES sheet
- `run_pipeline.cmd` wires 23, 24, 25 (after 16b); full end-to-end run PASS with `PCNR_APPROVED = 1`
- `docs/DECISIONS.md` gains PCM-D-26 (PCM-D-21..25 and 27 were written in Phase 23; confirm, do not duplicate)

</domain>

<decisions>
## Implementation Decisions

### D-01: PCM-D-26 — Program 17 Input: Not Repointed in v2.1

Program 17 stays on `g.analytic_cohort` in v2.1. Do NOT redirect it to `g.pcnr_analytic_cohort`.

Reasons:
- Every column name changes to `pcnr_*`, requiring the domain map behind `DOMAIN_MAP_APPROVED`
  to be rebuilt and re-approved — that is substantive analytical work, not wiring.
- Recoded values (e.g., 4,586 EmployeeStatus "Unknown" → missing; 758 race refused/unknown → missing)
  change reported statistics: denominators and category percentages shift.
- These are changes in results that require Gerard + Price sign-off before they ship.

Record in DECISIONS.md as:
> **PCM-D-26 (v2.1 resolution):** Program 17 reads `g.analytic_cohort` unchanged.
> Repointing to `g.pcnr_analytic_cohort` deferred; requires domain map re-approval and
> result review with Price before implementation. If needed sooner, a separate `17b` reading
> the pcnr cohort could run alongside.

Program 25 makes no changes to `sas/17_summary_stats_by_domain.sas`.

### D-02: Dictionary — Standalone PCNR_DICTIONARY.xlsx in qc/

Produce a new file `qc/PCNR_DICTIONARY.xlsx` (on P: merge tree, not in `docs/`). Do NOT
modify the existing `docs/DATA_DICTIONARY.xlsx` generator (`08_dictionary.sas`).

Sheet structure (KEY sheet leftmost):
1. **KEY** — what each sheet and column in the workbook means
2. **VARIABLES** — one row per pcnr column: `pcnr_name`, `source_name`, `role`, `label`, `type`,
   `length`, `n_recoded` (from `qc/24_pcnr_recode_totals.csv`), `n_missing_after`
3. **RECODES** — rule-level detail from `qc/24_pcnr_recode_counts.csv` (one row per MISSING rule)
4. **COHORT_N** — the PCNR-13 before/after complete-case N table (same data as
   `qc/25_complete_case_n.csv`)

Formatting:
- UF blue (#0021A5) column headers, frozen panes, autofilter on VARIABLES and RECODES
- Use `ODS EXCEL` + `styles.uf_inventory` (same pattern as existing ODS Excel outputs)

Also write `qc/25_pcnr_variables.csv` — the VARIABLES sheet as a machine-readable flat file.
Read this file in the planner and executor with a DATA step `infile` using explicit `$` informats
(PCM-T-16 — never PROC IMPORT).

Location rationale: `qc/` on P: keeps it alongside other generated QC outputs; `docs/` is
for human-owned gate files and the existing DATA_DICTIONARY (which lives on P: too).
Since the file contains only column metadata (no row-level data), there is no PHI concern.

### D-03: Runner Wiring — Programs 23, 24, 25; Insert After 16b

Wire all three new programs in `run_pipeline.cmd`, in order: 23 → 24 → 25.

**Insert position: after `16b_cohort_rebuild.sas`, before `17_summary_stats_by_domain.sas`.**
(Corrected 2026-09-28: the earlier "after 10b, before 16b" placed 25 before 16b, but program 25
reads `g.analytic_cohort`, which 16b writes -- 25 would have compared against the PREVIOUS run's
cohort. 16b only reads `g.master_data_harmonized`, so running 23 after 16b keeps the modate
reasoning below intact.)

Do NOT insert after program 20. The reason:
- Program 10b reads `g.master_data_harmonized` and WORK-then-promotes it, changing its `modate`.
- Program 23 writes `qc/23_sentinel_fingerprint.txt` with the current nobs/nvars/modate.
- If 23 runs before 10b, the fingerprint reflects the pre-10b modate; 10b then changes it;
  program 24's gate aborts every subsequent run on the fingerprint check.
- 23 must run AFTER 10b so it captures the post-10b modate that will remain stable.
- 25 must run AFTER 16b because it reads `g.analytic_cohort` (n_before and the ID-set check).

Final program order in runner (other programs, e.g. 19b if wired in Phase 22, keep their places):
```
01 02 03 04 05 06 07 08
19 20
10b
16b
23 24 25
17 18
```

Program 23 is a full pipeline participant (not a run-once checkpoint): re-running it on each
pipeline pass is correct and by design — it re-reads `g.master_data_harmonized` and refreshes
the fingerprint and draft CSVs. The human-owned `docs/` files are unchanged by program 23.

**Also add `options errorabend;` for `in_pipeline = 1`** in program 25 (and confirm it is
present in 23 and 24 if not already). It must be set immediately after the `00_config.sas`
include and BEFORE any gate check -- the Phase 24 test run showed a gate whose `%if` errors
fails open and lets later sections run. The config `%include` itself must be in OPEN CODE,
never inside a macro (a macro-wrapped include makes every config variable local).

### D-04: PCNR-13 Output — QC CSV with Assertions

Write `qc/25_complete_case_n.csv` with columns:
`measure, n_before, n_after, n_difference`

Measures: `pcnr_Admit_BMI`, `pcnr_Cognitive_Score`, `pcnr_Frailty_Score`, `all_three`.
`n_before` = complete-case N in `g.analytic_cohort` (benchmarks: 12,726 / 7,252 / 8,150 / 6,523).
`n_after` = complete-case N in `g.pcnr_analytic_cohort`.
`n_difference = n_before - n_after`. Admit_BMI, Cognitive_Score and Frailty_Score are numeric
and PCM-D-24 approved no numeric recodes, so every n_difference must currently be 0; program 25
asserts n_difference = 0 for a measure whenever `qc/24_pcnr_recode_totals.csv` shows 0 recodes
for its column(s), and n_after <= n_before otherwise.

Two assertions (both use `%fail_out` on failure):
1. `n_after <= n_before` for every measure — recoding only adds missing, never fills them.
2. Both cohorts are exactly 13,890 rows with an identical PRECEDE_STUDY_ID set.

Assertion 2 matters because the PCM-D-05 filter now runs on `pcnr_Patient_Type` (where `?`
values have been recoded to missing). The filter must still select exactly the same 13,890
INPATIENT + OBSERVATION rows — assert it rather than assume it.

Reproduce the COHORT_N sheet in the dictionary from this same CSV (read via DATA step `infile`,
not PROC IMPORT — PCM-T-16).

### D-05: Program 25 Structure

Single file `sas/25_pcnr_cohort.sas`. Sections:

```
SECTION 0: Options, log redirect, %fail_out macro, errorabend for pipeline
SECTION 1: Subset g.pcnr_harmonized → work._pcnr_cohort_candidate (Patient_Type filter)
SECTION 2: Assertions (N = 13,890; PRECEDE_STUDY_ID set identity; source unchanged)
SECTION 3: WORK-then-promote → g.pcnr_analytic_cohort
SECTION 4: Compute complete-case Ns before (from g.analytic_cohort) and after
SECTION 5: Assertions on n_after ≤ n_before; write qc/25_complete_case_n.csv
SECTION 6: Build PCNR_DICTIONARY.xlsx (KEY + VARIABLES + RECODES + COHORT_N)
SECTION 7: Write qc/25_pcnr_variables.csv
```

Follow the same structure as `sas/16b_cohort_rebuild.sas` for Sections 0–3.
The dictionary is generated by program 25 alone — do not extend `08_dictionary.sas`.

Static checks (include in plan acceptance criteria):
- `grep -ni "proc import" sas/25_pcnr_cohort.sas` → expect 0
- `grep -c '\$hex\.' sas/25_pcnr_cohort.sas` → expect 0
- `grep -ni "%put WARNING" sas/25_pcnr_cohort.sas` → expect 0

### Claude's Discretion

- Exact ODS EXCEL syntax for PCNR_DICTIONARY.xlsx (follow `sas/08_dictionary.sas` pattern)
- Whether n_missing_after in the VARIABLES sheet is computed inside program 25 or read from an
  intermediate summary (compute inline — one PROC SQL pass over `g.pcnr_analytic_cohort`)
- Log verbosity: `%put NOTE:` at section transitions (match existing program pattern)
- Whether `qc/25_pcnr_variables.csv` uses fixed-width or delimited format (delimited; match
  the `qc/24_pcnr_recode_totals.csv` format convention)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements
- `.planning/REQUIREMENTS.md` §pcnr Cohort, Dictionary & Wiring — PCNR-12 through PCNR-17

### Prior phase context (decisions locked there)
- `.planning/phases/24-build-g-pcnr-harmonized/24-CONTEXT.md` — recode counts schema, gate files, PCM-T-16, WORK-then-promote
- `.planning/phases/23-sentinel-name-inventory/23-CONTEXT.md` — name map schema, role values (KEY/KEEP/DROP), pcnr_name derivation

### Existing pipeline programs (patterns to follow)
- `sas/00_config.sas` — `%fail_out`, `%hexkey`, `PCNR_APPROVED` gate, `in_pipeline` flag, `errorabend` pattern
- `sas/16b_cohort_rebuild.sas` — cohort subsetting structure: Section 0 options/log/macros, filter step, assertions, WORK-then-promote; model for program 25 Sections 0–3
- `sas/08_dictionary.sas` — ODS EXCEL structure, KEY sheet leftmost pattern, `styles.uf_inventory`, UF blue headers; model for the dictionary sections of program 25
- `run_pipeline.cmd` — current runner; Phase 25 adds programs 23, 24, 25 (count may include 19b from Phase 22)

### QC inputs (program 25 reads these)
- `qc/24_pcnr_recode_totals.csv` — per-variable n_recoded_total; feeds VARIABLES sheet
- `qc/24_pcnr_recode_counts.csv` — rule-level detail; feeds RECODES sheet
- `docs/pcnr_name_map.csv` — pcnr_name, source_name, role, label; feeds VARIABLES sheet

### Source datasets
- `g.pcnr_harmonized` — 41,150 rows; produced by program 24 (read-only in program 25)
- `g.analytic_cohort` — 13,890 rows; read-only; used only to compute n_before benchmarks

### Decisions log
- `docs/DECISIONS.md` — PCM-D-21 through PCM-D-26 recorded here; read existing format before writing new entries

No external specs — requirements fully captured in REQUIREMENTS.md and prior CONTEXT.md files.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/16b_cohort_rebuild.sas` — Section 0 boilerplate (options, log redirect, `%fail_out`, pipeline guard) is a direct template for program 25 Sections 0–3
- `sas/08_dictionary.sas` — ODS EXCEL + `styles.uf_inventory` pattern; KEY sheet leftmost; UF blue headers; frozen panes; adapt for the four-sheet PCNR workbook
- `sas/00_config.sas` `%fail_out` macro — standard abort path; use throughout assertions
- `sas/20_pecan_id.sas` — example of reading a `docs/` gate file via DATA step `infile` with `$` informats (PCM-T-16)

### Established Patterns
- WORK-then-promote: `data g.pcnr_analytic_cohort; set work._pcnr_cohort_candidate; run;`
- PCM-C-05: each program runs as a separate `sas.exe` session; no shared WORK across programs
- PCM-T-16: never PROC IMPORT gate files or QC CSVs — always DATA step `infile` with explicit `$` informats
- `errorabend` for `in_pipeline = 1` (Phase 22 pattern — confirm in 23 and 24 too)
- No `%put WARNING` lines — scanner counts them (use `%put NOTE:` or `%put ERROR:`)
- All counts via `SELECT COUNT(*) INTO :macvar TRIMMED` (never automatic row-count macros)

### Integration Points
- `run_pipeline.cmd` — insert programs 23, 24, 25 after `16b_cohort_rebuild.sas`, before `17_summary_stats_by_domain.sas`
- `sas/00_config.sas` — `PCNR_APPROVED` flag (default 0; flip to 1 after gate files confirmed); `in_pipeline` detection
- `g` libname — `g.pcnr_analytic_cohort` promoted here; `g.analytic_cohort` and `g.pcnr_harmonized` read here
- `qc/` on P: — all outputs land here (PCNR_DICTIONARY.xlsx, 25_complete_case_n.csv, 25_pcnr_variables.csv)

</code_context>

<specifics>
## Specific Ideas

- **PCM-D-26 note for DECISIONS.md:** Record as "not repointed in v2.1; revisit once pcnr_analytic_cohort is in use and domain map is re-approved with Price." A separate 17b program reading the pcnr cohort is the preferred path if recoded statistics are needed sooner.
- **Runner insert point:** After 16b (which is after 10b) — 10b changes modate of g.master_data_harmonized, and 25 reads 16b's g.analytic_cohort. Planner must verify by reading `run_pipeline.cmd` and confirming the position.
- **Actual CSV schemas program 25 reads (verified against the files):**
  - `docs/pcnr_name_map.csv`: source_name, source_label, role, h_strip, proposed_name, override_name, final_name, name_len, collision_flag, id_flag (final_name BLANK for KEY/DROP)
  - `qc/24_pcnr_recode_totals.csv`: variable, final_name, n_recoded_total
  - `qc/24_pcnr_recode_counts.csv`: variable, final_name, raw_value, raw_hex, var_type, rule_source, n_expected, n_recoded
- **DECISIONS.md numbering:** Phase 23 already wrote PCM-D-21..D-25 and PCM-D-27 (column scope, renumbered from D-25 to keep REQUIREMENTS' meaning of D-25 = companion columns). Phase 25 adds PCM-D-26 only and must not duplicate or rewrite the others.
- **Complete-case N benchmarks** (n_before values to assert against):
  `pcnr_Admit_BMI = 12,726`, `pcnr_Cognitive_Score = 7,252`, `pcnr_Frailty_Score = 8,150`, `all_three = 6,523`.
  These are the within-cohort Ns from `g.analytic_cohort` as of v2.0; the planner may re-derive from
  STATE.md or `qc/` files.
- **Cognitive_Score = 0 forward note:** If PCM-D-24 is later updated to recode Cognitive_Score = 0 as MISSING, the Cognitive N in `qc/25_complete_case_n.csv` will drop visibly — this table is the right place to catch it.
- **PCNR_DICTIONARY.xlsx vs git:** The file lives on P: and has no PHI; committing is optional. The machine-readable `qc/25_pcnr_variables.csv` is also on P: (covered by `*.csv` gitignore). No force-add needed.

</specifics>

<deferred>
## Deferred Ideas

- **Program 17b (recoded stats):** A separate program reading `g.pcnr_analytic_cohort` for summary statistics, so both pre- and post-recode outputs exist side by side. Deferred to v2.2 — requires domain map re-approval with Price.
- **Repointing program 17 to pcnr cohort (PCM-D-26):** Deferred to v2.2+ pending domain map rebuild and result review with Price.

</deferred>

---

*Phase: 25-pcnr-cohort-dictionary-wiring*
*Context gathered: 2026-09-28*
