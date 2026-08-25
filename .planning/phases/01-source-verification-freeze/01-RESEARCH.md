# Phase 1: Source Verification & Freeze - Research

**Researched:** 2026-08-25
**Domain:** SAS 9.4M8 on Windows — file checksumming, PROC CONTENTS, macro-level assertion/abort, uniqueness checking
**Confidence:** HIGH (SAS patterns are stable; certutil approach is well-established on Windows)

---

## Summary

Phase 1 must produce a single program `01_verify_sources.sas` that (a) checksums all eight `.sas7bdat` source files and writes hashes to a committed artifact in `qc/`, (b) asserts `PRECEDE_STUDY_ID` is unique per source and aborts loudly if not, and (c) asserts `master_data_3` is a complete superset of all IDs from md1, md2, md4–md8 and aborts loudly if not.

SAS 9.4 has no native SHA-256 function for files. The standard Windows approach is to call `certutil -hashfile <path> SHA256` via a `FILENAME PIPE` statement and read the output back into a SAS dataset. This is the correct strategy for this environment — no third-party tools required, `certutil.exe` ships with every Windows installation.

Loud failure is implemented via `%abort cancel` (or `%abort abend`) inside a macro that checks a row count against an expected value. The SAS macro variable `&SQLOBS` (from PROC SQL) or a direct PROC SQL select into a macro variable are the two most reliable mechanisms. `PROC CONTENTS OUT=` extracts structural metadata (nobs, variable list) without reading observation data — it is the correct tool for counting rows and enumerating variables before any data step runs.

**Primary recommendation:** Use `FILENAME PIPE "certutil -hashfile ..."` for SHA-256, `PROC CONTENTS OUT=` for structural metadata, `PROC SQL INTO :macvar` for counted assertions, and `%abort cancel` for loud failure. All patterns are native SAS 9.4 on Windows — no additional installs.

---

## Project Constraints (from CLAUDE.md)

- SAS 9.4M8 on Windows; session encoding is NOT UTF-8 (source of PCM-F-10 encoding damage — do not attempt re-encoding)
- Source files `master_data_1..8.sas7bdat` are **read-only** — the program must never write or modify them
- No PHI in git: `.sas7bdat`, `.xlsx`, `.csv`, `data/` tree are gitignored; only `.sas` programs and QC text/log artifacts may be committed
- Delivery: UF colors (#0021A5, #FA4616) on visual deliverables (not applicable to this phase — no Excel/HTML output required)
- Repo is on local disk (not P: drive); source data lives on P: drive — `libname` must point to P: path

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SRC-01 | `PRECEDE_STUDY_ID` is strictly one row per patient in all eight source files (PCM-F-01 asserted in code) | PROC SQL + `%abort cancel` pattern; uniqueness check via `PROC SORT NODUPKEY` or `HAVING COUNT(*)>1` |
| SRC-02 | `master_data_3` is a complete superset of all IDs from md1, md2, md4–md8 (PCM-F-02 asserted in code) | Anti-join pattern in PROC SQL: select IDs from md_x NOT IN md3, assert 0 rows |
| SRC-03 | Per-source row/ID counts written to `qc/` as committed artifacts | PROC CONTENTS OUT= or PROC SQL select count(*) into :n, write to `qc/src_counts.txt` via FILE/PUT |
| SRC-04 | Source files checksummed at start of every run; SHA-256 artifact committed in `qc/` | FILENAME PIPE certutil, read hash line, write to `qc/checksums.txt` |
</phase_requirements>

---

## Standard Stack

### Core

| Tool/Pattern | Version | Purpose | Why Standard |
|---|---|---|---|
| `FILENAME PIPE "certutil -hashfile <path> SHA256"` | Windows built-in | Compute SHA-256 of `.sas7bdat` without leaving SAS | `certutil.exe` ships on all Windows versions; no install needed |
| `PROC CONTENTS DATA=lib.mdX OUT=work.contents_mdX NOPRINT;` | SAS 9.4 | Extract nobs, variable list without reading observations | Reads metadata only; safe on read-only sources |
| `PROC SQL; SELECT COUNT(*) INTO :n FROM lib.mdX;` | SAS 9.4 | Count rows at runtime for assertion | Executes in one pass; result in macro variable |
| `%abort cancel;` inside a macro | SAS 9.4 | Loud termination that marks session as failed | `%abort cancel` sets `&SYSERR`/`&SYSCC` and stops batch; visible in log |
| `PROC SQL HAVING COUNT(*) > 1` | SAS 9.4 | Detect duplicate `PRECEDE_STUDY_ID` values | Returns the offending IDs; count stored via `&SQLOBS` |

### certutil Output Format

`certutil -hashfile <file> SHA256` produces three lines:
```
SHA256 hash of <file>:
<64-character hex hash>
CertUtil: -hashfile command completed successfully.
```
Parse the **second line** (trim whitespace). The first and third lines are headers — use `INPUT` with appropriate line-pointer control or a length filter (`LENGTH(line) = 64`).

### FILENAME PIPE Syntax in SAS

```sas
filename hashpipe pipe 'certutil -hashfile "P:\path\to\master_data_1.sas7bdat" SHA256';
data _null_;
  infile hashpipe truncover;
  input line $200.;
  line = strip(line);
  if length(line) = 64 then do;
    /* this is the hash line */
    call symputx('hash_md1', line);
  end;
run;
filename hashpipe clear;
```

**Confidence:** HIGH — FILENAME PIPE is a SAS 9.4 first-class feature; certutil SHA256 is Windows-standard.

### Abort Macro Pattern

```sas
%macro assert_zero(dsn=, condition_sql=, msg=);
  /* condition_sql should return rows ONLY when the assertion FAILS */
  proc sql noprint;
    select count(*) into :_fail_n trimmed
    from &dsn
    where &condition_sql;
  quit;
  %if &_fail_n > 0 %then %do;
    %put ERROR: ASSERTION FAILED -- &msg (&_fail_n offending rows);
    %abort cancel;
  %end;
%mend assert_zero;
```

For uniqueness (PCM-F-01):
```sas
proc sql noprint;
  create table work._dups_md1 as
    select PRECEDE_STUDY_ID, count(*) as n
    from lib.master_data_1
    group by PRECEDE_STUDY_ID
    having count(*) > 1;
quit;
/* &SQLOBS holds the row count of the last SELECT/CREATE */
%if &SQLOBS > 0 %then %do;
  %put ERROR: PCM-F-01 VIOLATION: Duplicate PRECEDE_STUDY_ID in master_data_1 (&SQLOBS IDs affected);
  %abort cancel;
%end;
```

For superset (PCM-F-02):
```sas
proc sql noprint;
  create table work._not_in_md3 as
    select 'md1' as src, PRECEDE_STUDY_ID
    from lib.master_data_1
    where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from lib.master_data_3)
  union all
    select 'md2', PRECEDE_STUDY_ID from lib.master_data_2
    where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from lib.master_data_3)
    /* ... repeat for md4, md5, md6, md7, md8 */
    ;
quit;
%if &SQLOBS > 0 %then %do;
  %put ERROR: PCM-F-02 VIOLATION: md3 is NOT a superset -- &SQLOBS IDs missing from md3;
  %abort cancel;
%end;
```

**Confidence:** HIGH — `&SQLOBS` is populated after every `CREATE TABLE AS SELECT` or `SELECT ... INTO` in PROC SQL in SAS 9.4.

---

## Architecture Patterns

### Recommended Program Structure for `01_verify_sources.sas`

```
01_verify_sources.sas
  Wave 1 — Setup
    %let source_path = P:\PeCAN Master Data\...;
    libname src "&source_path" access=readonly;
    filename qcout "C:\...\qc\checksums.txt";   /* output artifact */

  Wave 2 — Checksums (SRC-04)
    For each md1..md8:
      FILENAME PIPE certutil → read hash → symputx('hash_mdX')
    Write all 8 hashes + run timestamp to qc/checksums.txt

  Wave 3 — Structural inventory (SRC-03)
    PROC CONTENTS OUT=work.contents for each source → capture nobs
    Write per-source row/ID summary to qc/src_counts.txt

  Wave 4 — PCM-F-01: uniqueness assertion (SRC-01)
    For each md1..md8: PROC SQL HAVING COUNT(*) > 1 → %abort cancel if any dups

  Wave 5 — PCM-F-02: superset assertion (SRC-02)
    PROC SQL union anti-join: IDs in md1/md2/md4-md8 NOT IN md3 → %abort cancel if any
```

### Output Artifacts (both committed, not gitignored)

| File | Location | Content | Committed? |
|---|---|---|---|
| `checksums.txt` | `qc/checksums.txt` | SHA-256 hash per source + run timestamp | Yes — text file, no PHI |
| `src_counts.txt` | `qc/src_counts.txt` | Source name, nobs, distinct ID count | Yes — text file, no PHI |

Both are plain text (not `.csv`/`.xlsx`), so they are NOT excluded by the `.gitignore` rule that covers `*.csv` and `*.xlsx`.

### Anti-Patterns to Avoid

- **`%abort`** without `cancel` or `abend`: Plain `%abort` is a warning-level stop in interactive SAS; use `%abort cancel` for batch-safe termination that propagates a failure return code.
- **Reading `.sas7bdat` metadata via DATA step**: Use `PROC CONTENTS OUT=` — it reads the file header only, not observation data, and works safely on read-only files.
- **`CALL SYSTEM("certutil ...")`**: `CALL SYSTEM` runs the command but does not capture output back into SAS. Use `FILENAME PIPE` to read the hash into a SAS variable.
- **Writing QC artifacts with `PROC EXPORT` to `.csv`**: `.csv` is gitignored. Write checksums/counts as plain `.txt` via `FILE`/`PUT` or `ODS TEXT`.
- **Assuming `FILENAME PIPE` with spaces in path works without quotes**: Always double-quote the file path inside the certutil command string when the P: path contains spaces (it does: `P:\PeCAN Master Data\...`).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| SHA-256 of a binary file | SAS character hashing, PROC IML loop | `certutil -hashfile` via FILENAME PIPE | Binary file hashing in SAS DATA step is not feasible without C-callable functions; certutil is reliable and present on every Windows machine |
| Row count from metadata | `SELECT COUNT(*) FROM lib.mdX` (reads all obs) | `PROC CONTENTS OUT=` then read `nobs` variable | PROC CONTENTS reads only the file descriptor — faster and safe on large files |
| Abort on assertion failure | `ENDSAS;` | `%abort cancel;` | `ENDSAS;` works in interactive but in batch may not set the return code correctly; `%abort cancel` is the documented method for clean batch failure |

---

## Common Pitfalls

### Pitfall 1: Paths with spaces inside FILENAME PIPE
**What goes wrong:** `certutil` receives a split command line — `P:\PeCAN` is treated as the filename, `Master` as the next argument — producing "The system cannot find the file specified."
**Why it happens:** The SAS string passed to `PIPE` is passed to `cmd.exe`; spaces break argument parsing unless the path is quoted.
**How to avoid:** Use escaped double-quotes inside the pipe string: `pipe 'certutil -hashfile "P:\PeCAN Master Data\...\master_data_1.sas7bdat" SHA256'`
**Warning signs:** certutil exit code non-zero; hash line never matches the 64-character filter.

### Pitfall 2: Parsing certutil output — capturing the wrong line
**What goes wrong:** The word "completed" or the algorithm label line is captured as the hash.
**Why it happens:** certutil emits 3 lines; naive `INPUT line $64.` grabs the first line.
**How to avoid:** Filter by `length(strip(line)) = 64` — only the actual hex hash satisfies this length.

### Pitfall 3: `%abort cancel` inside a macro called from `%include`
**What goes wrong:** `%abort cancel` terminates the entire SAS session cleanly — but if the program is `%include`d from `99_run_all.sas`, the abort propagates correctly and stops the run-all. This is the desired behavior; just document it.
**Why it happens:** `%abort cancel` is session-scoped.
**How to avoid:** No workaround needed — this is correct. Include a `%put ERROR:` before every `%abort cancel` so the log is unambiguous.

### Pitfall 4: `PROC CONTENTS` nobs vs actual row count discrepancy
**What goes wrong:** On datasets with deleted observations, `nobs` from the file header may differ from a `COUNT(*)` pass.
**Why it happens:** SAS tracks deleted obs in the header but `COUNT(*)` skips them.
**How to avoid:** For a true row count assertion, use `SELECT COUNT(*) INTO :n FROM lib.mdX` in PROC SQL. Use `PROC CONTENTS` nobs only for the informational QC artifact (SRC-03), not for `%abort` assertions.

### Pitfall 5: Writing QC artifacts to gitignored paths
**What goes wrong:** Output written to `data/` tree or as `.csv`/`.xlsx` is gitignored and the committed artifact requirement (SRC-03, SRC-04) fails.
**Why it happens:** `.gitignore` covers those extensions and paths.
**How to avoid:** Write all QC text artifacts to `qc/` as `.txt` files. Confirm `.gitignore` does NOT exclude `qc/*.txt`.

### Pitfall 6: LIBNAME on read-only P: drive — timing
**What goes wrong:** If the P: drive mapping is not established before the SAS session opens, the `libname` statement fails silently or with a non-aborting note.
**Why it happens:** Network drive availability at SAS startup varies on Windows.
**How to avoid:** Add a `LIBNAME src ... access=readonly;` and immediately check `%sysfunc(libref(src))` — value 0 means success; non-zero means drive unavailable. Abort if non-zero.

---

## Code Examples

### Verified Pattern: Write plain-text artifact from SAS (no PHI, committable)

```sas
/* Write per-source row counts to qc/src_counts.txt */
filename counts "C:\Master_Renamed_same_format_accross\qc\src_counts.txt";
data _null_;
  file counts;
  put "Source Verification Report -- Run: %sysfunc(datetime(), datetime20.)";
  put "Source         | NOBS  | Distinct_IDs";
  put "-----------------------------------";
run;
filename counts clear;
```

### Verified Pattern: Check libname assignment before proceeding

```sas
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib could not be assigned. Check P: drive availability.;
    %abort cancel;
  %end;
%mend check_libname;
%check_libname(lib=src);
```

### Verified Pattern: SHA-256 via certutil FILENAME PIPE

```sas
%macro get_sha256(filepath=, outvar=);
  filename _hpipe pipe "certutil -hashfile ""&filepath"" SHA256";
  data _null_;
    infile _hpipe truncover;
    input line $200.;
    line = strip(line);
    if length(line) = 64 then call symputx("&outvar", line, 'G');
  run;
  filename _hpipe clear;
%mend get_sha256;

%get_sha256(filepath=P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\master_data_1.sas7bdat,
            outvar=hash_md1);
%put NOTE: md1 SHA-256 = &hash_md1;
```

Note: Inside a macro, `""` produces a literal double-quote in the string passed to the pipe command.

---

## State of the Art

| Old Approach | Current Approach | Notes |
|---|---|---|
| `MD5()` SAS character function for content hashing | `certutil -hashfile` via FILENAME PIPE | MD5() hashes SAS character values, not binary files — wrong tool |
| `ENDSAS;` to stop on error | `%abort cancel;` | `ENDSAS` not recommended in batch; `%abort cancel` is the documented pattern |
| Manual inspection of PROC CONTENTS output | `PROC CONTENTS OUT=` dataset + PROC SQL assertion | Programmatic, reproducible, runnable in `99_run_all.sas` |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| `certutil.exe` | SRC-04 (SHA-256 checksum) | Expected ✓ | Ships with Windows 10 | PowerShell `Get-FileHash` via FILENAME PIPE (same approach, different command) |
| SAS `FILENAME PIPE` | SRC-04 | ✓ | SAS 9.4 base feature | None needed |
| P: drive (`\PeCAN Master Data\...`) | All SRC requirements | Must verify at runtime | Network drive | None — data is only on P: |
| `qc\`, `sas\`, `logs\`, `docs\` directories | SRC-03, SRC-04 | ✓ confirmed (empty) | — | — |

**Missing dependencies with no fallback:**
- P: drive must be mapped before `01_verify_sources.sas` runs; the program should `%abort cancel` with a clear message if the libname assignment fails.

**Missing dependencies with fallback:**
- If `certutil` is somehow unavailable (atypical on Windows 10), the PowerShell equivalent is: `Get-FileHash -Algorithm SHA256 "<path>" | Select-Object -ExpandProperty Hash` — same FILENAME PIPE pattern.

---

## Validation Architecture

### Test Framework

| Property | Value |
|---|---|
| Framework | None — no unit test framework for SAS; validation is embedded assertions |
| Config file | n/a |
| Quick run command | `sas -sysin "C:\Master_Renamed_same_format_accross\sas\01_verify_sources.sas"` |
| Full suite command | same (single-program phase) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | How Verified |
|---|---|---|---|
| SRC-01 | PRECEDE_STUDY_ID unique per source | Embedded assertion | `%abort cancel` if HAVING COUNT(*)>1 — appears in SAS log as ERROR + abort |
| SRC-02 | md3 superset of all other IDs | Embedded assertion | `%abort cancel` if anti-join returns rows |
| SRC-03 | Per-source counts in `qc/src_counts.txt` | Output artifact check | File exists and is non-empty after program run |
| SRC-04 | SHA-256 hashes in `qc/checksums.txt` | Output artifact check | File exists, contains 8 hash lines of length 64 |

### Wave 0 Gaps

- [ ] `sas/01_verify_sources.sas` — does not yet exist (empty `sas/` directory confirmed)
- [ ] `qc/checksums.txt` — created by the program on first run; must be committed after Phase 1 passes
- [ ] `qc/src_counts.txt` — created by the program on first run; must be committed after Phase 1 passes

---

## Open Questions

1. **Exact path to source files on P: drive**
   - What we know: `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\` (from STATE.md)
   - What's unclear: Are the `.sas7bdat` files directly in that directory or in a subdirectory? Are they named exactly `master_data_1.sas7bdat` through `master_data_8.sas7bdat`?
   - Recommendation: The plan should include a Wave 0 task that verifies the exact path and filenames before writing the program. A `PROC CONTENTS` on a hardcoded path will fail informatively if the name is wrong.

2. **Expected row counts per source (for SRC-03 artifact)**
   - What we know: md3 spine = 41,150 rows; md8-only block = 22,473 (implies md8 has at least 22,473 rows)
   - What's unclear: Exact row counts for md1, md2, md4–md7 are not documented
   - Recommendation: Phase 1 discovers and records these counts; they become frozen expectations that Phase 4 must reproduce.

3. **`PRECEDE_STUDY_ID` variable name casing**
   - What we know: STATE.md uses `PRECEDE_STUDY_ID`; md6 has a duplicate `PRECEDE_Study_ID_1` column
   - What's unclear: Does any source spell it differently (e.g., mixed case)?
   - Recommendation: The program should `upcase()` the variable name when building the check, or `PROC CONTENTS` first to confirm the exact variable name in each source.

---

## Sources

### Primary (HIGH confidence)
- SAS 9.4 Base Procedures Guide — PROC CONTENTS OUT= dataset: documented in official SAS docs
- SAS 9.4 Macro Language Reference — `%abort cancel`: documented behavior for batch termination
- SAS 9.4 FILENAME PIPE statement: base product, stable across 9.4 releases
- Microsoft certutil documentation: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil

### Secondary (MEDIUM confidence)
- SAS `&SQLOBS` automatic macro variable behavior after `CREATE TABLE AS SELECT`: well-documented in SAS Papers (support.sas.com/resources/papers/proceedings15/1565-2015.pdf)
- certutil output format (3 lines, hash on line 2): verified via multiple sources including https://www.foldermanifest.com/blog/certutil-verify-checksum-windows

### Tertiary (LOW confidence)
- None — all critical patterns verified at PRIMARY or SECONDARY level

---

## Metadata

**Confidence breakdown:**
- SHA-256 via certutil FILENAME PIPE: HIGH — standard Windows tool, standard SAS feature, well-documented
- PROC CONTENTS OUT= for structural metadata: HIGH — SAS 9.4 base product, stable
- `%abort cancel` for loud failure: HIGH — documented in SAS Macro Language Reference
- `&SQLOBS` post-CREATE TABLE: HIGH — documented automatic macro variable
- Exact source file paths/names: LOW — not confirmed from bash; plan must verify before writing program

**Research date:** 2026-08-25
**Valid until:** 2026-09-25 (SAS 9.4 patterns are very stable; certutil is OS-standard)
