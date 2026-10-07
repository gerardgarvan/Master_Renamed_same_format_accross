# Phase 28: r7/r8/r9 Linkage Investigation — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-07
**Phase:** 28-r7-r8-r9-linkage-investigation
**Areas discussed:** SAS program vs. doc-only, v2.3 scope statement, evidence sufficiency, output artifacts

---

## SAS Program vs. Documentation Only

| Option | Description | Selected |
|--------|-------------|----------|
| Documentation only | Read qc/20_linkage_reach.txt, synthesize existing evidence, write PCM-D-28 | |
| Standalone one-time SAS program | Write 28_linkage_investigation.sas (like 27_md8_count.sas); run once manually | ✓ |

**User's choice:** Standalone one-time SAS program, NOT added to run_pipeline.cmd.

**Notes:** Three investigation blocks — SHA pair comparison, ID-format profile, normalized match. Most evidence costs nothing to collect. User noted that before running Block 3, the provenance of the 14.5/64/41% figures in PROJECT.md should be established via git log and prior SUMMARYs, so the program knows what it is trying to reproduce.

User also provided key pre-established evidence from 19_raw_files.csv:
- 2018-2019 and 2018-2022 raw\ copies differ from their raw\master counterparts by exactly 80,233 bytes; raw\ copies dated 17 Aug 2026, raw\master copies 28 Apr 2026
- The gap is constant across files of very different row counts, ruling out a per-row-per-column explanation
- 2020–2022 file pairs are same byte size but different SHA-256 — not byte-identical
- Crypto files (MRN + ENCOUNTER) cover 2018-2019 only (14,781 rows each, 2 cols) — cannot speak to 2022 linkage
- r7/r8/r9 identified by path from sas/20_pecan_id.sas: r7=2022_Education_20240124.csv, r8=2022_RES_20230927.csv, r9=All_YEARS_LAT_LONG_20231127.csv

---

## v2.3 Scope Statement

| Option | Description | Selected |
|--------|-------------|----------|
| Not feasible | MRN linking not feasible — exclude r7-r9 permanently | |
| Unknown pending specific check | Phase 29 excludes tentatively; PCM-D-28 names condition for reopening | ✓ |
| Feasible | MRN linking feasible — scope to v2.3 | |

**User's choice:** "Unknown pending specific check."

**Notes:** A permanent exclusion requires positive evidence, not just unexplained mismatches. PCM-D-28 must name a specific condition for reopening (e.g., a 2022 Crypto file, or an ID crosswalk from the extract producer). Phase 29 excludes r7-r9 tentatively with a reference to PCM-D-28 and the stated condition.

---

## Evidence Sufficiency (14.5% / 64% / 41% rates)

| Option | Description | Selected |
|--------|-------------|----------|
| Use PROJECT.md figures directly | 14.5/64/41% are sufficient to write PCM-D-28 | |
| Reproduce with documentation | Program re-derives rates with source pair, key, normalization, denominator documented | ✓ |

**User's choice:** Reproduce with documentation; existing figures are unprovenanced and must not appear in PCM-D-28 as-is.

**Notes:** Before re-deriving, check git log, Phase 20 SUMMARY, Phase 21 SUMMARY, and PROJECT.md history to establish provenance. Report both directions (match_rate_left = n_matched/n_left, match_rate_right = n_matched/n_right) — a single rate hides which side failed to match.

---

## Output Artifacts

| Option | Description | Selected |
|--------|-------------|----------|
| DECISIONS.md only | No separate QC file | |
| qc/28_linkage_investigation.csv | One row per comparison; columns: source_pair, key_used, normalization_applied, n_left, n_right, n_matched, match_rate_left, match_rate_right, sha_identical_flag | ✓ |

**User's choice:** `qc/28_linkage_investigation.csv` committed to P: drive (gitignored). Counts only, no PHI. PCM-D-28 cites it the same way PCM-D-31 cites qc/27_md8_count.csv.

---

## Claude's Discretion

Internal structure of 28_linkage_investigation.sas; whether to attempt additional normalizations beyond those listed if the primary ones produce a match rate of 0.

## Corrections Made During Discussion

- Initial reflection incorrectly attributed the 80,233-byte difference to a $41 vs $40 ENCRYPTED_MRN width difference. User corrected: the gap is constant across files of very different row counts, so a per-row explanation is impossible. Record as observed, unexplained.
- Normalization in D-01 was initially described as a single approach; user corrected: split by comparison. The $18 vs $12 issue applies only to 2018-2019 Crypto vs masters. For r7-r9 vs md3/md7, the issue is numeric vs character PRECEDE IDs.
- Match rates initially described as single-direction; user corrected: report both directions.
- PHI guard added: ENCRYPTED_MRN widths and counts only; no min/max or sample values in logs or CSV.
