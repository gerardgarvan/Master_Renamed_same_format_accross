---
phase: 24-build-g-pcnr-harmonized
plan: "01"
subsystem: pcnr-build
tags: [sas, code-generation, gate-check, recode-rules]
dependency_graph:
  requires: [phase-23-outputs: docs/sentinel_decisions.csv, docs/pcnr_name_map.csv, qc/23_sentinel_candidates.csv, qc/23_sentinel_fingerprint.txt]
  provides: [sas/24_pcnr_build.sas SECTIONS 0-2, docs/pcnr_name_map.csv canonical name]
  affects: [phase-24-plan-02]
tech_stack:
  added: []
  patterns: [SAS DATA step infile (PCM-T-16), PROC SQL into trimmed, hash objects for sequential code generation, WORK-then-promote]
key_files:
  created:
    - sas/24_pcnr_build.sas
  modified:
    - sas/00_config.sas
    - docs/pcnr_name_map.csv (renamed from docs/23_pcnr_name_map.csv)
decisions:
  - "PCNR_APPROVED=1 committed to 00_config.sas with approval comment (gate files reviewed Phase 23)"
  - "docs/23_pcnr_name_map.csv renamed to docs/pcnr_name_map.csv via git mv (single canonical copy)"
  - "SECTION 2 uses sequential DATA step set with retained _prev_var (simpler than hash iterator for ordered data)"
metrics:
  duration: "~30 min"
  completed_date: "2026-09-28"
  tasks: 3
  files: 3
---

# Phase 24 Plan 01: Gate Check + Rule Resolution + Code Generation Summary

**One-liner:** Gate macro with 11 abort-on-failure checks, wildcard/per-variable MISSING rule resolution into `work._recode_rules`, and code-generated `qc/24_recode_rules_generated.sas` select/when snippet.

---

## What Was Built

### Task 1: Name map rename + PCNR_APPROVED gate flip
- `docs/23_pcnr_name_map.csv` renamed to `docs/pcnr_name_map.csv` via `git mv` (single copy, no drift)
- `sas/00_config.sas` line 40: `%let PCNR_APPROVED = 1;` with approval comment above it
- Verified: no remaining `23_pcnr_name_map` references in `sas/` (only DRAFT qc/ references remain, which are correct)

### Task 2: SECTION 0 — %pcnr_gate_check macro (11 checks)

All checks call `%fail_out(msg=...)` on failure. No bare open-code `%if`.

| Check | Description |
|-------|-------------|
| 1 | Gate flag: `PCNR_APPROVED ne 1` aborts |
| 2 | Fingerprint: nobs, nvar, modate vs `qc/23_sentinel_fingerprint.txt` |
| 3 | Load decisions via `infile` from `docs/sentinel_decisions.csv` (16 columns) |
| 4 | Load candidates + name map via `infile` (roles come from name map only, not candidates) |
| 5 | Coverage: every KEEP/KEY candidate has per-variable row or valid wildcard match |
| 6 | AMBIGUOUS guard: AMBIGUOUS candidates require per-variable row (no wildcard) |
| 7 | Stale per-variable: decision rows must reference existing (variable, raw_hex) |
| 8 | Stale wildcard: wildcard normalized_value must match at least one KEEP/KEY char non-AMBIGUOUS candidate |
| 9 | Wildcard type: all wildcard rows have var_type='char' |
| 10 | Action validity: every row has action in ('MISSING','KEEP') |
| 11 | Duplicate decision keys: unique on (variable, raw_hex) per-var; unique on normalized_value wildcard |

### Task 3: SECTION 1 rule resolution + SECTION 2 code generation

**SECTION 1** — `work._recode_rules`:
- Two SQL tables stacked via `outer union corr`: `work._rules_pv` (per-variable MISSING) + `work._rules_wc` (wildcard expansion)
- Wildcard expansion joins on `upcase(normalized_value)` (never on raw_hex which is blank on wildcard rows)
- Wildcard excludes AMBIGUOUS candidates; per-variable row wins via `not exists` subquery
- `rule_source` length=8 so 'WILDCARD' (8 chars) is not truncated to 'WILDCAR'
- Uniqueness assertion on (variable, raw_hex) aborts if violated

**SECTION 2** — `qc/24_recode_rules_generated.sas`:
- Three-step write: header comment, char rules, numeric rules (currently empty)
- Char rules: sequential `set work._char_rules` with retained `_prev_var` to detect variable breaks
- Per variable: one `select (%hexkey(var)); when ... call missing(var); otherwise; end;` block
- `raw_value` sanitized in comment: bytes outside 0x20-0x7E replaced with `<non-ascii>`; `*/` replaced with `* /`
- Numeric branch present for future PCM-D-24 approved rules: `if var = value and not missing(var) then call missing(var);`
- File is plain SAS snippet: no `options`, no `%include`, no `run;` inside

**SECTIONS 3-8**: Stub markers in place for Plan 24-02.

---

## Static Checks (all pass)

```
grep -ci "proc import" sas/24_pcnr_build.sas  -> 0
grep -c '\$hex\.' sas/24_pcnr_build.sas        -> 0
grep -ci "put WARNING" sas/24_pcnr_build.sas   -> 0
grep -c "length=7" sas/24_pcnr_build.sas       -> 0
```

---

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | fe08c32 | feat(24-01): rename name map + PCNR_APPROVED=1 |
| 2+3 | 3082453 | feat(24-01): create sas/24_pcnr_build.sas SECTIONS 0-2 + stubs 3-8 |

---

## Deviations from Plan

### Auto-fixed Issues

None.

### Minor Implementation Notes

1. **SECTION 2 writer approach**: Plan suggested hash iterator; implementation uses sequential `set work._char_rules` with retained `_prev_var`. Both produce identical output; the sequential approach is simpler and avoids the constraint that `declare hash` cannot be re-declared inside a loop.

2. **`%macro _24_include_config`**: Added a `%symexist(sas_path)` guard around the config `%include` (matches the `_set_pipeline_default` pattern already in `00_config.sas`). The plan said to copy 10b's include guard "verbatim" — 10b uses a bare `%include` at line 74 without a guard, so this is a slight improvement (Rule 2: prevents double-include side effects in pipeline runs).

---

## Known Stubs

SECTIONS 3-8 are intentional stubs; Plan 24-02 fills them. These do not prevent Plan 01's goal (gate + resolve + generate) from being achieved.

---

## Self-Check: PASSED

- `sas/24_pcnr_build.sas` exists: FOUND
- `docs/pcnr_name_map.csv` exists: FOUND
- `docs/23_pcnr_name_map.csv` absent: CONFIRMED
- Commit fe08c32 exists: CONFIRMED
- Commit 3082453 exists: CONFIRMED
