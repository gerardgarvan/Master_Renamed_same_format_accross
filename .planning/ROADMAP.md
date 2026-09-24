# ROADMAP.md — PeCAN Master Dataset Integration

## Milestones

- ✅ **v1** — PeCAN Master Dataset Integration Pipeline (Phases 1-8, 14-18) — shipped 2026-09-22
  Archive: .planning/milestones/v1-ROADMAP.md
- ✅ **v2.0** — pecan_ID + Raw Directory Inventory (Phases 19-21) — shipped 2026-09-24
  Archive: .planning/milestones/v2.0-ROADMAP.md
- 🚧 **v2.1** — pcnr_ Clean Analysis Dataset (Phases 22-25) — in progress

---

## Phase Progress

<details>
<summary>✅ v1 PeCAN Master Dataset Integration Pipeline (Phases 1-8, 14-18) — SHIPPED 2026-09-22</summary>

| Phase | Name | Plans Complete | Status | Completed |
|-------|------|---------------|--------|-----------|
| 1 | Source Verification & Freeze | 2/2 | Complete | 2026-08-26 |
| 2 | Ownership Map | 2/2 | Complete | 2026-08-26 |
| 3 | Per-Source Normalization | 6/6 | Complete | 2026-09-14 |
| 4 | Merge | 2/2 | Complete | 2026-08-27 |
| 5 | Merge QC | 3/3 | Complete | 2026-09-14 |
| 6 | Variable Reconciliation | 3/3 | Complete | 2026-09-14 |
| 7 | Cohort & Missingness | 2/2 | Complete | 2026-09-22 |
| 8 | Documentation & Handoff | 3/3 | Complete | 2026-09-22 |
| 14 | Label-Similarity Sweep | 2/2 | Complete | 2026-09-21 |
| 15 | Extend the Harmonized Dataset | 2/2 | Complete | 2026-09-21 |
| 16 | Rebuild the Analytic Cohort | 2/2 | Complete | 2026-09-22 |
| 17 | Summary Stats by Domain | 4/4 | Complete | 2026-09-22 |
| 18 | Supplemental Raw Inventory | 2/2 | Complete | 2026-09-22 |

</details>

<details>
<summary>✅ v2.0 pecan_ID + Raw Directory Inventory (Phases 19-21) — SHIPPED 2026-09-24</summary>

| Phase | Name | Plans Complete | Status | Completed |
|-------|------|----------------|--------|-----------|
| 19 | Raw Directory Inventory | 2/2 | Complete | 2026-09-23 |
| 20 | pecan_ID Derivation | 2/2 | Complete | 2026-09-23 |
| 21 | Runner Wiring & D3 Fix | 2/2 | Complete | 2026-09-24 |

**Known gap:** INV-07 (workbook formatting — UF colors, KEY sheet legend, FAMILIES sheet) deferred to v2.1

</details>

### 🚧 v2.1 pcnr_ Clean Analysis Dataset (Phases 22-25)

**Goal:** `g.pcnr_harmonized` and `g.pcnr_analytic_cohort`, fully derived from
`g.master_data_harmonized`, with placeholder values (`?`, `Unknown`, ...) set to missing
and every analysis variable renamed `pcnr_<original name>`. Source datasets untouched;
every recoded cell counted and traceable to an approved decision.

| Phase | Name | Requirements | Depends on | Status |
|-------|------|--------------|------------|--------|
| 22 | Pipeline Green & Hardening | FIX-02, RUN-02, RUN-03, INV-07, DOC-05 | — | Not started |
| 23 | Sentinel & Name Inventory | PCNR-01..06 | 22 (FIX-02) | Not started |
| 24 | Build g.pcnr_harmonized | PCNR-07..11 | 23 + PCNR_APPROVED=1 | Not started |
| 25 | pcnr Cohort, Dictionary & Wiring | PCNR-12..17 | 24 | Not started |

#### Phase 22: Pipeline Green & Hardening

**Goal:** A clean full `run_pipeline.cmd` run before anything new is added. The 2026-09-24
run stopped at 16b, and every v2.1 program runs after 16b.

**Success criteria:**
1. Full run exits clean; 16b writes `qc/16b_pecan_id_counts.txt` and 12 `h_within_cohort_*` lines
2. Program 20 log carries no `SHA-256 FAILED` warning; `work._sha_md3` has 1 row
3. Runner warning counts reflect real warnings only (10b = 0)
4. `SAS_EXE` set per machine without a code edit
5. `qc/19_raw_inventory.xlsx` in UF colors with KEY sheet leftmost (INV-07)

**Note:** INV-07 is independent and can run in parallel with the rest of the phase.

#### Phase 23: Sentinel & Name Inventory

**Goal:** Evidence, then decisions. Every candidate placeholder value and every name that
cannot take the prefix is enumerated and put in front of a human before any value changes.

**Program:** `sas/23_pcnr_inventory.sas` (read-only against `g.master_data_harmonized`)

**Success criteria:**
1. `qc/23_sentinel_candidates.csv` covers every character column (sweep, not sample)
2. Numeric sentinel scan and ambiguous-value report produced; nothing recoded
3. `docs/pcnr_name_map.csv` complete; all names 32 characters or fewer and unique
4. `docs/sentinel_decisions.csv` has a decision for every candidate; `PCNR_APPROVED=1`
5. PCM-D-21..D-25 resolved and attributed

**Checkpoint:** human review of the candidate list and name map (Gerard; Price for D-21, D-24, D-25).

#### Phase 24: Build g.pcnr_harmonized

**Goal:** Apply exactly the approved decisions and prove nothing else changed.

**Program:** `sas/24_pcnr_build.sas`

**Success criteria:**
1. `g.pcnr_harmonized`: 41,150 rows, same column count as the source, keys identical
2. Per variable: missing after = missing before + recoded, exactly
3. Every non-recoded cell identical to source (full comparison)
4. Zero remaining approved-sentinel values
5. `qc/24_pcnr_recode_counts.csv` written; source confirmed unmodified

#### Phase 25: pcnr Cohort, Dictionary & Wiring

**Goal:** The clean dataset is usable end to end: cohort, documentation, runner, and the
downstream summary program.

**Program:** `sas/25_pcnr_cohort.sas`; dictionary via `08_dictionary.sas` extension or a
new program (decided in the plan)

**Success criteria:**
1. `g.pcnr_analytic_cohort`: N = 13,890, same `PRECEDE_STUDY_ID` set as `g.analytic_cohort`
2. Complete-case N differences explained exactly by recode counts
3. pcnr dictionary with KEY sheet leftmost and UF blue headers
4. `run_pipeline.cmd` runs 16 programs; full run PASS on both target machines
5. Program 17 input resolved (PCM-D-26); DECISIONS.md updated

---

*Next: `/gsd:discuss-phase 22` (or `/gsd:plan-phase 22`)*
