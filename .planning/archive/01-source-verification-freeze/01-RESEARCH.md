# Phase 1: Source Verification & Freeze - Research

**Researched:** 2026-08-25
**Revised:** 2026-08-25 (post-review)
**Domain:** SAS 9.4M8 on Windows — file checksumming, PROC CONTENTS, macro-level assertion/abort, uniqueness checking
**Confidence:** HIGH for SAS patterns and certutil; **XCMD availability is UNVERIFIED and gates SRC-04 entirely**

## Revision log — 2026-08-25 post-review

| Change | Reason |
|---|---|
| `&SQLOBS` removed from all assertion patterns; replaced with `SELECT COUNT(*) INTO :n TRIMMED` | It was the abort trigger for both structural guarantees, and its CREATE TABLE behavior is version/context-dependent (Pitfall 7). The body rated it HIGH while the citation was filed Secondary. |
| Added SRC-05 (blank-key assertion), ordered BEFORE SRC-01 | A blank key passes uniqueness and the superset check, then becomes a Phase 4 merge key joining unrelated patients (Pitfall 10) |
| Added SRC-06 (key name/type/length across all eight) | md7's key was `NUM8` originally, destroyed by PCM-T-01, and rebuilt — it now shows `Char 12` with no format/informat while the others show `$12.`. A numeric key silently breaks the SRC-02 anti-join. Also resolves Open Questions 1 and 3, which the original plan answered for md3 only. |
| Added XCMD as a Wave 0 blocker | `FILENAME PIPE` requires it, and the documented PowerShell fallback uses the same mechanism — so there was no fallback at all under `NOXCMD` (Pitfall 8) |
| Corrected "Don't Hand-Roll" row-count guidance | It contradicted Pitfall 4 in the same document |
| Softened the `%abort cancel` return-code claim | Halting and logging is established; nonzero OS exit code is not |
| Added the checksum regeneration caveat, to be printed in the artifact itself | A `.sas7bdat` hash changes on re-import; the sources are already from two import runs (Pitfall 9) |

---

## Summary

Phase 1 must produce a single program `01_verify_sources.sas` that (a) checksums all eight `.sas7bdat` source files and writes hashes to a committed artifact in `qc/`, (b) asserts `PRECEDE_STUDY_ID` is unique per source and aborts loudly if not, and (c) asserts `master_data_3` is a complete superset of all IDs from md1, md2, md4–md8 and aborts loudly if not.

SAS 9.4 has no native SHA-256 function for files. The standard Windows approach is to call `certutil -hashfile <path> SHA256` via a `FILENAME PIPE` statement and read the output back into a SAS dataset. This is the correct strategy for this environment — no third-party tools required, `certutil.exe` ships with every Windows installation.

Loud failure is implemented via `%abort cancel` inside a macro that checks a row count against an expected value. **Use an explicit `SELECT COUNT(*) INTO :macvar TRIMMED` for every assertion — do not use `&SQLOBS`** (see Pitfall 7). `PROC CONTENTS OUT=` extracts structural metadata (variable name, type, length) without reading observation data — it is the correct tool for enumerating and type-checking variables before any data step runs, but **not** for row counts used in assertions (Pitfall 4).

**Primary recommendation:** Use `FILENAME PIPE "certutil -hashfile ..."` for SHA-256, `PROC CONTENTS OUT=` for structural metadata and key type/length verification, `PROC SQL INTO :macvar` for all counted assertions, and `%abort cancel` for loud failure. All patterns are native SAS 9.4 on Windows — no additional installs. **`FILENAME PIPE` requires the `XCMD` system option to be enabled; verify this in Wave 0 before anything else** (Pitfall 8).

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

| ID | PROJECT.md ref | Description | Research Support |
|----|---|-------------|------------------|
| SRC-01 | PCM-F-01 | `PRECEDE_STUDY_ID` is strictly one row per patient in all eight source files (asserted in code) | PROC SQL + `%abort cancel` pattern; uniqueness check via `HAVING COUNT(*)>1` counted into a macro variable |
| SRC-02 | PCM-F-02 | `master_data_3` is a complete superset of all IDs from md1, md2, md4–md8 (asserted in code) | Anti-join pattern in PROC SQL: select IDs from md_x NOT IN md3, assert 0 rows |
| SRC-03 | PCM-R-14 | Per-source row/ID counts written to `qc/` as committed artifacts | PROC SQL select count(*) into :n, write to `qc/src_counts.txt` via FILE/PUT |
| SRC-04 | PCM-R-13 | Source files checksummed at start of every run; SHA-256 artifact committed in `qc/` | FILENAME PIPE certutil, read hash line, write to `qc/checksums.txt` |
| SRC-05 | PCM-R-04 | `PRECEDE_STUDY_ID` is non-missing in every row of all eight sources | `sum(missing(PRECEDE_STUDY_ID))` per source, asserted to zero — must run BEFORE SRC-01 |
| SRC-06 | PCM-T-01 | `PRECEDE_STUDY_ID` is `Char 12` in all eight sources (name, type, and length verified, not assumed) | `PROC CONTENTS OUT=` across all eight, single PROC SQL assertion on type/length |

**Namespace note:** `SRC-xx` are phase-local IDs. `PCM-R-13` (checksums) and `PCM-R-14`
(per-source counts) must be added to PROJECT.md §4 — they currently exist only as a Phase 1
exit criterion, which breaks the traceability chain the ID scheme exists to provide.
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
| `PROC SQL HAVING COUNT(*) > 1` | SAS 9.4 | Detect duplicate `PRECEDE_STUDY_ID` values | Returns the offending IDs; count captured via `SELECT COUNT(*) INTO :n` — NOT `&SQLOBS` (Pitfall 7) |
| `%sysfunc(getoption(xcmd))` | SAS 9.4 | Confirm shell-out is permitted before relying on FILENAME PIPE | SRC-04 is unimplementable under `NOXCMD` (Pitfall 8) |

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

For blank keys (SRC-05) — must run BEFORE uniqueness, so a blank produces a
"blank ID" error rather than a confusing duplicate error:
```sas
proc sql noprint;
  select sum(missing(PRECEDE_STUDY_ID)) into :n_blank trimmed
  from lib.master_data_1;
quit;
%if &n_blank > 0 %then %do;
  %put ERROR: SRC-05 VIOLATION: &n_blank blank PRECEDE_STUDY_ID in master_data_1;
  %abort cancel;
%end;
```

For uniqueness (PCM-F-01) — count into a macro variable, not `&SQLOBS`:
```sas
proc sql noprint;
  select count(*) into :n_dups trimmed
  from (select PRECEDE_STUDY_ID
        from lib.master_data_1
        group by PRECEDE_STUDY_ID
        having count(*) > 1);
quit;
%if &n_dups > 0 %then %do;
  %put ERROR: PCM-F-01 VIOLATION: Duplicate PRECEDE_STUDY_ID in master_data_1 (&n_dups IDs affected);
  %abort cancel;
%end;
```

For superset (PCM-F-02) — same discipline. Build the anti-join table (useful for
diagnosis when it fails), then count it explicitly:
```sas
proc sql noprint;
  create table work._not_in_md3 as
    select 'md1' as src length=3, PRECEDE_STUDY_ID
    from lib.master_data_1
    where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from lib.master_data_3)
  union all
    select 'md2', PRECEDE_STUDY_ID from lib.master_data_2
    where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from lib.master_data_3)
    /* ... repeat for md4, md5, md6, md7, md8 */
    ;

  select count(*) into :n_orphan trimmed from work._not_in_md3;
quit;
%if &n_orphan > 0 %then %do;
  %put ERROR: PCM-F-02 VIOLATION: md3 is NOT a superset -- &n_orphan IDs missing from md3;
  %abort cancel;
%end;
```

**Confidence:** HIGH for the counted-macro-variable pattern. See Pitfall 7 for why
`&SQLOBS` is not used here.

### Key type/length verification (SRC-06)

`PROC CONTENTS OUT=` on all eight in one pass, then a single assertion. This matters
specifically because md7's `PRECEDE_STUDY_ID` was `NUM8` in the original crosswalk, was
destroyed by a `PROC SQL UPDATE ... CATS` (PCM-T-01), and was rebuilt from Excel — it now
shows `Char 12` with **no format or informat**, while the other seven show `$12. / $12.`.
The data matches today, but a numeric key in any source would make the SRC-02 anti-join
either fail on type mismatch or coerce silently.

```sas
proc contents data=src._all_ out=work._allvars
  (keep=memname name type length) noprint;
run;

proc sql noprint;
  select count(*) into :n_badkey trimmed
  from work._allvars
  where upcase(name) = 'PRECEDE_STUDY_ID'
    and upcase(memname) in ('MASTER_DATA_1','MASTER_DATA_2','MASTER_DATA_3','MASTER_DATA_4',
                            'MASTER_DATA_5','MASTER_DATA_6','MASTER_DATA_7','MASTER_DATA_8')
    and not (type = 2 and length = 12);   /* type=2 is character */
quit;
```

Note `PROC CONTENTS DATA=src._all_` also picks up `PRECEDE_Study_ID_1` in md6 — the
`upcase(name) = 'PRECEDE_STUDY_ID'` filter excludes it, since the duplicate column's
name differs by the `_1` suffix.

---

## Architecture Patterns

### Recommended Program Structure for `01_verify_sources.sas`

```
01_verify_sources.sas
  Setup — preconditions
    %let source_path = P:\PeCAN Master Data\...;
    libname src "&source_path" access=readonly;
    check libref(src) = 0                        → %abort cancel if not
    check %sysfunc(getoption(xcmd)) = XCMD       → %abort cancel if NOXCMD  (Pitfall 8)

  Structural discovery (SRC-06)
    PROC CONTENTS DATA=src._all_ OUT=work._allvars
    Assert PRECEDE_STUDY_ID present, type=char, length=12 in ALL EIGHT
                                                 → %abort cancel if not

  Checksums (SRC-04)
    For each md1..md8:
      FILENAME PIPE certutil → read hash → symputx('hash_mdX', ..., 'G')
    Guard: every hash_mdX non-blank            → %abort cancel if any empty
    Write 8 hashes + timestamp + regeneration caveat to qc/checksums.txt

  Structural inventory (SRC-03)
    PROC SQL COUNT(*) and COUNT(DISTINCT id) per source
    Write per-source row/ID summary to qc/src_counts.txt

  --- assertions below this line; order matters ---

  SRC-05: blank-key assertion       (runs FIRST — Pitfall 10)
    For each md1..md8: sum(missing(id)) = 0    → %abort cancel if any

  SRC-01 / PCM-F-01: uniqueness assertion
    For each md1..md8: HAVING COUNT(*) > 1, counted INTO :n
                                                 → %abort cancel if any dups

  SRC-02 / PCM-F-02: superset assertion
    Union anti-join: IDs in md1/md2/md4-md8 NOT IN md3, counted INTO :n
                                                 → %abort cancel if any
```

Assertion order is load-bearing: SRC-06 before anything that compares IDs (a numeric key
breaks the anti-join), and SRC-05 before SRC-01 (a blank key otherwise surfaces as a
confusing duplicate error).

### Output Artifacts (both committed, not gitignored)

| File | Location | Content | Committed? |
|---|---|---|---|
| `checksums.txt` | `qc/checksums.txt` | SHA-256 hash per source + run timestamp | Yes — text file, no PHI |
| `src_counts.txt` | `qc/src_counts.txt` | Source name, nobs, distinct ID count | Yes — text file, no PHI |

Both are plain text (not `.csv`/`.xlsx`), so they are NOT excluded by the `.gitignore` rule that covers `*.csv` and `*.xlsx`.

### Anti-Patterns to Avoid

- **`%abort`** without `cancel` or `abend`: Plain `%abort` is a warning-level stop in interactive SAS; use `%abort cancel` to stop processing cleanly. **Do not assume `%abort cancel` sets a nonzero OS return code** — it reliably halts the run and writes ERROR to the log, which is what Phase 1 needs, but if `99_run_all.sas` is ever scheduled or run under CI and must fail visibly to the caller, verify the return code or switch to `%abort abend` / `%abort return <n>`, which set it unambiguously. Decision deferred to Phase 8.
- **Reading `.sas7bdat` metadata via DATA step**: Use `PROC CONTENTS OUT=` — it reads the file header only, not observation data, and works safely on read-only files.
- **`CALL SYSTEM("certutil ...")`**: `CALL SYSTEM` runs the command but does not capture output back into SAS. Use `FILENAME PIPE` to read the hash into a SAS variable.
- **Writing QC artifacts with `PROC EXPORT` to `.csv`**: `.csv` is gitignored. Write checksums/counts as plain `.txt` via `FILE`/`PUT` or `ODS TEXT`.
- **Assuming `FILENAME PIPE` with spaces in path works without quotes**: Always double-quote the file path inside the certutil command string when the P: path contains spaces (it does: `P:\PeCAN Master Data\...`).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| SHA-256 of a binary file | SAS character hashing, PROC IML loop | `certutil -hashfile` via FILENAME PIPE | Binary file hashing in SAS DATA step is not feasible without C-callable functions; certutil is reliable and present on every Windows machine |
| Structural metadata (variable names, types, lengths) | Hand-parsing a DATA step against the source | `PROC CONTENTS OUT=` | Reads the file descriptor only — safe and fast on read-only sources |
| Abort on assertion failure | `ENDSAS;` | `%abort cancel;` | `ENDSAS;` works in interactive but in batch may not set the return code correctly; `%abort cancel` is the documented method for clean batch failure |

**Row counts are the exception:** use `SELECT COUNT(*) INTO :n` for any count that feeds
an assertion, NOT `PROC CONTENTS` nobs — see Pitfall 4. These eight files total ~78 MB, so
the full-pass cost is negligible and correctness wins. An earlier draft of this table
recommended nobs for row counts; that was wrong and contradicted Pitfall 4.

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

### Pitfall 7: `&SQLOBS` after `CREATE TABLE AS SELECT`
**What goes wrong:** The assertion silently never fires (or fires spuriously) because
`&SQLOBS` holds a stale value from an earlier statement, or 0 after a CREATE TABLE.
**Why it happens:** `SQLOBS` is documented for `SELECT`. Its behavior after
`CREATE TABLE ... AS SELECT` is version- and context-dependent, and it is not reset by
statements that produce no output — so a preceding `SELECT ... INTO` can leave a value
behind that the next `%if` reads. The supporting citation for the CREATE TABLE case is
rated MEDIUM in Sources below, not HIGH.
**How to avoid:** Never use `&SQLOBS` for an assertion. Always
`select count(*) into :n trimmed`, which sets the macro variable unconditionally.
**Why it matters here:** `&SQLOBS` was the abort trigger for both SRC-01 and SRC-02 in the
first draft — i.e. both structural guarantees of the freeze rested on it.

### Pitfall 8: `FILENAME PIPE` blocked by `NOXCMD`
**What goes wrong:** Every `filename ... pipe` statement fails, SRC-04 produces no hashes,
and the empty-hash guard aborts the run with a message that points at certutil rather than
at the real cause.
**Why it happens:** Many managed/server SAS deployments run with `NOXCMD`, which disables
all shell-out mechanisms. The option cannot be changed at runtime — it is set at invocation.
**How to avoid:** Check `%sysfunc(getoption(xcmd))` in Wave 0, before writing any code that
depends on it. Note the documented PowerShell `Get-FileHash` fallback **is not a fallback**
— it also goes through `FILENAME PIPE` and fails identically under `NOXCMD`.
**Real fallback if XCMD is off:** a weaker freeze from `sashelp.vtable` — `filesize`,
`crdate`, `modate`, `nobs`, `nvar` per source. Not tamper-evident, but reproducible and
committable, and enough to detect a changed extract.

### Pitfall 9: Treating a `.sas7bdat` hash as a hash of the data
**What goes wrong:** A future run reports a checksum mismatch and someone concludes the
data is corrupt, when the file was simply re-imported.
**Why it happens:** A `.sas7bdat` embeds its creation datetime and other run-specific
header bytes. Re-importing byte-identical data from the same `.xlsx` produces a different
SHA-256 every time.
**How to avoid:** State this in the artifact itself, not just in documentation. Note that
the current sources are already from two different import runs — `PROC CONTENTS` shows
md1/md4/md7 created ~15:05–15:09 and the other five at ~14:43 — so mixed creation
timestamps are the expected state, not an anomaly.
**What the hash IS good for:** proving that the files verified in Phase 1 are byte-identical
to the files Phase 4 merges, within a single working session.

### Pitfall 10: Blank `PRECEDE_STUDY_ID` passing every check
**What goes wrong:** A blank key passes uniqueness (a single blank is unique), passes the
superset check (md3 has a blank too), and then becomes a merge key in Phase 4 that joins
unrelated patient records.
**Why it happens:** Uniqueness and superset assertions both test relationships between
values, not the validity of the values themselves.
**How to avoid:** Assert `sum(missing(PRECEDE_STUDY_ID)) = 0` per source (SRC-05) and run it
**before** SRC-01, so the error message names the actual problem.
**Related:** SAS SQL treats missing as a comparable value in `NOT IN`, unlike ANSI SQL's
three-valued logic — so a blank does not poison the anti-join, it just passes through it.

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
| **SAS `XCMD` system option** | **SRC-04 (gates FILENAME PIPE)** | **MUST VERIFY — Wave 0** | set at invocation, not runtime | `sashelp.vtable` metadata freeze (filesize/crdate/modate/nobs/nvar) — weaker, but the only option if XCMD is off |
| `certutil.exe` | SRC-04 (SHA-256 checksum) | Expected ✓ | Ships with Windows 10 | PowerShell `Get-FileHash` — **only if XCMD is on**; it uses the same PIPE mechanism, so it is not a fallback for NOXCMD |
| SAS `FILENAME PIPE` | SRC-04 | ✓ base feature, but **requires XCMD** | SAS 9.4 base feature | see XCMD row |
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
| SRC-01 | PRECEDE_STUDY_ID unique per source | Embedded assertion | `%abort cancel` if counted dups > 0 — appears in SAS log as ERROR + abort |
| SRC-02 | md3 superset of all other IDs | Embedded assertion | `%abort cancel` if counted anti-join rows > 0 |
| SRC-03 | Per-source counts in `qc/src_counts.txt` | Output artifact check | File exists, 8 data rows each with two integers |
| SRC-04 | SHA-256 hashes in `qc/checksums.txt` | Output artifact check | File exists, contains 8 hash lines matching `^[0-9a-fA-F]{64}$` |
| SRC-05 | PRECEDE_STUDY_ID non-missing per source | Embedded assertion | `%abort cancel` if `sum(missing(id))` > 0 |
| SRC-06 | Key is Char 12 in all eight sources | Embedded assertion | `%abort cancel` if any source's key is absent, numeric, or not length 12 |

### Wave 0 Gaps

- [ ] **`XCMD` enabled** — run `%put %sysfunc(getoption(xcmd));` before writing any checksum code. If `NOXCMD`, SRC-04 must be rewritten against `sashelp.vtable` (Pitfall 8)
- [ ] `sas/01_verify_sources.sas` — does not yet exist (empty `sas/` directory confirmed)
- [ ] `qc/checksums.txt` — created by the program on first run; must be committed after Phase 1 passes
- [ ] `qc/src_counts.txt` — created by the program on first run; must be committed after Phase 1 passes

---

## Open Questions

1. **Exact path to source files on P: drive**
   - What we know: `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\` (from STATE.md)
   - What's unclear: Are the `.sas7bdat` files directly in that directory or in a subdirectory? Are they named exactly `master_data_1.sas7bdat` through `master_data_8.sas7bdat`?
   - Recommendation: RESOLVED by SRC-06 — `PROC CONTENTS DATA=src._all_` enumerates whatever is actually in the library, so wrong names surface immediately with an informative failure rather than being assumed.

2. **Expected row counts per source (for SRC-03 artifact)**
   - What we know: md3 spine = 41,150 rows; md8-only block = 22,473 (implies md8 has at least 22,473 rows)
   - What's unclear: Exact row counts for md1, md2, md4–md7 are not documented
   - Recommendation: Phase 1 discovers and records these counts; they become frozen expectations that Phase 4 must reproduce.

3. **`PRECEDE_STUDY_ID` variable name casing**
   - What we know: STATE.md uses `PRECEDE_STUDY_ID`; md6 has a duplicate `PRECEDE_Study_ID_1` column
   - What's unclear: Does any source spell it differently (e.g., mixed case)?
   - Recommendation: RESOLVED by SRC-06 — the assertion runs `upcase(name) = 'PRECEDE_STUDY_ID'` across all eight sources, so a casing or naming difference in ANY source aborts the run. The earlier plan checked md3 only, which would have deferred the failure to a later, less legible step.

---

## Sources

### Primary (HIGH confidence)
- SAS 9.4 Base Procedures Guide — PROC CONTENTS OUT= dataset: documented in official SAS docs
- SAS 9.4 Macro Language Reference — `%abort cancel`: documented behavior for batch termination
- SAS 9.4 FILENAME PIPE statement: base product, stable across 9.4 releases
- Microsoft certutil documentation: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil

### Secondary (MEDIUM confidence)
- SAS `&SQLOBS` automatic macro variable behavior after `CREATE TABLE AS SELECT`: SAS Papers (support.sas.com/resources/papers/proceedings15/1565-2015.pdf) — **no longer relied upon**; retained only to document why Pitfall 7 exists. The body of this research originally rated this HIGH while its own citation sat under Secondary; that gap is what triggered the review.
- certutil output format (3 lines, hash on line 2): verified via multiple sources including https://www.foldermanifest.com/blog/certutil-verify-checksum-windows

### Tertiary (LOW confidence)
- None — all critical patterns verified at PRIMARY or SECONDARY level

---

## Metadata

**Confidence breakdown:**
- SHA-256 via certutil FILENAME PIPE: HIGH — standard Windows tool, standard SAS feature, well-documented
- PROC CONTENTS OUT= for structural metadata: HIGH — SAS 9.4 base product, stable
- `%abort cancel` for loud failure: HIGH — documented in SAS Macro Language Reference
- `&SQLOBS` post-CREATE TABLE: MEDIUM — DOWNGRADED. Documented for SELECT; behavior after CREATE TABLE is version/context-dependent and it is not reset by statements producing no output. Replaced throughout with `SELECT COUNT(*) INTO :n TRIMMED` (Pitfall 7). The supporting source was already filed under Secondary while the body claimed HIGH — that inconsistency is what prompted the change.
- `XCMD` availability: UNVERIFIED — gates SRC-04 entirely; Wave 0 must confirm before implementation (Pitfall 8)
- `%abort cancel` OS return code: MEDIUM — halts the run and logs ERROR reliably; nonzero exit code to the caller not verified (see Anti-Patterns)
- Exact source file paths/names: LOW — not confirmed from bash; SRC-06 now discovers them at runtime via `src._all_` rather than assuming

**Research date:** 2026-08-25
**Valid until:** 2026-09-25 (SAS 9.4 patterns are very stable; certutil is OS-standard)
