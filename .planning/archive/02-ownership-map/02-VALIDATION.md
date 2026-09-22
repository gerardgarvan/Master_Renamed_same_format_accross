---
phase: 2
slug: ownership-map
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-25
updated: 2026-08-25
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Two layers: (a) static grep checks on `sas/02_ownership.sas`, agent-checkable without SAS; (b) SAS log inspection + artifact-shape checks after a run |
| **Config file** | none — SAS session-level |
| **Quick run command** | `sas -sysin sas\02_ownership.sas -log logs\02_ownership.log` |
| **Log error gate** | `findstr /C:"ERROR:" logs\02_ownership.log & if %errorlevel%==0 exit /b 1` |
| **Full suite command** | `qc\check_phase2.ps1` (see Automated Checks below) |
| **Estimated runtime** | ~60 seconds |

**Log path is `logs/`, not `qc/`.** `qc/` holds committed QC artifacts; `logs/` holds run
logs (PROJECT.md section 5). Confirm `.gitignore` covers `*.log`.

**`findstr` exit-code semantics are inverted from what you want.** It returns 0 when it
*finds* a match, so `sas ... && findstr "ERROR" log` succeeds precisely when the run
failed. Every log gate below tests for `errorlevel 0` meaning FAIL.

---

## Sampling Rate

- **After every task commit:** static grep criteria from the plan's `acceptance_criteria` (no SAS needed)
- **After every plan wave:** quick run + log error gate
- **Before `/gsd:verify-work`:** `check_phase2.ps1` exits 0, and a second consecutive run does not duplicate the DECISIONS.md conflict block
- **Max feedback latency:** 120 seconds

---

## Automated Checks

`qc/check_phase2.ps1` — committable, no PHI, exits non-zero on failure:

```powershell
$fail = 0

# OWN-01: log is ERROR-free and reached the completion marker
if (Select-String -Path logs\02_ownership.log -Pattern '^ERROR' -Quiet) {
    Write-Error "OWN-01: ERROR lines in log"; $fail = 1
}
if (-not (Select-String -Path logs\02_ownership.log -Pattern 'Phase 2 ownership map complete' -Quiet)) {
    Write-Error "OWN-01: completion marker absent - program did not finish"; $fail = 1
}

# OWN-02: ownership map exists and has content rows
$rows = Select-String -Path qc\02_ownership_map.txt -Pattern '^\S+\s+\S+'
if ($rows.Count -lt 10) { Write-Error "OWN-02: ownership map has $($rows.Count) rows"; $fail = 1 }

# OWN-03: conflict table present, and exactly one generated block
$marks = Select-String -Path docs\DECISIONS.md -Pattern 'OWN-03 CONFLICT ROWS GENERATED'
if ($marks.Count -ne 1) {
    Write-Error "OWN-03: expected exactly 1 generated block, found $($marks.Count) (re-run guard)"; $fail = 1
}
if (-not (Select-String -Path docs\DECISIONS.md -Pattern '\| Variable \| Sources \|' -Quiet)) {
    Write-Error "OWN-03: conflict table header missing"; $fail = 1
}

# OWN-04: every coalesce check resolved to OK, SKIP, or TYPE MISMATCH - none silently absent
$own04 = Select-String -Path logs\02_ownership.log -Pattern 'OWN-04 (OK|SKIP|TYPE MISMATCH|--)'
if ($own04.Count -lt 14) { Write-Error "OWN-04: only $($own04.Count) coalesce results logged, expected >= 14"; $fail = 1 }

# No PHI in committed artifacts
if (Select-String -Path qc\*.txt, docs\DECISIONS.md -Pattern 'Precede\w*\d' -Quiet) {
    Write-Error "PHI RISK: a study ID appears in a committed artifact"; $fail = 1
}

exit $fail
```

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | OWN-01 | automated (artifact) | `test -f docs/DECISIONS.md` and `grep -c "PCM-D-0" docs/DECISIONS.md` = 7 | ❌ W0 | ⬜ pending |
| 2-01-02 | 01 | 1 | OWN-01 | automated (static) | plan acceptance greps: `in (` present, `in:` absent, `allvars_src` present | ❌ W0 | ⬜ pending |
| 2-01-03 | 01 | 1 | OWN-02 | automated (artifact) | `check_phase2.ps1` → ownership map has ≥10 rows | ❌ W0 | ⬜ pending |
| 2-02-01 | 02 | 2 | OWN-03 | automated (artifact) | `check_phase2.ps1` → exactly 1 generated block, table header present | ❌ W0 | ⬜ pending |
| 2-02-02 | 02 | 2 | OWN-04 | automated (static) | `grep -i "Admit_BMI"` and `grep -i "Race"` both hit; `grep "var=BMI,"` does not | ❌ W0 | ⬜ pending |
| 2-02-03 | 02 | 2 | OWN-04 | automated (log) | `check_phase2.ps1` → ≥14 `OWN-04` result lines | ❌ W0 | ⬜ pending |
| 2-02-04 | 02 | 2 | (hygiene) | automated (static) | `grep -q "filename dcsngrp pipe"` returns NO match (no XCMD dependency) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Plan/Wave columns corrected:** OWN-03 and OWN-04 are implemented in plan **02**, wave
**2**. The earlier table listed all five rows as plan 01, and row 1 as wave 0.

---

## Wave 0 Requirements

- [ ] `docs/` directory created (Phase 1 created only `qc/`)
- [ ] `docs/DECISIONS.md` stub committed, containing the `## OWN-03 Variable Conflicts` anchor
- [ ] `qc/` directory exists (from Phase 1)
- [ ] `logs/` directory exists and `*.log` is gitignored
- [ ] Confirm the exact spelling of every variable named in Plan 02 against a `PROC CONTENTS` listing — `BMI` vs `Admit_BMI` cost a run in the first draft

*Wave 0 must run before `02_ownership.sas` to avoid FILE MOD edge cases on missing directories.*

**No XCMD requirement.** Phase 1 needed `%check_xcmd` for `FILENAME PIPE`. Phase 2's
re-run guard reads DECISIONS.md with `infile` instead, so Phase 2 has no shell-out
dependency. If a pipe is ever reintroduced, `%check_xcmd` must be added to Section 1.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Ownership table is human-readable and reviewable | OWN-02 | Readability is subjective | Open `qc/02_ownership_map.txt`; confirm each variable has exactly one owner, no column collision in the Sources field, and conflicts are visible |
| DECISIONS.md conflict entries are accurate | OWN-03 | Requires domain knowledge | Review each conflict entry against source dataset contents; confirm `PRECEDE_STUDY_ID` is absent (it is the key, not a conflict) |
| Conflict list is complete, not just the known set | OWN-03 | Only runtime enumeration knows | Compare `n_conflicts` in the log against the Known Conflicts table in RESEARCH — the table is a floor, not a ceiling |
| md8 TYPE MISMATCH results are correct, not failures | OWN-04 | Requires reading intent | `Admit_BMI` vs md8 SHOULD report TYPE MISMATCH (Char there, Num elsewhere). That is the check working, not breaking |

**OWN-04 is informational by design.** RESEARCH Pattern 5 and both plans specify
WARNING-only, no `%abort`. An earlier version of this table asked the reviewer to confirm
`%abort cancel` fires on a coalesce mismatch — that contradicts the design. The automated
gate is instead that every expected check produced a result line, so a silently skipped
check fails the suite.

---

## Known Gaps

- **Ownership is documented, not enforced.** RESEARCH Pitfall 3 stands: nothing in Phase 2 stops Phase 4 from ignoring the map and doing a last-wins merge. The `qclib.ownership_map` dataset exists so Phase 4 *can* assert against it — that assertion is a Phase 4 requirement and must be written there.
- **`qc/ownership_map.sas7bdat` is gitignored** (`*.sas7bdat` per PCM-C-03), so it is not a committed artifact. Only `qc/02_ownership_map.txt` satisfies OWN-02. This is intended: the dataset is a Phase 4 input, the text file is the reviewable record. It holds variable names only, no PHI.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending — blocked on Wave 0 (docs/ directory + DECISIONS.md stub + variable-name confirmation)
