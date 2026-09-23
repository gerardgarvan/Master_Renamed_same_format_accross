# PeCAN Master Dataset Integration -- DECISIONS.md

This file tracks pending and resolved analytical decisions for the PCM pipeline.
All entries are ASCII only (session encoding is not UTF-8).

---

## Pending Decisions

| ID | Topic | Status | Owner |
|----|-------|--------|-------|
| PCM-D-01 | Death variable naming (Death_Date_Y_N / IsDead_Y_N / Death) | **Resolved 2026-08-27 -- keep separate** | Gerard |
| PCM-D-02 | Frailty component encoding (char Y/N vs numeric _Value) | **Resolved 2026-08-27 -- keep separate** | Gerard |
| PCM-D-03 | ISO_SEV naming (md4/md8 vs others) | **Resolved 2026-08-27 -- keep separate** | Gerard |
| PCM-D-04 | Emergent usability (7 and 21 positives) | **Resolved 2026-08-27 -- retain despite rarity** | Gerard |
| PCM-D-05 | Analytic cohort INPATIENT/OBSERVATION restriction | Resolved -- Phase 16, 2026-09-21, Gerard | Gerard |
| PCM-D-06 | PRECEDE_Study_ID_1 drop vs retain | Resolved -- drop (PREP-04), proven identical first | Gerard |
| PCM-D-07 | Age floor (minimum 64) | **Deferred 2026-08-27 -- not pursuing** | Gerard |
| PCM-D-08 | The 9 envelope-violating rows | **Resolved 2026-08-27 -- flag, don't null** | Gerard |
| PCM-D-09 | QC-05 operative-interval ceilings never fire | **Resolved 2026-08-27 -- drop them** | Gerard |
| PCM-D-10 | Negatives in other rt_* variables | **Resolved 2026-08-27 -- see entry below** | Gerard |
| PCM-D-11 | md3-owns missingness trade-off | **Closed 2026-08-27 -- costs nothing** | Gerard |
| PCM-D-12 | %abort cancel return code on Windows batch | **Resolved 2026-09-22 -- return code = 3** | Gerard |
| PCM-D-13 | SSDI/CPT1/label-sweep concept harmonization (HARM-04) | **Resolved 2026-09-22 -- see entry below** | Gerard |
| PCM-D-14 | Pipeline-derived column rule (HARM-07) | **Resolved 2026-09-14 -- see entry below** | Gerard |
| PCM-D-17 | pecan_ID derivation method + MRN retention | **Resolved 2026-09-23 -- see entry below** | Gerard |
| PCM-D-18 | pecan_ID attach point (10b + 16b at build time) | **Resolved 2026-09-23 -- see entry below** | Gerard |

---

## PCM-D-05 -- Analytic cohort INPATIENT/OBSERVATION restriction: RESOLVED

**Decision:** The analytic cohort is restricted to patients with Patient_Type IN
('INPATIENT', 'OBSERVATION'). Cohort N = 13,890 (INPATIENT 13,223 + OBSERVATION 667).
Dataset: g.analytic_cohort. Rebuilt by sas/16b_cohort_rebuild.sas (Phase 16); supersedes
the Phase 7 cohort built from g.master_data_merged.

**True rationale (new -- replaces PCM-F-12):** Admit_BMI forces the restriction. All 12,726
non-missing BMI values are inside the admitted cohort; zero ambulatory patients have a
non-missing Admit_BMI. Any analysis that uses BMI has no choice but to restrict to the
admitted cohort.

The OLD rationale (PCM-F-12: ambulatory patients were never eligible for geriatric
assessments, so restricting to INPATIENT/OBSERVATION is a patient-eligibility filter) is
VOID after MRG-06 / PCM-F-19. After the md8 coalesce, most cognitive and frailty scores
belong to ambulatory rows: 13,288 of 20,540 Cognitive_Score values and 15,161 of 23,311
Frailty_Score values sit OUTSIDE the admitted cohort. A cognitive/frailty-only analysis
may not want the admitted restriction at all; anything using BMI has no choice.

**What the restriction does -- population shift (Phase 13 figures):**
The restriction selects a clinically different population, not a convenience missingness
filter. Key shifts from the full 41,150-row file to the 13,890-row cohort:

  Charlson Comorbidity Index = 0:   60.8% (full) -> 34.5% (cohort)
  General anaesthesia:              57.6% -> 84.2%
  GI service:                       18.4% -> 1.7%
  Colonoscopy:                       8.5% -> 0.4%
  RACE = WHITE:                     79.8% -> 87.1%  (7.3-point shift -- required in any
                                                      methods section for generalisability)

**BMI availability within the 13,890 admitted cohort (from sas/16b_cohort_rebuild.sas run,
2026-09-22):**
  HAVE Admit_BMI: 12,726 of 13,890 = 91.6%
  LACK Admit_BMI:  1,164 of 13,890 =  8.4%
  (Denominator is the 13,890 admitted cohort, NOT the 41,150 full harmonized file.)

**Cross-reference:** sas/16b_cohort_rebuild.sas (Phase 16); HARM-10 satisfied.
QC output: qc/16b_cohort_missingness.txt.

**Attribution:** Decided by Gerard, 2026-09-21. Price: informed.

**Resolved:** 2026-09-21 | Owner: Gerard | Phase 16 Plan 02

---

## PCM-D-08: g library location

**Decision:** Use `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge` as the `g` libpath for all Phase 3+ prep datasets (`g.prep_mdN`, `g.master_data_merged`).

**Rationale:** The git repo on the analysis machine is cloned into the `\merge` subdirectory on the P: drive. Keeping the `g` library in that same directory simplifies the two-machine workflow -- no separate `C:\PeCAN_work\data` directory needs to be created or maintained. The P: drive path is outside the git working tree (`.sas7bdat` files are gitignored), satisfying PHI safety (RESEARCH Pitfall 9 / PCM-C-04).

**Resolved:** 2026-08-26 | Owner: Gerard

---

## PCM-D-09: md3-owns missingness trade-off (Phase 4 merge)

**Decision:** Any variable assigned to md3 in the ownership resolution step inherits
md3's missingness pattern. If md3 has a missing value for a patient on a given variable,
the merged file will also be missing for that patient -- even if another source carried a
non-missing value -- because under KEEP= only md3's copy enters the merge PDV.

**Rationale:** md3 is the spine (41,150 rows, complete superset of all patient IDs,
PCM-F-02). Accepting its missingness avoids arbitrary tie-breaking where sources
disagree. For Admit_BMI this is provably free (PCM-F-07: coalescing every other source
recovers nothing; all 28,424 missings in the 41,150-row merged file are missing at
source in md3 and equally missing in every other source that has the patient). For other
md3-owned variables this has NOT been verified. This is a deliberate design choice.

**Implication for analysts:** Where md3 has a missing value on a variable it owns,
analysts should not assume that the variable was unavailable for that patient in ALL
sources. They should check the per-source prep datasets (g.prep_mdN) if imputation or
recovery from another source is later authorized.

**Resolved:** 2026-08-26 | Owner: Gerard | Phase 4 Plan 01

---

## Resolutions -- 2026-08-27

### PCM-D-01 -- Death variable naming: KEEP SEPARATE

`Death_Date_Y_N` (md1-md5), `IsDead_Y_N` (md6) and `Death` (md7) land as three columns in the
merged file. `_30_DAY_MORTALITY` and `Death_Days_After_Surgery` are separate measures and were
never candidates for merging.

**Rationale:** this project delivers an analysis-ready merged file, not analysis decisions.
Collapsing three source-specific names into one asserts they measure the same thing, which
nobody has verified. Keeping them separate preserves the information and lets whoever runs the
mortality analysis make that call with the provenance flags in hand.

**Consequence:** any mortality analysis must decide which column applies to which patients.
`in_md1`-`in_md8` make that determinable. Note in the data dictionary.

### PCM-D-02 -- Frailty component encoding: KEEP SEPARATE

The five frailty items exist as character Y/N (md6, md7) and numeric `_Value` (md3, md5) -- ten
columns for five concepts. All ten are retained.

**Rationale:** the width difference that forced the md7 ownership override ($3 in md7 vs $1 in
md6) is itself evidence the two encodings are not interchangeable. Reconciling them without
knowing why they differ would be guessing.

### PCM-D-03 -- ISO_SEV naming: KEEP SEPARATE

`ISO_SEV_Exp_IntraOp_MAC_Average` (md1-md3), `ISO_SEV_IntraOp_MAC_Average` (md4) and
`ISO_SEV_MAC_TOTAL_Exp` (md8) land as three columns.

**Rationale:** md8's is a **TOTAL**, not an average -- it was never a naming variant and must
stay separate on its own merits. The md4 name may be a variant of the md1-md3 name, but that
is unverified.

### PCM-D-04 -- Emergent: RETAIN despite rarity

`Emergent` stays in the merged file at 0.05% / 0.09% positive (7 in md1, 21 in md8).

**Rationale:** the rate is consistent across two independently exported cohorts, and the
blank/missing share matches to within a tenth of a percent (7.92% vs 7.98%). Whatever the
field means, it behaves consistently. Dropping a column is irreversible for downstream users;
documenting its limitation is not.

**Caveat for the data dictionary:** at 7 and 21 positives this is almost certainly a field
clinicians rarely complete rather than a true emergency rate. `Patient_Type` and `Admit_Source`
are likely better urgency proxies. Do not model on `Emergent` without checking that first.

### PCM-D-07 -- Age floor: DEFERRED

The observed minimum of 64 is not being investigated in this project.

**Consequence:** the QC-05 `Age_at_Encounter` floor of 18 stays as a type-sanity guard and
cannot fire. **Do not tighten it to 64** -- that would convert an unexamined question into a
pipeline abort. Whoever defines the analytic cohort in Phase 7 inherits this.

### PCM-D-08 -- The 9 envelope-violating rows: FLAG, DON'T NULL

9 rows have an operative sub-interval longer than the room-occupancy interval containing it
(5 on `rt_INCISE_to_DRESS_mins`, 4 on `rt_RM_START_to_INCISION_mins`). All values are positive
and were inside the old QC-05 bounds.

**Resolution:** add `rt_envelope_flag` (MRG-05), derived in the Phase 4 merge DATA step. Values
are retained.

**Rationale:** each of the three timestamps is individually plausible; only the combination is
impossible, and nothing identifies which one is wrong. Nulling would destroy two good values to
punish one bad one. A flag preserves all three and moves the judgment to the analyst.

**Why Phase 4 and not Phase 3:** the ownership map is built in Phase 2 from the source files, so
a variable invented during prep is not in it -- and MRG-04 asserts zero unmapped columns in the
merged file. A prep-created flag would fail that assertion. Derived at merge time, it joins the
exclusion list beside `n_sources` and `in_md1`-`in_md8`.

**QC-06 is reframed** to assert zero *unflagged* violations. It passes now and still fires if a
future re-extract introduces a violation the flag logic misses. Asserting zero violations would
have meant a permanently red pipeline or eventually deleting the check.

**Still open:** report the 9 upstream to the PeCAN data group. The flag makes the pipeline
honest; it does not fix the extract.

### PCM-D-09 -- Operative-interval ceilings: DROP

The three QC-05 ceilings (`rt_INCISE_to_DRESS_mins` 2000, `rt_RM_START_to_INCISION_mins` 500,
`rt_RM_START_to_RM_END_mins` 2000) are removed. QC-05 goes from 8 assertions to 5.

**Rationale:** none of the three fired on any of 41,150 rows. Every QC-05 time failure was a
negative value. A bound that has never fired and has no mechanism to fire is not a check -- it is
an invitation to widen it later to make a run green.

**What replaced them:** floors are handled at source by PREP-08 (negatives nulled); impossible
combinations by QC-06. The SECTION 5c distribution report is retained as the record of the
measurement that justified this.

### PCM-D-11 -- md3-owns missingness: CLOSED, costs nothing

**Question:** ownership gives md3 first claim on every variable it carries, so the merged file
inherits md3's missing values and discards any value another source holds for the same patient.
How much is lost?

**Answer: nothing measurable.**

| Variable | Comparison | Recoverable |
|---|---|---|
| `Admit_BMI` | md3 <- all seven others | 0 (PCM-F-07) |
| `Cognitive_Score` | md3 <- md5 | 0 |
| `Cognitive_Score` | md3 <- md6 | 0 |
| `Frailty_Score` | md3 <- md5 | 0 |
| `Frailty_Score` | md3 <- md6 | 0 |

Where md3 carries a column and the value is blank, no other source has a value for that patient.
Consistent with md3 being the fullest extract, not merely the widest. Recorded as **PCM-F-17**.

**Caveat:** three variables, not all of them -- but these three drive the 6,523 complete-case N,
so the ones that matter are checked. A patient present only in md3 cannot be recovered from
anywhere, so zero here means "no recoverable overlap," not "no missingness."

---

### PCM-D-10 -- Negatives in other rt_* variables: TRIAGED FROM PREP-09

The PREP-09 report (logs/03_negtime_md3.txt) was scanned for negative values in every
rt_* variable other than the three PREP-08 already nulls. Counts are guarded
(IS NOT MISSING AND var < 0, per PCM-T-11).

**Anchor offsets -- negatives are LEGITIMATE, NOT nulled:**
rt_ANCHOR_to_ADMIT_days, rt_ANCHOR_to_SURGERY_days, rt_ANCHOR_to_DISCHG_days are offsets
from an anchor date, not durations. A negative value means the event preceded the anchor,
which is meaningful. Report counts: 0 negatives across all sources for all three variables.
NO ACTION -- do not null.

**PREP-08 already-handled variables (Bucket B, confirmed 0 post-null):**
rt_INCISE_to_DRESS_mins: 0 across all sources (nulled by PREP-08).
rt_RM_START_to_INCISION_mins: 0 across all sources (nulled by PREP-08).
rt_RM_START_to_RM_END_mins: 0 across all sources (nulled by PREP-08).
NO further action.

**Duration variables (rt_*_mins) with zero negatives (Bucket C -- clean):**
All rt_*_mins variables not listed in Bucket B or Bucket D showed 0 guarded negatives.
These include rt_AN_START_to_AN_END_mins, rt_ADMIT_to_AN_END_mins, rt_ADMIT_to_RM_END_mins,
and all others not named below.

**Duration variables with non-zero negatives (Bucket D -- RETAIN-WITH-DOC):**
Per-source guarded negative counts from PREP-09:

  rt_RM_START_to_AN_START_mins:
    md1: 7369  md2: 7369  md3: 22575  md4: 4778  md5: 4778  md6: 5524  md7: 4904  md8: n/a
  rt_ADMIT_to_AN_START_mins:
    md1: 3  md2: 3  md3: 4  md4: 1  md5: 1  md6: 0  md7: 0
  rt_ADMIT_to_BLOCK_START_mins:
    md1: 3  md2: 3  md3: 3  md4: 0  md5: 0
  rt_ADMIT_to_BLOCK_END_mins:
    md1: 3  md2: 3  md3: 3  md4: 0  md5: 0
  rt_ADMIT_to_RM_START_mins:
    md1: 3  md2: 3  md3: 3
  rt_ADMIT_to_INCISION_mins:
    md1: 2  md2: 2  md3: 2
  rt_ADMIT_to_DRESS_mins:
    md3: 1  md4: 1  md5: 1
  rt_RM_START_to_DRESS_mins:
    md3: 2  md4: 2  md5: 2
  rt_RM_START_to_INDUCTION_mins:
    md3: 29  md4: 13  md5: 13  md6: 14  md7: 2
  rt_RM_START_to_EMERGENCE_mins:
    md3: 1  md7: 1
  rt_BLOCK_START_TO_BLOCK_END_mins:
    md1: 1  md2: 1  md3: 1

**Interpretation of rt_RM_START_to_AN_START_mins:** The very large counts (4,778-22,575)
indicate that anesthesia start is systematically recorded before room start across all
sources. This is a workflow pattern -- anesthesia preparation begins before the patient
enters the room -- not random data error. The negative values are internally consistent
and carry clinical meaning.

**Interpretation of small-count variables (1-29 negatives):** These small counts likely
represent the same few problem records appearing across sources due to the multi-source
structure of the dataset.

**Bucket-D decision -- RETAIN-WITH-DOC (no Phase 3->4->5 re-run):**
Human decision 2026-08-27: all Bucket D variables retain their negative values unchanged.
No nulling. No Phase 3->4->5 re-run is triggered. Rationale: the large counts in
rt_RM_START_to_AN_START_mins reflect a systematic and clinically interpretable workflow
pattern; the small counts in the remaining variables affect at most ~29 records and likely
reflect the same few records replicated across sources. Analysts using these variables
should be aware that negative values are present and represent real sequencing, not errors.

**Resolved:** 2026-08-27 | Owner: Gerard | Phase 6 Plan 01

---

## Standing note for the data dictionary

Three concepts appear as multiple columns by decision, not by oversight:

| Concept | Columns | Decision |
|---|---|---|
| Mortality flag | `Death_Date_Y_N`, `IsDead_Y_N`, `Death` | PCM-D-01 |
| Frailty components | five char Y/N + five numeric `_Value` | PCM-D-02 |
| ISO_SEV exposure | three columns; md8's is a TOTAL | PCM-D-03 |

Anyone consuming the merged file needs to know these are deliberate.

---

## OWN-03 Variable Conflicts
<!-- generated by 02_ownership.sas Plan 02 - do not hand-edit the generated block -->
 
<!-- OWN-03 CONFLICT ROWS GENERATED   26AUG2026:11:16:47 -->
| Variable | Sources | Declared Owner | Resolution |
|----------|---------|----------------|------------|
| ADMIT_BMI | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| ADMIT_SOURCE | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| AGE_AT_ENCOUNTER | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| ANESTHESIA_TYPE | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| ASA__ANESTH_RECORD_ | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| BASE_PROCEDURE_1 | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| BASE_PROCEDURE_CODE_1 | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| BRADEN_ACTIVITY | md3|md6|md7 | TBD | Pending |
| BRADEN_MOBILITY | md3|md6|md7 | TBD | Pending |
| BRADEN_SENSORY_PERCEPTION | md3|md6|md7 | TBD | Pending |
| CHARGES | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| CHARLSON_COMORBIDITY_INDEX | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COGNITIVEDISORDER_YN | md1|md2|md3 | TBD | Pending |
| COGNITIVE_CATEGORY | md3|md4|md5|md6|md7|md8 | TBD | Pending |
| COGNITIVE_DISORDER | md4|md5 | TBD | Pending |
| COGNITIVE_SCORE | md3|md4|md5|md6|md7|md8 | TBD | Pending |
| COMP10_T80 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMP10_T81 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMP10_T82 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMP10_T83 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMP10_T84 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMP10_T85 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMP10_T86 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMP10_T87 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMP10_T88 | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| COMPLICATION_SUM | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| CPT1_CLASS | md1|md3|md4|md6|md7 | TBD | Pending |
| CPT1_LABEL | md1|md3|md4|md6|md7 | TBD | Pending |
| CPT_1 | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| CPT_1_DESCRIPTION | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| DAY_OF_WEEK__CHAR_ | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| DAY_OF_WEEK__NUM_ | md3|md6|md7 | TBD | Pending |
| DEATH_DATE_Y_N | md1|md2|md3|md4|md5 | TBD | Pending |
| DEATH_DAYS_AFTER_SURGERY | md3|md4|md5|md6|md7 | TBD | Pending |
| DIABETES | md4|md5 | TBD | Pending |
| DIABETES_YN | md1|md2|md3 | TBD | Pending |
| DISCHG_DISPOSITION | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| EDUCATION | md1|md2|md3|md4|md5|md8 | TBD | Pending |
| EMERGENT | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| EMPLOYEECODE | md3|md6|md7 | TBD | Pending |
| EMPLOYEESTATUS | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| ENCRYPTED_ENCOUNTER | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| ENCRYPTED_MRN | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| ETHNICITY | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| FEELS_EXAUSTED | md6|md7 | TBD | Pending |
| FEELS_EXAUSTED_VALUE | md3|md5 | TBD | Pending |
| FENTANYL_SUBLIMAZE_MG_INTRAOP_TO | md1|md2|md3|md4 | TBD | Pending |
| FENTANYL_SUBLIMAZE_MG__1_7_TOTAL | md1|md2|md3|md4 | TBD | Pending |
| FRAILTY_CATEGORY | md3|md4|md5|md6|md7|md8 | TBD | Pending |
| FRAILTY_SCORE | md3|md4|md5|md6|md7|md8 | TBD | Pending |
| HOLIDAYS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| HYDROMORPHONE_MG_INTRAOP_TOTAL | md1|md2|md3|md4 | TBD | Pending |
| HYDROMORPHONE_MG__1_7_TOTAL | md1|md2|md3|md4 | TBD | Pending |
| HYPERLIPIDEMIA | md4|md5 | TBD | Pending |
| HYPERLIPIDEMIA_YN | md1|md2|md3 | TBD | Pending |
| HYPERTENSION | md4|md5 | TBD | Pending |
| HYPERTENSION_YN | md1|md2|md3 | TBD | Pending |
| ICD10_PRINCIPAL_DIAGNOSIS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| ICD10_PRINCIPAL_DIAGNOSIS_DESC | md1|md2|md3|md4|md5 | TBD | Pending |
| ICD10_PRINCIPAL_DIAGNOSIS_POA | md6|md7 | TBD | Pending |
| ICU_LOS_TOTAL_TIME_HOURS | md2|md3|md4 | TBD | Pending |
| INTRAOP_KETAMINE | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| ISO_EXP_INTRAOP_MAC_AVERAGE | md1|md2|md3|md4|md8 | TBD | Pending |
| ISO_EXP_INTRAOP_MAC_MINUTES_TOTA | md1|md2|md3|md4|md8 | TBD | Pending |
| ISO_EXP_INTRAOP_MAC_TOTAL | md1|md2|md3|md4|md8 | TBD | Pending |
| ISO_EXP_INTRAOP_TOTAL | md1|md2|md3|md4|md8 | TBD | Pending |
| ISO_SEV_EXP_INTRAOP_MAC_AVERAGE | md1|md2|md3 | TBD | Pending |
| KETAMINE_MG_1_7_TOTAL | md1|md2|md3|md4|md8 | TBD | Pending |
| KETAMINE_MG_INTRAOP_TOTAL | md1|md2|md3|md4|md8 | TBD | Pending |
| LATITUDE | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| LIDOCAINE_MG_1_7_TOTAL | md1|md2|md3|md4 | TBD | Pending |
| LIDOCAINE_MG_INTRAOP_TOTAL | md1|md2|md3|md4 | TBD | Pending |
| LONGITUDE | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| LOS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| LOS_IN_HOURS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| LOW_PHYSICAL_ACTIVITY | md6|md7 | TBD | Pending |
| LOW_PHYSICAL_ACTIVITY_VALUE | md3|md5 | TBD | Pending |
| MARITAL_STATUS | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| MOVEMENTDISORDER | md4|md5 | TBD | Pending |
| MOVEMENTDISORDER_YN | md1|md2|md3 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_GIVEN__1_7_T | md1|md2|md3|md4|md8 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_INTRAOP_TOTA | md1|md2|md3|md4|md8 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_MG_POD_DAY1 | md1|md2|md3|md4|md8 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_MG_POD_DAY2 | md1|md2|md3|md4|md8 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_MG_POD_DAY3 | md2|md3|md4|md8 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_MG_POD_DAY4 | md2|md3|md4|md8 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_MG_POD_DAY5 | md2|md3|md4|md8 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_MG_POD_DAY6 | md2|md3|md8 | TBD | Pending |
| ORAL_MORPHINE_EQUIV_MG_POD_DAY7 | md2|md3|md4|md8 | TBD | Pending |
| PATIENT_TYPE | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| PAYER | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| PREOP_BLOCK | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| PROPOFOL_MG_1_7_TOTAL | md1|md2|md3|md4|md8 | TBD | Pending |
| PROPOFOL_MG_INTRAOP_TOTAL | md1|md2|md3|md4|md8 | TBD | Pending |
| RACE | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| ROOM_TYPE | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ADMIT_TO_AN_END_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ADMIT_TO_AN_START_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ADMIT_TO_BLOCK_END_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ADMIT_TO_BLOCK_START_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ADMIT_TO_DRESS_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ADMIT_TO_INCISION_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ADMIT_TO_RM_END_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ADMIT_TO_RM_START_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ANCHOR_TO_ADMIT_DAYS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ANCHOR_TO_DISCHG_DAYS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_ANCHOR_TO_SURGERY_DAYS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_AN_START_TO_AN_END_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_BLOCK_START_TO_BLOCK_END_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_INCISE_TO_DRESS_MINS | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| RT_RM_START_TO_AN_START_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_RM_START_TO_DRESS_MINS | md1|md2|md3|md4|md5|md6|md7 | TBD | Pending |
| RT_RM_START_TO_EMERGENCE_MINS | md3|md4|md5|md6|md7 | TBD | Pending |
| RT_RM_START_TO_INCISION_MINS | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| RT_RM_START_TO_INDUCTION_MINS | md3|md4|md5|md6|md7 | TBD | Pending |
| RT_RM_START_TO_RM_END_MINS | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| SERVICE | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| SEV_EXP_INTRAOP_MAC_AVERAGE | md1|md2|md3|md4|md8 | TBD | Pending |
| SEV_EXP_INTRAOP_MAC_MINUTES_TOTA | md1|md2|md3|md4|md8 | TBD | Pending |
| SEV_EXP_INTRAOP_MAC_TOTAL | md1|md2|md3|md4|md8 | TBD | Pending |
| SEV_EXP_INTRAOP_TOTAL | md1|md2|md3|md4|md8 | TBD | Pending |
| SEX | md1|md2|md3|md4|md5|md6|md7|md8 | TBD | Pending |
| SLEEP_APNEA | md4|md5 | TBD | Pending |
| SLEEP_APNEA_YN | md1|md2|md3 | TBD | Pending |
| SLOW_WALKING_SPEED | md6|md7 | TBD | Pending |
| SLOW_WALKING_SPEED_VALUE | md3|md5 | TBD | Pending |
| SORT_ID | md4|md5 | TBD | Pending |
| SSDI_DEATH_DATE_Y_N | md1|md2|md3 | TBD | Pending |
| SSDI_DEATH_Y_N | md4|md5|md6 | TBD | Pending |
| SUFENTANIL_MG_INTRAOP_TOTAL | md1|md2|md3|md4 | TBD | Pending |
| SUFENTANIL_MG__1_7_TOTAL | md1|md2|md3|md4 | TBD | Pending |
| UNINTENDED_WEIGHT_LOSS | md6|md7 | TBD | Pending |
| UNINTENDED_WEIGHT_LOSS_VALUE | md3|md5 | TBD | Pending |
| WEEKEND_INDICATOR | md1|md2|md3|md4|md5 | TBD | Pending |
| WEEK_GRIP_STRENGTH | md6|md7 | TBD | Pending |
| WEEK_GRIP_STRENGTH_VALUE | md3|md5 | TBD | Pending |
| _30_DAY_MORTALITY | md1|md2 | TBD | Pending |

---

### PCM-D-13 -- SSDI/CPT1/label-sweep concept harmonization (HARM-04)

Confirmed 2026-09-21 by Gerard. The following concepts from the Phase 14 label
sweep (14_label_similarity.sas) were screened for gate (m) characters, reviewed
against label_similarity_candidates.csv, marked CONFIRMED=YES in
concept_decisions.csv, and applied by 10b_concept_harmonize.sas (not by hand):

  SSDI_DEATH_FLAG -> h_ssdi_death
    Sources: SSDI_DEATH_DATE_Y_N (priority 1), SSDI_DEATH_Y_N (priority 2),
             SSDI_DEATH (priority 3)
    Values: Y/N pass-through (TARGET_VALUE = VALUE_TXT; no remapping needed)

  Label-similarity candidates: none confirmed

CPT1_CODE_LABEL: keep separate -- resolved 2026-09-22 by Gerard.
  CPT1_CLASS (numeric procedure code) and CPT1_LABEL (text description) are
  complementary variables, not encoding aliases. The same pattern as
  ICD10_PRINCIPAL_DIAGNOSIS + ICD10_PRINCIPAL_DIAGNOSIS_DESC, which are already
  kept separate in the merged file. No rows added to concept_decisions.csv;
  no harmonization step runs for this pair.

Rationale: SSDI_DEATH_FLAG is the same three-variant death-flag shape as the
PCM-D-01 family already harmonized. All five observed values (Y and N across
three source columns) are clean alphanumeric strings. No label-similarity
candidate pairs were judged to be the same underlying concept by the reviewer.
Attribution: the CSV records the decision; this entry records who confirmed it
and when (HARM-04 requires attributed and dated).

---

### PCM-D-14 -- Pipeline-derived column rule (HARM-07)

Decided 2026-09-14 by Gerard. g.master_data_harmonized CARRIES in_md1, in_md2,
in_md4..in_md8, n_sources, rt_envelope_flag, and rt_* (source membership, row count,
clinical timing). It DROPS in_md3 (constant: md3 is the spine) and every h_*_src
companion. Companions are dropped only because each is single-valued -- no secondary
source fires -- and that premise is asserted in every run (assert_src_single), not
assumed; a companion that ever becomes multi-valued fails the run and forces the
concept back to review.

Enforcement: drop= dataset option in the SECTION 5 DATA step of 10b_concept_harmonize.sas,
gated by drop_pipeline_noinfo=1; SECTION 6 assertions assert_src_single (premise) and
assert_harm07 (absence); assert_merged_unchanged re-queries g.master_data_merged post-run.
g.master_data_merged is never written by 10b.

---

## PCM-D-12 -- %abort cancel return code on Windows batch

**Question:** When 99_run_all.sas is submitted via "sas -sysin ...", what OS return
code does Windows receive when a %abort cancel fires?

**Answer:** Return code = 3 (observed on this machine, SAS 9.4M8, Windows 10 Home
10.0.19045, 2026-09-22).

**Test method:** sas -sysin test_abort.sas -sasuser WORK where test_abort.sas contains
only "%abort cancel;". Return code captured via %ERRORLEVEL% in CMD immediately after
SAS exits. The -sasuser WORK flag was required because the default SASUSER library path
is invalid in headless batch mode on this machine.

**Consequence for scheduling:** Any Windows Task Scheduler job or CI step running
99_run_all.sas must treat return code 3 as a pipeline failure. A return code of 0
from the SAS process means all phases completed without an abort.

**Resolved:** 2026-09-22 | Owner: Gerard | Phase 8 Plan 02

---

## PCM-D-17 -- pecan_ID Derivation Method: RESOLVED

**Decision:** pecan_ID is a surrogate sequential integer (1, 2, 3...). Distinct
ENCRYPTED_MRN values in g.master_data_merged are numbered in ascending order of each
MRN's smallest PRECEDE_STUDY_ID, evaluated numerically (so that "10" follows "9", not
precedes it). MRNs added on later pipeline runs are appended after the existing maximum,
preserving all prior patient numbers. Blank MRNs (empty after strip()) and placeholder
MRNs (literal string NULL after strip(upcase())) receive no pecan_ID and are excluded
from the crosswalk entirely.

**Crosswalk:** g.pecan_id_xwalk (columns: ENCRYPTED_MRN $40, pecan_ID num) is
append-only. The reference for "unchanged" is the latest dated backup, not the table
itself. On each re-run: (1) assert the current g.pecan_id_xwalk equals the latest backup
before appending; (2) add new MRNs via PROC APPEND only -- the table is never fully
rewritten; (3) after appending, assert every backup row is still present; (4) write a
new dated backup. First run: skip pre/post assertions, build the crosswalk, write the
first backup, and log the run as the initial build.

**MRN retention:** ENCRYPTED_MRN is retained in all analysis outputs
(g.master_data_harmonized, g.analytic_cohort) alongside pecan_ID. No DROP statement;
no schema change to existing columns.

**Backup:** A dated backup copy of g.pecan_id_xwalk is written to the path defined by
the macro variable xwalk_backup_path in 00_config.sas, which points to a directory on
P: outside qc/ and outside the git working tree (ENCRYPTED_MRN values must not enter
qc/ or git). If the crosswalk is ever deleted, program 20 aborts with an error directing
the user to restore from the backup before re-running.

**Ruled out:** Unsalted SHA-256 hash (no privacy benefit over the MRN itself; produces
a 64-char key awkward for analysis joins). Salted/keyed hash (requires managing a secret
outside git). Program 20 rewriting 10b/16b output datasets directly (violates PCM-T-02
and PCM-T-05 single-producer rule).

**Attribution:** Gerard Garvan, 2026-09-23.

**Resolved:** 2026-09-23 | Owner: Gerard | Phase 20 Plan 01

---

## PCM-D-18 -- pecan_ID Attach Point: RESOLVED

**Decision:** pecan_ID is attached to analysis datasets by programs 10b and 16b at
build time (option 2 -- attachment at the producer step). Each dataset has a single
producer. The merged file g.master_data_merged is untouched -- no pecan_ID column is
added to it.

**Datasets that receive pecan_ID:**
- g.master_data_harmonized: attached by program 10b (sas/10b_concept_harmonize.sas);
  column count goes from 174 to 175.
- g.analytic_cohort: attached by program 16b (sas/16b_cohort_rebuild.sas);
  column count goes from 174 to 175.

**PID-05 assertions** (one set in each producer program): row count unchanged after
join; zero blank pecan_ID where ENCRYPTED_MRN is non-blank and non-placeholder; zero
PRECEDE_STUDY_IDs gaining a second pecan_ID after attachment.

**Column-count assertions** updated in both 10b and 16b: g.master_data_harmonized and
g.analytic_cohort each assert 175 columns after the join. The g.master_data_merged
column-count assertion in 10b (176 columns) is unaffected -- pecan_ID is not added
to merged.

**DATA_DICTIONARY.xlsx** is updated by program 08 (sas/08_dictionary.sas), which
appends an explicit pecan_ID row to work.dict_final after the main derivation_map join
(the join is left on g.master_data_merged columns, so an entry in derivation_map would
be silently dropped). The _gate5 assertion is updated to expect n_dict_meta + 1 rows.
One row; derivation note names both datasets that carry pecan_ID.

**Attribution:** Gerard Garvan, 2026-09-23.

**Resolved:** 2026-09-23 | Owner: Gerard | Phase 20 Plan 01
