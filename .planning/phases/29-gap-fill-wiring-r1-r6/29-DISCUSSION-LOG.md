# Phase 29: Gap-Fill Wiring (r1-r6) — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-07
**Phase:** 29-gap-fill-wiring-r1-r6
**Areas discussed:** Column selection, Wiring architecture, pcnr map & sentinel entries, Pre-change snapshot

---

## Column Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Fill rate only | Any NEW-bucket column above a threshold gets wired automatically | |
| Two-stage: prefilter + human allowlist | Automatic prefilter (not in base, fill rate ≥ threshold, not an ID column) then Gerard approves the final list | ✓ |

**User's choice:** Two-stage rule. Fill rate alone is insufficient — r2 alone has ~3,987 columns; a fill-rate cutoff without a secondary gate would pull in thousands of clock and neuropsych columns.

**Notes:** If D15_APPROVED=1 was set against an existing unchanged 18_gap_candidates.txt, check git history for a previously approved column list before asking for a fresh review. Name r1–r6 by canonical file path in CONTEXT, not by label.

---

## Fan-Out Risk (raised by user before wiring architecture discussion)

**User flagged:** Several source files have more rows than the cohort they describe:
- `2018_2019_Precede_Database.xlsx` (r2): 14,807 rows vs 14,778 (2018–19 cohort)
- `2018_2019_2020_Induction_Emergent` (r1): 22,476 vs 22,473 (md8)
- `2020_Precede_Database_Edu.xlsx` (r4): 7,696 vs 7,695 (2020 cohort)
- `2018-2022_PACU_STAY`: 41,423 vs 41,150 (md3) — file not in current program 18 call list; confirm candidacy
- Plain left join without de-dup would fan out rows — PROHIBITED by GAP-03 (41,150 must hold)

**Resolution:** Prep program must detect and abort on duplicates. Each duplicate must have a documented de-dup rule in DECISIONS.md before the prep program is considered complete.

---

## Wiring Architecture

| Option | Description | Selected |
|--------|-------------|----------|
| Post-merge separate program | New program after 04_merge.sas reads g.master_data_merged and appends columns | |
| Extended prep programs (03_prep_r1..r6.sas) | Individual prep programs for each r file, merge block in 04_merge.sas | |
| Single prep + merge block (md8 pattern) | `03r_prep_gapfill.sas` preps all r1–r6; gap-fill block added to 04_merge.sas next to MRG-06 | ✓ |

**User's choice:** Follow the md8 (MRG-06) pattern exactly. `03r_prep_gapfill.sas` for prep (ID normalization, de-dup enforcement, KEEP approved columns); a new gap-fill block in `04_merge.sas` adjacent to MRG-06.

**Notes:** Post-merge program rejected because it would require either a new dataset name (downstream ripple to 16b, 17, 24, 25) or a `data X; set X;` in-place rewrite (PCM-T-02 violation). The `g.master_data_merged` name is preserved so no downstream program changes.

---

## pcnr Map and Sentinel Entries for New Columns

| Option | Description | Selected |
|--------|-------------|----------|
| Hand-write CSV rows | Manually add entries to pcnr_name_map.csv and sentinel_decisions.csv | |
| Auto-generate candidates, human approves | Program writes proposed rows with PCNR_APPROVED=0; Gerard reviews and sets =1; gate blocks 24 if any column is unmapped | ✓ |
| Re-run program 23 only | Re-running 23 regenerates candidates from the current g.master_data_merged | |

**User's choice:** Auto-generate candidate rows following the FIX-03/FIX-04 workflow. A step produces draft rows for review; gate flag (same PCNR_APPROVED pattern) blocks program 24 if any wired column is unmapped.

**Notes:** Do not hand-write entries. Pipeline must fail before program 24 if any wired column lacks an approved map entry.

---

## Pre-Change Snapshot Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Rename existing dataset | Rename g.master_data_merged to g.master_data_merged_pre | |
| Copy within g libname | PROC COPY in=g out=g; select master_data_merged (renamed) | |
| PROC COPY to separate snap libname | Copy to a separate libname directory outside g; PROC COMPARE base=snap compare=g | ✓ |

**User's choice:** PROC COPY into a `snap` libname on P: before wiring runs. Separate directory prevents overwrite on next pipeline run. Rename rejected because it leaves pipeline broken if run aborts mid-wiring.

**PROC COMPARE spec:**
- `base=snap.master_data_merged compare=g.master_data_merged`, `id PRECEDE_STUDY_ID`
- Variable list restricted to original (pre-wiring) columns
- Assert row count unchanged (41,150), ID set unchanged
- Assert `%eval(&sysinfo & 4096) = 0` (value-mismatch bit must not be set)
- New variables in compare-only dataset = expected result (not a failure)
- Any value difference in an original column = phase fails

---

## Claude's Discretion

- Exact fill-rate threshold for D-01 prefilter (5% suggested as example)
- Macro layout and section numbering within `03r_prep_gapfill.sas`
- Whether PROC COMPARE lives in standalone program or as final section of wiring program
- Specific de-dup rules per file (planner surfaces duplicates; Gerard approves the rules)

## Deferred Ideas

None — discussion stayed within phase scope.
