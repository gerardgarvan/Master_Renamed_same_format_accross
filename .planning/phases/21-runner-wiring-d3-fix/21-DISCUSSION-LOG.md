# Phase 21: Runner Wiring & D3 Fix - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-09-23
**Phase:** 21-runner-wiring-d3-fix
**Areas discussed:** Runner invocation model, D3 fix scope

---

## Runner Invocation Model

| Option | Description | Selected |
|--------|-------------|----------|
| .cmd batch script | `start "" /wait sas.exe -sysin ... -log ...` per program; no execution-policy risk; readable on any Windows machine | ✓ |
| PowerShell script | Same capability; better error formatting; execution-policy risk on UF-managed machines | |
| SAS SYSTASK driver | Keeps everything in SAS; XCMD already required; but driver itself runs in a session that can be interrupted | |

**User's choice:** `.cmd` batch script

**Exit-code policy:**
- 0/1 = continue (exit code 1 = warnings only; programs 19/20 reset syscc after expected warnings)
- 2+ = stop and name the failing program
- Driver counts WARNING: lines in each log for the summary (log scanning is for summary only, not a stop condition)

**in_pipeline flag:**
- `-set in_pipeline 1` was rejected: creates OS env var, not SAS macro var; programs would still see in_pipeline=0
- Chosen: driver passes `-set RUN_ALL 1`; `00_config.sas` %_set_pipeline_default checks `%sysget(RUN_ALL)` and sets in_pipeline=1 when present
- 13 existing programs stay untouched; driver names each log with -log flag
- `logs/99_run_all.log` = driver summary (timestamps, exit codes, warning counts)

---

## D3 Fix Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Set DOMAIN_MAP_APPROVED=1 only | DATALINES rows are already correct; gate is the only blocker | ✓ |
| Add/fix DATALINES rows | COGNITIVE_SCORE/COGNITIVE_CATEGORY rows already exist at lines 1711-1712 | |
| Add pecan_ID DATALINES row | pecan_ID not in program 17's inputs (g.master_data_merged or g.analysis_base) | |

**User's choice:** Set DOMAIN_MAP_APPROVED=1 with PCM-D-19 attribution

**Notes:**
- User corrected premise: pecan_ID is NOT in g.master_data_merged (PCM-D-05 -- merged file untouched). g.analysis_base is a pre-v2 artifact; also pecan_ID-free. No DATALINES row needed.
- stat_route is computed from vtype/n_levels in Section 4, not stored in DATALINES -- no structural change needed
- Variable name case is not an issue: Section 4 join upcases both sides
- PCM-D-19 comment must state: approval supersedes v1 checkpoint-2 (made when D3 was missing); confirms D3 sheet populated in new run

---

## Program Order (confirmed, not discussed)

Order: 1-8 -- 19 -- 20 -- 10b -- 16b -- 17 -- 18

User correction: description had the 20/10b dependency direction wrong. Program 20 writes g.pecan_id_xwalk; program 10b reads it (not the reverse).

Claude corrected premise: pecan_ID is not in g.master_data_merged (PCM-D-05 -- merged file untouched); g.analysis_base predates Phase 20. No DATALINES row for pecan_ID needed (under current program 17 inputs).

Programs 10 (concept_profile) and 14 (label_similarity) are human-gated prerequisites -- NOT in the runner.

---

## Claude's Discretion

- Exact .cmd file name and location
- Whether driver echoes program names to console as it runs
- Log-scanning implementation detail (findstr vs FOR /F loop)
- Whether 99_run_all.sas is renamed, archived, or repurposed as documentation

## Deferred Ideas

- PCM-D-15 extension-column gap-fill wiring -- deferred to v2.1 per REQUIREMENTS.md
