---
phase: 4
slug: merge
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-26
updated: 2026-08-26
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Three layers: (a) static checks on `sas/04_merge.sas`, agent-checkable without SAS; (b) SAS log assertion markers; (c) artifact-shape checks on `qc/04_merge_provenance.txt` |
| **Config file** | none — assertions embedded in 04_merge.sas |
| **Quick run command** | `sas -sysin sas\04_merge.sas -log logs\04_merge.log` |
| **Log error gate** | `findstr /B /C:"ERROR" logs\04_merge.log & if %errorlevel%==0 exit /b 1` |
| **Full suite command** | `qc\check_phase4.ps1` (see Automated Checks) |
| **Estimated runtime** | ~60–120 seconds (8 PROC SORTs plus a 41,150-row merge over the P: drive) |

**`findstr` returns 0 when it FINDS a match**, so `sas ... && findstr "ERROR" log` succeeds
exactly when the run failed. Gates below treat `errorlevel 0` as FAIL. **Do not gate on
WARNING** — SAS emits warnings routinely for reasons unrelated to correctness.

**Assertion count, stated once:** FIVE assertion categories (row count, distinct IDs, blank key,
provenance totals, NULL sentinel), implemented as FOURTEEN `%assert_eq` calls — 11 numeric,
1 sentinel, 2 ownership reconciliation. Earlier drafts said "five" and "twelve" in different
places; both were describing the same design at different granularity.

---

## Sampling Rate

- **After every task commit:** the plan's static checks (no SAS needed)
- **After every plan wave:** run 04_merge.sas; check log markers
- **Before `/gsd:verify-work`:** `check_phase4.ps1` exits 0
- **Max feedback latency:** 120 seconds for static checks; ~2 min for a full run

---

## Automated Checks

`qc/check_phase4.ps1` — committable, no PHI, exits non-zero on failure:

```powershell
$fail = 0

# MRG-01: log clean and reached completion
if (Select-String -Path logs\04_merge.log -Pattern '^ERROR' -Quiet) {
    Write-Error "MRG-01: ERROR lines in log"; $fail = 1
}
if (-not (Select-String -Path logs\04_merge.log -Pattern 'Phase 4 merge complete' -Quiet)) {
    Write-Error "MRG-01: completion marker absent"; $fail = 1
}

# All assertions passed, none failed
if (Select-String -Path logs\04_merge.log -Pattern 'MRG ASSERTION FAILED' -Quiet) {
    Write-Error "Assertion failure present in log"; $fail = 1
}
$ok = Select-String -Path logs\04_merge.log -Pattern 'MRG ASSERTION OK'
if ($ok.Count -lt 14) { Write-Error "Only $($ok.Count) of 14 assertions passed"; $fail = 1 }

# MRG-04: ownership reconciliation specifically
foreach ($m in 'unmapped columns in merged file = 0','mapped variables absent from merged file = 0',
               'MRG-04 OK -- every mapped variable has exactly one owner') {
    if (-not (Select-String -Path logs\04_merge.log -Pattern ([regex]::Escape($m)) -Quiet)) {
        Write-Error "MRG-04: missing pass: $m"; $fail = 1
    }
}

# MRG-03: provenance artifact, Actual = Expected on all eight
$rows = Select-String -Path qc\04_merge_provenance.txt -Pattern 'in_md\d\s+Expected=(\d+)\s+Actual=(\d+)'
if ($rows.Count -ne 8) { Write-Error "MRG-03: expected 8 provenance rows, found $($rows.Count)"; $fail = 1 }
foreach ($r in $rows) {
    if ($r.Matches[0].Groups[1].Value -ne $r.Matches[0].Groups[2].Value) {
        Write-Error "MRG-03 mismatch: $($r.Line)"; $fail = 1
    }
}

# Static: KEEP= ownership present on all 8, no _d_ rename scheme
$src = Get-Content sas\04_merge.sas -Raw
if (([regex]::Matches($src,'in=in\d keep=PRECEDE_STUDY_ID &keep')).Count -ne 8) {
    Write-Error "MRG-04: not all 8 sources carry IN= plus a generated KEEP= list"; $fail = 1
}
if ($src -match '_d_') { Write-Error "MRG-04: _d_ RENAME= scheme present (32-char name overflow)"; $fail = 1 }
if ($src -notmatch 'qclib\.ownership_map') { Write-Error "MRG-04: keep lists not generated from the Phase 2 map"; $fail = 1 }

# Multi-line PCM violation checks (single-line greps cannot see these)
if ($src -match '(?s)data\s+g\.master_data_merged\s*;.{0,200}?set\s+g\.master_data_merged') {
    Write-Error "PCM-T-02: in-place rewrite of g.master_data_merged"; $fail = 1
}
if ($src -match '(?is)proc\s+sql\b.{0,400}?^\s*update\s') {
    Write-Error "PCM-T-01: PROC SQL UPDATE present"; $fail = 1
}

# No PHI in the committed artifact
if (Select-String -Path qc\04_merge_provenance.txt -Pattern 'Precede\w*\d' -Quiet) {
    Write-Error "PHI RISK: a study ID appears in qc/04_merge_provenance.txt"; $fail = 1
}

exit $fail
```

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | MRG-01 | automated (static) | six SECTION markers; md3 first after MERGE | ❌ W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | MRG-04 | automated (static) | 8 × `in=inN keep=PRECEDE_STUDY_ID &keepN`; `_d_` count = 0 | ❌ W0 | ⬜ pending |
| 04-01-03 | 01 | 1 | MRG-04 | automated (static) | `qclib.ownership_map` and `build_keeplists` both present | ❌ W0 | ⬜ pending |
| 04-01-04 | 01 | 1 | MRG-02, MRG-03 | automated (static) | `assert_eq` count ≥ 15; `&SQLOBS` count = 0 | ❌ W0 | ⬜ pending |
| 04-01-05 | 01 | 1 | PCM hygiene | automated (static) | multi-line in-place-rewrite and PROC SQL UPDATE checks return 0 | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 2 | MRG-01 | automated (log) | `check_phase4.ps1` → completion marker, 0 ERROR | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 2 | MRG-01, MRG-02 | automated (log) | `check_phase4.ps1` → ≥ 14 `MRG ASSERTION OK`, 0 FAILED | ❌ W0 | ⬜ pending |
| 04-02-03 | 02 | 2 | MRG-03 | automated (artifact) | `check_phase4.ps1` → 8 provenance rows, Actual = Expected | ❌ W0 | ⬜ pending |
| 04-02-04 | 02 | 2 | MRG-04 | automated (log) | `check_phase4.ps1` → ownership reconciliation passes | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Corrected from the earlier draft:** it named `%assert_row_count(...)` and
`%assert_no_blank_key(...)`, neither of which exists — the macro is
`%assert_eq(actual=, expected=, label=)`. It also assigned all four rows to plan 01 with none
for plan 02, which does the run and verification.

---

## Wave 0 Requirements

- [ ] `g_path` agreed and IDENTICAL in Phase 3 and Phase 4. Keep the P: location (outside the git tree — the real constraint) but move it out of the source folder to a sibling such as `P:\PeCAN Master Data\Gerard\_prep`, so `src._all_` scans in Phases 1–3 do not enumerate the prep datasets. Update the Phase 3 documents to match.
- [ ] All eight `g.prep_mdN` exist with the frozen row counts (Phase 3 complete)
- [ ] `qclib.ownership_map` exists and is readable, with a `sources_present` column the resolution rule can parse
- [ ] `qc/` and `logs/` directories writable
- [ ] `qc/03_charvars_all.txt` available — the LENGTH block needs each variable's **owner's** width

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| The resolution rule produced sensible owners | MRG-04 | Judgment, not syntax | Print `work.ownership_resolved`; spot-check that md3 owns everything md3 carries, and that the five frailty components are overridden to md7 |
| md3-owns missingness is acceptable per variable | MRG-04 | Needs the analysis plan | For each variable central to the analysis, compare non-missing counts in `g.prep_md3` vs the merged file. Proven free for `Admit_BMI` (PCM-F-07); unchecked elsewhere. Record the trade-off in `docs/DECISIONS.md` |
| Pending decisions land as separate columns, unreconciled | PCM-D-01/02/03 | Requires reading intent | Confirm `Death_Date_Y_N`, `IsDead_Y_N` and `Death` are three columns; the five frailty components and their five `_Value` variants are ten columns; the three `ISO_SEV*` names are three columns. That is correct pending Erin's sign-off, not a defect |

---

## Known Gaps

- **The NULL-sentinel assertion may be vacuous by construction, and that is fine.** md8 owns only the single-source hemodynamic block, which is entirely numeric — so no md8-owned character variable exists to carry the sentinel. The program reports this explicitly rather than scanning md3-owned columns and reporting a meaningless 0.
- **`n_sources` cannot be 0** for any row, since md3 contributes all 41,150. If a 0 ever appears, the merge key alignment is broken, not the flag logic.
- **Ownership resolution is a rule applied in code, not 135 recorded decisions.** If Erin later wants a different owner for a specific variable, the override belongs next to the five frailty-component overrides in SECTION 2b, where it is visible in one place.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s for static checks
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending — blocked on Wave 0 (g_path agreement, Phase 3 outputs, ownership map readable)
