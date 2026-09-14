---
phase: 15
slug: extend-the-harmonized-dataset
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-14
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS assertions (`%fail_out` -> `%abort cancel`) + log inspection; PowerShell one-liners for CSV/markdown checks |
| **Config file** | `sas/00_config.sas` |
| **Quick run command** | PowerShell checks listed per task below (no SAS needed for 15-01 or 15-02 Tasks 1–3) |
| **Full suite command** | Submit `sas/10b_concept_harmonize.sas` in a fresh SAS 9.4 session (15-02 Task 4). There is no separate Phase 15 program. |
| **Estimated runtime** | ~2–5 minutes (10b re-run over 41,150 rows) |

---

## Sampling Rate

- **After every task commit:** run that task's automated check (grep / Import-Csv) or inspect SAS log for ERROR lines
- **After every plan wave:** Wave 1 → CSV row arithmetic + PCM-D-13 present; Wave 2 → full 10b run green
- **Before `/gsd:verify-work`:** full SAS run completes with zero ERRORs and all seven required NOTE lines
- **Max feedback latency:** one task (every task except the two human-judgment checkpoints has an automated check)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | HARM-04 | manual (human-verify) | Human confirms three CSVs on disk | n/a | ⬜ pending |
| 15-01-02 | 01 | 1 | HARM-04 | manual (decision) + screen | `Import-Csv docs\concept_decisions_EXT_TEMPLATE.csv \| ? { ($_.VALUE_TXT+$_.TARGET_VALUE) -match '["&%]' } \| Group CONCEPT` — must be empty for every confirmed concept | ✅ (template, after 15-01-01) | ⬜ pending |
| 15-01-03 | 01 | 1 | HARM-04 | PowerShell | YES-row count = n_yes_before + n_ext_yes; exactly one `^CONCEPT,` line; `PCM-D-13` matches ≥ 2 in DECISIONS.md | ✅ | ⬜ pending |
| 15-02-01 | 02 | 2 | HARM-07 | grep | `drop_pipeline_noinfo`, `drop=in_md3`, `work.src_check`, rule header string all present in 10b | ✅ | ⬜ pending |
| 15-02-02 | 02 | 2 | HARM-07 | grep | `assert_src_single`, `n_noinfo_present`, `n_merged_rows`, `a.name ne 'IN_MD3'` all present in 10b | ✅ | ⬜ pending |
| 15-02-03 | 02 | 2 | HARM-07 | grep | `PCM-D-14` matches ≥ 2 in DECISIONS.md | ✅ | ⬜ pending |
| 15-02-04 | 02 | 2 | HARM-04, HARM-07 | SAS run (human-verify) | Zero ERROR lines; seven required NOTE lines; PROC CONTENTS checks | ⬜ written in 15-02-01/02 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Required log lines for 15-02-04

1. `decision file passed all thirteen validation gates`
2. `&n_yes confirmed mappings across &n_con_yes concepts` (n_con_yes = 11 + concepts confirmed in 15-01)
3. `every observed value of every confirmed column is mapped`
4. `<sv> vs <pv> -- would add 0 rows, 0 disagreements` for each newly dropped alias
5. `HARM-07 premise OK -- every h_*_src companion is single-valued`
6. `HARM-07 OK -- in_md3 and every h_*_src companion dropped`
7. `g.master_data_merged confirmed post-run -- 176 columns and 41150 rows -- unmodified`

---

## Wave 0 Requirements

Wave 0 is a precondition check, not a build step. Nothing in this phase requires new test
infrastructure: the SAS assertion pattern and `%fail_out` already exist, and the Phase 15
assertions are delivered by Plan 15-02 Tasks 1–2 as part of the work they verify.

- [ ] `docs/concept_decisions_EXT_TEMPLATE.csv` exists on disk (Phase 14 artifact) — gates 15-01-02
- [ ] `docs/label_similarity_candidates.csv` exists on disk (Phase 14 artifact) — gates 15-01-02
- [ ] `docs/concept_decisions.csv` exists on disk (Phase 10 artifact) — gates 15-01-03

If any is absent: run `sas/14_label_similarity.sas` in a fresh session (15-01 Task 1).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Phase 14 artifacts present | HARM-04 | Disk state outside git | 15-01 Task 1: confirm three paths resolve |
| Label-similarity candidate judgment | HARM-04 | Program cannot decide two labels denote one concept | 15-01 Task 2: review pairs; mark CONFIRMED=YES per concept, all-or-nothing |
| Gate (m) deferrals recorded | HARM-04 | Judgment that deferral (not sanitizing) is correct | 15-01 Task 3: PCM-D-13 lists each deferred concept with example value |
| Fresh-session run | HARM-04, HARM-07 | `%abort cancel` requires session restart; log must be read | 15-02 Task 4: restart SAS, submit 10b, check the seven NOTE lines and PROC CONTENTS |

---

## Known Failure Signatures (15-02 Task 4)

| Log text | Cause | Remedy |
|----------|-------|--------|
| `N concepts are only PARTIALLY confirmed` | Gate (k): YES/blank mixed within a concept | Fix EXT template, redo 15-01 Task 3 |
| gate (m) abort naming a value with `"`, `&`, `%` | 15-01 screen skipped | Defer that concept; redo 15-01 Tasks 2–3 |
| `columns vanished ... WITHOUT being proven redundant` for `IN_MD3` | src_changed exclusion missing | 15-02 Task 2 item 1 |
| `harmonized names collide with an existing column` | Gate (c) | Rename in CSV (pinned names should not trip this) |
| `HARM-07 premise violated` | A new secondary fires | Revisit that concept's PRIORITY/mapping in concept_decisions.csv — do not weaken the rule |
| `HARM-07 violation -- in_md3 or h_*_src columns not dropped` | drop= missing or gate = 0 | 15-02 Task 1 |
| `g.master_data_merged has ... post-run` | Merged file written | Stop; this must never happen (PCM-T-02) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or are declared human-judgment checkpoints above
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (15-01-01 and 15-01-02 are the only consecutive manual pair)
- [ ] Wave 0 covers all MISSING references (three Phase 14/10 CSVs)
- [ ] No watch-mode flags
- [ ] Feedback latency: one task
- [ ] `nyquist_compliant: true` set in frontmatter when complete

**Approval:** pending
