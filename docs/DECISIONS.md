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
| PCM-D-05 | Analytic cohort INPATIENT/OBSERVATION restriction | Pending -- Phase 7 | TBD |
| PCM-D-06 | PRECEDE_Study_ID_1 drop vs retain | Resolved -- drop (PREP-04), proven identical first | Gerard |
| PCM-D-07 | Age floor (minimum 64) | **Deferred 2026-08-27 -- not pursuing** | Gerard |
| PCM-D-08 | The 9 envelope-violating rows | **Resolved 2026-08-27 -- flag, don't null** | Gerard |
| PCM-D-09 | QC-05 operative-interval ceilings never fire | **Resolved 2026-08-27 -- drop them** | Gerard |
| PCM-D-10 | Negatives in other rt_* variables | Pending -- needs the PREP-09 report | Gerard |
| PCM-D-11 | md3-owns missingness trade-off | **Closed 2026-08-27 -- costs nothing** | Gerard |

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
