USE Project0821712;

DROP TABLE IF EXISTS dbo.progression;
CREATE TABLE dbo.progression (
    PatientDurableKey BIGINT,
    Laterality VARCHAR(11),
    first_npdr_date DATE,
    progression_date DATE,
    days_to_progression INT,
    progressed_flag INT
);

DROP TABLE IF EXISTS dbo.final_events;
CREATE TABLE dbo.final_events (
    PatientDurableKey BIGINT,
    Laterality VARCHAR(11),
    Date_retin_dx DATE,
    Date_complication DATE,
    icd_code VARCHAR(300),
    complication_type VARCHAR(30),
    hydroxyurea_exposed_event INT,
    exposed_at_index INT,
    first_start_after_index DATE,
    exposure_start_date DATE
);

DROP TABLE IF EXISTS dbo.injection_complication_long;
CREATE TABLE dbo.injection_complication_long (
    PatientDurableKey BIGINT,
    CptCode NVARCHAR(50),
    injection_date DATE,
    Laterality VARCHAR(2)
);

DROP TABLE IF EXISTS dbo.sx_complication_long;
CREATE TABLE dbo.sx_complication_long (
    PatientDurableKey BIGINT,
    CptCode NVARCHAR(50),
    complication_sx_date DATE,
    Laterality VARCHAR(2)
);

DROP TABLE IF EXISTS dbo.va_timepoints;
CREATE TABLE dbo.va_timepoints (
    PatientDurableKey BIGINT,
    Laterality VARCHAR(11),
    IndexDate DATE,
    baseline_va NUMERIC(18,2),
    va_3m NUMERIC(18,2),
    va_6m NUMERIC(18,2),
    va_9m NUMERIC(18,2),
    va_1y NUMERIC(18,2),
    va_2y NUMERIC(18,2),
    va_3y NUMERIC(18,2),
    va_5y NUMERIC(18,2)
);

DROP TABLE IF EXISTS dbo.Dx_complication_long;
CREATE TABLE dbo.Dx_complication_long (
    PatientDurableKey BIGINT,
    EncounterKey BIGINT,
    DateValue DATE,
    icd10 NVARCHAR(300),
    Years INT,
    DisplayString NVARCHAR(300),
    CoverageFinancialClass NVARCHAR(300),
    Laterality VARCHAR(11),
    PrevDate DATE,
    NewEpisodeFlag INT,
    EpisodeNumber INT
);

DROP TABLE IF EXISTS dbo.SC_retin_dx;
CREATE TABLE dbo.SC_retin_dx (
    PatientDurableKey BIGINT,
    Date_retin_dx DATE,
    Age_retin_dx INT,
    icd_retin_dx NVARCHAR(300),
    DisplayString_retin_dx NVARCHAR(300),
    Insurance_retin_dx NVARCHAR(300),
    Laterality VARCHAR(11),
    was_inferred INT,
    EncounterCountAfterFirstDate_opt INT,
    LastEncounterDate_opt DATE,
    EncounterCountAfterFirstDate INT,
    LastEncounterDate DATE,
    FU_day_opt INT,
    FU_day INT
);

DROP TABLE IF EXISTS dbo.SC_pt;
CREATE TABLE dbo.SC_pt (
    PatientDurableKey BIGINT,
    EncounterKey BIGINT,
    Date_SC_dx DATE,
    Age_SC_dx INT,
    icd_SC_dx NVARCHAR(300),
    DisplayString NVARCHAR(300),
    Genotype VARCHAR(5),
    Insurance_sc_dx NVARCHAR(300)
);

DROP TABLE IF EXISTS dbo.final_cohort_meds;
CREATE TABLE dbo.final_cohort_meds (
    PatientDurableKey BIGINT,
    Date_retin_dx DATE,
    Age_retin_dx INT,
    icd_retin_dx NVARCHAR(300),
    DisplayString_retin_dx NVARCHAR(300),
    Insurance_retin_dx NVARCHAR(300),
    Laterality VARCHAR(11),
    was_inferred INT,
    Date_complication DATE,
    icd_complication NVARCHAR(300),
    age_complication INT,
    DisplayString_complication NVARCHAR(300),
    Insurance_complication NVARCHAR(300),
    Laterality_complication VARCHAR(11),
    Days_complication INT,
    EncounterCountAfterFirstDate_opt INT,
    LastEncounterDate_opt DATE,
    EncounterCountAfterFirstDate INT,
    LastEncounterDate DATE,
    FU_day INT,
    startdate_hydroxyurea DATE,
    endDate_hydroxyurea DATE,
    Date_SC_dx DATE,
    Age_SC_dx INT,
    icd_SC_dx NVARCHAR(300),
    DisplayString NVARCHAR(300),
    Genotype VARCHAR(5),
    Insurance_sc_dx NVARCHAR(300),
    exposed_group VARCHAR(18),
    days_sc_dx_to_hydrox INT,
    days_retin_dx_to_hydrox INT
);

DROP TABLE IF EXISTS dbo.PatientDemo;
CREATE TABLE dbo.PatientDemo (
    PatientDurableKey BIGINT,
    BirthDate DATE,
    Sex NVARCHAR(300),
    MaritalStatus NVARCHAR(300),
    PreferredLanguage NVARCHAR(300),
    [Language] NVARCHAR(11),
    Ethnicity NVARCHAR(300),
    FirstRace NVARCHAR(300),
    MultiRacial TINYINT,
    DeathDate DATE,
    [Status] NVARCHAR(300),
    Country NVARCHAR(300),
    StateOrProvince NVARCHAR(300),
    StateOrProvinceAbbreviation NVARCHAR(300),
    svi_overall_2020 NUMERIC(6,4),
    svi_ses_2020 NUMERIC(6,4),
    svi_house_2020 NUMERIC(6,4),
    svi_minority_2020 NUMERIC(6,4),
    svi_transport_2020 NUMERIC(6,4),
    ruca NVARCHAR(50)
);

DROP TABLE IF EXISTS dbo.final_cohort;
CREATE TABLE dbo.final_cohort (
    PatientDurableKey BIGINT,
    Date_retin_dx DATE,
    Age_retin_dx INT,
    icd_retin_dx NVARCHAR(300),
    DisplayString_retin_dx NVARCHAR(300),
    Insurance_retin_dx NVARCHAR(300),
    Laterality VARCHAR(11),
    was_inferred INT,
    Date_complication DATE,
    icd_complication NVARCHAR(300),
    age_complication INT,
    DisplayString_complication NVARCHAR(300),
    Insurance_complication NVARCHAR(300),
    Laterality_complication VARCHAR(11),
    Days_complication INT,
    EncounterCountAfterFirstDate_opt INT,
    LastEncounterDate_opt DATE,
    EncounterCountAfterFirstDate INT,
    LastEncounterDate DATE,
    FU_day INT
);