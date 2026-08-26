---
phase: 1
slug: source-verification-freeze
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-25
updated: 2026-08-25
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Two layers: (a) PowerShell artifact-shape checks on `qc/*.txt`, automatable once the program has run once; (b) SAS log inspection for assertion behavior |
| **Config file** | none |
| **Quick run command** | `sas -sysin "C:\Master_Renamed_same_format_accross\sas\01_verify_sources.sas"` (check log for ERROR/ABORT) |
| **Artifact check command** | `pwsh -File qc\check_artifacts.ps1` (see Automated Artifact Checks below) |
| **Full suite command** | Quick run, then artifact check, then confirm expected NOTE lines in the log |
| **Estimated runtime** | ~30–120 seconds (depends on P: drive latency) |

---

## Sampling Rate

- **After every task commit:** Run the program and scan the log for `ERROR:` / `ABORT`
- **After every plan wave:** Run `check_artifacts.ps1` — must exit 0
- **Before `/gsd:verify-work`:** Full program runs clean, both QC files present and passing shape checks, and all expected NOTE lines present in the log
- **Max feedback latency:** 120 seconds

---

## Automated Artifact Checks

`qc/check_artifacts.ps1` — committable, no PHI, exits non-zero on failure. This is what
makes the artifact requirements (SRC-03, SRC-04) automatically verifiable rather than
eyeballed:

```powershell
$fail = 0

# SRC-04: eight lines of "master_data_N <64-hex>"
$h = Select-String -Path qc\checksums.txt -Pattern '^master_data_\d\s+[0-9a-fA-F]{64}$'
if ($h.Count -ne 8) { Write-Error "SRC-04: expected 8 hash lines, found $($h.Count)"; $fail = 1 }

# SRC-04: the regeneration caveat must be present in the artifact itself
if (-not (Select-String -Path qc\checksums.txt -Pattern 'not evidence of corruption' -Quiet)) {
    Write-Error "SRC-04: checksums.txt is missing the regeneration caveat"; $fail = 1
}

# SRC-03: eight source rows, each with two integer columns
$c = Select-String -Path qc\src_counts.txt -Pattern '^master_data_\d\s+\d+\s+\d+'
if ($c.Count -ne 8) { Write-Error "SRC-03: expected 8 count rows, found $($c.Count)"; $fail = 1 }

# No PHI: qc artifacts must contain only hashes, names, and integers
if (Select-String -Path qc\*.txt -Pattern 'Precede\w*\d' -Quiet) {
    Write-Error "PHI RISK: a study ID appears in a qc artifact"; $fail = 1
}

exit $fail
```

Log-line checks (also automatable via `Select-String` on the .log):
`XCMD enabled`, `SRC-06 OK`, 8 × `SRC-05 OK`, 8 × `PCM-F-01 OK`, 1 × `PCM-F-02 OK`.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-00 | 01 | 1 | SRC-06 | automated (log) | `Select-String '<log>' -Pattern 'SRC-06 OK'` → 1 match | ❌ W0 | ⬜ pending |
| 1-01-01 | 01 | 1 | SRC-04 | automated (artifact) | `check_artifacts.ps1` → 8 hash lines + caveat present | ❌ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | SRC-03 | automated (artifact) | `check_artifacts.ps1` → 8 count rows, two integers each | ❌ W0 | ⬜ pending |
| 1-02-01 | 02 | 2 | SRC-05 | automated (log) + manual (injection) | `Select-String '<log>' -Pattern 'SRC-05 OK'` → 8 matches | ❌ W0 | ⬜ pending |
| 1-02-02 | 02 | 2 | SRC-01 | automated (log) + manual (injection) | `Select-String '<log>' -Pattern 'PCM-F-01 OK'` → 8 matches | ❌ W0 | ⬜ pending |
| 1-02-03 | 02 | 2 | SRC-02 | automated (log) + manual (injection) | `Select-String '<log>' -Pattern 'PCM-F-02 OK'` → 1 match | ❌ W0 | ⬜ pending |
| 1-02-04 | 02 | 2 | (hygiene) | automated (static) | `grep -c SQLOBS sas\01_verify_sources.sas` → 0 | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

Plan column corrected: SRC-01, SRC-02 and SRC-05 are implemented in plan **02**, not 01.

---

## Wave 0 Requirements

- [ ] **`XCMD` enabled** — `%put %sysfunc(getoption(xcmd));` returns `XCMD`. **BLOCKER for SRC-04.** Under `NOXCMD`, `FILENAME PIPE` is unavailable and the PowerShell `Get-FileHash` alternative fails identically (same mechanism); SRC-04 must be re-planned against `sashelp.vtable` metadata. Verify this before plan 01-01 Task 1 is written.
- [ ] `qc/` directory exists and is writable (local disk, not P:)
- [ ] P: drive is accessible from the SAS session (LIBNAME resolves without error)
- [ ] `certutil.exe` available (ships with Windows — verify with `certutil /?` in cmd, not via SAS, since SAS access depends on XCMD)
- [ ] PowerShell available for `check_artifacts.ps1`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| certutil FILENAME PIPE reads the correct hash line | SRC-04 | SAS has no self-test for pipe output parsing | Run `certutil -hashfile <file> SHA256` in cmd, compare to the `qc/checksums.txt` entry |
| `%abort cancel` fires on a blank key | SRC-05 | Requires injecting a blank PRECEDE_STUDY_ID — cannot automate without modifying read-only source | Copy one source to WORK, blank one ID, point the macro at the copy, confirm abort with the SRC-05 ERROR |
| `%abort cancel` fires on a uniqueness violation | SRC-01 | Same — requires a duplicate row | Same approach with a duplicated ID |
| `%abort cancel` fires on a superset violation | SRC-02 | Same — requires an md1 ID absent from md3 | Same approach with an orphan ID |
| `%abort cancel` fires under NOXCMD | SRC-04 | Cannot toggle XCMD at runtime | Only testable if a NOXCMD session is available; otherwise confirm by inspection that the check precedes all FILENAME PIPE use |
| md7 key type regression | SRC-06 | The realistic failure (numeric key) cannot be injected without rebuilding a source | Confirm by inspection that `type = 2 and length = 12` covers all eight; the assertion itself is the test |

---

## Known Gaps

- **`%abort cancel` OS return code is unverified.** It halts the run and writes ERROR to the log, which is what Phase 1 needs. Whether it returns a nonzero exit code to the caller is not established. If `99_run_all.sas` is ever scheduled or run under CI, verify this or switch to `%abort abend` / `%abort return <n>`. Decision deferred to Phase 8; recorded here so it is not silently assumed.
- **Checksums freeze bytes, not data.** A `.sas7bdat` re-imported from identical source data hashes differently. The artifact states this on its face; the validation contract does not treat a future mismatch as a failure.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every task now has an automated log or artifact check; injection tests are supplementary)
- [x] Wave 0 covers all MISSING references (XCMD added as the blocker)
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending — blocked on Wave 0 XCMD verification
