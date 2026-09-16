# Phase 18: Supplemental Raw Inventory — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-16
**Phase:** 18-supplemental-raw-inventory
**Areas discussed:** 2022 ID mismatch resolution, Gap-fill scope, PCM-D-15 gate, Output naming

---

## 2022 ID Mismatch Resolution

| Option | Description | Selected |
|--------|-------------|----------|
| Abort and report — human decides | Program prints diagnostic, writes qc\18_id_diagnostic.txt, aborts with named message. Gerard inspects. PCM-D-16 cannot be auto-closed. | ✓ |
| Auto-apply cast if numeric rendering explains it | If cats(id_num) matches char ids, auto-applies cast and proceeds. Risks silently joining wrong rows if true ID-series difference. | |
| Attempt cast, report result, require flag to proceed | Try cats(), count matches, write diagnostic, gate on %let D16_RESOLVED=0 flag. | |

**User's choice:** Abort and report — human decides (recommended default)
**Notes:** PCM-D-16 may be a true ID-series difference, not just a formatting artefact. Auto-closing risks silent data errors.

---

## Gap-Fill Scope

| Option | Description | Selected |
|--------|-------------|----------|
| All matched files — every IN_BASE column on r1–r6 | Covers all files with >0 matched IDs. Gives PCM-D-15 the full picture in one pass. | ✓ |
| Named candidates only (r1, r2, r8) | Faster but leaves r3–r6 unmeasured; may require a second pass. | |

**User's choice:** All matched files (recommended default)
**Notes:** r7/r8 excluded until 2022 ID resolved. r9 excluded (IN_BASE columns already in base).

---

## PCM-D-15 Gate

| Option | Description | Selected |
|--------|-------------|----------|
| Human checkpoint — Gerard reviews, updates DECISIONS.md, gate required | %let D15_APPROVED=0 gate; explicit, attributable, auditable. Same pattern as Phase 17 Checkpoint 1. | ✓ |
| Price approval required before gate clears | PCM-D-15 attributed to Price in Phase 16 spec; gate comment names Price. | |
| No gate — Phase 17 proceeds on counts alone | Risky: decision invisible to 99_run_all.sas reviewers. | |

**User's choice:** Human checkpoint — Gerard reviews (recommended default)
**Notes:** Attribution to Gerard for Phase 18 scope; Price may be consulted separately before Gerard sets the flag.

---

## Output Naming

| Option | Description | Selected |
|--------|-------------|----------|
| 18_supplemental_raw_gap.sas — qc\18_*.txt outputs | Fits phase-number-matches-program-number convention. Clean break from Phase 16. | ✓ |
| 16b_supplemental_raw_gap.sas | Faithful to spec "16b" language but breaks numbering convention. | |

**User's choice:** 18_supplemental_raw_gap.sas (recommended default)

---

## Claude's Discretion

- Exact format of `18_gap_candidates.txt` (sorted by recoverable-count descending is a reasonable default)
- Whether to produce a single combined gap table or one section per file
- Macro structure (one macro per file vs a generalized loop)

## Deferred Ideas

- Actual gap-fill joins — Phase 17+ work, gated on PCM-D-15
- 2022 ID cast application — gated on PCM-D-16 resolution
- r7/r8 gap-fill — deferred until PCM-D-16 resolved
