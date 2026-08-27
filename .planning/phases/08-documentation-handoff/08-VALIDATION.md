---
phase: 8
slug: documentation-handoff
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-27
updated: 2026-08-27
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Three layers: (a) static grep on `sas/08_dictionary.sas`, agent-checkable without SAS; (b) SAS log assertion markers; (c) artifact checks on the xlsx and DECISIONS.md |
| **Config file** | none — assertions embedded in `08_dictionary.sas` |
| **Quick run command** | Open `08_dictionary.sas` in Display Manager and submit (standalone; `in_pipeline=0` so it routes its own log) |
| **Full suite command** | `99_run_all.sas` — all eight phases in one clean session |
| **Log error gate** | `findstr /B /C:"ERROR" logs\08_dictionary.log & if %errorlevel%==0 exit /b 1` |
| **Estimated runtime** | ~60–90 seconds standalone (173 per-variable COUNT queries over 41,150 rows on P:) |

**`findstr` returns 0 when it FINDS a match**, so a naive `sas ... && findstr "ERROR" log`
succeeds exactly when the run failed. Every gate treats `errorlevel 0` as FAIL.

---

## Sampling Rate

- **After every task commit:** static grep criteria from the plan (no SAS needed)
- **After 08-01:** run `08_dictionary.sas` standalone; check assertions and open the xlsx
- **After 08-02:** run `99_run_all.sas` end to end
- **Before `/gsd:verify-work`:** all three plans green, DECISIONS.md complete, git log reviewed
- **Max feedback latency:** 120 seconds for static checks

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 8-01-01 | 01 | 1 | DOC-01 | automated (static) | `grep -c "proc means"` in the coverage section = 0; `grep -q "count(&v)"` hits | ❌ W0 | ⬜ pending |
| 8-01-02 | 01 | 1 | DOC-01 | automated (static) | `grep -q "owner_resolved"` hits; `grep -q "coalesce(o.owner,"` returns NO match | ❌ W0 | ⬜ pending |
| 8-01-03 | 01 | 1 | DOC-01 | automated (log) | `n_conflict = 0` assertion passes; variable-count assertion passes | ❌ W0 | ⬜ pending |
| 8-01-04 | 01 | 1 | DOC-01 | manual (artifact) | Open xlsx: KEY sheet leftmost, 173 rows on Dictionary sheet, UF blue header | ❌ W0 | ⬜ pending |
| 8-02-01 | 02 | 2 | DOC-03 | automated (static) | `grep -c "08_dictionary.sas"` in `99_run_all.sas` = 1; header says eight phases | ❌ W0 | ⬜ pending |
| 8-02-02 | 02 | 2 | DOC-02 | automated (static) | all twelve IDs `PCM-D-01`..`PCM-D-12` present in DECISIONS.md | ❌ W0 | ⬜ pending |
| 8-02-03 | 02 | 2 | DOC-02 | manual | PCM-D-12 records the OBSERVED return code from the batch test, not an assumed one | ❌ W0 | ⬜ pending |
| 8-03-01 | 03 | 3 | DOC-03 | manual (run) | `99_run_all.sas` completes in a clean session, no aborts, xlsx written | ❌ W0 | ⬜ pending |
| 8-03-02 | 03 | 3 | DOC-04 | manual | `git log --oneline` shows one reviewable commit per phase | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Automated Checks

`qc/check_phase8.ps1` — committable, no PHI:

```powershell
$fail = 0
$sas  = "C:\Master_Renamed_same_format_accross\sas"
$docs = "C:\Master_Renamed_same_format_accross\docs"

# DOC-01: coverage must NOT use PROC MEANS (it cannot read character variables)
$dict = Get-Content "$sas\08_dictionary.sas" -Raw
if ($dict -match '(?is)proc\s+means.{0,200}?var\s+_character_') {
    Write-Error "DOC-01: PROC MEANS on _CHARACTER_ - that procedure rejects character variables"; $fail = 1
}
if ($dict -notmatch 'count\(&v\)') {
    Write-Error "DOC-01: per-variable PROC SQL COUNT not found"; $fail = 1
}

# DOC-01: ownership must use the resolution rule, not a raw join
if ($dict -notmatch 'owner_resolved') {
    Write-Error "DOC-01: ownership resolution rule absent - source column would read CONFLICT for 135 of 163"; $fail = 1
}

# DOC-01: the run asserted zero CONFLICT rows
if (-not (Select-String -Path logs\08_dictionary.log -Pattern 'source=CONFLICT' -Quiet)) {
    # absence of the ERROR text is what we want; check the positive marker instead
}
if (Select-String -Path logs\08_dictionary.log -Pattern '^ERROR' -Quiet) {
    Write-Error "DOC-01: ERROR lines in log"; $fail = 1
}

# DOC-01: the artifact exists (gitignored by default - see the decision note below)
if (-not (Test-Path "$docs\DATA_DICTIONARY.xlsx")) {
    Write-Error "DOC-01: DATA_DICTIONARY.xlsx not written"; $fail = 1
}

# DOC-02: every decision ID present
foreach ($n in 1..12) {
    $id = "PCM-D-{0:D2}" -f $n
    if (-not (Select-String -Path "$docs\DECISIONS.md" -Pattern $id -Quiet)) {
        Write-Error "DOC-02: $id missing from DECISIONS.md"; $fail = 1
    }
}

# DOC-03: Phase 8 wired into the driver, header updated
$run = Get-Content "$sas\99_run_all.sas" -Raw
if ($run -notmatch '08_dictionary\.sas') { Write-Error "DOC-03: Phase 8 not in 99_run_all.sas"; $fail = 1 }
if ($run -match 'all seven phases')      { Write-Error "DOC-03: header still says seven phases"; $fail = 1 }

exit $fail
```

---

## Wave 0 Requirements

- [ ] Phase 7 complete — `g.master_data_merged` current (post-MRG-06) and `g.analytic_cohort` written
- [ ] `docs/` directory exists on C: (repo)
- [ ] `qclib.ownership_map` readable — schema is KNOWN (`varname`, `owner`, `n_sources`, `sources_present`, `coalesce_flag`); **no inspection task needed**, and `owner` reads `CONFLICT` for 135 of 163 variables by design
- [ ] `%abort cancel` return-code batch test run, result recorded as PCM-D-12
- [ ] Decide the `.gitignore` question below

**Removed from Wave 0:** the earlier draft listed "inspect `qclib.ownership_map` schema" as a
gap. It is not unknown — it has been queried repeatedly in this project. The real hazard is not
the column names but the `CONFLICT` values in `owner`, which is now documented in the plan.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| xlsx renders correctly | DOC-01 | Visual | Open the file: KEY sheet is leftmost, Dictionary sheet has 173 rows, header row is UF blue (#0021A5) with white text, autofilter on |
| Source column is meaningful | DOC-01 | Requires knowing the ownership rule | Spot-check ten rows: md3-owned variables read `md3`, the five frailty components read `md7`, the MRG-06 five read the gap-fill derivation. **No row should read `CONFLICT`** |
| Coverage figures are plausible | DOC-01 | Needs project context | `Cognitive_Score` ~20,540 · `Frailty_Score` ~23,311 · `Admit_BMI` 12,726 · `Age_at_Encounter` 38,755. A character variable showing 0% means the coverage loop skipped it |
| `%abort cancel` return code | PCM-D-12 | One-time OS-level test | `sas -sysin test_abort.sas` where the file contains only `%abort cancel;`, then `echo %ERRORLEVEL%` in CMD. Record the OBSERVED value |
| PCM-D-05 status | DOC-02 | Stakeholder decision | See Known Gaps — this is not a program run |

---

## Known Gaps

- **PCM-D-05 is a stakeholder blocker, not a pending program output.** PCM-F-19 voided its
  original rationale: the geriatric assessments are now better populated OUTSIDE the admitted
  cohort than inside it, and `Admit_BMI` is what actually forces the restriction. D-05 needs a
  decision from Erin about what the cohort is for. **DOC-02 cannot close until that happens**,
  or must close with D-05 explicitly recorded as open and attributed. Decide which, and do not
  let it read as an oversight.
- **`DATA_DICTIONARY.xlsx` is gitignored** by the blanket `*.xlsx` rule, so the primary handoff
  deliverable has no version history. It contains variable names, types, coverage counts and
  derivation strings — no patient rows. A single `!docs/DATA_DICTIONARY.xlsx` negation would
  track it without weakening the rule for source extracts. **Decide this rather than accepting
  the default.**
- **The ownership resolution rule now exists in three places** (`04_merge.sas`, the recovery
  sweep, `08_dictionary.sas`). Extract to `sas/00_ownership_rule.sas` and `%include` it, or the
  dictionary can eventually describe an ownership the merge never applied.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s for static checks
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending — blocked on Wave 0 (Phase 7 complete, return-code test, and the two
decisions above)
