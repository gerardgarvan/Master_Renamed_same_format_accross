# Phase 2: Ownership Map - Research

**Researched:** 2026-08-25
**Revised:** 2026-08-25 (post-review)
**Domain:** SAS 9.4M8 — PROC CONTENTS metadata enumeration, macro-driven ownership table construction, DECISIONS.md conflict documentation
**Confidence:** HIGH — all patterns are native SAS 9.4 already established in Phase 1

## Revision log — 2026-08-25 post-review

| Change | Reason |
|---|---|
| Pattern 1: `IN:` corrected to `IN` | `IN:` matches on prefix, so `MASTER_DATA_7B` matched `'MASTER_DATA_7'` and readmitted the stale artifact Pitfall 1 exists to exclude |
| Pattern 1: writes `work.allvars_src`, not back into `work.allvars` | `data X; set X;` is prohibited by PCM-R-01 (the rule PCM-T-02 produced) |
| Pattern 3: field widths corrected | `$40.` at @58 collided with a field at @82, silently truncating the source list for the most-conflicted variables |
| Pattern 3: artifact renamed `02_ownership_map.txt` | Research said `ownership_map.txt` while both plans and the validation contract said `02_ownership_map.txt` — the test map pointed at a file that would never exist |
| Pattern 4: re-run guard rewritten without FILENAME PIPE | The `findstr` pipe added an XCMD dependency to a phase that otherwise needs none (new Pitfall 7); a plain `infile` scan is equivalent |
| Pattern 4: cross-reference corrected to Pitfall 2 | It cited Pitfall 3, which is a different topic |
| Pattern 5: `VVALUE()` removed | Not reliable in PROC SQL; unnecessary once the sentinel guard is type-conditional |
| Pattern 5: type guard added | `Admit_BMI` and seven others are Char in md8 and Num elsewhere — a cross-type comparison is an error, not a disagreement (new Pitfall 8) |
| Pattern 5: fixed md3-vs-md1 pair replaced with iteration | That pair is already proven identical by PCM-F-04, so the check passed trivially |
| Known Conflicts table: `BMI` corrected to `Admit_BMI` | No variable named `BMI` exists in any source |

---

## Summary

Phase 2 must produce `02_ownership.sas`, a program that (a) reads structural metadata from all eight source files, (b) builds a variable→source ownership table and writes it to a committed artifact, (c) detects every variable name that appears in more than one source and lists all conflicts in `docs/DECISIONS.md`, and (d) names coalesce-wanted variables (BMI, Race) explicitly and asserts they do not silently disagree across sources.

The program does not modify any source data. It operates entirely on `PROC CONTENTS OUT=` metadata and then reads the actual data only for coalesce-conflict assertions on specific named variables. The output is two artifacts: `qc/02_ownership_map.txt` (human-readable, committed, reviewable before any merge) and `qc/ownership_map.sas7bdat` (machine-readable, gitignored, for Phase 4) and a DECISIONS.md conflict block in `docs/`.

The ownership model for this pipeline is "single declared owner per variable name." Where the same variable appears in multiple sources, one source is declared owner (written in code as a comment with rationale) and the others are declared non-contributing for that variable. Where coalesce-semantics are wanted (the value is taken from whichever source is non-missing), that is explicitly named in the program with a cross-source disagreement assertion.

**Primary recommendation:** Use `PROC CONTENTS DATA=src._ALL_ OUT=work.allvars NOPRINT` to enumerate all variables across all eight sources in a single step, then `PROC SQL` grouping to detect multi-source names. Write the ownership table as a SAS dataset to `qc/` (for downstream consumption by Phase 4) and a human-readable `.txt` alongside it. Write conflict rows and coalesce-wanted rows directly to `docs/DECISIONS.md` via FILE/PUT.

---

## Project Constraints (from CLAUDE.md)

- SAS 9.4M8 on Windows; session encoding is NOT UTF-8 — do not write non-ASCII characters to output files
- Source files `master_data_1..8.sas7bdat` are **read-only** — `02_ownership.sas` may read them but never write to them
- No PHI in git: `.sas7bdat`, `.xlsx`, `.csv`, `data/` tree are gitignored; `qc/` text artifacts and `docs/` markdown files may be committed
- Repo on local disk; source data on P: drive — `libname src` must point to `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross`
- `qc/` directory already exists (created in Phase 1); `docs/` directory does not exist yet — program must check and create or error
- Delivery: UF colors on visual deliverables — not applicable to this phase (no Excel/HTML output required)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| OWN-01 | User can run `02_ownership.sas` to produce a variable→source ownership table written to disk | `PROC CONTENTS DATA=src._ALL_ OUT=work.allvars` + PROC SQL grouping + FILE/PUT to `qc/02_ownership_map.txt`; also write SAS dataset `qc.ownership_map` for Phase 4 consumption |
| OWN-02 | User can review the ownership map before any merge executes (committed artifact) | Artifact is a plain-text file in `qc/` committed to git (not a `.sas7bdat`); the `qc/` path is already in the repo and tracked |
| OWN-03 | All variable name conflicts across sources are explicitly listed in `docs/DECISIONS.md` | PROC SQL `HAVING COUNT(DISTINCT memname) > 1` identifies multi-source names; each conflict row is written to `docs/DECISIONS.md` via FILE/PUT with APPEND mode |
| OWN-04 | Coalesce-wanted variables explicitly named in `02_ownership.sas` with disagreement-check assertions | Hard-code variable list (BMI, Race, etc.) in the program; for each, query non-missing values across sources and assert cross-source agreement or emit an informational divergence warning |
</phase_requirements>

---

## Standard Stack

### Core

| Tool/Pattern | Version | Purpose | Why Standard |
|---|---|---|---|
| `PROC CONTENTS DATA=src._ALL_ OUT=work.allvars(keep=memname name type length varnum) NOPRINT;` | SAS 9.4 | Enumerate every variable in every source in one step | Reads metadata only; safe on read-only sources; established in Phase 1 |
| `PROC SQL GROUP BY upcase(name) HAVING COUNT(DISTINCT upcase(memname)) > 1` | SAS 9.4 | Identify variable names that appear in more than one source | Single SQL pass; result is a table of conflict names with contributing source list |
| `FILE "path" MOD;` / `PUT "...";` | SAS 9.4 | Append conflict block to `docs/DECISIONS.md` | MOD mode appends to an existing file without truncation |
| `%abort cancel;` inside a macro | SAS 9.4 | Loud termination on structural violations | Established pattern from Phase 1; `%abort` is only valid inside a macro definition |
| `PROC SQL INTO :macvar TRIMMED` | SAS 9.4 | Count-based assertions | Do NOT use `&SQLOBS` (Phase 1 Pitfall 7) |
| `LIBNAME qclib "C:\Master_Renamed_same_format_accross\qc";` | SAS 9.4 | Write ownership map as a SAS dataset artifact | Allows Phase 4 to `SET qclib.ownership_map` rather than re-parsing text |

### Supporting

| Tool/Pattern | Version | Purpose | When to Use |
|---|---|---|---|
| `PROC SORT; BY upcase(name) upcase(memname);` | SAS 9.4 | Sort allvars before grouping or report generation | Needed before any DATA step BY-group processing |
| `%sysfunc(fileexist(path))` | SAS 9.4 | Gate docs/ directory creation check | Precondition before the first FILE statement targeting docs/ |
| `%sysfunc(libref(src))` | SAS 9.4 | Verify libname resolved (same pattern as Phase 1) | Precondition 1, identical to Phase 1 |

---

## Architecture Patterns

### Recommended Program Structure

```
02_ownership.sas
  SECTION 0: Options, libnames, path macro-variables
  SECTION 1: Preconditions
    1a. libname src resolves
    1b. qc/ directory exists
    1c. docs/ directory exists (create if missing, or abort)
  SECTION 2: Enumerate all variables via PROC CONTENTS src._ALL_
  SECTION 3: Build ownership assignments
    3a. Single-source variables: declared owner = the one source
    3b. Multi-source variables: declared owner written as hard-coded
        comment in code; non-owners flagged
  SECTION 4: Write ownership table to qc/ownership_map.txt (human)
             and work.ownership_map / qclib.ownership_map (machine)
  SECTION 5: Write conflict block to docs/DECISIONS.md
  SECTION 6: Coalesce-wanted assertions (BMI, Race, ...)
  SECTION 7: Final NOTE, libname clears
```

### Pattern 1: Single PROC CONTENTS across all eight sources

```sas
/* Enumerate all variables from all eight sources in one step.
   src._ALL_ expands to every dataset in the library.
   Filter to the eight master_data_N names to exclude stale artifacts. */
proc contents data=src._all_
  out=work.allvars(keep=memname name type length varnum)
  noprint;
run;

/* Normalise case for reliable grouping.
   Write to a NEW dataset -- never `data X; set X;` (PCM-R-01 / PCM-T-02).
   Keeping the raw PROC CONTENTS output intact means a wrong filter costs
   nothing to correct; rewriting in place would force a re-run.            */
data work.allvars_src;
  set work.allvars;
  where upcase(memname) in
    ('MASTER_DATA_1','MASTER_DATA_2','MASTER_DATA_3','MASTER_DATA_4',
     'MASTER_DATA_5','MASTER_DATA_6','MASTER_DATA_7','MASTER_DATA_8');
  name_u    = upcase(name);
  memname_u = upcase(memname);
run;
```

**CRITICAL — use `IN`, never `IN:`.** The truncated-comparison operator `IN:`
matches on prefix, so `MASTER_DATA_7B` matches the literal `'MASTER_DATA_7'` and the
stale artifact `master_data_7b` is readmitted — defeating the entire point of Pitfall 1.
An earlier draft of this pattern used `IN:`; that was a bug. Greps that verify this must
test for `in (` , not bare `in`, or they match the broken form too.

**Confidence:** HIGH — identical approach used in Phase 1 SRC-06.

### Pattern 2: Detect multi-source variable names

```sas
proc sql noprint;
  create table work.conflicts as
    select name_u,
           count(distinct memname_u) as n_sources,
           /* Build a pipe-delimited source list for the report */
           catx('|', min(case when memname_u='MASTER_DATA_1' then 'md1' end),
                     min(case when memname_u='MASTER_DATA_2' then 'md2' end),
                     min(case when memname_u='MASTER_DATA_3' then 'md3' end),
                     min(case when memname_u='MASTER_DATA_4' then 'md4' end),
                     min(case when memname_u='MASTER_DATA_5' then 'md5' end),
                     min(case when memname_u='MASTER_DATA_6' then 'md6' end),
                     min(case when memname_u='MASTER_DATA_7' then 'md7' end),
                     min(case when memname_u='MASTER_DATA_8' then 'md8' end))
                as sources_present length=40
    from work.allvars
    group by name_u
    having count(distinct memname_u) > 1
    order by name_u;

  select count(*) into :n_conflicts trimmed from work.conflicts;
quit;
%put NOTE: OWN-03 -- &n_conflicts variable name conflicts detected across sources.;
```

**Confidence:** HIGH — standard PROC SQL GROUP BY / HAVING pattern.

### Pattern 3: Write ownership table to disk (text + SAS dataset)

```sas
/* Text artifact for human review (OWN-02).
   Artifact name is 02_ownership_map.txt -- prefixed to match the program
   number, consistent with the plans and the validation contract.          */
filename owntxt "&qc_path.\02_ownership_map.txt";
data _null_;
  set work.ownership_map;  /* built in Section 3 */
  file owntxt;
  if _n_ = 1 then do;
    put "Variable Ownership Map -- Run: %sysfunc(datetime(), datetime20.)";
    put @1 "Variable" @35 "Owner" @50 "N_Src" @58 "Sources" @95 "Coalesce";
    put @1 "------------------------------------------------------------------------------------------------";
  end;
  put @1 varname $32. @35 owner $12. @50 n_sources 3. @58 sources_present $32. @95 coalesce_flag $1.;
run;
filename owntxt clear;

/* SAS dataset artifact for Phase 4 consumption */
libname qclib "&qc_path";
data qclib.ownership_map;
  set work.ownership_map;
run;
libname qclib clear;
```

**Column arithmetic must not overlap.** `sources_present` can hold up to
`md1|md2|md3|md4|md5|md6|md7|md8` = 31 characters. A `$40.` field starting at @58 runs to
column 97 and collides with anything placed at @82 — silently truncating the source list
for exactly the most-conflicted variables. Allow `$32.` at @58 and place the next field at
@95 or later. Check the arithmetic whenever a column is added.

**Confidence:** HIGH — FILE/PUT column pointer pattern from Phase 1.

### Pattern 4: Append conflict block to docs/DECISIONS.md

```sas
/* FILE ... MOD appends; first run creates the section; subsequent runs
   re-append (idempotency handled by a dated header line that is greppable). */
filename dcsnmd "&docs_path.\DECISIONS.md";
data _null_;
  file dcsnmd mod;
  put " ";
  put "## OWN-03 Variable Conflicts -- generated by 02_ownership.sas";
  put "Run: %sysfunc(datetime(), datetime20.)";
  put " ";
  put "| Variable | Sources | Declared Owner | Resolution |";
  put "|----------|---------|----------------|------------|";
run;

/* One row per conflict */
data _null_;
  set work.conflicts;
  file dcsnmd mod;
  put "| " name_u $32. "| " sources_present $20. "| TBD | Pending |";
run;
filename dcsnmd clear;
```

**Caution:** MOD mode appends on every run. Phase 2 plan should write the conflict table
once; a re-run guard prevents duplicate blocks. See **Pitfall 2** (an earlier draft cited
Pitfall 3, which is about ownership-as-documentation).

**Re-run guard without FILENAME PIPE.** A `findstr` pipe works but adds an XCMD dependency
to a phase that otherwise needs none (Pitfall 7). Read the file directly instead:

```sas
%let own03_written = 0;
data _null_;
  infile "&docs_path.\DECISIONS.md" truncover end=eof;
  input line $256.;
  retain hits 0;
  if index(line, 'OWN-03 CONFLICT ROWS GENERATED') > 0 then hits + 1;
  if eof then call symputx('own03_written', hits, 'G');
run;
```

Note the `%let` before the step: if DECISIONS.md is empty the DATA step never iterates,
`eof` is never set, and `symputx` never fires — the pre-set value is what keeps the
following `%if` from reading an undefined variable.

### Pattern 5: Coalesce-wanted disagreement check

```sas
/* For each coalesce-wanted variable, check whether non-missing values
   across sources agree. This is informational (not abort-on-fail) for
   most variables; BMI is a special case where prior analysis confirmed
   coalescing recovers nothing (all 28,424 missings are missing at source). */
/* Compares ONE source against the md3 spine. Type-aware: md8 stores several
   numerics as character, so a naive comparison is a type error, not a
   disagreement. The caller iterates this over the sources that actually
   carry the variable.                                                      */
%macro check_coalesce_agreement(var=, dsb=, dsa=master_data_3);
  %local n_disagree type_a type_b;

  /* Guard 1: both sides must carry the variable, with the same type.
     Types come from work.allvars_src, already built in Section 2.          */
  proc sql noprint;
    select type into :type_a trimmed from work.allvars_src
      where memname_u = %upcase("&dsa") and name_u = %upcase("&var");
    select type into :type_b trimmed from work.allvars_src
      where memname_u = %upcase("&dsb") and name_u = %upcase("&var");
  quit;

  %if %superq(type_a) = or %superq(type_b) = %then %do;
    %put NOTE: OWN-04 SKIP -- &var not present in both &dsa and &dsb.;
    %return;
  %end;
  %if &type_a ne &type_b %then %do;
    %put WARNING: OWN-04 TYPE MISMATCH -- &var is type &type_a in &dsa but &type_b in &dsb.;
    %put WARNING- Not comparable as values. Resolve the type before any coalesce.;
    %put WARNING- Expected for md8: Admit_BMI, ASA__Anesth_Record_, Age_at_Encounter,;
    %put WARNING- Cognitive_Score, Frailty_Score and the rt_* timings are Char there.;
    %return;
  %end;

  /* Guard 2: the md8 'NULL' sentinel is a 4-char string, not missing().
     Applies to CHARACTER variables only (type=2) -- a numeric can never
     hold it, and upcase() on a numeric forces an unwanted conversion.      */
  proc sql noprint;
    create table work._coalesce_&var as
      select a.PRECEDE_STUDY_ID, a.&var as val_a, b.&var as val_b
      from src.&dsa as a
      inner join src.&dsb as b
        on a.PRECEDE_STUDY_ID = b.PRECEDE_STUDY_ID
      where not missing(a.&var)
        and not missing(b.&var)
        %if &type_a = 2 %then %do;
        and strip(upcase(a.&var)) ne 'NULL'
        and strip(upcase(b.&var)) ne 'NULL'
        %end;
        and a.&var ne b.&var;

    select count(*) into :n_disagree trimmed from work._coalesce_&var;
  quit;

  %if &n_disagree > 0 %then
    %put WARNING: OWN-04 -- &n_disagree rows where &var disagrees between &dsa and &dsb. Review before coalescing.;
  %else
    %put NOTE: OWN-04 OK -- &var consistent across &dsa/&dsb (or missing/NULL in all).;
%mend check_coalesce_agreement;
```

**Do not use `VVALUE()` for the sentinel guard.** VVALUE is a DATA-step variable-
information function requiring a variable descriptor; it is not reliable in PROC SQL. The
type-conditional `strip(upcase(a.&var))` above achieves the same thing and only where the
sentinel can actually occur.

**Iterate the real sources, not a fixed pair.** Hard-coding `md3 vs md1` tests the one
pair PCM-F-04 already proved agrees exactly (Race, Sex, Age, BMI, all 14,778 shared
records, zero disagreements). That check passes trivially and proves nothing about
md4-md8, where the risk lives. Drive the calls from `work.conflicts.sources_present`.

**Note:** Coalesce-wanted variables must be named explicitly in the program (not
discovered dynamically) to satisfy OWN-04. **The BMI variable is `Admit_BMI`** — there is
no variable named `BMI` in any source.

### Anti-Patterns to Avoid

- **Relying on `src._ALL_` without filtering by memname:** Stale artifacts (`master_data_all`, `master_data_dedup`, `master_data_merged`) may be present in the P: drive folder and will appear in allvars. Always filter to the eight exact names.
- **Using `FILE ... REPLACE` to write DECISIONS.md:** This truncates on every run. Use MOD with a re-run guard.
- **Silently resolving conflicts in code comments only:** OWN-03 requires conflicts to appear in `docs/DECISIONS.md`. A comment in `02_ownership.sas` that is not replicated to DECISIONS.md does not satisfy the requirement.
- **Using `&SQLOBS` for counts:** Established pitfall from Phase 1 — use explicit `SELECT COUNT(*) INTO :n TRIMMED`.
- **Opening src library without access=readonly:** Source files must remain read-only.
- **Writing the ownership assignment as pure metadata (no assertions):** The program must assert, not just document. A variable listed as "owned by md3" with no downstream enforcement is not a guarantee.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-dataset variable enumeration | Custom DATA step reading each dataset separately | `PROC CONTENTS DATA=src._ALL_ OUT=work.allvars` | One step, reads metadata only, no observation scan |
| Detecting duplicate variable names | Nested macro loops comparing lists | `PROC SQL GROUP BY name HAVING COUNT(DISTINCT memname) > 1` | Standard set operation; correct and readable |
| Writing structured text reports | ODS TEXT or PROC PRINT to file | `DATA _NULL_; FILE ...; PUT @col ...;` | Exact column layout control; no ODS overhead |
| Checking type consistency | Manual IF-THEN per variable | Filter `work.allvars WHERE type ne <expected>` after the PROC CONTENTS step | Leverages already-available metadata |

---

## Known Variable Conflicts (from project context)

These are confirmed or suspected multi-source variable names from the accumulated project knowledge. The planner must address each in the ownership assignment section of `02_ownership.sas`.

| Variable | Sources | Status | Decision |
|----------|---------|--------|----------|
| `PRECEDE_STUDY_ID` | All 8 | Not a conflict — it is the merge key | Exclude from conflict table |
| `Death_Date_Y_N` / `IsDead_Y_N` / `Death` | Multiple (exact sources TBD by program) | PCM-D-01 — Pending Erin sign-off | List in DECISIONS.md as Pending; do not silently resolve |
| Frailty component variables (`Feels_Exausted`, etc.) | Multiple | PCM-D-02 — Pending Erin sign-off | List in DECISIONS.md as Pending |
| `ISO_SEV` | md4, md8 | PCM-D-03 — naming discrepancy | List in DECISIONS.md as Pending |
| `PRECEDE_Study_ID_1` (md6 only) | md6 | PCM-D-06 — resolved as drop (PREP-04) | Document the drop decision in DECISIONS.md |
| `Admit_BMI` (NOT `BMI`) | md1-md7 (Num); md8 (Char 11 — type mismatch) | OWN-04 — prior analysis: coalescing recovers nothing, all 28,424 missings are missing at source | Name in program with assertion; declare single owner. The exact name is `Admit_BMI`. |
| `Race` | All 8 (Char 15 in md6/md7, Char 16 elsewhere) | OWN-04 | Name in program with assertion. Note md1/md3 already verified identical (PCM-F-04), as were `Sex` and `Age_at_Encounter` — equally valid candidates if the list is extended |
| `Emergent` | Multiple (near-zero positives) | PCM-D-04 — pending | List in DECISIONS.md |
| `Age_at_Encounter` | Multiple (age floor PCM-D-07 pending) | PCM-D-07 | List in DECISIONS.md |

**Cross-type variables (md8).** These are Char in md8 and Num in the other sources, so any
value comparison spanning md8 is a type error rather than a disagreement:
`Admit_BMI`, `ASA__Anesth_Record_`, `Age_at_Encounter`, `Cognitive_Score`, `Frailty_Score`,
`rt_INCISE_to_DRESS_mins`, `rt_RM_START_to_INCISION_mins`, `rt_RM_START_to_RM_END_mins`.
`Base_Procedure_Code_1` splits the other way (Char in md1/2/3/8, Num in md4-md7).

**Important:** The program will discover the complete conflict list at runtime. The planner must not assume the above is exhaustive. The program must treat whatever `work.conflicts` returns as the authoritative list.

---

## Common Pitfalls

### Pitfall 1: src._ALL_ picks up stale artifacts from the P: drive folder
**What goes wrong:** Stale datasets (`master_data_all`, `master_data_dedup`, `master_data_7b`, `master_data_merged`) still present on P: drive show up in `PROC CONTENTS DATA=src._ALL_` and inflate the conflict count.
**Why it happens:** `src._ALL_` enumerates everything in the library directory.
**How to avoid:** After PROC CONTENTS, immediately filter `work.allvars` with `WHERE upcase(memname) IN ('MASTER_DATA_1', ..., 'MASTER_DATA_8')`.
**Warning signs:** `n_conflicts` is unexpectedly high; variable names specific to derived/merged datasets appear in the conflict table.

### Pitfall 2: FILE...MOD appends duplicate conflict blocks on re-run
**What goes wrong:** Each run of `02_ownership.sas` appends another copy of the conflict section to `docs/DECISIONS.md`, making it unreadable.
**Why it happens:** `FILE ... MOD` always appends.
**How to avoid:** Before writing, check if the section header already exists (e.g., `%sysfunc(find(...))` or a grep-equivalent via FILENAME PIPE), and skip the write if found. Alternatively, write the conflict block to a separate `qc/conflicts.txt` and only write to DECISIONS.md once (manually or via a separate documentation step).
**Warning signs:** DECISIONS.md has duplicate `## OWN-03` sections after a second run.

### Pitfall 3: Treating "ownership" as documentation only, not enforcement
**What goes wrong:** The ownership table is written to `qc/` but nothing prevents Phase 4 from ignoring it and doing a last-wins DATA step merge anyway.
**Why it happens:** The table is an artifact, not a SAS-enforced constraint.
**How to avoid:** Phase 4 plan must reference the ownership table and include an assertion step. Phase 2 research note: the program should write the table as a SAS dataset (not just text) so Phase 4 can `SET qclib.ownership_map` and programmatically check which variables it is allowed to use from which source.
**Warning signs:** Phase 4 ignores the ownership map; a variable has two contributing sources with no assertion.

### Pitfall 4: Coalesce disagreement check uses missing() incorrectly for character variables
**What goes wrong:** `missing(charvar)` returns 1 only for blank. The md8 literal `NULL` string is not blank, so `missing()` returns 0 for a `NULL` value — the cross-source join treats it as non-missing and compares it against a real value, generating false disagreements.
**Why it happens:** md8 stores `NULL` as a 4-character string, not as a SAS missing value.
**How to avoid:** In coalesce checks that include md8 as a source, add `AND strip(upcase(a.&var)) ne 'NULL'` alongside the `not missing()` guard. This is the same NULL-sentinel awareness from Phase 1.
**Warning signs:** Coalesce disagreement count is unexpectedly high for variables drawn from md8.

### Pitfall 5: %abort used in open code (not inside a macro)
**What goes wrong:** `%abort cancel;` in open code causes a compile-time error in some SAS modes; it is only reliable inside a `%macro ... %mend` definition.
**Why it happens:** SAS macro processor restriction.
**How to avoid:** Wrap every assertion that ends with `%abort cancel` inside a named macro and call it. This is the established pattern from Phase 1.
**Warning signs:** SAS log shows "WARNING: The %ABORT macro is only valid in a macro definition."

### Pitfall 7: A new FILENAME PIPE dependency without an XCMD precondition
**What goes wrong:** The re-run guard shells out to `findstr`. Under `NOXCMD` the pipe
yields nothing, the guard reads zero hits, and the conflict block is appended on every
single run — the exact duplication Pitfall 2 exists to prevent, now failing silently.
**Why it happens:** Phase 1 gated every pipe behind `%check_xcmd`. Phase 2 introduced a new
pipe without carrying that precondition forward.
**How to avoid:** Don't use a pipe here. Read `DECISIONS.md` with `infile` and scan for the
marker with `index()` (Pattern 4). Phase 2 then has no XCMD dependency at all. If a pipe is
kept for some other reason, `%check_xcmd` must be added to Section 1.
**Warning signs:** DECISIONS.md grows a new conflict block per run despite the guard.

### Pitfall 8: Comparing a variable that is Char in md8 and Num elsewhere
**What goes wrong:** `a.Admit_BMI ne b.Admit_BMI` across the md8 boundary raises a type
mismatch, or coerces and reports every row as a disagreement.
**Why it happens:** md8 came from an Excel export where the `NULL` sentinel forced eight
numerics to character. See the cross-type list in Known Variable Conflicts.
**How to avoid:** Read `type` from `work.allvars_src` for both sides before joining; skip
with a WARNING when they differ (Pattern 5). The type check must come first — the NULL
sentinel guard is meaningless if the join errors before reaching it.
**Warning signs:** A disagreement count equal to the full overlap row count; or
"Expression using not equals (ne) has components that are of different data types".

### Pitfall 6: docs/ directory does not exist
**What goes wrong:** The first `FILE "&docs_path.\DECISIONS.md"` statement silently creates a file in an unexpected location, or fails.
**Why it happens:** Phase 1 only created `qc/`; `docs/` was never confirmed to exist.
**How to avoid:** Precondition check `%sysfunc(fileexist(&docs_path))` before any FILE statement targeting `docs/`. If missing, either create it via SYSTASK/X command or abort with an actionable error message.
**Warning signs:** `docs/DECISIONS.md` is not created; no error in log because SAS sometimes creates intermediate directories silently.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | SAS log assertions — `%abort cancel` on violation; `NOTE:` messages for pass |
| Config file | none — SAS 9.4 has no external test config |
| Quick run command | `sas -sysin sas/02_ownership.sas -log logs/02_ownership.log` |
| Full suite command | `sas -sysin sas/99_run_all.sas` (Phase 8) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Signal | File Exists? |
|--------|----------|-----------|------------------|-------------|
| OWN-01 | `02_ownership.sas` runs without ERROR in log | smoke | Log contains `NOTE: ==== Phase 2 ownership map complete`; no `ERROR:` lines | No — Wave 0 |
| OWN-01 | `qc/02_ownership_map.txt` exists after run | smoke | `%sysfunc(fileexist(...))` assertion at end of program | No — Wave 0 |
| OWN-02 | Ownership map artifact is committed to git | manual | `git status qc/02_ownership_map.txt` shows tracked | N/A |
| OWN-03 | `docs/DECISIONS.md` contains conflict entries | smoke | `%sysfunc(fileexist(docs/DECISIONS.md))` + grep for `OWN-03` section | No — Wave 0 |
| OWN-04 | Coalesce-wanted variables explicitly named in program | automated | `grep -i "Admit_BMI" sas/02_ownership.sas` and `grep -i "Race" sas/02_ownership.sas` both return hits | No — Wave 0 |
| OWN-04 | Disagreement assertions run without abort | smoke | Log contains `NOTE: OWN-04 OK` lines for each named variable | No — Wave 0 |

### Sampling Rate
- **Per task commit:** Run `sas -sysin sas/02_ownership.sas -log logs/02_ownership.log` and verify log is ERROR-free
- **Per wave merge:** Same (single program phase)
- **Phase gate:** `qc/02_ownership_map.txt` exists, `docs/DECISIONS.md` conflict block written, log is ERROR-free

### Wave 0 Gaps
- [ ] `sas/02_ownership.sas` — does not exist yet; Wave 0 creates stub
- [ ] `docs/` directory — must be created before program can write DECISIONS.md
- [ ] `docs/DECISIONS.md` — does not exist yet; program will create on first run or a stub should be committed
- [ ] `logs/` directory — confirm exists or create in Wave 0 (used by 99_run_all.sas)

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| SAS 9.4M8 | All steps | Assumed (project constraint) | M8 | None |
| P: drive (src libname) | Section 2 variable enumeration | Assumed (Phase 1 passed) | — | None — abort precondition |
| `qc/` directory | Writing ownership_map.txt | Yes (created by Phase 1) | — | — |
| `docs/` directory | Writing DECISIONS.md | Not confirmed | — | Create via `%sysexec mkdir` or abort |
| `logs/` directory | Log routing in 99_run_all.sas | Not confirmed | — | Create in Wave 0 |

---

## Open Questions

1. **What is the complete list of multi-source variable conflicts?**
   - What we know: Several known conflicts (death variables, frailty components, ISO_SEV, BMI, Race) from accumulated project context
   - What's unclear: The full list will only be known after `PROC CONTENTS DATA=src._ALL_` runs; unknown shared column names may exist
   - Recommendation: The planner should treat the "Known Conflicts" table as a minimum, not a ceiling. The program discovers the full list at runtime.

2. **Which variables are wanted for coalesce semantics?**
   - What we know: `Admit_BMI` (confirmed recovers nothing) and `Race` are explicitly mentioned in project context. Note `Sex` and `Age_at_Encounter` were verified identical in the same PCM-F-04 check and are equally defensible candidates
   - What's unclear: Are there others? The answer affects how many `%check_coalesce_agreement` calls appear in OWN-04
   - Recommendation: Hard-code BMI and Race for now; add a `%put NOTE:` directing future maintainers to add others

3. **Should docs/DECISIONS.md be created fresh or appended?**
   - What we know: The file does not exist yet (docs/ directory not confirmed)
   - What's unclear: Will Phase 2 create DECISIONS.md, or should it be a pre-committed stub?
   - Recommendation: Create a minimal stub `docs/DECISIONS.md` in Wave 0 (a git-committed file with just a header), then Phase 2 appends to it. This avoids the MOD-creates-blank-file edge case.

4. **How granular should ownership assignments be?**
   - What we know: "Single ownership per variable" is a locked decision (STATE.md established decisions)
   - What's unclear: Does the planner hard-code ownership for every known conflict, or does the program infer it from position (e.g., md3 owns everything it has)?
   - Recommendation: Hard-code ownership for all known conflict variables as named constants in the program. For variables that appear only in one source, the program can declare ownership automatically. This makes the rationale explicit and auditable.

---

## Sources

### Primary (HIGH confidence)
- Phase 1 SAS program `sas/01_verify_sources.sas` — established patterns for PROC CONTENTS, PROC SQL assertions, %abort, FILE/PUT column pointers
- Phase 1 RESEARCH.md — pitfall inventory (especially Pitfall 7 re: &SQLOBS, Pitfall 8 re: XCMD)
- STATE.md — locked decisions, known variable conflicts, pending decisions (PCM-D-01 through D-07)
- REQUIREMENTS.md — OWN-01 through OWN-04 verbatim

### Secondary (MEDIUM confidence)
- SAS 9.4 documentation (training knowledge): `PROC CONTENTS DATA=lib._ALL_` behavior, FILE MOD mode, `%sysfunc(fileexist())`, macro scoping rules

### Tertiary (LOW confidence)
- None — all claims are grounded in Phase 1 established patterns or project context

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all patterns are native SAS 9.4 confirmed in Phase 1
- Architecture: HIGH — single-program, metadata-first approach matches Phase 1 structure exactly
- Pitfalls: HIGH — drawn from Phase 1 validated pitfall inventory plus project-specific known issues
- Conflict variable list: MEDIUM — known conflicts from project context; complete list requires runtime execution
- Exact variable names: previously LOW and unflagged — `BMI` was carried through this document and both plans when the real name is `Admit_BMI`. Every variable named in a plan must be checked against a PROC CONTENTS listing before it reaches code
- `VVALUE()` in PROC SQL: NOT SUPPORTED — removed from Pattern 5

**Research date:** 2026-08-25
**Valid until:** Stable — SAS 9.4 patterns do not change; re-research only if environment changes
