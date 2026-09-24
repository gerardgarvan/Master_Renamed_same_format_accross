# ROADMAP.md — PeCAN Master Dataset Integration

## Milestones

- ✅ **v1** — PeCAN Master Dataset Integration Pipeline (Phases 1-8, 14-18) — shipped 2026-09-22
  Archive: .planning/milestones/v1-ROADMAP.md
- ✅ **v2.0** — pecan_ID + Raw Directory Inventory (Phases 19-21) — shipped 2026-09-24
  Archive: .planning/milestones/v2.0-ROADMAP.md

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

---

## v2.1 Pipeline Green & Hardening (Phase 22) -- IN PROGRESS

| Phase | Name | Plans Complete | Status | Completed |
|-------|------|----------------|--------|-----------|
| 22 | Pipeline Green & Hardening | 1/3 | In Progress | -- |

### Phase 22 Plan Progress

| Plan | Name | Status | Commit |
|------|------|--------|--------|
| 22-01 | Runner hardening + log scanner (RUN-02, RUN-03, D-11) | Complete | 24b853b, e9e5ddc, 24e9d3f |
| 22-02 | INV-07 workbook formatting | Not started | -- |
| 22-03 | DOC-05 documentation drift | Not started | -- |

---

*Next milestone: v2.1 pcnr_ Clean Analysis Dataset -- Phase 22 in progress*
