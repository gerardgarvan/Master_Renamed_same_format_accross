---
phase: 6
slug: variable-reconciliation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-26
updated: 2026-08-27
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4M8 batch execution + file-existence checks |
| **Config file** | none — SAS programs self-contained |
| **Quick run command** | `sas -sysin sas\06_reconcile.sas -log logs\06_reconcile.log` (path is `sas\`, not `src\`) |
| **Full suite command** | run the program, then `qc\check_phase6.ps1` (below). NOTE: `find` on Windows is a text-search tool, not a file locator -- use `Test-Path` / `dir` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Check log for ERROR/WARNING and verify output file exists
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** DECISIONS.md updated, qc/06_reconcile_summary.txt present, no ERRORs in log
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 6-01-01 | 01 | 1 | PCM-D-10 | manual review | read `logs\03_negtime_md3.txt`; every rt_* bucketed A/B/C/D | ❌ W0 | ⬜ pending |
| 6-01-02 | 01 | 1 | PCM-D-10 | automated (static) | `findstr "TRIAGED FROM PREP-09" docs\DECISIONS.md` | ❌ W0 | ⬜ pending |
| 6-02-01 | 02 | 2 | REC-01..03 | automated (log) | `findstr /c:"PASS" logs\06_reconcile.log` count >= 18 | ❌ W0 | ⬜ pending |
| 6-02-02 | 02 | 2 | D-04 | automated (static) | `findstr "upcase(Emergent) = 'Y'" sas\06_reconcile.sas` present; `Emergent = '1'` ABSENT | ❌ W0 | ⬜ pending |
| 6-02-03 | 02 | 2 | REC-06 | automated (artifact) | summary contains `rt_envelope_flag` and a Populated counts block | ❌ W0 | ⬜ pending |
| 6-03-01 | 03 | 2 | D-07 | automated (static) | `findstr "PCM-D-07" docs\data_dictionary_notes.txt` and `findstr "Phase 7"` both hit | ❌ W0 | ⬜ pending |
| 6-03-02 | 03 | 2 | MRG-05 | automated (static) | `findstr "rt_envelope_flag" docs\data_dictionary_notes.txt` hits; `findstr "always 9"` does not | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Wave column corrected:** plan 06-02 is `wave: 2` in its frontmatter (it depends on 06-01);
the earlier table listed its tasks as wave 1.

---

## Automated Checks

`qc/check_phase6.ps1` -- committable, no PHI, exits non-zero on failure:

```powershell
$fail = 0

# REC-01..03: all 18 presence checks passed
$pass = Select-String -Path logs\06_reconcile.log -Pattern 'PASS'
if ($pass.Count -lt 18) { Write-Error "Only $($pass.Count) of 18 presence checks passed"; $fail = 1 }
if (Select-String -Path logs\06_reconcile.log -Pattern '^ERROR' -Quiet) {
    Write-Error "ERROR lines in log"; $fail = 1
}

# D-04: Emergent coded against Y/N, not 1/0
if (Select-String -Path sas\06_reconcile.sas -Pattern "Emergent = '1'" -Quiet) {
    Write-Error "D-04: Emergent coded as 1/0 -- it is Y/N/blank (PCM-F-06); both counts will read 0"; $fail = 1
}

# Flag count must NOT be asserted
if (Select-String -Path sas\06_reconcile.sas -Pattern 'assert.*n_flag1|n_flag1.*=.*9' -Quiet) {
    Write-Error "MRG-05: flagged count is asserted -- it is an observation, not an invariant"; $fail = 1
}

# Artifacts present and populated-check reported
foreach ($t in 'Emergent','rt_envelope_flag','PCM-D-10','Populated') {
    if (-not (Select-String -Path qc\06_reconcile_summary.txt -Pattern ([regex]::Escape($t)) -Quiet)) {
        Write-Error "Summary missing: $t"; $fail = 1
    }
}

# A present-but-empty deliberate column is a real finding
if (Select-String -Path qc\06_reconcile_summary.txt -Pattern '^\s*\S+\s+0\s' -Quiet) {
    Write-Warning "A populated count reads 0 -- check whether a keep-separate column landed empty"
}

# ASCII only in the docs
foreach ($d in 'docs\DECISIONS.md','docs\data_dictionary_notes.txt') {
    if (Get-Content $d -Raw | Select-String -Pattern '[^\x00-\x7F]' -Quiet) {
        Write-Error "Non-ASCII bytes in $d (session encoding is not UTF-8)"; $fail = 1
    }
}

exit $fail
```

---

## Wave 0 Requirements

- [ ] `logs/03_negtime_md3.txt` — must exist (produced by Phase 3 plan 06); if missing, PCM-D-10 triage is blocked
- [ ] `docs/DECISIONS.md` — must exist (produced by Phase 2); if missing, documentation tasks are blocked

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| PCM-D-10 negative-rt_* triage | PCM-D-10 | Requires human judgment on whether negatives are legitimate offsets or data errors | Read logs/03_negtime_md3.txt, check each rt_*_mins variable for negatives; confirm rt_ANCHOR_to_*_days left alone |
| Erin sign-off on multi-column retention | D-01,D-02,D-03 | Stakeholder decision | Confirm qc/06_reconcile_summary.txt shows 16 deliberate columns; share with Erin for sign-off. NOTE: keep-separate was resolved 2026-08-27 and is NOT blocking -- this is informational review, not a gate |
| Populated counts are plausible | REC-01..03 | Needs source-count context | In the summary's Populated block, check each count against its owner's row total: md3-owned ~41,150, md6 ~9,462, md7 ~9,215, md8 ~22,473. A count of 0 means the column landed empty -- presence checking cannot detect that |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending -- blocked on Wave 0 (`logs/03_negtime_md3.txt` must exist from 03-06)
