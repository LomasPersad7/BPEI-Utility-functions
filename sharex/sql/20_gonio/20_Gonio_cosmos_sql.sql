USE COSMOS;
GO

DROP TABLE IF EXISTS #all_cpt;

WITH main_proc AS (
    SELECT DISTINCT
        procevent.PatientDurableKey,
        procevent.[Type] AS proc_type,
        dd.Years,
        procevent.EncounterKey,
        dated.DateValue,
        procdim.CptCode,
        x.Modifier AS LateralityModifier
        -- x.ModifierSource -- optional: which modifier field it came from
    FROM ProcedureEventFact procevent
    INNER JOIN ProcedureDim procdim
        ON procevent.ProcedureDurableKey = procdim.DurableKey -- matching on procedure event data
    LEFT JOIN DurationDim dd
        ON procevent.AgeAtProcedureDateKey = dd.DurationKey
    LEFT JOIN DateDim dated
        ON dated.DateKey = procevent.ProcedureStartDateKey
    CROSS APPLY (
        SELECT TOP 1 val AS Modifier, src AS ModifierSource
        FROM (VALUES
            (procevent.FirstModifier, 'FirstModifier'),
            (procevent.SecondModifier, 'SecondModifier'),
            (procevent.ThirdModifier, 'ThirdModifier'),
            (procevent.FourthModifier, 'FourthModifier')
        ) AS Modifiers(val, src)
        WHERE val IN ('RT', 'LT', '50')
    ) AS x
    WHERE procevent.Count > 0
        AND procevent.ProcedureStartDateKey > 0
        AND dd.Years >= 18
        AND procdim.CptCode IN ('66174', '65820') -- goniotomy cases
        AND procevent.[Type] IN ('PB Charge Procedure', 'Charge Procedure', 'Coded Procedure', 'External Charge Procedure')
        AND EXISTS (
            SELECT 1
            FROM EyeExamTestFact e
            WHERE e.PatientDurableKey = procevent.PatientDurableKey
              AND e.ExamType = N'IOP: Tonometry'
        )
),
ExpandedProcedures AS (
    -- Replace '50' with 'RT' for right eye (Select bilateral cases)
    SELECT
        p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, p.proc_type,
        'RT' AS LateralityModifier
    FROM main_proc p
    WHERE p.LateralityModifier = '50'

    UNION ALL

    -- Replace '50' with 'LT' for left eye (Same bilateral cases)
    SELECT
        p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, p.proc_type,
        'LT' AS LateralityModifier
    FROM main_proc p
    WHERE p.LateralityModifier = '50'

    UNION ALL

    -- Include original rows where Laterality is not '50' (Keep original Laterality for non-bilateral cases)
    SELECT
        p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, p.proc_type,
        p.LateralityModifier
    FROM main_proc p
    WHERE p.LateralityModifier <> '50'
),
procdata AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, LateralityModifier
            ORDER BY DateValue ASC
        ) AS rn
    FROM ExpandedProcedures
)
SELECT
    PatientDurableKey,
    EncounterKey AS EncounterKey_proc,
    -- proc_type,
    DateValue AS proc_date,
    CptCode,
    Years AS AgeAtProcedure,
    LateralityModifier AS Laterality
INTO #all_cpt
FROM procdata
WHERE rn = 1;

-- Verification Queries
SELECT * FROM #all_cpt ORDER BY PatientDurableKey;
SELECT * FROM #all_cpt ORDER BY PatientDurableKey, Laterality, proc_date;
SELECT COUNT(*) FROM #all_cpt;
SELECT COUNT(DISTINCT CONCAT(PatientDurableKey, Laterality)) FROM #all_cpt;
SELECT COUNT(DISTINCT PatientDurableKey) FROM #all_cpt;
SELECT Laterality, COUNT(Laterality) AS N FROM #all_cpt GROUP BY Laterality;


-- Glaucoma dx
DROP TABLE IF EXISTS #Glaucoma;

SELECT DISTINCT
    DiagnosisKey,
    TerminologyConceptKey,
    [Value],
    DisplayString,
    -- dd.Name, NameAndCode, GroupedNameAndCode,
    CASE
        WHEN [Value] LIKE 'H40.10%' THEN 'Unspecified open-angle glaucoma'
        WHEN [Value] LIKE 'H40.11%' THEN 'Primary open-angle glaucoma'
        WHEN [Value] LIKE 'H40.12%' THEN 'Low-tension glaucoma'
        WHEN [Value] LIKE 'H40.13%' THEN 'Pigmentary glaucoma'
        WHEN [Value] LIKE 'H40.14%' THEN 'Capsular glaucoma with pseudo-exfoliation of lens'
        WHEN [Value] LIKE 'H40.15%' THEN 'Residual stage of open-angle glaucoma'
        ELSE 'Other glaucoma'
    END AS glaucoma_type,
    CASE
        WHEN DisplayString LIKE '%right eye%' THEN 'Right'
        WHEN DisplayString LIKE '%left eye%' THEN 'Left'
        WHEN DisplayString LIKE '%bilateral%' THEN 'Bilateral'
        WHEN DisplayString LIKE '%unspecified eye%' THEN 'Unspecified'
        ELSE 'Unspecified' -- Use 999 or another code for cases with no laterality info
    END AS Laterality,
    -- Severity Staging
    CASE
        -- Handle residual glaucoma first (no staging)
        WHEN [Value] LIKE 'H40.15%' THEN 'No stage indicated'
        -- For other types with complete 7-character codes
        WHEN LEN([Value]) = 7 THEN
            CASE SUBSTRING([Value], 7, 1)
                WHEN '0' THEN 'Unspecified'
                WHEN '1' THEN 'Mild'
                WHEN '2' THEN 'Moderate'
                WHEN '3' THEN 'Severe'
                WHEN '4' THEN 'Indeterminate'
                ELSE 'Invalid stage'
            END
        -- Missing stage character
        ELSE 'Stage missing'
    END AS severity
INTO #Glaucoma
FROM DiagnosisTerminologyDim
-- LEFT JOIN DiagnosisDim dd ON dd.DiagnosisKey = DiagnosisTerminologyDim.DiagnosisKey
WHERE [Type] = N'ICD-10-CM'
  AND [Value] LIKE N'H40.1%';

-- Extract All Diagnosis Events for Cohort
DROP TABLE IF EXISTS #all_Dx;

SELECT
    diagEvt.DiagnosisEventKey,
    diagEvt.PatientDurableKey,
    age.Years AS DxAge,
    -- limit to dx max Proc_date
    diagEvt.StartDateKey AS DxDateKey,
    diagStartDate.DateValue AS DxDate,
    diags.[Value],
    diags.DisplayString,
    diags.Laterality
INTO #all_Dx
FROM DiagnosisEventFact diagEvt
-- This join serves two purposes: filtering diagnoses to target codes and mapping values
INNER JOIN #Glaucoma diags
    ON diagEvt.DiagnosisKey = diags.DiagnosisKey
INNER JOIN DurationDim age
    ON diagEvt.AgeKey = age.DurationKey
INNER JOIN DateDim diagStartDate
    ON diagStartDate.DateKey = diagEvt.StartDateKey
INNER JOIN (
    SELECT PatientDurableKey, MAX(proc_date) AS proc_date
    FROM #all_cpt
    GROUP BY PatientDurableKey
) pats
    ON pats.PatientDurableKey = diagEvt.PatientDurableKey
   AND diagStartDate.DateValue <= pats.proc_date
WHERE diagEvt.[Type] <> 'Problem List';


DROP TABLE IF EXISTS #OAG_Last3mo;

WITH expanded_DX AS (
    -- Replace 'Bilateral' with 'RT' for right eye (Select bilateral cases)
    SELECT
        DiagnosisEventKey, PatientDurableKey, 'RT' AS Laterality,
        DxDate, DxAge, [Value], DisplayString
    FROM #all_Dx
    WHERE Laterality = 'Bilateral'

    UNION ALL

    -- Replace 'Bilateral' with 'LT' for left eye (Same bilateral cases)
    SELECT
        DiagnosisEventKey, PatientDurableKey, 'LT' AS Laterality,
        DxDate, DxAge, [Value], DisplayString
    FROM #all_Dx
    WHERE Laterality = 'Bilateral'

    UNION ALL

    -- Include original rows where Laterality is not 'Bilateral'
    SELECT
        DiagnosisEventKey, PatientDurableKey,
        CASE
            WHEN Laterality IN ('Right') THEN 'RT'
            WHEN Laterality IN ('Left') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality,
        DxDate, DxAge, [Value], DisplayString
    FROM #all_Dx
    WHERE Laterality <> 'Bilateral' AND Laterality <> 'Unspecified'
),
matched_laterality AS (
    SELECT
        pt.PatientDurableKey, pt.Laterality, pt.proc_date,
        DE.DiagnosisEventKey, DE.DxDate, DE.DxAge, DE.[Value], DE.DisplayString,
        ROW_NUMBER() OVER (
            PARTITION BY pt.PatientDurableKey, pt.Laterality
            ORDER BY DE.DxDate DESC
        ) AS rn_firstDx
    FROM (SELECT PatientDurableKey, Laterality, proc_date FROM #all_cpt) pt
    INNER JOIN expanded_DX DE
        ON DE.PatientDurableKey = pt.PatientDurableKey
       AND DE.Laterality = pt.Laterality
    WHERE DE.DxDate BETWEEN DATEADD(MONTH, -3, pt.proc_date) AND DATEADD(DAY, 1, pt.proc_date)
),
match_remainder AS (
    SELECT
        pt.PatientDurableKey, pt.Laterality, pt.proc_date,
        DE.DiagnosisEventKey, DE.DxDate, DE.DxAge, DE.[Value], DE.DisplayString,
        ROW_NUMBER() OVER (
            PARTITION BY pt.PatientDurableKey, pt.Laterality
            ORDER BY DE.DxDate DESC
        ) AS rn_firstDx
    FROM (
        SELECT * FROM #all_cpt mp
        WHERE NOT EXISTS (
            SELECT 1
            FROM matched_laterality ml
            WHERE ml.PatientDurableKey = mp.PatientDurableKey
              AND ml.Laterality = mp.Laterality
        )
    ) pt
    INNER JOIN (
        SELECT * FROM expanded_DX WHERE Laterality = 'Unspecified'
    ) DE
        ON DE.PatientDurableKey = pt.PatientDurableKey
    WHERE DE.DxDate BETWEEN DATEADD(MONTH, -3, pt.proc_date) AND DATEADD(DAY, 1, pt.proc_date)
),
joined_data AS (
    SELECT * FROM matched_laterality WHERE rn_firstDx = 1
    UNION ALL
    SELECT * FROM match_remainder WHERE rn_firstDx = 1
)
SELECT *,
    DATEDIFF(DAY, proc_date, DxDate) AS Dx_sx_days
INTO #OAG_Last3mo
FROM joined_data;

DROP TABLE IF EXISTS #cohort_dx_sx;

SELECT
    pt.PatientDurableKey,
    pt.Laterality,
    dx.DiagnosisEventKey,
    dx.DxDate,
    dx.DxAge,
    dx.[Value] AS dx_icd,
    dx.DisplayString,
    dx.Dx_sx_days,
    pt.EncounterKey_proc,
    pt.proc_date,
    pt.CptCode,
    pt.AgeAtProcedure
INTO #cohort_dx_sx
FROM #all_cpt pt
INNER JOIN #OAG_Last3mo dx
    ON dx.PatientDurableKey = pt.PatientDurableKey
   AND dx.Laterality = pt.Laterality;


DROP TABLE IF EXISTS #cohort_with_followup_procedures;

WITH main_proc AS (
    SELECT DISTINCT
        procevent.PatientDurableKey,
        dd.Years,
        procevent.EncounterKey,
        dated.DateValue,
        procdim.CptCode,
        x.Modifier AS LateralityModifier
    FROM (SELECT DISTINCT PatientDurableKey FROM #cohort_dx_sx) pt
    LEFT JOIN ProcedureEventFact procevent
        ON procevent.PatientDurableKey = pt.PatientDurableKey
    INNER JOIN ProcedureDim procdim
        ON procevent.ProcedureDurableKey = procdim.DurableKey
    LEFT JOIN DurationDim dd
        ON procevent.AgeAtProcedureDateKey = dd.DurationKey
    LEFT JOIN DateDim dated
        ON dated.DateKey = procevent.ProcedureStartDateKey
    CROSS APPLY (
        SELECT TOP 1 val AS Modifier, src AS ModifierSource
        FROM (VALUES
            (procevent.FirstModifier, 'FirstModifier'),
            (procevent.SecondModifier, 'SecondModifier'),
            (procevent.ThirdModifier, 'ThirdModifier'),
            (procevent.FourthModifier, 'FourthModifier')
        ) AS Modifiers(val, src)
        WHERE val IN ('RT', 'LT', '50')
    ) AS x
    WHERE procevent.Count > 0
        AND procevent.ProcedureStartDateKey > 0
        AND dd.Years >= 18
        AND procdim.CptCode IN (
            '65815', '65930', '66179', '66180',
            '66183', '66170', '66172', '0449T', '0450T'
        )
        AND procevent.[Type] IN ('PB Charge Procedure', 'Charge Procedure', 'Coded Procedure', 'External Charge Procedure')
),
ExpandedProcedures AS (
    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, 'RT' AS LateralityModifier
    FROM main_proc p WHERE p.LateralityModifier = '50'

    UNION ALL

    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, 'LT' AS LateralityModifier
    FROM main_proc p WHERE p.LateralityModifier = '50'

    UNION ALL

    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, p.LateralityModifier
    FROM main_proc p WHERE p.LateralityModifier <> '50'
),
all_postOP_sx AS (
    SELECT
        p.PatientDurableKey,
        p.Laterality,
        ep.DateValue AS PostOp_date,
        ep.CptCode AS PostOp_cpt,
        ep.Years AS AgeAtPostOp,
        CASE
            WHEN ep.CptCode IN ('65815', '65930') THEN 'Anterior chamber washout'
            WHEN ep.CptCode IN ('66179', '66180') THEN 'Aqueous shunt'
            WHEN ep.CptCode IN ('66170', '66172') THEN 'Trabeculectomy'
            WHEN ep.CptCode IN ('0449T', '0450T', '66183') THEN 'Xen cases'
        END AS PostOP_treatment
    FROM #cohort_dx_sx p
    LEFT JOIN ExpandedProcedures ep
        ON ep.PatientDurableKey = p.PatientDurableKey
       AND ep.LateralityModifier = p.Laterality
    WHERE ep.DateValue BETWEEN DATEADD(DAY, 1, p.proc_date) AND DATEADD(WEEK, 6, p.proc_date)
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality, PostOP_treatment
            ORDER BY PostOp_date ASC
        ) AS PostOP_treatment_rank
    FROM all_postOP_sx
)
SELECT *
INTO #cohort_with_followup_procedures
FROM ranked
WHERE PostOP_treatment_rank = 1;

-- Baseline IOP
DROP TABLE IF EXISTS #Baseline_IOP;

WITH all_iop AS (
    SELECT
        dx.PatientDurableKey,
        dt.DateValue AS [Date],
        eyef.IntraocularPressure,
        eyef.TonometryMethod,
        CASE
            WHEN eyef.Laterality IN ('Right Eye') THEN 'RT'
            WHEN eyef.Laterality IN ('Left Eye') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality
    FROM (SELECT DISTINCT PatientDurableKey FROM #cohort_dx_sx) dx
    LEFT JOIN EyeExamTestFact eyef ON eyef.PatientDurableKey = dx.PatientDurableKey
    LEFT JOIN DateDim dt ON dt.DateKey = eyef.EncounterStartDateKey
    WHERE eyef.ExamType = N'IOP: Tonometry'
      AND eyef.IntraocularPressure IS NOT NULL
      AND eyef.Count = 1
),
ranked AS (
    SELECT
        p.PatientDurableKey, p.Laterality,
        iop.[Date] AS baseline_iop_date,
        iop.IntraocularPressure AS baseline_iop,
        DATEDIFF(DAY, p.proc_date, iop.[Date]) AS interval_sx_iop,
        ROW_NUMBER() OVER (
            PARTITION BY p.PatientDurableKey, p.Laterality
            ORDER BY ABS(DATEDIFF(DAY, p.proc_date, iop.[Date])) ASC
        ) AS Closest_IOP_rank
    FROM #cohort_dx_sx p
    LEFT JOIN all_iop iop
        ON iop.PatientDurableKey = p.PatientDurableKey
       AND iop.Laterality = p.Laterality
    WHERE iop.[Date] BETWEEN DATEADD(DAY, -90, p.proc_date) AND DATEADD(DAY, -1, p.proc_date)
)
SELECT *
INTO #Baseline_IOP
FROM ranked
WHERE Closest_IOP_rank = 1;

-- Follow-Up IOP
DROP TABLE IF EXISTS #IOP_followup_sx;

WITH all_iop AS (
    SELECT
        dx.PatientDurableKey,
        dt.DateValue AS [Date],
        eyef.IntraocularPressure,
        eyef.TonometryMethod,
        CASE
            WHEN eyef.Laterality IN ('Right Eye') THEN 'RT'
            WHEN eyef.Laterality IN ('Left Eye') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality
    FROM (SELECT DISTINCT PatientDurableKey FROM #cohort_with_followup_procedures) dx
    LEFT JOIN EyeExamTestFact eyef ON eyef.PatientDurableKey = dx.PatientDurableKey
    LEFT JOIN DateDim dt ON dt.DateKey = eyef.EncounterStartDateKey
    WHERE eyef.ExamType = N'IOP: Tonometry'
      AND eyef.IntraocularPressure IS NOT NULL
      AND eyef.Count = 1
),
ranked AS (
    SELECT
        p.PatientDurableKey, p.Laterality,
        iop.[Date] AS PostOp_iop_date,
        iop.IntraocularPressure AS PostOp_iop,
        DATEDIFF(DAY, p.PostOp_date, iop.[Date]) AS interval_PostOp_iop,
        ROW_NUMBER() OVER (
            PARTITION BY p.PatientDurableKey, p.Laterality
            ORDER BY ABS(DATEDIFF(DAY, p.PostOp_date, iop.[Date])) ASC
        ) AS Closest_IOP_rank
    FROM (
        SELECT DISTINCT f.PatientDurableKey, f.Laterality, f.PostOp_date, c.proc_date
        FROM #cohort_with_followup_procedures f
        JOIN #cohort_dx_sx c
            ON f.PatientDurableKey = c.PatientDurableKey
           AND f.Laterality = c.Laterality
    ) p
    LEFT JOIN all_iop iop
        ON iop.PatientDurableKey = p.PatientDurableKey
       AND iop.Laterality = p.Laterality
    WHERE iop.[Date] BETWEEN DATEADD(DAY, 1, p.proc_date) AND p.PostOp_date
)
SELECT *
INTO #IOP_followup_sx
FROM ranked
WHERE Closest_IOP_rank = 1;

-- Final Cohort Assembly
DROP TABLE IF EXISTS #final_cohort;

SELECT
    pt.*,
    fu.PostOp_date,
    fu.PostOp_cpt,
    fu.AgeAtPostOp,
    fu.PostOP_treatment,
    DATEDIFF(DAY, pt.proc_date, fu.PostOp_date) AS Sx_PostOpSX_days,
    biop.baseline_iop,
    biop.baseline_iop_date,
    biop.interval_sx_iop,
    i.PostOp_iop_date,
    i.PostOp_iop,
    i.interval_PostOp_iop
INTO #final_cohort
FROM #cohort_dx_sx pt
LEFT JOIN #cohort_with_followup_procedures fu
    ON fu.PatientDurableKey = pt.PatientDurableKey AND fu.Laterality = pt.Laterality
LEFT JOIN #Baseline_IOP biop
    ON biop.PatientDurableKey = pt.PatientDurableKey AND biop.Laterality = pt.Laterality
LEFT JOIN #IOP_followup_sx i
    ON i.PatientDurableKey = pt.PatientDurableKey AND i.Laterality = pt.Laterality;



DROP TABLE IF EXISTS #all_cataract;

SELECT DISTINCT
    procevent.PatientDurableKey,
    dd.Years,
    procevent.EncounterKey,
    dated.DateValue,
    procdim.CptCode,
    x.Modifier AS Laterality
INTO #all_cataract
FROM (SELECT DISTINCT PatientDurableKey FROM #final_cohort) pt
LEFT JOIN ProcedureEventFact procevent
    ON procevent.PatientDurableKey = pt.PatientDurableKey
INNER JOIN ProcedureDim procdim
    ON procevent.ProcedureDurableKey = procdim.DurableKey
LEFT JOIN DurationDim dd
    ON procevent.AgeAtProcedureDateKey = dd.DurationKey
LEFT JOIN DateDim dated
    ON dated.DateKey = procevent.ProcedureStartDateKey
CROSS APPLY (
    SELECT TOP 1 val AS Modifier, src AS ModifierSource
    FROM (VALUES
        (procevent.FirstModifier, 'FirstModifier'),
        (procevent.SecondModifier, 'SecondModifier'),
        (procevent.ThirdModifier, 'ThirdModifier'),
        (procevent.FourthModifier, 'FourthModifier')
    ) AS Modifiers(val, src)
    WHERE val IN ('RT', 'LT', '50')
) AS x
WHERE procevent.Count > 0
  AND procevent.ProcedureStartDateKey > 0
  AND dd.Years >= 18
  AND procdim.CptCode IN ('66984', '66982')
  AND procevent.[Type] IN ('PB Charge Procedure', 'Charge Procedure', 'Coded Procedure', 'External Charge Procedure');

DROP TABLE IF EXISTS #all_cataract_expanded;

WITH ExpandedProcedures AS (
    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, 'RT' AS Laterality
    FROM #all_cataract p WHERE p.Laterality = '50'

    UNION ALL

    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, 'LT' AS Laterality
    FROM #all_cataract p WHERE p.Laterality = '50'

    UNION ALL

    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.Years, p.Laterality
    FROM #all_cataract p WHERE p.Laterality <> '50'
)
SELECT *
INTO #all_cataract_expanded
FROM ExpandedProcedures;

DROP TABLE IF EXISTS #final_cohort_cataract;

WITH concurrent_cataract_gonio AS (
    SELECT
        f.PatientDurableKey,
        f.Laterality,
        ac.DateValue AS concurrent_cataract_gonio_date,
        MIN(ac.CptCode) AS concurrent_cataract_gonio_code
    FROM #final_cohort f
    JOIN #all_cataract_expanded ac
        ON f.PatientDurableKey = ac.PatientDurableKey
       AND f.Laterality = ac.Laterality
       AND f.proc_date = ac.DateValue
    GROUP BY f.PatientDurableKey, f.Laterality, ac.DateValue
),
concurrent_cataract_PostOp AS (
    SELECT
        f.PatientDurableKey,
        f.Laterality,
        ac.DateValue AS concurrent_cataract_PostOp_date,
        MIN(ac.CptCode) AS concurrent_cataract_PostOp_code
    FROM #final_cohort f
    JOIN #all_cataract_expanded ac
        ON f.PatientDurableKey = ac.PatientDurableKey
       AND f.Laterality = ac.Laterality
       AND f.PostOp_date = ac.DateValue
    GROUP BY f.PatientDurableKey, f.Laterality, ac.DateValue
)
SELECT
    f.*,
    g.concurrent_cataract_gonio_date,
    g.concurrent_cataract_gonio_code,
    c.concurrent_cataract_PostOp_date,
    c.concurrent_cataract_PostOp_code
INTO #final_cohort_cataract
FROM #final_cohort f
LEFT JOIN concurrent_cataract_gonio g
    ON f.PatientDurableKey = g.PatientDurableKey AND g.Laterality = f.Laterality
LEFT JOIN concurrent_cataract_PostOp c
    ON f.PatientDurableKey = c.PatientDurableKey AND c.Laterality = f.Laterality;



DROP TABLE IF EXISTS #MedKeys;

WITH all_AP AS (
    SELECT DISTINCT
        MedicationKey, PharmaceuticalClass, SimpleGenericName, TherapeuticClass, 'Antiplatelet' AS Class
    FROM MedicationDim
    WHERE TherapeuticClass LIKE N'%Antiplatelet%'
      AND (
          SimpleGenericName LIKE '%Aspirin%'
          OR SimpleGenericName LIKE '%clopidogrel%'
          OR SimpleGenericName LIKE '%Ticagrelor%'
          OR SimpleGenericName LIKE '%prasugrel%'
      )
),
all_AC AS (
    SELECT DISTINCT
        MedicationKey, PharmaceuticalClass, SimpleGenericName, TherapeuticClass, 'Anticoagulant' AS Class
    FROM MedicationDim
    WHERE TherapeuticClass LIKE N'%anticoagulant%'
      AND (
          SimpleGenericName LIKE '%warfarin%'
          OR SimpleGenericName LIKE '%Apixaban%'
          OR SimpleGenericName LIKE '%Enoxaparin%'
          OR SimpleGenericName LIKE '%Dabigatran%'
          OR SimpleGenericName LIKE '%Rivaroxaban%'
          OR SimpleGenericName LIKE '%edoxaban%'
          OR SimpleGenericName LIKE '%dalteparin%'
          OR SimpleGenericName LIKE '%fondaparinux%'
          OR SimpleGenericName LIKE '%argatroban%'
          OR SimpleGenericName LIKE '%bivalirudin%'
          OR SimpleGenericName LIKE '%desirudin%'
      )
),
combined AS (
    SELECT * FROM all_AP
    UNION ALL
    SELECT * FROM all_AC
)
SELECT DISTINCT *
INTO #MedKeys
FROM combined;

DROP TABLE IF EXISTS #Meds;

WITH OuterOrders AS (
    SELECT
        orders.MedicationKey,
        orders.PatientDurableKey,
        startDateInfo.DateValue AS StartDate,
        meds.Class,
        1 AS HasDiagnosis
    FROM (
        SELECT PatientDurableKey, MIN(proc_date) AS proc_date
        FROM #final_cohort_cataract
        GROUP BY PatientDurableKey
    ) pt
    JOIN MedicationOrderFact orders
        ON orders.PatientDurableKey = pt.PatientDurableKey
    INNER JOIN #MedKeys meds
        ON orders.MedicationKey = meds.MedicationKey
    INNER JOIN DateDim startDateInfo
        ON startDateInfo.DateKey = orders.StartDateKey
       AND orders.StartDateKey > 0
    WHERE startDateInfo.DateValue < pt.proc_date
)
SELECT
    PatientDurableKey,
    MAX(CASE WHEN Class = 'Antiplatelet' THEN StartDate ELSE NULL END) AS antiplatelet_date,
    MAX(CASE WHEN Class = 'Anticoagulant' THEN StartDate ELSE NULL END) AS anticoagulant_date,
    MAX(CASE WHEN Class = 'Antiplatelet' THEN 1 ELSE 0 END) AS Had_Antiplatelet,
    MAX(CASE WHEN Class = 'Anticoagulant' THEN 1 ELSE 0 END) AS Had_Anticoagulant
INTO #Meds
FROM OuterOrders
GROUP BY PatientDurableKey;

DROP TABLE IF EXISTS #LastEncounters_opt;

WITH allenc AS (
    SELECT
        ef.PatientDurableKey,
        pt.proc_date AS index_date,
        ef.EncounterKey,
        dd.Years,
        dt.DateValue,
        ef.[Type],
        dept.DepartmentSpecialty
    FROM (
        SELECT PatientDurableKey, MAX(proc_date) AS proc_date
        FROM #final_cohort_cataract
        GROUP BY PatientDurableKey
    ) pt
    LEFT JOIN EncounterFact ef
        ON ef.PatientDurableKey = pt.PatientDurableKey
    INNER JOIN DepartmentDim dept
        ON ef.DepartmentKey = dept.DepartmentKey
    LEFT JOIN DateDim dt
        ON dt.DateKey = ef.DateKey
    LEFT JOIN DurationDim dd
        ON dd.DurationKey = ef.AgeKey
    WHERE dt.DateValue > pt.proc_date
      AND ef.[Type] IN (
          'Follow-Up', 'Results Follow-Up', 'Office Visit', 'Procedure visit', 'Ophth Exam', 'Consult',
          'Hospital Encounter', 'Outside Procedure', 'Prep for Procedure', 'Case Management', 'Surgery',
          'Allied Health', 'Walk-In', 'Patient Care Review', 'Nurse Triage', 'Appointment', 'Pre-op/Pre-procedure Orders',
          'Treatment', 'Pre-Admission Testing'
      )
      AND (dept.DepartmentSpecialty LIKE N'%ophth%' OR dept.DepartmentSpecialty LIKE N'%optom%')
),
lastdates AS (
    SELECT
        PatientDurableKey,
        index_date,
        MAX(DateValue) AS LastEncounterDate,
        COUNT(DISTINCT DateValue) AS EncounterCountAfter
    FROM allenc
    GROUP BY PatientDurableKey, index_date
)
SELECT
    PatientDurableKey,
    index_date,
    LastEncounterDate,
    EncounterCountAfter,
    DATEDIFF(MONTH, index_date, LastEncounterDate) AS FU_Month
INTO #LastEncounters_opt
FROM lastdates;

-- Build combined table
DROP TABLE IF EXISTS #final_cohort_cataract_meds;

SELECT DISTINCT
    p.*,
    g.glaucoma_type,
    g.severity,
    m.anticoagulant_date,
    m.antiplatelet_date,
    m.Had_Anticoagulant,
    m.Had_Antiplatelet,
    l.LastEncounterDate,
    l.EncounterCountAfter,
    l.FU_Month
INTO #final_cohort_cataract_meds
FROM #final_cohort_cataract p
LEFT JOIN (SELECT DISTINCT [Value], glaucoma_type, severity FROM #Glaucoma) g
    ON g.[Value] = p.dx_icd
LEFT JOIN #Meds m
    ON m.PatientDurableKey = p.PatientDurableKey
LEFT JOIN #LastEncounters_opt l
    ON l.PatientDurableKey = p.PatientDurableKey;

-- Filter for valid demographics and adequate follow-up
DROP TABLE IF EXISTS #final_cohort_cataract_meds_filtered;

SELECT va.*
INTO #final_cohort_cataract_meds_filtered
FROM #final_cohort_cataract_meds va
JOIN PatientDim pt
    ON va.PatientDurableKey = pt.DurableKey
WHERE pt.Sex NOT IN ('Unknown', 'Masked', 'Unspecified', 'Other')
  AND pt.Ethnicity NOT IN ('Unknown', 'Masked', 'Unspecified')
  AND NULLIF(pt.FirstRace, '') IS NOT NULL
  AND NULLIF(pt.Sex, '') IS NOT NULL
  AND NULLIF(pt.Ethnicity, '') IS NOT NULL
  AND ((PostOp_date IS NULL AND FU_Month > 3) OR (PostOp_date IS NOT NULL AND PostOp_iop IS NOT NULL));

INSERT INTO PROJECTS.ProjectD41FDE6.dbo.Final_cohort
SELECT * FROM #final_cohort_cataract_meds_filtered;



DROP TABLE IF EXISTS #cohort;
SELECT * INTO #cohort
FROM PROJECTS.ProjectD41FDE6.dbo.Final_cohort
WHERE PostOp_date IS NOT NULL;

-- 1. High IOP Failure (> 21 mmHg on consecutive visits)
DROP TABLE IF EXISTS #iop_fail_high;

WITH all_iop AS (
    SELECT
        dx.PatientDurableKey,
        dt.DateValue AS result_date,
        CASE
            WHEN eyef.Laterality IN ('Right Eye') THEN 'RT'
            WHEN eyef.Laterality IN ('Left Eye') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality,
        AVG(eyef.IntraocularPressure) AS daily_mean_iop
    FROM (SELECT PatientDurableKey FROM #cohort) dx
    LEFT JOIN EyeExamTestFact eyef ON eyef.PatientDurableKey = dx.PatientDurableKey
    LEFT JOIN DateDim dt ON dt.DateKey = eyef.EncounterStartDateKey
    WHERE eyef.ExamType = N'IOP: Tonometry'
      AND eyef.IntraocularPressure IS NOT NULL
      AND eyef.Count = 1
    GROUP BY dx.PatientDurableKey, eyef.Laterality, dt.DateValue
),
iop_after_sx AS (
    SELECT
        pt.PatientDurableKey, pt.Laterality, pt.PostOp_date AS PostOp_treatment_date,
        iop.result_date,
        iop.daily_mean_iop,
        LAG(iop.daily_mean_iop) OVER (
            PARTITION BY pt.PatientDurableKey, pt.Laterality
            ORDER BY iop.result_date
        ) AS prev_iop_value
    FROM #cohort pt
    LEFT JOIN all_iop iop
        ON pt.PatientDurableKey = iop.PatientDurableKey
       AND pt.Laterality = iop.Laterality
    WHERE iop.result_date > DATEADD(DAY, 90, pt.PostOp_date)
),
high_iop_failures AS (
    SELECT *,
        CASE
            WHEN daily_mean_iop > 21 AND prev_iop_value > 21 THEN 1
            ELSE 0
        END AS high_iop_failure
    FROM iop_after_sx
),
ranked AS (
    SELECT
        PatientDurableKey,
        Laterality,
        PostOp_treatment_date,
        result_date,
        daily_mean_iop,
        high_iop_failure,
        DATEDIFF(DAY, PostOp_treatment_date, result_date) AS high_iop_failure_days,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY result_date
        ) AS rank
    FROM high_iop_failures
    WHERE high_iop_failure = 1
)
SELECT *
INTO #iop_fail_high
FROM ranked
WHERE rank = 1;

-- 2. Low IOP Failure (< 6 mmHg on consecutive visits)
DROP TABLE IF EXISTS #iop_fail_low;

WITH all_iop AS (
    SELECT
        dx.PatientDurableKey,
        dt.DateValue AS result_date,
        CASE
            WHEN eyef.Laterality IN ('Right Eye') THEN 'RT'
            WHEN eyef.Laterality IN ('Left Eye') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality,
        AVG(eyef.IntraocularPressure) AS daily_mean_iop
    FROM (SELECT PatientDurableKey FROM #cohort) dx
    LEFT JOIN EyeExamTestFact eyef ON eyef.PatientDurableKey = dx.PatientDurableKey
    LEFT JOIN DateDim dt ON dt.DateKey = eyef.EncounterStartDateKey
    WHERE eyef.ExamType = N'IOP: Tonometry'
      AND eyef.IntraocularPressure IS NOT NULL
      AND eyef.Count = 1
    GROUP BY dx.PatientDurableKey, eyef.Laterality, dt.DateValue
),
iop_after_sx AS (
    SELECT
        pt.PatientDurableKey, pt.Laterality, pt.PostOp_date AS PostOp_treatment_date,
        iop.result_date,
        iop.daily_mean_iop,
        LAG(iop.daily_mean_iop) OVER (
            PARTITION BY pt.PatientDurableKey, pt.Laterality
            ORDER BY iop.result_date
        ) AS prev_iop_value
    FROM #cohort pt
    LEFT JOIN all_iop iop
        ON pt.PatientDurableKey = iop.PatientDurableKey
       AND pt.Laterality = iop.Laterality
    WHERE iop.result_date > DATEADD(DAY, 90, pt.PostOp_date)
),
iop_failures AS (
    SELECT *,
        CASE
            WHEN daily_mean_iop < 6 AND prev_iop_value < 6 THEN 1
            ELSE 0
        END AS low_iop_failure
    FROM iop_after_sx
),
ranked AS (
    SELECT
        PatientDurableKey,
        Laterality,
        PostOp_treatment_date,
        result_date,
        daily_mean_iop,
        low_iop_failure,
        DATEDIFF(DAY, PostOp_treatment_date, result_date) AS low_iop_failure_days,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY result_date
        ) AS rank
    FROM iop_failures
    WHERE low_iop_failure = 1
)
SELECT *
INTO #iop_fail_low
FROM ranked
WHERE rank = 1;

-- 3. Insufficient IOP Reduction (< 20% reduction)
DROP TABLE IF EXISTS #iop_fail_reduction;

WITH all_iop AS (
    SELECT
        dx.PatientDurableKey,
        dt.DateValue AS result_date,
        CASE
            WHEN eyef.Laterality IN ('Right Eye') THEN 'RT'
            WHEN eyef.Laterality IN ('Left Eye') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality,
        AVG(eyef.IntraocularPressure) AS daily_mean_iop
    FROM (SELECT PatientDurableKey FROM #cohort) dx
    LEFT JOIN EyeExamTestFact eyef ON eyef.PatientDurableKey = dx.PatientDurableKey
    LEFT JOIN DateDim dt ON dt.DateKey = eyef.EncounterStartDateKey
    WHERE eyef.ExamType = N'IOP: Tonometry'
      AND eyef.IntraocularPressure IS NOT NULL
      AND eyef.Count = 1
    GROUP BY dx.PatientDurableKey, eyef.Laterality, dt.DateValue
),
iop_after_sx AS (
    SELECT
        pt.PatientDurableKey, pt.Laterality, pt.PostOp_date AS PostOp_treatment_date,
        iop.result_date,
        iop.daily_mean_iop,
        DATEDIFF(DAY, pt.PostOp_date, iop.result_date) AS failure_days,
        ((pt.PostOp_iop - iop.daily_mean_iop) * 1.0) / NULLIF(pt.PostOp_iop, 0) AS reduction
    FROM #cohort pt
    LEFT JOIN all_iop iop
        ON pt.PatientDurableKey = iop.PatientDurableKey
       AND pt.Laterality = iop.Laterality
    WHERE iop.result_date > DATEADD(DAY, 90, pt.PostOp_date)
      AND ((pt.PostOp_iop - iop.daily_mean_iop) * 1.0) / NULLIF(pt.PostOp_iop, 0) < 0.20
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY result_date
        ) AS rank
    FROM iop_after_sx
)
SELECT *
INTO #iop_fail_reduction
FROM ranked
WHERE rank = 1;

-- 4. Visual Acuity Loss (NLP - No Light Perception)
DROP TABLE IF EXISTS #va_fail_nlp;

WITH all_VA AS (
    SELECT
        dx.PatientDurableKey,
        dt.DateValue AS result_date,
        CASE
            WHEN eyef.Laterality IN ('Right Eye') THEN 'RT'
            WHEN eyef.Laterality IN ('Left Eye') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality,
        MAX(eyef.DistanceVisualAcuity) AS DistanceVisualAcuity
    FROM (SELECT PatientDurableKey FROM #cohort) dx
    LEFT JOIN EyeExamTestFact eyef ON eyef.PatientDurableKey = dx.PatientDurableKey
    LEFT JOIN DateDim dt ON dt.DateKey = eyef.EncounterStartDateKey
    WHERE eyef.DistanceVisualAcuity IS NOT NULL
      AND eyef.Count = 1
      AND eyef.ExamType = N'VA: Visual Acuity'
      AND eyef.EncounterStartDateKey > 0
    GROUP BY dx.PatientDurableKey, eyef.Laterality, dt.DateValue
),
va_matches AS (
    SELECT
        va.PatientDurableKey,
        va.Laterality,
        va.result_date,
        va.DistanceVisualAcuity AS result_value,
        pt.PostOp_date,
        LAG(va.DistanceVisualAcuity) OVER (
            PARTITION BY va.PatientDurableKey, va.Laterality
            ORDER BY va.result_date
        ) AS prev_va_value
    FROM all_VA va
    JOIN #cohort pt
        ON pt.PatientDurableKey = va.PatientDurableKey
       AND pt.Laterality = va.Laterality
       AND va.result_date > pt.PostOp_date
),
NLP_failures AS (
    SELECT *,
        CASE
            WHEN result_value = 'NLP' AND prev_va_value = 'NLP' THEN 1
            ELSE 0
        END AS nlp_failure
    FROM va_matches
),
ranked AS (
    SELECT
        PatientDurableKey,
        Laterality,
        PostOp_date,
        result_date AS failure_date,
        result_value,
        DATEDIFF(DAY, PostOp_date, result_date) AS failure_days,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY result_date
        ) AS rank
    FROM NLP_failures
    WHERE nlp_failure = 1
)
SELECT *
INTO #va_fail_nlp
FROM ranked
WHERE rank = 1;

-- 5. Reoperation Failure
DROP TABLE IF EXISTS #reop_fail;

WITH main_proc AS (
    SELECT DISTINCT
        procevent.PatientDurableKey,
        procevent.[Type] AS proc_type,
        dd.Years,
        procevent.EncounterKey,
        dated.DateValue,
        procdim.CptCode,
        CASE
            WHEN procdim.CptCode IN ('66179', '66180') THEN 'Aqueous Shunt'
            WHEN procdim.CptCode IN ('66170', '66172') THEN 'Trabeculectomy'
            WHEN procdim.CptCode IN ('66710', '66711', '66987', '66988') THEN 'Cyclophotocoagulation'
            WHEN procdim.CptCode IN ('0449T', '0450T', '66183') THEN 'Xen implantation'
            ELSE 'Revision surgery'
        END AS reoperation_grp,
        x.Modifier AS Laterality
    FROM (SELECT DISTINCT PatientDurableKey FROM #cohort) pt
    INNER JOIN ProcedureEventFact procevent ON pt.PatientDurableKey = procevent.PatientDurableKey
    INNER JOIN ProcedureDim procdim ON procevent.ProcedureDurableKey = procdim.DurableKey
    LEFT JOIN DurationDim dd ON procevent.AgeAtProcedureDateKey = dd.DurationKey
    LEFT JOIN DateDim dated ON dated.DateKey = procevent.ProcedureStartDateKey
    CROSS APPLY (
        SELECT TOP 1 val AS Modifier, src AS ModifierSource
        FROM (VALUES
            (procevent.FirstModifier, 'FirstModifier'),
            (procevent.SecondModifier, 'SecondModifier'),
            (procevent.ThirdModifier, 'ThirdModifier'),
            (procevent.FourthModifier, 'FourthModifier')
        ) AS Modifiers(val, src)
        WHERE val IN ('RT', 'LT', '50')
    ) AS x
    WHERE procevent.Count > 0
      AND procevent.ProcedureStartDateKey > 0
      AND dd.Years >= 18
      AND procdim.CptCode IN (
          '66179', '66180', '66183', '66170', '66172',
          '66710', '66711', '66987', '66988', '66250', '0449T', '0450T'
      )
      AND procevent.[Type] IN ('PB Charge Procedure', 'Charge Procedure', 'Coded Procedure', 'External Charge Procedure')
),
ExpandedProcedures AS (
    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.reoperation_grp, p.Years, p.proc_type, 'RT' AS Laterality
    FROM main_proc p WHERE p.Laterality = '50'

    UNION ALL

    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.reoperation_grp, p.Years, p.proc_type, 'LT' AS Laterality
    FROM main_proc p WHERE p.Laterality = '50'

    UNION ALL

    SELECT p.PatientDurableKey, p.EncounterKey, p.DateValue, p.CptCode, p.reoperation_grp, p.Years, p.proc_type, p.Laterality
    FROM main_proc p WHERE p.Laterality <> '50'
),
reop_after_sx AS (
    SELECT
        pt.PatientDurableKey,
        pt.Laterality,
        pt.PostOp_date,
        ex.DateValue AS failure_date,
        ex.CptCode AS failure_code,
        ex.reoperation_grp
    FROM (SELECT DISTINCT PatientDurableKey, Laterality, PostOp_date FROM #cohort) pt
    JOIN ExpandedProcedures ex
        ON pt.PatientDurableKey = ex.PatientDurableKey
       AND pt.Laterality = ex.Laterality
    WHERE ex.DateValue > pt.PostOp_date
),
ranked AS (
    SELECT *,
        DATEDIFF(DAY, PostOp_date, failure_date) AS failure_days,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality, reoperation_grp
            ORDER BY failure_date
        ) AS rank_grp,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY failure_date
        ) AS rank
    FROM reop_after_sx
)
SELECT *
INTO #reop_fail
FROM ranked
WHERE rank_grp = 1;

DROP TABLE IF EXISTS #reop_fail_r;

SELECT
    PatientDurableKey,
    Laterality,
    failure_date AS reop_failure_date,
    failure_code AS reop_failure_code,
    reoperation_grp,
    failure_days AS reop_failure_days,
    rank_grp AS reop_rank_grp,
    rank AS reop_rank
INTO #reop_fail_r
FROM #reop_fail;

-- Combine All Failure Modes
DROP TABLE IF EXISTS #final_failures;

SELECT
    f.*,
    h.high_iop_failure_days,
    l.low_iop_failure_days,
    r.failure_days AS reduction_failure_days,
    n.failure_days AS nlp_failure_days,
    reop.reoperation_grp,
    reop.reop_failure_code,
    reop.reop_failure_days
INTO #final_failures
FROM (SELECT DISTINCT PatientDurableKey, Laterality FROM #cohort) f
LEFT JOIN #iop_fail_high h ON h.PatientDurableKey = f.PatientDurableKey AND h.Laterality = f.Laterality
LEFT JOIN #iop_fail_low l ON l.PatientDurableKey = f.PatientDurableKey AND l.Laterality = f.Laterality
LEFT JOIN #iop_fail_reduction r ON r.PatientDurableKey = f.PatientDurableKey AND r.Laterality = f.Laterality
LEFT JOIN #va_fail_nlp n ON n.PatientDurableKey = f.PatientDurableKey AND n.Laterality = f.Laterality
LEFT JOIN #reop_fail_r reop ON reop.PatientDurableKey = f.PatientDurableKey AND reop.Laterality = f.Laterality;



DROP TABLE IF EXISTS #PatientDemo;

SELECT
    pt.PatientDurableKey,
    BirthDate, Sex, MaritalStatus, PreferredLanguage, Ethnicity,
    FirstRace, SecondRace, ThirdRace, FourthRace, FifthRace, MultiRacial,
    Country, StateOrProvince, StateOrProvinceAbbreviation, SourceCountry_X,
    PostalCodeKey,
    SviOverallPctlRankingByZip2018_X AS [svi_overall],
    SviHouseholdCompositionPct1RankingByZip2018_X AS [svi_house],
    SviHousingTypeTransportationPct1RankingByZip2018_X AS [svi_transport],
    SviMinorityStatusLanguagePctRankingByZip2018_X AS [svi_minority],
    SviSocioeconomicPct1RankingByZip2018_X AS [svi_ses],
    SviOverallPctlRankByZip2020_X AS [svi_overall_2020],
    SviSocioeconomicPct1RankByZip2020_X AS [svi_ses_2020],
    SviHouseholdCharacteristicsPctlRankByZip2020_X AS [svi_house_2020],
    SviRacialEthnicMinorityStatusPct1RankByZip2020_X AS [svi_minority_2020],
    SviHousingTypeTransportationPct1RankByZip2020_X AS [svi_transport_2020],
    PrimaryRUCA_X AS [ruca]
INTO #PatientDemo
FROM (SELECT DISTINCT PatientDurableKey FROM PROJECTS.ProjectD41FDE6.dbo.Final_cohort) pt
JOIN PatientDim ON pt.PatientDurableKey = PatientDim.DurableKey;

-- Rapid Reoperations
DROP TABLE IF EXISTS #rapid_reop_eyes;

SELECT *
INTO #rapid_reop_eyes
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY Sx_PostOpSX_days ASC
        ) AS rn
    FROM PROJECTS.ProjectD41FDE6.dbo.Final_cohort
    WHERE PostOp_date IS NOT NULL
) pt
WHERE rn = 1;

DROP TABLE IF EXISTS #allDX_Hyphema;

WITH alldx AS (
    SELECT
        diagEvt.DiagnosisEventKey,
        diagEvt.PatientDurableKey,
        age.Years AS DxAge,
        diagStartDate.DateValue AS DxDate,
        diags.[Value],
        diags.DisplayString,
        diags.Laterality
    FROM (SELECT PatientDurableKey FROM #rapid_reop_eyes) pt
    INNER JOIN DiagnosisEventFact diagEvt ON pt.PatientDurableKey = diagEvt.PatientDurableKey
    INNER JOIN (
        SELECT DISTINCT
            DiagnosisKey, [Value], DisplayString,
            CASE
                WHEN DisplayString LIKE '%right eye%' THEN 'Right'
                WHEN DisplayString LIKE '%left eye%' THEN 'Left'
                WHEN DisplayString LIKE '%bilateral%' THEN 'Bilateral'
                WHEN DisplayString LIKE '%unspecified eye%' THEN 'Unspecified'
                ELSE 'Unspecified'
            END AS Laterality
        FROM DiagnosisTerminologyDim
        WHERE [Type] = N'ICD-10-CM'
          AND [Value] LIKE N'H21.0%'
    ) diags ON diagEvt.DiagnosisKey = diags.DiagnosisKey
    INNER JOIN DurationDim age ON diagEvt.AgeKey = age.DurationKey
    INNER JOIN DateDim diagStartDate ON diagStartDate.DateKey = diagEvt.StartDateKey
    WHERE diagEvt.[Type] <> 'Problem List'
),
expanded_DX AS (
    SELECT DiagnosisEventKey, PatientDurableKey, 'RT' AS Laterality, DxDate, DxAge, [Value], DisplayString
    FROM alldx WHERE Laterality = 'Bilateral'

    UNION ALL

    SELECT DiagnosisEventKey, PatientDurableKey, 'LT' AS Laterality, DxDate, DxAge, [Value], DisplayString
    FROM alldx WHERE Laterality = 'Bilateral'

    UNION ALL

    SELECT DiagnosisEventKey, PatientDurableKey,
        CASE
            WHEN Laterality IN ('Right') THEN 'RT'
            WHEN Laterality IN ('Left') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality,
        DxDate, DxAge, [Value], DisplayString
    FROM alldx WHERE Laterality <> 'Bilateral' AND Laterality <> 'Unspecified'
)
SELECT * INTO #allDX_Hyphema FROM expanded_DX;

-- Deduplicate Hyphema diagnoses on same day
DROP TABLE IF EXISTS #rapid_reop_eyes_hyphema;

WITH specified AS (
    SELECT DISTINCT PatientDurableKey, Laterality, DxDate, [Value], DisplayString
    FROM #allDX_Hyphema WHERE Laterality <> 'Unspecified'
),
unspecified AS (
    SELECT DISTINCT PatientDurableKey, Laterality, DxDate, [Value], DisplayString
    FROM #allDX_Hyphema WHERE Laterality = 'Unspecified'
),
unspec_with_spec_same_day AS (
    SELECT u.PatientDurableKey, u.DxDate
    FROM unspecified u
    JOIN specified s ON s.PatientDurableKey = u.PatientDurableKey AND s.DxDate = u.DxDate
    GROUP BY u.PatientDurableKey, u.DxDate
),
kept_unspecified AS (
    SELECT u.*
    FROM unspecified u
    LEFT JOIN unspec_with_spec_same_day dropme
        ON dropme.PatientDurableKey = u.PatientDurableKey AND dropme.DxDate = u.DxDate
    WHERE dropme.PatientDurableKey IS NULL
),
all_kept AS (
    SELECT * FROM specified
    UNION ALL
    SELECT * FROM kept_unspecified
),
join_all AS (
    SELECT
        e.*, k.DxDate, k.[Value], k.DisplayString,
        k.Laterality AS hyphema_laterality_code,
        ABS(DATEDIFF(DAY, e.PostOp_date, k.DxDate)) AS days_to_dx,
        ROW_NUMBER() OVER (
            PARTITION BY e.PatientDurableKey, e.Laterality
            ORDER BY ABS(DATEDIFF(DAY, e.PostOp_date, k.DxDate))
        ) AS rn
    FROM (
        SELECT PatientDurableKey, Laterality, proc_date, PostOp_date, PostOp_cpt, PostOP_treatment
        FROM #rapid_reop_eyes
    ) e
    JOIN all_kept k ON k.PatientDurableKey = e.PatientDurableKey
    WHERE (k.Laterality = e.Laterality OR k.Laterality = 'Unspecified')
      AND (k.DxDate BETWEEN e.proc_date AND e.PostOp_date)
)
SELECT
    PatientDurableKey, Laterality, DxDate,
    [Value] AS dx_icd, DisplayString, hyphema_laterality_code, days_to_dx
INTO #rapid_reop_eyes_hyphema
FROM join_all
WHERE rn = 1;

-- Export to permanent tables
INSERT INTO PROJECTS.ProjectD41FDE6.dbo.Failures
SELECT * FROM #final_failures;

INSERT INTO PROJECTS.ProjectD41FDE6.dbo.PatientDemo
SELECT * FROM #PatientDemo;

INSERT INTO PROJECTS.ProjectD41FDE6.dbo.rapid_reop_eyes_hyphema
SELECT * FROM #rapid_reop_eyes_hyphema;



USE COSMOS;

DROP TABLE IF EXISTS #reduced_pts;

SELECT va.*
INTO #reduced_pts
FROM PROJECTS.ProjectD41FDE6.dbo.Final_cohort va
JOIN PROJECTS.ProjectD41FDE6.dbo.PatientDemo pt ON va.PatientDurableKey = pt.PatientDurableKey
WHERE pt.Sex NOT IN ('Unknown', 'Masked', 'Unspecified', 'Other')
  AND pt.Ethnicity NOT IN ('Unknown', 'Masked', 'Unspecified')
  AND NULLIF(pt.FirstRace, '') IS NOT NULL
  AND NULLIF(pt.Sex, '') IS NOT NULL
  AND NULLIF(pt.Ethnicity, '') IS NOT NULL
  AND ((PostOp_date IS NULL AND FU_Month > 3) OR (PostOp_date IS NOT NULL AND PostOp_iop IS NOT NULL));

DROP TABLE IF EXISTS #Baseline_IOP;

WITH all_iop AS (
    SELECT
        dx.PatientDurableKey, dt.DateValue AS [Date],
        eyef.IntraocularPressure, eyef.TonometryMethod,
        CASE
            WHEN Laterality IN ('Right Eye') THEN 'RT'
            WHEN Laterality IN ('Left Eye') THEN 'LT'
            ELSE 'Unspecified'
        END AS Laterality
    FROM (SELECT DISTINCT PatientDurableKey FROM #reduced_pts) dx
    LEFT JOIN EyeExamTestFact eyef ON eyef.PatientDurableKey = dx.PatientDurableKey
    LEFT JOIN DateDim dt ON dt.DateKey = eyef.EncounterStartDateKey
    WHERE eyef.ExamType = N'IOP: Tonometry'
      AND eyef.IntraocularPressure IS NOT NULL
      AND eyef.Count = 1
),
ranked AS (
    SELECT
        p.PatientDurableKey, p.Laterality,
        iop.[Date] AS baseline_iop_date,
        iop.IntraocularPressure AS baseline_iop,
        DATEDIFF(DAY, p.proc_date, iop.[Date]) AS interval_sx_iop,
        ROW_NUMBER() OVER (
            PARTITION BY p.PatientDurableKey, p.Laterality
            ORDER BY ABS(DATEDIFF(DAY, p.proc_date, iop.[Date])) ASC
        ) AS Closest_IOP_rank
    FROM #reduced_pts p
    LEFT JOIN all_iop iop
        ON iop.PatientDurableKey = p.PatientDurableKey
       AND iop.Laterality = p.Laterality
    WHERE iop.[Date] BETWEEN DATEADD(DAY, -90, p.proc_date) AND p.proc_date
)
SELECT *
INTO #Baseline_IOP
FROM ranked
WHERE Closest_IOP_rank = 1;

DROP TABLE IF EXISTS #med_exposure_patient;

WITH patient_index AS (
    SELECT PatientDurableKey, MIN(proc_date) AS index_sx_date
    FROM #reduced_pts
    GROUP BY PatientDurableKey
),
meds_joined AS (
    SELECT
        p.PatientDurableKey,
        p.index_sx_date,
        meds.Class AS grp,
        CASE WHEN orders.StartDateKey > 0 THEN d_start.DateValue ELSE NULL END AS start_date,
        CASE WHEN orders.EndDateKey > 0 THEN d_end.DateValue ELSE NULL END AS raw_stop_date
    FROM patient_index p
    JOIN MedicationOrderFact orders ON orders.PatientDurableKey = p.PatientDurableKey
    JOIN #MedKeys meds ON orders.MedicationKey = meds.MedicationKey
    LEFT JOIN DateDim d_start ON d_start.DateKey = orders.StartDateKey AND orders.StartDateKey > 0
    LEFT JOIN DateDim d_end ON d_end.DateKey = orders.EndDateKey AND orders.EndDateKey > 0
),
meds_clean AS (
    SELECT *,
        CASE
            WHEN raw_stop_date IS NOT NULL
                 AND start_date IS NOT NULL
                 AND raw_stop_date > start_date
            THEN raw_stop_date
            ELSE NULL
        END AS stop_date
    FROM meds_joined
),
meds_timeline AS (
    SELECT
        PatientDurableKey, grp, index_sx_date,
        /* anchors BEFORE surgery */
        MAX(CASE WHEN start_date < index_sx_date THEN start_date END) AS first_start_pre,
        MAX(CASE WHEN stop_date < index_sx_date THEN stop_date END) AS last_stop_pre,
        /* anchors AFTER surgery */
        MIN(CASE WHEN start_date >= index_sx_date THEN start_date END) AS first_start_post,
        MIN(CASE WHEN stop_date >= index_sx_date THEN stop_date END) AS first_stop_post,
        /* presence flags */
        MAX(CASE WHEN start_date IS NOT NULL THEN 1 ELSE 0 END) AS has_any_start,
        MAX(CASE WHEN stop_date IS NOT NULL THEN 1 ELSE 0 END) AS has_any_stop
    FROM meds_clean
    GROUP BY PatientDurableKey, grp, index_sx_date
),
meds_exposure AS (
    SELECT
        PatientDurableKey, grp, index_sx_date,
        CASE
            /* Truly indefinite: 0 start dates AND NO stop dates anywhere */
            WHEN has_any_start = 0 AND has_any_stop = 0 THEN 1
            /* Started before surgery, ongoing (no stop before surgery) */
            WHEN first_start_pre IS NOT NULL AND last_stop_pre IS NULL THEN 1
            /* Started before surgery, stopped after surgery */
            WHEN first_start_pre IS NOT NULL AND first_stop_post IS NOT NULL THEN 1
            ELSE 0
        END AS active_at_surgery,
        /* audit fields */
        first_start_pre AS start_date_used,
        first_stop_post AS stop_date_used
    FROM meds_timeline
)
SELECT *
INTO #med_exposure_patient
FROM meds_exposure;

DROP TABLE IF EXISTS #med_exposure_flags;

SELECT
    PatientDurableKey,
    /* Primary exposure flags */
    MAX(CASE WHEN grp = 'Antiplatelet' AND active_at_surgery = 1 THEN 1 ELSE 0 END) AS Had_Antiplatelet,
    MAX(CASE WHEN grp = 'Anticoagulant' AND active_at_surgery = 1 THEN 1 ELSE 0 END) AS Had_Anticoagulant,
    /* Useful derived flag */
    MAX(CASE WHEN active_at_surgery = 1 THEN 1 ELSE 0 END) AS Had_Any_Antithrombotic
INTO #med_exposure_flags
FROM #med_exposure_patient
GROUP BY PatientDurableKey;

-- Final output writes
INSERT INTO PROJECTS.ProjectD41FDE6.dbo.baseline_IOP
SELECT
    PatientDurableKey,
    Laterality,
    baseline_iop_date,
    baseline_iop,
    interval_sx_iop
FROM #Baseline_IOP;

INSERT INTO PROJECTS.ProjectD41FDE6.dbo.med_exposure_flags
SELECT * FROM #med_exposure_flags;