---
phase: 3
slug: per-source-normalization
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-26
updated: 2026-08-26
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Three layers: (a) static grep checks on the `.sas` files, agent-checkable without SAS; (b) SAS log marker/ERROR inspection; (c) artifact-shape checks on the 17 output files |
| **Config file** | none — SAS batch |
| **Quick run command** | `sas -sysin sas\03_prep_all.sas -log logs\03_prep_all.log` (driver runs setup + all eight) |
| **Log error gate** | `findstr /B /C:"ERROR" logs\03_prep_all.log & if %errorlevel%==0 exit /b 1` |
| **Full suite command** | `qc\check_phase3.ps1` (see Automated Checks) |
| **Estimated runtime** | ~2–5 minutes for the full driver (md3 is 41,150 × 124 over the P: drive) |

**`findstr` returns 0 when it FINDS a match**, so a naive `sas ... && findstr "ERROR" log`
succeeds exactly when the run failed. Every log gate below treats `errorlevel 0` as FAIL.
**Do not gate on WARNING** — SAS emits warnings routinely for reasons unrelated to correctness.
Gate on `ERROR` and on the presence of the expected completion markers.

---

## Sampling Rate

- **After every task commit:** the plan's static grep `acceptance_criteria` (no SAS needed)
- **After every plan wave:** run the affected prep programs; check log markers
- **Before `/gsd:verify-work`:** `check_phase3.ps1` exits 0
- **Max feedback latency:** 120 seconds for static checks; ~5 min for a full driver run

---

## Automated Checks

`qc/check_phase3.ps1` — committable, no PHI, exits non-zero on failure:

```powershell
$fail = 0
$srcs = 1..8

# PREP-01: driver reached completion, no ERROR
if (Select-String -Path logs\03_prep_all.log -Pattern '^ERROR' -Quiet) {
    Write-Error "PREP-01: ERROR lines in driver log"; $fail = 1
}
if (-not (Select-String -Path logs\03_prep_all.log -Pattern '==== Phase 3 COMPLETE' -Quiet)) {
    Write-Error "PREP-01: driver did not reach completion marker"; $fail = 1
}

# PREP-02 / PREP-06: all 16 per-source artifacts exist
foreach ($n in $srcs) {
    if (-not (Test-Path "qc\03_exceptions_md$n.txt"))  { Write-Error "PREP-02: missing exceptions md$n"; $fail = 1 }
    if (-not (Test-Path "logs\03_conversions_md$n.txt")) { Write-Error "PREP-06: missing conversions md$n"; $fail = 1 }
}

# PREP-02: every exception report reports a MEASURED count, not a hardcoded zero
foreach ($n in $srcs) {
    if (Select-String -Path "qc\03_exceptions_md$n.txt" -Pattern 'anomalies \(abort if nonzero\): 0$' -Quiet) {
        Write-Error "PREP-02: md$n exception report has a hardcoded zero (Pitfall 10)"; $fail = 1
    }
}

# PREP-02: sentinel scan passed for every source
$sent = Select-String -Path logs\03_prep_all.log -Pattern 'PREP-02 OK -- 0 NULL sentinel'
if ($sent.Count -lt 7) { Write-Error "PREP-02: only $($sent.Count) sentinel-scan passes, expected >= 7"; $fail = 1 }

# PREP-03: md8 conversions
foreach ($m in '0 surviving NULL sentinel','0 forced-char numerics still CHARACTER') {
    if (-not (Select-String -Path logs\03_prep_all.log -Pattern ([regex]::Escape($m)) -Quiet)) {
        Write-Error "PREP-03: missing md8 assertion pass: $m"; $fail = 1
    }
}

# PREP-04: md6 duplicate proven identical BEFORE drop, then absent after
foreach ($m in 'PREP-04 OK -- PRECEDE_Study_ID_1 identical','PREP-04 OK -- PRECEDE_Study_ID_1 absent') {
    if (-not (Select-String -Path logs\03_prep_all.log -Pattern ([regex]::Escape($m)) -Quiet)) {
        Write-Error "PREP-04: missing assertion pass: $m"; $fail = 1
    }
}

# PREP-07: Base_Procedure_Code_1 is CHARACTER in all four NUM-coded sources
$bpc = Select-String -Path logs\03_prep_all.log -Pattern 'PREP-07 OK'
if ($bpc.Count -lt 4) { Write-Error "PREP-07: only $($bpc.Count) of 4 type assertions passed (md4-md7)"; $fail = 1 }

# Summary: Actual = Expected for all eight
$rows = Select-String -Path qc\03_prep_summary.txt -Pattern '^g\.prep_md\d\s+(\d+)\s+(\d+)'
if ($rows.Count -ne 8) { Write-Error "Summary: expected 8 rows, found $($rows.Count)"; $fail = 1 }
foreach ($r in $rows) {
    if ($r.Matches[0].Groups[1].Value -ne $r.Matches[0].Groups[2].Value) {
        Write-Error "Summary row mismatch: $($r.Line)"; $fail = 1
    }
}

# No PHI in committed artifacts
if (Select-String -Path qc\03_*.txt -Pattern 'Precede\w*\d' -Quiet) {
    Write-Error "PHI RISK: a study ID appears in a committed qc artifact"; $fail = 1
}

# g library must NOT sit inside the repo tree (RESEARCH Pitfall 9)
if (Select-String -Path sas\03_prep_*.sas -Pattern 'g_path\s*=\s*C:\\Master_Renamed' -Quiet) {
    Write-Error "PHI RISK: g library is inside the git working tree"; $fail = 1
}

exit $fail
```

**Note on the exception-report detail rows.** `qc/03_exceptions_mdN.txt` appends offending
`PRECEDE_STUDY_ID` values when the count is nonzero — those are study IDs in a **committed**
file. The PHI check above catches it. If a report ever legitimately needs detail rows, write
them to the out-of-repo g location instead and keep only counts in `qc/`.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 0 | PREP-01 | automated (static) | g_path is outside the repo root; `test -d` the chosen path | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 0 | PREP-05 | automated (artifact) | `qc/03_charvars_all.txt` lists char vars for MASTER_DATA_1..8 | ❌ W0 | ⬜ pending |
| 3-02-01 | 02 | 1 | PREP-02 | automated (static) | `grep -c "notdigit(compress"` ≥ 8; `assert_zero(n=&n_enc` absent | ❌ W0 | ⬜ pending |
| 3-02-02 | 02 | 1 | PREP-03 | automated (log) | `check_phase3.ps1` → md8 sentinel + numeric-type assertions pass | ❌ W0 | ⬜ pending |
| 3-02-03 | 02 | 1 | PREP-05 | automated (static) | first `length` line < first `set src.master_data_8` line | ❌ W0 | ⬜ pending |
| 3-03-01 | 03 | 1 | PREP-01,02 | automated (static) | md1/md2/md3: `%let expected_nobs =` present; no hardcoded `0` anomaly line | ❌ W0 | ⬜ pending |
| 3-03-02 | 03 | 1 | PREP-05 | automated (static) | md1/md2/md3: LENGTH precedes SET | ❌ W0 | ⬜ pending |
| 3-04-01 | 04 | 1 | PREP-04 | automated (log) | `check_phase3.ps1` → BOTH md6 assertions (identical, then absent) | ❌ W0 | ⬜ pending |
| 3-04-02 | 04 | 1 | PREP-07 | automated (log) | `check_phase3.ps1` → 4 × `PREP-07 OK` (md4–md7) | ❌ W0 | ⬜ pending |
| 3-05-01 | 05 | 2 | PREP-01 | automated (static) | `grep -c "%include" sas/03_prep_all.sas` ≥ 9 | ❌ W0 | ⬜ pending |
| 3-05-02 | 05 | 2 | PREP-06 | automated (artifact) | `check_phase3.ps1` → all 16 per-source artifacts exist | ❌ W0 | ⬜ pending |
| 3-05-03 | 05 | 2 | all | automated (artifact) | `check_phase3.ps1` → summary Actual = Expected × 8 | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Coverage corrected.** The earlier table had rows only for plans 01 and 02 — plans 03, 04 and
05 (six of the eight prep programs, plus the driver) had no verification at all. It also
attributed PREP-04 to plan 02; the md6 drop is plan 04.

---

## Wave 0 Requirements

- [ ] g-library directory created **outside the git working tree** (`C:\PeCAN_work\data` or `P:\PeCAN Master Data\Gerard\_prep`) — RESEARCH Pitfall 9
- [ ] `logs/` directory created (PREP-06 blocker)
- [ ] `qc/` directory confirmed (from Phase 1)
- [ ] `qc/03_charvars_all.txt` produced by `03_prep_setup.sas` — **blocks every LENGTH block in plans 02–05**; widths must come from this file, never from a plan or research table
- [ ] Confirm `logs/*.txt` and `qc/03_*.txt` are not gitignored (they are committed artifacts), while `*.log` is

*Wave 0 must complete before any prep program writes a concrete LENGTH statement.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| md8 numeric values are clinically plausible after INPUT() | PREP-03 | Range checks need clinical judgment | `proc means data=g.prep_md8 n nmiss min max; var Age_at_Encounter Admit_BMI Cognitive_Score Frailty_Score; run;` — Age min ≈ 64 (PCM-D-07 open), BMI roughly 10–80, no negatives |
| PREP-07 did not lose procedure codes | PREP-07 | Needs a before/after comparison | Compare distinct `Base_Procedure_Code_1` counts in `src.master_data_N` vs `g.prep_mdN` for md4–md7 — they must match. A drop means the num→char conversion lost information |
| Exception reports reviewed before Phase 4 | PREP-02 | Human sign-off | Open all eight `qc/03_exceptions_mdN.txt`; confirm sentinel counts are 0 and note the encoding-damage counts (expected ≤9 per source, flag-only) |
| Encoding damage is unchanged, not "fixed" | PCM-C-01 | Requires reading intent | Confirm no program modifies `Base_Procedure_1`; the count is recorded, the values are untouched |

---

## Known Gaps

- **Phase 3 does not resolve PCM-D-01/D-02/D-03.** Death-variable naming, frailty encoding, and ISO_SEV naming remain split across sources and are deferred to Phase 6 pending Erin's sign-off. Phase 4 must not assume they are harmonized. PREP-07 (`Base_Procedure_Code_1`) is the one type conflict Phase 3 *does* resolve, because it awaits no decision.
- **`%abort cancel` inside a `%include`d program cancels the whole submit**, so a failure in, say, md4 stops the driver before the summary is written. That is intended — but it means a failed run produces no `qc/03_prep_summary.txt`, and the artifact check will report it missing rather than reporting the real cause. Read the log first.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s for static checks
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending — blocked on Wave 0 (out-of-repo g library, `logs/`, and `qc/03_charvars_all.txt`)
