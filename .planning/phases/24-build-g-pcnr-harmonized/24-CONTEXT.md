# Phase 24: Build g.pcnr_harmonized - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply the approved sentinel decisions and name map to `g.master_data_harmonized`,
produce `g.pcnr_harmonized`, and prove exhaustively that nothing else changed.

Program: `sas/24_pcnr_build.sas`

Deliverables:
- `g.pcnr_harmonized` — 41,150 rows; columns renamed per `docs/pcnr_name_map.csv`; approved sentinels set to missing
- `qc/24_recode_rules_generated.sas` — machine-generated audit file; `%include`d inside the recode DATA step
- `qc/24_pcnr_recode_counts.csv` — detail: one row per MISSING rule (including zero-hit rules)
- `qc/24_pcnr_recode_totals.csv` — per-variable total rows changed (0 for untouched columns)
- All PCNR-11 assertions pass; `g.master_data_harmonized` confirmed unchanged

Gate: `PCNR_APPROVED = 1` in `00_config.sas` must be set before program 24 runs. It is set in
the COMMITTED config (same pattern as `D15_APPROVED`): program 24 %includes 00_config.sas, so a
value set only in the run session would be reset before the gate check.

</domain>

<decisions>
## Implementation Decisions

### D-01: Gate Check at Program Top

`%pcnr_gate_check` macro runs at the very top of program 24 before any data work.
It reads both gate files via DATA step `infile` with explicit `$` informats (PCM-T-16 — never PROC IMPORT).

Gate reads (source for each check):
- `qc/23_sentinel_fingerprint.txt` — nobs, nvars, modate; abort if any field mismatches current `g.master_data_harmonized`
- `docs/sentinel_decisions.csv` — authoritative human-owned decisions file
- `qc/23_sentinel_candidates.csv` — authoritative candidate list (for coverage and stale checks)
- `docs/pcnr_name_map.csv` — authoritative name map

Gate checks (all abort on failure):
- Fingerprint fields match current dataset (nobs, nvars, modate)
- Every KEEP/KEY candidate has a decision (per-variable row or wildcard coverage)
- Every AMBIGUOUS KEEP/KEY candidate has a per-variable row (wildcard may not resolve AMBIGUOUS)
- No per-variable decision row references a `(variable, raw_hex)` absent from the candidates scan (stale per-variable)
- No wildcard row's `normalized_value` appears in zero KEEP/KEY column scans (stale wildcard)
- Every wildcard row has `var_type = char` (prevents wildcard from resolving numeric candidates)
- Every decision row has `action` in (MISSING, KEEP); no duplicate decision keys

Role (KEEP/KEY/DROP) comes only from `docs/pcnr_name_map.csv`; the candidates file's `role`
column is display-only (Phase 23 D-04). Wildcard rows have blank `raw_value`/`raw_hex` and
match on `upcase(normalized_value)`, never on `raw_hex`.

Key lookup: `(variable, raw_hex)` — same hex encoding used by `%hexkey` macro in `00_config.sas`.

### D-02: Recode Step — Code Generation, Not Macro Loops

**Three-step pass structure:** recode (original names) → compare → rename.

**Step 1: Resolve rules into an explicit table**

Read `docs/sentinel_decisions.csv` (action = MISSING rows only) and resolve wildcards
against `qc/23_sentinel_candidates.csv`. Expand each `variable = *` wildcard into one
explicit row per KEEP/KEY column where that `normalized_value` appears. Result:
`work._recode_rules` — one row per `(variable, raw_hex, action = MISSING)`.

Skip DROP-role columns (they will be dropped later and are not recoded).
Wildcard expansion skips AMBIGUOUS candidates and skips any `(variable, raw_hex)` that has a
per-variable decision row, whatever that row's action -- the per-variable row always wins.
`work._recode_rules` must be unique on `(variable, raw_hex)`; `rule_source` is length 8
(`WILDCARD` is 8 characters).
For numeric columns: include only rows where PCM-D-24 has approved action = MISSING
(default is KEEP; no wildcard rows allowed for var_type = num per D-04 from Phase 23).

**Step 2: Write `qc/24_recode_rules_generated.sas`**

One `select`/`when` block per column that has at least one MISSING rule, using the column's
character rules grouped together. Numeric rules use direct comparison (`if var = value then
call missing(var);`). Format:

```sas
/* variable: Race  (3 rules) */
select (%hexkey(Race));
  when ('554E4B4E4F574E') call missing(Race);        /* UNKNOWN -- wildcard */
  when ('3F')            call missing(Race);          /* ?       -- per-var  */
  when ('3F3F')          call missing(Race);          /* ??      -- per-var  */
  otherwise;
end;
/* numeric: clock_variable (1 rule, PCM-D-24 approved) */
if clock_variable = -999 and not missing(clock_variable) then call missing(clock_variable);
```

Include a comment per rule noting `raw_value` (display only) and whether it came from a
per-variable row or wildcard expansion.

**Step 3: Apply rules in one DATA step**

```sas
data work._recoded;
  set g.master_data_harmonized;
  %include "&qc_path./24_recode_rules_generated.sas";
run;
```

One pass over 41,150 rows. No macro loops inside the DATA step. The generated file is the
complete audit trail of what ran.

### D-03: Full-Comparison Assertion — Two-SET DATA Step, Not PROC COMPARE

After the recode step, read source and recoded in parallel by row position:

```sas
data work._compare_out;
  set g.master_data_harmonized;          /* source */
  set work._recoded (rename=(...));      /* recoded, columns renamed positionally _rc1.. / _rn1.. */
  array src{*}  <all 175 columns>;
  array rec{*}  <all 175 _r_ columns>;
  do _i = 1 to dim(src);
    if src{_i} ne rec{_i} then do;
      /* authorized: output must be missing AND the hex key must be in the MISSING rule set */
      /* unauthorized: %fail_out */
    end;
  end;
run;
```

For character columns: use character arrays; for numeric: numeric arrays. Separate array
pairs to handle mixed types.

Authorized change criteria: the recoded cell is missing AND the source cell's `%hexkey`
value appears in `work._recode_rules` for that column. Anything else → `%fail_out`.

Output from comparison: one row per authorized change (variable, row, raw_value, raw_hex).

**Two cross-checks after comparison:**
1. `n_compare_changes` equals `n_recode_step_changes` (independent recode counts agree)
2. Per-rule: rows changed equals `n_rows` from `qc/23_sentinel_candidates.csv` (catches
   source drift that slipped past the fingerprint)

PROC COMPARE is not used — it reports that cells differ but cannot verify each difference
was authorized.

### D-04: Rename Step — Single Final DATA Step

After the comparison passes, apply the name map in one DATA step:

```sas
data work.pcnr_harmonized;
  set work._recoded (
    drop   = <DROP-role columns>
    rename = (<source_name> = <final_name> for all KEEP rows)
  );
  %include "&qc_path.\24_label_stmts_generated.sas";
  /* PCNR-09: keep the original label; a blank original label becomes the original name.
     Labels are written to a generated file (single-quoted), not a macro variable, so
     & or % in label text is never macro-resolved. */
run;
```

Generate the `drop=` and `rename=` clauses from `docs/pcnr_name_map.csv` using macro variable
lists, and the labels via the generated file above. KEY columns stay with their original names
(no rename); their `final_name` is blank in the file, so use `coalescec(final_name, source_name)`.

After rename, assert:
- Variable set equals KEY names + KEEP `final_name` values exactly (nothing extra, nothing missing)
- Column count equals source column count (1:1; DROP columns are excluded from `final_name`
  count, so this asserts DROP count + KEEP count + KEY count = source column count)
- Type and length of every column unchanged

Then WORK-then-promote: `data g.pcnr_harmonized; set work.pcnr_harmonized; run;`

PROC DATASETS MODIFY is not used — the DATA step handles drop, rename, and labels in one place.

### D-05: Recode Counts — Two Tidy CSVs, No TOTAL Rows

**`qc/24_pcnr_recode_counts.csv` (detail):**
Columns: `variable, final_name, raw_value, raw_hex, var_type, rule_source, n_expected, n_recoded`

- One row per MISSING rule (from `work._recode_rules`)
- `rule_source`: `PER_VAR` or `WILDCARD`
- `n_expected`: `n_rows` from `qc/23_sentinel_candidates.csv` for that `(variable, raw_hex)`
- `n_recoded`: rows actually changed in this run
- Include rules with `n_recoded = 0` (gaps are visible)
- `final_name`: from the name map (for Phase 25 dictionary use)

**`qc/24_pcnr_recode_totals.csv` (per variable):**
Columns: `variable, final_name, n_recoded_total`

- One row per KEEP and KEY column
- `n_recoded_total = 0` for columns with no MISSING rules or no hits
- Include all columns (not just those with recodes)

No `TOTAL` sentinel value in `raw_value` column — avoids embedding a sentinel in a file
about sentinels and avoids forcing every reader to filter it out.

Both files: fixed ASCII headers; read by Phase 25 via DATA step `infile` with `$` informats
(same PCM-T-16 rule as gate files). Do not use PROC IMPORT on these files.

### D-06: Program Structure and Sections

Single file `sas/24_pcnr_build.sas`. Sections:

```
SECTION 0: %pcnr_gate_check macro + gate execution
SECTION 1: Resolve rules → work._recode_rules
SECTION 2: Generate qc/24_recode_rules_generated.sas
SECTION 3: Apply rules → work._recoded (one DATA step, %include generated file)
SECTION 4: Full comparison → work._compare_out + cross-checks
SECTION 5: Rename + label + drop → work.pcnr_harmonized
SECTION 6: WORK-then-promote → g.pcnr_harmonized
SECTION 7: Write qc/24_pcnr_recode_counts.csv + qc/24_pcnr_recode_totals.csv
SECTION 8: PCNR-11 assertions (row count, key identity, column count, missing math, source unchanged)
```

Static checks (must pass before commit):
- `grep -ni "proc import" sas/24_pcnr_build.sas` → expect 0
- `grep -c '\$hex\.' sas/24_pcnr_build.sas` → expect 0 (only `%hexkey` used)
- `grep -ni "%put WARNING" sas/24_pcnr_build.sas` → expect 0

### Claude's Discretion

- Exact character array syntax for mixed-type parallel-set comparison (SAS 9.4 constraint: character and numeric arrays must be separate; planner confirms working pattern)
- Whether `work._recode_rules` is written as a SAS dataset or held entirely in indexed macro variables (dataset preferred for debuggability; macro variables acceptable if rule count fits)
- Log verbosity: `%put NOTE:` lines at section transitions (match existing program pattern)
- Whether the generated `.sas` file omits columns with zero MISSING rules entirely vs includes them as empty `select`/`when` blocks (omit entirely — cleaner file)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements
- `.planning/REQUIREMENTS.md` §Build g.pcnr_harmonized — PCNR-07 through PCNR-11 acceptance criteria

### Phase 23 context (gate schema, key decisions locked there)
- `.planning/phases/23-sentinel-name-inventory/23-CONTEXT.md` — D-01 through D-09; gate schema, wildcard rules, hex key approach, PCM-T-16, draft/docs split

### Existing pipeline programs (patterns to follow)
- `sas/00_config.sas` — `%fail_out` macro, `%hexkey` macro, `PCNR_APPROVED` gate flag, `D15_APPROVED` gate pattern
- `sas/10b_concept_harmonize.sas` — gate abort pattern, WORK-then-promote, assertions structure; **do not replicate `%emit_rules` loop pattern** — Phase 24 uses code generation instead
- `sas/20_pecan_id.sas` — example of a program that reads a `docs/` gate file via DATA step `infile`

### Gate files (inputs to program 24)
- `docs/sentinel_decisions.csv` — human-owned authoritative decisions (action = MISSING/KEEP per candidate)
- `docs/pcnr_name_map.csv` — human-owned authoritative name map (role, final_name, h_strip, etc.)
- `qc/23_sentinel_candidates.csv` — candidate list from program 23 (for coverage/stale checks and n_expected)
- `qc/23_sentinel_fingerprint.txt` — nobs, nvars, modate of `g.master_data_harmonized` at program 23 run time

### Column inventory
- `qc/03_contents_all.txt` — committed PROC CONTENTS export; planner uses for column list, types, lengths

### Source dataset
- `g.master_data_harmonized` — 41,150 rows, 175 columns (read-only; PCM-T-02 forbids writing to it)

### Decisions log
- `docs/DECISIONS.md` — PCM-D-24 (numeric sentinel approval) and PCM-D-25 (no companion columns) will be recorded here

No external specs — requirements fully captured above and in REQUIREMENTS.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/00_config.sas` `%fail_out` macro — standard abort path; use throughout all gate checks and assertions
- `sas/00_config.sas` `%hexkey` macro — `substr(put(&var, $hex400.), 1, 2*length(&var))`; must be used identically in gate and in recode rules
- `sas/10b_concept_harmonize.sas` — WORK-then-promote pattern, assertion structure, log routing macros (`%route_log`, `%restore_log`)
- `sas/10_concept_profile.sas` — column-sweep DATA step pattern over `g.master_data_harmonized`

### Established Patterns
- WORK-then-promote: build in WORK, assert, then `data g.lib.dataset; set work.dataset; run;`
- Gate default: `%let PCNR_APPROVED = 0;` with `%put NOTE:` — already in `00_config.sas`
- PCM-C-05: program runs as a separate `sas.exe` session; no shared WORK between programs
- `IS NOT MISSING` only in PROC SQL; `NOT MISSING()` in DATA step (PCM compliance)
- No bare open-code `%if` — every `%if` inside a `%macro...%mend`
- No `%put WARNING` — use `%put NOTE:` or `%put ERROR:` (scanner counts WARNING lines)

### Integration Points
- `sas/00_config.sas` — `PCNR_APPROVED` already present (default 0); flip to 1 after gate files confirmed
- `run_pipeline.cmd` — program 24 wired after program 23 (Phase 25 handles full wiring)
- `qc/` — outputs: `24_recode_rules_generated.sas`, `24_pcnr_recode_counts.csv`, `24_pcnr_recode_totals.csv`
- `g` libname — `g.pcnr_harmonized` promoted here after assertions pass

</code_context>

<specifics>
## Specific Ideas

- **Recode DATA step structure:** `select (%hexkey(Race)); when ('...hex...') call missing(Race); otherwise; end;` — one `select/when` block per character column with rules; numeric rules use `if var = value and not missing(var) then call missing(var);`
- **Parallel-set comparison:** `set g.master_data_harmonized; set work._recoded(rename=...);` reads both datasets by position — this requires row counts to be identical (asserted by PCNR-11 row count check that runs immediately before). Character and numeric arrays must be separate (SAS 9.4 constraint).
- **`n_expected` cross-check:** after comparison, per-rule `n_recoded` must equal `n_rows` in `qc/23_sentinel_candidates.csv`. This is the source-drift check that fingerprint alone cannot catch.
- **`qc/24_recode_rules_generated.sas` is an audit artifact:** it must be written to `qc/` and readable post-run. It is not committed (covered by `*.sas` exclusion? — check: if `*.sas` is NOT in `.gitignore` then this file would be committed; planner should verify and add a `.gitignore` entry if needed). The file is a plain ASCII SAS source snippet, not a full program — it has no `options`, no `%include`, no `run;`.
- **Zero-hit rules visible:** include all MISSING-decision rows in `qc/24_pcnr_recode_counts.csv` even when `n_recoded = 0`. A zero-hit rule is informative (the candidate was present in the scan but absent from this run's source, or was already missing).
- **PCM-D-25 confirmed:** no companion columns for `Declined`/`Refused`/`Not applicable` recodes. `qc/24_pcnr_recode_counts.csv` provides the per-value record that satisfies the audit need.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 24-build-g-pcnr-harmonized*
*Context gathered: 2026-09-28*
