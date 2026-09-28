---
phase: 23
slug: sentinel-name-inventory
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-09-28
revised: 2026-09-28
---

# Phase 23 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Regenerated to match the replanned 3-plan / 3-wave structure.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4M8 — DATA step FILE / CSV + log-assertion checks; grep static checks on the .sas source |
| **Config file** | none — outputs are file-based CSV/txt checks + git ls-files |
| **Quick run command** | `dir qc\23_sentinel_candidates.csv` |
| **Full suite command** | `sas sas/23_pcnr_inventory.sas` then verify all qc/ outputs exist |
| **Estimated runtime** | ~30–120 seconds (depends on g.master_data_harmonized size) |

---

## Sampling Rate

- **After every task commit:** grep static checks on sas/23_pcnr_inventory.sas + target output file exists
- **After every plan wave:** run full SAS program; check all qc/ outputs
- **Before `/gsd:verify-work`:** all qc/ outputs present; both docs/ gate files git-tracked; DECISIONS.md updated
- **Max feedback latency:** ~120 seconds

Note: `PCNR_APPROVED` lives in `sas/00_config.sas` (NOT in any csv) and stays **0** at the end of
Phase 23. The flip to 1 is Phase 24 scope.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 23-01-01 | 01 | 1 | %hexkey + gate flag | grep-check | `grep -n "%macro hexkey" sas/00_config.sas` | n/a | ⬜ pending |
| 23-01-02 | 01 | 1 | Preconditions + fingerprint + char sweep | grep + file-check | `grep -n "%check_preconditions" sas/23_pcnr_inventory.sas` ; `dir qc\23_sentinel_fingerprint.txt` | ❌ W1 | ⬜ pending |
| 23-01-03 | 01 | 1 | Numeric scan + ambiguous + case variants | grep + file-check | `grep -n "array _n" sas/23_pcnr_inventory.sas` ; `dir qc\23_case_variants.csv` | ❌ W1 | ⬜ pending |
| 23-02-01 | 02 | 2 | Name-map draft + truncation + DROP | grep + file-check | `dir qc\23_pcnr_name_map_DRAFT.csv` | ❌ W2 | ⬜ pending |
| 23-02-02 | 02 | 2 | Decisions draft + SECTION 8 validation | grep + file-check | `dir qc\23_sentinel_decisions_DRAFT.csv` ; `grep -n "SECTION 8" sas/23_pcnr_inventory.sas` | ❌ W2 | ⬜ pending |
| 23-03-01 | 03 | 3 | Human review checkpoint | manual | reviewer confirms candidates + name map | n/a | ⬜ pending |
| 23-03-02 | 03 | 3 | PHI gate + git add -f | git-check | `git ls-files docs/sentinel_decisions.csv docs/pcnr_name_map.csv` | n/a | ⬜ pending |
| 23-03-03 | 03 | 3 | DECISIONS.md D-21..25 + PCM-T-16 | grep-check | `grep -n "PCM-D-21" docs/DECISIONS.md` | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- No new test framework needed. SAS outputs verified by file existence, log assertions, and grep
  static checks on the source. The recurring static checks (mandatory each wave):
  - `grep -n '\$hex\.' sas/*.sas` must return NOTHING (bare $hex. is the truncating form)
  - `grep -ni "proc import" sas/23_pcnr_inventory.sas` must return NOTHING (PCM-T-16)
  - `grep -ni "%put WARNING" sas/23_pcnr_inventory.sas` must return NOTHING (Phase 22 scanner fails on WARNING)
  - `grep -ni "docs" sas/23_pcnr_inventory.sas` shows ONLY the concept_decisions.csv read
  - every `%if` inside a `%macro ... %mend` block (PCM-T-15)

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Human review of qc/23_sentinel_candidates.csv | PCM-D-21, D-25 | Human judgement on placeholder values | Gerard opens qc/23_sentinel_candidates.csv (sorted AMBIGUOUS first); confirms classification |
| Name-map truncation review | PCM-D-23 | 10 names hit 32-char limit; human confirms/overrides | Gerard checks qc/23_pcnr_name_map_DRAFT.csv against the RESEARCH.md 10-name table |
| PCM-D-24 numeric approvals / D-25 column scope | PCM-D-24, D-25 | Price sign-off on analytic-facing decisions | Price reviews numeric sentinel rows and demographic/score column lists |
| Copy drafts P: qc/ -> C: docs/ | PCNR-06 | P: drive inaccessible to the agent | Human copies + edits docs/sentinel_decisions.csv and docs/pcnr_name_map.csv |
| Pre-commit PHI scan | D-09 | Hard gate before git add -f | Agent scans REVIEW rows' raw_value; PHI hit -> add column to freetext_cols + rerun program 23 (never hand-delete) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or manual/Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all static-check references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
