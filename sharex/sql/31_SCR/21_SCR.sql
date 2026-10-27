USE COSMOS;

-- Clean retinopathy diagnoses
DROP TABLE IF EXISTS #SC_retin;
SELECT DISTINCT
    DiagnosisKey,
    TerminologyConceptKey,
    [Value],
    DisplayString,
    dd.Name AS NameAndCode,
    GroupedNameAndCode,
    CASE
        WHEN DisplayString LIKE '%right eye%' THEN 'RT'
        WHEN DisplayString LIKE '%left eye%' THEN 'LT'
        WHEN DisplayString LIKE '%bilateral%' THEN '50'
        WHEN DisplayString LIKE '%unspecified eye%' THEN 'Unspecified'
        ELSE '999' -- Code for cases with no laterality info
    END AS Laterality
INTO #SC_retin
FROM DiagnosisTerminologyDim
-- LEFT JOIN DiagnosisDim dd ON dd.DiagnosisKey = DiagnosisTerminologyDim.DiagnosisKey
WHERE [Type] = 'ICD-10-CM'
  AND (
      (([Value] LIKE 'E10.3%' AND [Value] <> 'E10.31') AND [Value] NOT LIKE 'E10.3[6-9]%') OR
      (([Value] LIKE 'E11.3%' AND [Value] <> 'E11.31') AND [Value] NOT LIKE 'E11.3[6-9]%') OR
      [Value] LIKE 'H36.81%' OR
      [Value] LIKE 'H36.82%'
  );

DROP TABLE IF EXISTS #all_sc_pt_all_dx;
WITH alldx AS (
    SELECT
        scdx.PatientDurableKey,
        retin.Laterality,
        retin.Date_retin_dx,
        retin.Age_retin_dx,
        retin.icd_retin_dx,
        retin.DisplayString_retin_dx,
        retin.Insurance_retin_dx
    FROM PROJECTS.Project0821712.dbo.SC_pt AS scdx
    JOIN (
        SELECT
            Diagnoses2.PatientDurableKey,
            Diagnoses2.StartDateKey,
            DiagnosisDate.DateValue AS Date_retin_dx,
            age.Years AS Age_retin_dx,
            D.[Value] AS icd_retin_dx,
            D.DisplayString AS DisplayString_retin_dx,
            D.Laterality,
            ins.PrimaryCoverageFinancialClass_X AS Insurance_retin_dx,
            ROW_NUMBER() OVER (
                PARTITION BY Diagnoses2.PatientDurableKey, D.[Value]
                ORDER BY Diagnoses2.StartDateKey ASC
            ) AS RowNum_retin
        FROM DiagnosisEventFact Diagnoses2
        INNER JOIN #SC_retin D ON D.DiagnosisKey = Diagnoses2.DiagnosisKey
        LEFT JOIN EncounterFact ins ON Diagnoses2.EncounterKey = ins.EncounterKey
        LEFT JOIN DateDim DiagnosisDate ON Diagnoses2.StartDateKey = DiagnosisDate.DateKey
        LEFT JOIN DurationDim age ON Diagnoses2.AgeKey = age.DurationKey
        WHERE Diagnoses2.StartDateKey IS NOT NULL
          AND Diagnoses2.[Type] <> N'Problem List'
    ) AS retin ON scdx.PatientDurableKey = retin.PatientDurableKey
    WHERE retin.Date_retin_dx >= scdx.Date_SC_dx
)
SELECT DISTINCT *
INTO #all_sc_pt_all_dx
FROM alldx;

-- Try to reduce unspecified laterality
DROP TABLE IF EXISTS #clean_sc_retin_dx;

-- STEP 1: Normalize and add severity rank
WITH ranked_dx AS (
    SELECT
        PatientDurableKey,
        icd_retin_dx,
        LEFT(icd_retin_dx, 6) AS icd_root,
        Laterality AS original_laterality,
        Date_retin_dx,
        CASE
            WHEN icd_retin_dx = 'H36.823' THEN 7
            WHEN icd_retin_dx IN ('H36.821', 'H36.822') THEN 6
            WHEN icd_retin_dx = 'H36.829' THEN 5
            WHEN icd_retin_dx = 'H36.813' THEN 4
            WHEN icd_retin_dx IN ('H36.811', 'H36.812') THEN 3
            WHEN icd_retin_dx = 'H36.819' THEN 2
            ELSE 1
        END AS severity_rank
    FROM #all_sc_pt_all_dx
),

-- STEP 2: Keep only the most severe dx per patient date
most_severe_dx AS (
    SELECT *
    FROM (
        SELECT *,
            ROW_NUMBER() OVER (
                PARTITION BY PatientDurableKey, Date_retin_dx
                ORDER BY severity_rank DESC
            ) AS rn
        FROM ranked_dx
    ) t
    WHERE rn = 1
),

-- STEP 4: Known values for window inference
known_laterality_window AS (
    SELECT
        PatientDurableKey,
        icd_retin_dx,
        icd_root,
        Date_retin_dx,
        original_laterality
    FROM most_severe_dx
    WHERE original_laterality IN ('LT', 'RT', '50')
),

-- STEP 5: 180 day inference if consistent
window_inference AS (
    SELECT
        u.PatientDurableKey,
        u.icd_retin_dx,
        u.icd_root,
        u.Date_retin_dx,
        k.original_laterality AS inferred_laterality_window,
        ROW_NUMBER() OVER (
            PARTITION BY u.PatientDurableKey, u.Date_retin_dx
            ORDER BY ABS(DATEDIFF(DAY, u.Date_retin_dx, k.Date_retin_dx)) ASC
        ) AS rn
    FROM (SELECT * FROM most_severe_dx WHERE original_laterality = 'Unspecified') u
    LEFT JOIN (SELECT * FROM most_severe_dx WHERE original_laterality IN ('LT', 'RT', '50')) k
        ON u.PatientDurableKey = k.PatientDurableKey
       AND u.icd_retin_dx = k.icd_retin_dx
       AND u.icd_root = k.icd_root
       AND k.Date_retin_dx BETWEEN DATEADD(DAY, -90, u.Date_retin_dx) AND DATEADD(DAY, 90, u.Date_retin_dx)
    WHERE u.original_laterality = 'Unspecified'
    GROUP BY u.PatientDurableKey, u.icd_retin_dx, u.icd_root, u.Date_retin_dx, k.original_laterality, k.Date_retin_dx
    HAVING COUNT(DISTINCT k.original_laterality) = 1
),

-- STEP 6: Final result
final_output AS (
    SELECT
        m.PatientDurableKey,
        m.icd_retin_dx,
        m.icd_root,
        m.Date_retin_dx,
        m.original_laterality,
        COALESCE(w.inferred_laterality_window, m.original_laterality) AS final_laterality,
        CASE
            WHEN m.original_laterality = 'Unspecified' AND w.inferred_laterality_window IS NOT NULL THEN 1
            ELSE 0
        END AS was_inferred
    FROM most_severe_dx m
    LEFT JOIN (SELECT * FROM window_inference WHERE rn = 1) w
        ON m.PatientDurableKey = w.PatientDurableKey
       AND m.icd_retin_dx = w.icd_retin_dx
       AND m.Date_retin_dx = w.Date_retin_dx
),

-- Build patient/icd root level summary of known laterality
known_laterality_summary AS (
    SELECT
        PatientDurableKey,
        icd_root,
        MAX(CASE WHEN final_laterality = '50' THEN 1 ELSE 0 END) AS has_bilateral,
        SUM(CASE WHEN final_laterality = 'LT' THEN 1 ELSE 0 END) AS lt_count,
        SUM(CASE WHEN final_laterality = 'RT' THEN 1 ELSE 0 END) AS rt_count
    FROM final_output
    WHERE final_laterality IN ('LT', 'RT', '50')
    GROUP BY PatientDurableKey, icd_root
),

-- Merge with rows where final laterality is still "Unspecified"
final_with_fallback AS (
    SELECT
        f.*,
        k.has_bilateral,
        k.lt_count,
        k.rt_count,
        CASE
            WHEN f.final_laterality = 'Unspecified' AND k.has_bilateral = 1 THEN '50'
            WHEN f.final_laterality = 'Unspecified' AND k.rt_count > k.lt_count THEN 'RT'
            WHEN f.final_laterality = 'Unspecified' AND k.lt_count > k.rt_count THEN 'LT'
            WHEN f.final_laterality = 'Unspecified' AND k.rt_count = k.lt_count AND k.rt_count > 0 THEN 'LT' -- Arbitrary tie-break
            ELSE f.final_laterality
        END AS final_laterality_final,
        CASE
            WHEN f.final_laterality = 'Unspecified' AND (k.has_bilateral = 1 OR k.lt_count > 0 OR k.rt_count > 0) THEN 1
            ELSE f.was_inferred
        END AS was_inferred_final
    FROM final_output f
    LEFT JOIN known_laterality_summary k
        ON f.PatientDurableKey = k.PatientDurableKey
       AND f.icd_root = k.icd_root
)
SELECT
    PatientDurableKey,
    icd_retin_dx,
    icd_root,
    Date_retin_dx,
    original_laterality,
    final_laterality_final AS final_laterality,
    was_inferred_final AS was_inferred
INTO #clean_sc_retin_dx
FROM final_with_fallback;

DROP TABLE IF EXISTS #clean_sc_retin_dx_expanded;

-- Deduplicate daily insurance records
WITH Insurance_ranked AS (
    SELECT
        PatientDurableKey,
        Laterality,
        Date_retin_dx,
        icd_retin_dx,
        Age_retin_dx,
        DisplayString_retin_dx,
        Insurance_retin_dx,
        CASE
            WHEN Insurance_retin_dx IN ('Medicaid', 'Medicare') THEN 1
            WHEN Insurance_retin_dx = 'Commercial/Private' THEN 2
            WHEN Insurance_retin_dx = 'Self-Pay' THEN 3
            WHEN Insurance_retin_dx = 'Not Applicable' THEN 4
            WHEN Insurance_retin_dx = 'Masked' THEN 5
            WHEN Insurance_retin_dx = 'Unspecified' THEN 6
            ELSE 7
        END AS insurance_rank
    FROM #all_sc_pt_all_dx
),
best_insurance_per_day AS (
    SELECT *
    FROM (
        SELECT *,
            ROW_NUMBER() OVER (
                PARTITION BY PatientDurableKey, Laterality, Date_retin_dx, icd_retin_dx
                ORDER BY insurance_rank ASC
            ) AS rn
        FROM Insurance_ranked
    ) t
    WHERE rn = 1
),
final_dx AS (
    SELECT
        a.PatientDurableKey,
        a.icd_retin_dx,
        a.Date_retin_dx,
        a.original_laterality,
        a.final_laterality AS Laterality,
        a.was_inferred,
        b.Age_retin_dx,
        b.DisplayString_retin_dx,
        b.Insurance_retin_dx
    FROM #clean_sc_retin_dx a
    JOIN best_insurance_per_day b
        ON a.PatientDurableKey = b.PatientDurableKey
       AND a.original_laterality = b.Laterality
       AND a.Date_retin_dx = b.Date_retin_dx
       AND a.icd_retin_dx = b.icd_retin_dx
),
expanded_DX AS (
    -- Split bilateral ('50') into RT and LT
    SELECT
        PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx,
        DisplayString_retin_dx, Insurance_retin_dx, 'RT' AS Laterality, was_inferred
    FROM final_dx WHERE Laterality = '50'

    UNION ALL

    SELECT
        PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx,
        DisplayString_retin_dx, Insurance_retin_dx, 'LT' AS Laterality, was_inferred
    FROM final_dx WHERE Laterality = '50'

    UNION ALL

    SELECT
        PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx,
        DisplayString_retin_dx, Insurance_retin_dx, Laterality, was_inferred
    FROM final_dx p
    WHERE Laterality <> '50' AND p.Laterality <> 'Unspecified'
)
SELECT *
INTO #clean_sc_retin_dx_expanded
FROM expanded_DX;

-- Calculate follow-up durations
DROP TABLE IF EXISTS #clean_sc_retin_dx_expanded_enc;

WITH first_retin_dx AS (
    SELECT PatientDurableKey, MIN(Date_retin_dx) AS min_Date_retin_dx
    FROM #clean_sc_retin_dx_expanded
    GROUP BY PatientDurableKey
),
last_opt_enc AS (
    SELECT
        pt.PatientDurableKey,
        MAX(dt.DateValue) AS LastEncounterDate_opt,
        COUNT(dt.DateValue) AS EncounterCountAfterFirstDate_opt
    FROM first_retin_dx pt
    JOIN EncounterFact ef ON ef.PatientDurableKey = pt.PatientDurableKey
    JOIN DepartmentDim dept ON ef.DepartmentKey = dept.DepartmentKey
    JOIN DateDim dt ON dt.DateKey = ef.DateKey
    WHERE dt.DateValue > pt.min_Date_retin_dx
      AND (dept.DepartmentSpecialty LIKE N'%ophth%' OR dept.DepartmentSpecialty LIKE N'%optom%')
    GROUP BY pt.PatientDurableKey
),
all_enc AS (
    SELECT
        pt.PatientDurableKey,
        MAX(dt.DateValue) AS LastEncounterDate,
        COUNT(dt.DateValue) AS EncounterCountAfterFirstDate
    FROM first_retin_dx pt
    JOIN EncounterFact ef ON ef.PatientDurableKey = pt.PatientDurableKey
    JOIN DepartmentDim dept ON ef.DepartmentKey = dept.DepartmentKey
    JOIN DateDim dt ON dt.DateKey = ef.DateKey
    WHERE dt.DateValue > pt.min_Date_retin_dx
    GROUP BY pt.PatientDurableKey
)
SELECT
    pt.*,
    opt.EncounterCountAfterFirstDate_opt,
    opt.LastEncounterDate_opt,
    e.EncounterCountAfterFirstDate,
    e.LastEncounterDate,
    DATEDIFF(DAY, pt.Date_retin_dx, opt.LastEncounterDate_opt) AS FU_day_opt,
    DATEDIFF(DAY, pt.Date_retin_dx, e.LastEncounterDate) AS FU_day
INTO #clean_sc_retin_dx_expanded_enc
FROM #clean_sc_retin_dx_expanded pt
LEFT JOIN last_opt_enc opt ON opt.PatientDurableKey = pt.PatientDurableKey
LEFT JOIN all_enc e ON e.PatientDurableKey = pt.PatientDurableKey;

INSERT INTO PROJECTS.Project0821712.dbo.SC_retin_dx
SELECT * FROM #clean_sc_retin_dx_expanded_enc;

DROP TABLE IF EXISTS #cohort;
SELECT *
INTO #cohort
FROM PROJECTS.Project0821712.dbo.SC_retin_dx
WHERE FU_day >= 180;

DROP TABLE IF EXISTS #first_sc_retin_dx;
WITH ordered AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY Date_retin_dx ASC
        ) AS rn
    FROM #cohort
),
dup_lat_pt_ordered AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey
            ORDER BY Date_retin_dx ASC
        ) AS rn_date
    FROM ordered
    WHERE rn = 1 AND PatientDurableKey IN (
        SELECT PatientDurableKey
        FROM ordered
        WHERE rn = 1
        GROUP BY PatientDurableKey
        HAVING COUNT(*) = 2
    )
),
dup_lat_pt AS (
    SELECT *
    FROM ordered
    WHERE PatientDurableKey IN (SELECT PatientDurableKey FROM dup_lat_pt_ordered) AND rn = 1
),
imputed_unspec AS (
    SELECT PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx, DisplayString_retin_dx, Insurance_retin_dx, 'LT' AS Laterality, 1 AS was_inferred
    FROM dup_lat_pt WHERE Laterality = 'Unspecified'
    UNION ALL
    SELECT PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx, DisplayString_retin_dx, Insurance_retin_dx, 'RT' AS Laterality, 1 AS was_inferred
    FROM dup_lat_pt WHERE Laterality = 'Unspecified'
    UNION ALL
    SELECT PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx, DisplayString_retin_dx, Insurance_retin_dx, Laterality, was_inferred
    FROM dup_lat_pt WHERE Laterality <> 'Unspecified'
),
ranked_imputed AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY Date_retin_dx ASC
        ) AS rn
    FROM imputed_unspec
),
final AS (
    SELECT PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx, DisplayString_retin_dx, Insurance_retin_dx, Laterality, was_inferred
    FROM ranked_imputed WHERE rn = 1
    UNION ALL
    SELECT PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx, DisplayString_retin_dx, Insurance_retin_dx, Laterality, was_inferred
    FROM ordered
    WHERE PatientDurableKey NOT IN (SELECT PatientDurableKey FROM dup_lat_pt) AND rn = 1
)
SELECT *
INTO #first_sc_retin_dx
FROM final;

-- Complication diagnosis selection
DROP TABLE IF EXISTS #complication_dx;
SELECT DISTINCT DiagnosisKey, TerminologyConceptKey, [Value], DisplayString,
    CASE
        WHEN DisplayString LIKE '%right eye%' THEN 'RT'
        WHEN DisplayString LIKE '%left eye%' THEN 'LT'
        WHEN DisplayString LIKE '%bilateral%' THEN '50'
        WHEN DisplayString LIKE '%unspecified eye%' THEN 'Unspecified'
        ELSE '999'
    END AS Laterality
INTO #complication_dx
FROM DiagnosisTerminologyDim
WHERE [Type] = 'ICD-10-CM'
  AND (
      (([Value] LIKE 'E10.3%' AND [Value] <> 'E10.31') AND [Value] NOT LIKE 'E10.3[6-9]%') OR
      (([Value] LIKE 'E11.3%' AND [Value] <> 'E11.31') AND [Value] NOT LIKE 'E11.3[6-9]%') OR
      [Value] LIKE 'H43.1%' OR
      [Value] LIKE 'H33.4%'
  );

DROP TABLE IF EXISTS #DxEvents_all;
SELECT
    diag.PatientDurableKey, diag.EncounterKey, diag.DiagnosisKey, diag.[Type], diag.[Status],
    diag.Chronic, diag.IsPrimary, age.Years, DiagnosisDate.DateValue, dtd.Name,
    rt.[Value], rt.DisplayString, rt.Laterality, ef.PrimaryCoverageFinancialClass_X
INTO #DxEvents_all
FROM DiagnosisEventFact diag
INNER JOIN #first_sc_retin_dx pt ON pt.PatientDurableKey = diag.PatientDurableKey
INNER JOIN DateDim DiagnosisDate ON DiagnosisDate.DateKey = diag.StartDateKey
INNER JOIN DiagnosisDim dtd ON diag.DiagnosisKey = dtd.DiagnosisKey
INNER JOIN #complication_dx rt ON diag.DiagnosisKey = rt.DiagnosisKey
INNER JOIN EncounterFact ef ON diag.EncounterKey = ef.EncounterKey
INNER JOIN DurationDim age ON diag.AgeKey = age.DurationKey
WHERE diag.StartDateKey IS NOT NULL
  AND age.Years >= 18
  AND diag.[Type] <> N'Problem List';

DROP TABLE IF EXISTS #DxEvents_all_expanded;
WITH InitialRTDx AS (
    SELECT * FROM #DxEvents_all
),
expanded_DX AS (
    SELECT p.PatientDurableKey, p.DateValue, p.[Value], p.[Type], p.[Status], p.Chronic, p.IsPrimary, p.Years, p.DisplayString, p.PrimaryCoverageFinancialClass_X AS CoverageFinancialClass, 'RT' AS Laterality
    FROM InitialRTDx p WHERE p.Laterality = '50'
    UNION ALL
    SELECT p.PatientDurableKey, p.DateValue, p.[Value], p.[Type], p.[Status], p.Chronic, p.IsPrimary, p.Years, p.DisplayString, p.PrimaryCoverageFinancialClass_X AS CoverageFinancialClass, 'LT' AS Laterality
    FROM InitialRTDx p WHERE p.Laterality = '50'
    UNION ALL
    SELECT p.PatientDurableKey, p.DateValue, p.[Value], p.[Type], p.[Status], p.Chronic, p.IsPrimary, p.Years, p.DisplayString, p.PrimaryCoverageFinancialClass_X AS CoverageFinancialClass,
        CASE WHEN p.Laterality IN ('Right') THEN 'RT' WHEN p.Laterality IN ('Left') THEN 'LT' ELSE p.Laterality END AS Laterality
    FROM InitialRTDx p WHERE p.Laterality <> '50'
)
SELECT *
INTO #DxEvents_all_expanded
FROM expanded_DX;

DROP TABLE IF EXISTS #Dx_exclusion;
WITH MYPatients AS (SELECT * FROM #first_sc_retin_dx),
expanded_DX AS (SELECT * FROM #DxEvents_all_expanded),
matched_laterality AS (
    SELECT pt.*, DE.PatientDurableKey AS DE_PatientDurableKey, DE.DateValue, DE.[Value], DE.Years, DE.DisplayString, DE.CoverageFinancialClass, DE.Laterality AS Laterality_dx,
        ROW_NUMBER() OVER (PARTITION BY pt.PatientDurableKey, pt.Laterality ORDER BY DE.DateValue ASC) AS rn_firstDx
    FROM (SELECT * FROM MYPatients WHERE Laterality <> 'Unspecified') pt
    INNER JOIN expanded_DX DE ON DE.PatientDurableKey = pt.PatientDurableKey AND DE.Laterality = pt.Laterality
    WHERE DE.DateValue <= pt.Date_retin_dx
),
match_remainder AS (
    SELECT pt.*, DE.PatientDurableKey AS DE_PatientDurableKey, DE.DateValue, DE.[Value], DE.Years, DE.DisplayString, DE.CoverageFinancialClass, DE.Laterality AS Laterality_dx,
        ROW_NUMBER() OVER (PARTITION BY pt.PatientDurableKey, pt.Laterality ORDER BY ABS(DATEDIFF(DAY, pt.Date_retin_dx, DE.DateValue)) ASC) AS rn_firstDx
    FROM (
        SELECT * FROM MYPatients mp
        WHERE NOT EXISTS (SELECT 1 FROM matched_laterality ml WHERE ml.PatientDurableKey = mp.PatientDurableKey AND ml.Laterality = mp.Laterality)
    ) pt
    INNER JOIN (SELECT * FROM expanded_DX WHERE Laterality <> 'Unspecified') DE ON DE.PatientDurableKey = pt.PatientDurableKey
    WHERE DE.DateValue <= pt.Date_retin_dx
),
Match_remainder_unspec AS (
    SELECT pt.*, DE.PatientDurableKey AS DE_PatientDurableKey, DE.DateValue, DE.[Value], DE.Years, DE.DisplayString, DE.CoverageFinancialClass, DE.Laterality AS Laterality_dx,
        ROW_NUMBER() OVER (PARTITION BY pt.PatientDurableKey, pt.Laterality ORDER BY ABS(DATEDIFF(DAY, pt.Date_retin_dx, DE.DateValue)) ASC) AS rn_firstDx
    FROM (
        SELECT * FROM MYPatients mp
        WHERE NOT EXISTS (SELECT 1 FROM matched_laterality ml WHERE ml.PatientDurableKey = mp.PatientDurableKey AND ml.Laterality = mp.Laterality)
          AND NOT EXISTS (SELECT 1 FROM match_remainder m2 WHERE m2.PatientDurableKey = mp.PatientDurableKey AND m2.Laterality = mp.Laterality)
    ) pt
    INNER JOIN (SELECT * FROM expanded_DX WHERE Laterality = 'Unspecified') DE ON DE.PatientDurableKey = pt.PatientDurableKey
    WHERE DE.DateValue <= pt.Date_retin_dx AND pt.Laterality = 'Unspecified'
),
joined_data AS (
    SELECT * FROM matched_laterality WHERE rn_firstDx = 1
    UNION ALL
    SELECT * FROM match_remainder WHERE rn_firstDx = 1
    UNION ALL
    SELECT * FROM Match_remainder_unspec WHERE rn_firstDx = 1
)
SELECT *, DATEDIFF(DAY, Date_retin_dx, DateValue) AS Dx_intervention_DaysDifference
INTO #Dx_exclusion
FROM joined_data;

DROP TABLE IF EXISTS #final_cohort;
SELECT dx.*
INTO #final_cohort
FROM #first_sc_retin_dx dx
WHERE NOT EXISTS (
    SELECT 1
    FROM #Dx_exclusion e
    WHERE e.PatientDurableKey = dx.PatientDurableKey AND e.Laterality = dx.Laterality
);


DROP TABLE IF EXISTS #final_cohort_recovered;

WITH still_unspec AS (
    SELECT * FROM #final_cohort WHERE Laterality = 'Unspecified'
),
matched_pt AS (
    SELECT
        pt.PatientDurableKey, pt.Date_retin_dx, pt.Age_retin_dx, pt.icd_retin_dx,
        pt.DisplayString_retin_dx, pt.Insurance_retin_dx, DE.Laterality AS Laterality,
        2 AS was_inferred,
        ROW_NUMBER() OVER (
            PARTITION BY pt.PatientDurableKey, DE.Laterality
            ORDER BY DE.DateValue DESC
        ) AS rn
    FROM still_unspec pt
    JOIN #DxEvents_all_expanded DE ON DE.PatientDurableKey = pt.PatientDurableKey
    WHERE DE.Laterality <> 'Unspecified' AND DE.DateValue <= pt.Date_retin_dx
),
removed AS (
    SELECT *
    FROM #final_cohort c
    WHERE c.PatientDurableKey NOT IN (SELECT PatientDurableKey FROM matched_pt) OR c.Laterality <> 'Unspecified'
),
joined AS (
    SELECT PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx, DisplayString_retin_dx, Insurance_retin_dx, Laterality, was_inferred FROM removed
    UNION ALL
    SELECT PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx, DisplayString_retin_dx, Insurance_retin_dx, Laterality, was_inferred FROM matched_pt WHERE rn = 1
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientDurableKey, Laterality
            ORDER BY Date_retin_dx DESC
        ) AS rn
    FROM joined
)
SELECT PatientDurableKey, Date_retin_dx, Age_retin_dx, icd_retin_dx, DisplayString_retin_dx, Insurance_retin_dx, Laterality, was_inferred
INTO #final_cohort_recovered
FROM ranked WHERE rn = 1;

DROP TABLE IF EXISTS #Dx_complication;
WITH MYPatients AS (SELECT * FROM #final_cohort_recovered),
expanded_DX AS (SELECT * FROM #DxEvents_all_expanded),
matched_laterality AS (
    SELECT pt.*, DE.PatientDurableKey AS DE_PatientDurableKey, DE.DateValue, DE.[Value], DE.Years, DE.DisplayString, DE.CoverageFinancialClass, DE.Laterality AS Laterality_dx,
        ROW_NUMBER() OVER (PARTITION BY pt.PatientDurableKey, pt.Laterality ORDER BY DE.DateValue ASC) AS rn_firstDx
    FROM (SELECT * FROM MYPatients WHERE Laterality <> 'Unspecified') pt
    INNER JOIN expanded_DX DE ON DE.PatientDurableKey = pt.PatientDurableKey AND DE.Laterality = pt.Laterality
    WHERE DE.DateValue > pt.Date_retin_dx
),
match_remainder AS (
    SELECT pt.*, DE.PatientDurableKey AS DE_PatientDurableKey, DE.DateValue, DE.[Value], DE.Years, DE.DisplayString, DE.CoverageFinancialClass, DE.Laterality AS Laterality_dx,
        ROW_NUMBER() OVER (PARTITION BY pt.PatientDurableKey, pt.Laterality ORDER BY ABS(DATEDIFF(DAY, pt.Date_retin_dx, DE.DateValue)) ASC) AS rn_firstDx
    FROM (
        SELECT * FROM MYPatients mp
        WHERE NOT EXISTS (SELECT 1 FROM matched_laterality ml WHERE ml.PatientDurableKey = mp.PatientDurableKey AND ml.Laterality = mp.Laterality)
    ) pt
    INNER JOIN (SELECT * FROM expanded_DX WHERE Laterality <> 'Unspecified') DE ON DE.PatientDurableKey = pt.PatientDurableKey
    WHERE DE.DateValue > pt.Date_retin_dx
),
Match_remainder_unspec AS (
    SELECT pt.*, DE.PatientDurableKey AS DE_PatientDurableKey, DE.DateValue, DE.[Value], DE.Years, DE.DisplayString, DE.CoverageFinancialClass, DE.Laterality AS Laterality_dx,
        ROW_NUMBER() OVER (PARTITION BY pt.PatientDurableKey, pt.Laterality ORDER BY ABS(DATEDIFF(DAY, pt.Date_retin_dx, DE.DateValue)) ASC) AS rn_firstDx
    FROM (
        SELECT * FROM MYPatients mp
        WHERE NOT EXISTS (SELECT 1 FROM matched_laterality ml WHERE ml.PatientDurableKey = mp.PatientDurableKey AND ml.Laterality = mp.Laterality)
          AND NOT EXISTS (SELECT 1 FROM match_remainder m2 WHERE m2.PatientDurableKey = mp.PatientDurableKey AND m2.Laterality = mp.Laterality)
    ) pt
    INNER JOIN (SELECT * FROM expanded_DX WHERE Laterality = 'Unspecified') DE ON DE.PatientDurableKey = pt.PatientDurableKey
    WHERE DE.DateValue > pt.Date_retin_dx AND pt.Laterality = 'Unspecified'
),
joined_data AS (
    SELECT * FROM matched_laterality WHERE rn_firstDx = 1
    UNION ALL
    SELECT * FROM match_remainder WHERE rn_firstDx = 1
    UNION ALL
    SELECT * FROM Match_remainder_unspec WHERE rn_firstDx = 1
)
SELECT *, DATEDIFF(DAY, Date_retin_dx, DateValue) AS Days_complication
INTO #Dx_complication
FROM joined_data;

DROP TABLE IF EXISTS #final_cohort_recovered_complications;
SELECT
    f.*,
    c.DateValue AS Date_complication,
    c.[Value] AS icd_complication,
    c.Years AS age_complication,
    c.DisplayString AS DisplayString_complication,
    c.CoverageFinancialClass AS Insurance_complication,
    c.Laterality_dx AS Laterality_complication,
    c.Days_complication
INTO #final_cohort_recovered_complications
FROM #final_cohort_recovered f
LEFT JOIN #Dx_complication c ON f.PatientDurableKey = c.PatientDurableKey AND c.Laterality = f.Laterality;

DROP TABLE IF EXISTS #PatientDemo;
SELECT
    DurableKey AS PatientDurableKey, BirthDate, Sex, MaritalStatus, PreferredLanguage,
    CASE WHEN PreferredLanguage = 'English' THEN 'English' ELSE 'Non-English' END AS [Language],
    Ethnicity, FirstRace, MultiRacial, DeathDate, [Status], Country, StateOrProvince, StateOrProvinceAbbreviation,
    svi_overall_2020_X AS svi_overall_2020,
    svi_ses_2020_X AS svi_ses_2020,
    svi_house_2020_X AS svi_house_2020,
    svi_minority_2020_X AS svi_minority_2020,
    svi_transport_2020_X AS svi_transport_2020,
    PrimaryRUCA_X AS ruca
INTO #PatientDemo
FROM PatientDim
WHERE DurableKey IN (SELECT DISTINCT PatientDurableKey FROM #final_cohort_recovered_complications);

DROP TABLE IF EXISTS #final_cohort_recovered_complications_pt_demo;
WITH encs AS (
    SELECT DISTINCT PatientDurableKey, EncounterCountAfterFirstDate_opt, LastEncounterDate_opt, EncounterCountAfterFirstDate, LastEncounterDate
    FROM #cohort
)
SELECT
    dx.*,
    e.EncounterCountAfterFirstDate_opt, e.LastEncounterDate_opt, e.EncounterCountAfterFirstDate, e.LastEncounterDate,
    DATEDIFF(DAY, dx.Date_retin_dx, e.LastEncounterDate) AS FU_day
INTO #final_cohort_recovered_complications_pt_demo
FROM #final_cohort_recovered_complications dx
LEFT JOIN encs e ON e.PatientDurableKey = dx.PatientDurableKey
WHERE dx.PatientDurableKey IN (SELECT PatientDurableKey FROM #PatientDemo);

INSERT INTO PROJECTS.Project0821712.dbo.PatientDemo
SELECT * FROM #PatientDemo;

INSERT INTO PROJECTS.Project0821712.dbo.final_cohort
SELECT * FROM #final_cohort_recovered_complications_pt_demo;


USE COSMOS;

DROP TABLE IF EXISTS #cohort;
WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY PatientDurableKey, Laterality ORDER BY Date_retin_dx ASC) AS rn
    FROM PROJECTS.Project0821712.dbo.final_cohort
)
SELECT *
INTO #cohort
FROM ranked WHERE rn = 1;

DROP TABLE IF EXISTS #meds;
WITH all_hydrox AS (
    SELECT DISTINCT MedicationKey, PharmaceuticalClass, SimpleGenericName, TherapeuticClass
    FROM MedicationDim
    WHERE SimpleGenericName LIKE '%hydroxyurea%'
      AND PharmaceuticalClass LIKE '%SICKLE CELL%'
),
OuterOrders AS (
    SELECT
        orders.MedicationKey, orders.PatientDurableKey, orders.RefillsWritten, orders.DiscontinueReason,
        orders.FirstIndicationForUse, orders.SecondIndicationForUse, orders.ThirdIndicationForUse, orders.FourthIndicationForUse, orders.Frequency,
        startDateInfo.DateValue AS StartDate, endDateInfo.DateValue AS EndDate,
        1 AS used_hydroxyurea, MRCF.StartDateKey, MRCF.EndDateKey, MRCF.ComponentType_X, MRCF.Frequency_X
    FROM (SELECT PatientDurableKey, MIN(Date_retin_dx) AS Date_retin_dx FROM #cohort GROUP BY PatientDurableKey) pt
    JOIN MedicationOrderFact orders ON orders.PatientDurableKey = pt.PatientDurableKey
    INNER JOIN all_hydrox meds ON orders.MedicationKey = meds.MedicationKey
    INNER JOIN DateDim startDateInfo ON startDateInfo.DateKey = orders.StartDateKey
    INNER JOIN DateDim endDateInfo ON endDateInfo.DateKey = orders.EndDateKey
    INNER JOIN MedicationOrderComponentFact MRCF ON MRCF.MedicationOrderKey = orders.MedicationOrderKey
)
SELECT *
INTO #meds
FROM OuterOrders;

DROP TABLE IF EXISTS #med_clean;
WITH step1 AS (
    SELECT PatientDurableKey,
        CASE WHEN StartDate IS NULL AND EndDate IS NOT NULL THEN DATEADD(day, -90, EndDate) ELSE StartDate END AS StartDate,
        CASE
            WHEN EndDate IS NULL AND StartDate IS NOT NULL THEN DATEADD(day, 90, StartDate)
            WHEN YEAR(EndDate) = 9999 THEN DATEADD(day, 90, StartDate)
            ELSE EndDate
        END AS EndDate
    FROM #meds
    WHERE NOT (StartDate IS NULL AND EndDate IS NULL)
),
step2 AS (
    SELECT PatientDurableKey, StartDate,
        CASE WHEN StartDate >= EndDate THEN DATEADD(day, 90, StartDate) ELSE EndDate END AS EndDate
    FROM step1
)
SELECT PatientDurableKey, StartDate, MAX(EndDate) AS EndDate
INTO #med_clean
FROM step2
GROUP BY PatientDurableKey, StartDate;

DROP TABLE IF EXISTS #baseline_exposure;
SELECT c.PatientDurableKey, c.Laterality, c.Date_retin_dx,
    CASE WHEN EXISTS (
        SELECT 1 FROM #med_clean m
        WHERE m.PatientDurableKey = c.PatientDurableKey
          AND m.StartDate <= c.Date_retin_dx
          AND m.EndDate >= c.Date_retin_dx
    ) THEN 1 ELSE 0 END AS exposed_at_index
INTO #baseline_exposure
FROM #cohort c;

DROP TABLE IF EXISTS #post_index_start;
SELECT c.PatientDurableKey, MIN(m.StartDate) AS first_start_after_index
INTO #post_index_start
FROM #cohort c
JOIN #med_clean m ON c.PatientDurableKey = m.PatientDurableKey
WHERE m.StartDate > c.Date_retin_dx
GROUP BY c.PatientDurableKey;

DROP TABLE IF EXISTS #exposure_timeline;
SELECT b.PatientDurableKey, b.Laterality, b.Date_retin_dx, b.exposed_at_index, p.first_start_after_index,
    CASE
        WHEN b.exposed_at_index = 1 THEN b.Date_retin_dx
        WHEN p.first_start_after_index IS NOT NULL THEN p.first_start_after_index
        ELSE NULL
    END AS exposure_start_date
INTO #exposure_timeline
FROM #baseline_exposure b
LEFT JOIN #post_index_start p ON b.PatientDurableKey = p.PatientDurableKey;


DROP TABLE IF EXISTS #dx_complications_followup;
SELECT c.PatientDurableKey, c.Laterality, d.icd10 AS code, d.DateValue AS Date_complication
INTO #dx_complications_followup
FROM #cohort c
JOIN PROJECTS.Project0821712.dbo.Dx_complication_long d
    ON c.PatientDurableKey = d.PatientDurableKey
   AND (c.Laterality = d.Laterality OR d.Laterality = 'Unspecified' OR c.Laterality = 'Unspecified')
WHERE d.DateValue > c.Date_retin_dx;

DROP TABLE IF EXISTS #sx_complications_followup;
SELECT c.PatientDurableKey, c.Laterality, s.CptCode AS code, s.complication_sx_date AS Date_complication
INTO #sx_complications_followup
FROM #cohort c
JOIN PROJECTS.Project0821712.dbo.sx_complication_long s
    ON c.PatientDurableKey = s.PatientDurableKey
   AND (c.Laterality = s.Laterality OR s.Laterality = 'Unspecified' OR c.Laterality = 'Unspecified')
WHERE s.complication_sx_date > c.Date_retin_dx;

DROP TABLE IF EXISTS #inj_complications_followup;
SELECT c.PatientDurableKey, c.Laterality, i.CptCode AS code, i.injection_date AS Date_complication
INTO #inj_complications_followup
FROM #cohort c
JOIN PROJECTS.Project0821712.dbo.injection_complication_long i
    ON c.PatientDurableKey = i.PatientDurableKey
   AND (c.Laterality = i.Laterality OR i.Laterality = 'Unspecified' OR c.Laterality = 'Unspecified')
WHERE i.injection_date > c.Date_retin_dx;

DROP TABLE IF EXISTS #all_complications;
WITH all_complications AS (
    SELECT PatientDurableKey, Laterality, Date_complication, code, 'dx' AS source FROM #dx_complications_followup
    UNION ALL
    SELECT PatientDurableKey, Laterality, Date_complication, code, 'sx' AS source FROM #sx_complications_followup
    UNION ALL
    SELECT PatientDurableKey, Laterality, Date_complication, code, 'injection' AS source FROM #inj_complications_followup
)
SELECT * INTO #all_complications FROM all_complications;

DROP TABLE IF EXISTS #complications_exposure;
SELECT c.*,
    CASE WHEN EXISTS (
        SELECT 1 FROM #exposure_timeline e
        WHERE e.PatientDurableKey = c.PatientDurableKey
          AND e.exposure_start_date IS NOT NULL
          AND c.Date_complication >= e.exposure_start_date
    ) THEN 1 ELSE 0 END AS hydroxyurea_exposed_event
INTO #complications_exposure
FROM #all_complications c;

ALTER TABLE #complications_exposure ADD complication_type VARCHAR(30);
GO

UPDATE #complications_exposure
SET complication_type = CASE
    WHEN code LIKE 'H43.1%' THEN 'vitreous hemorrhage'
    WHEN code LIKE 'H33.4%' THEN 'tractional rd'
    WHEN code = '67225' THEN 'PRP'
    WHEN code IN ('67036', '67039', '67040', '67041', '67042', '67043', '67107', '67108', '67112', '67113') THEN 'vitrectomy'
    WHEN code = '67028' THEN 'injection'
END;

DROP TABLE IF EXISTS #final_events;
SELECT
    c.PatientDurableKey, c.Laterality, c.Date_retin_dx, e.Date_complication, e.code, e.complication_type,
    e.hydroxyurea_exposed_event, et.exposed_at_index, et.first_start_after_index, et.exposure_start_date
INTO #final_events
FROM #cohort c
LEFT JOIN #complications_exposure e ON c.PatientDurableKey = e.PatientDurableKey AND c.Laterality = e.Laterality AND e.Date_complication > c.Date_retin_dx
LEFT JOIN #exposure_timeline et ON et.PatientDurableKey = c.PatientDurableKey AND et.Laterality = c.Laterality;

INSERT INTO PROJECTS.Project0821712.dbo.final_events
SELECT * FROM #final_events;

DROP TABLE IF EXISTS #long_dx;
SELECT * INTO #long_dx FROM PROJECTS.Project0821712.dbo.SC_retin_dx;

DROP TABLE IF EXISTS #lat_flags;
SELECT PatientDurableKey,
    MAX(CASE WHEN Laterality = 'RT' THEN 1 ELSE 0 END) AS has_RT,
    MAX(CASE WHEN Laterality = 'LT' THEN 1 ELSE 0 END) AS has_LT
INTO #lat_flags
FROM #long_dx
GROUP BY PatientDurableKey;

DROP TABLE IF EXISTS #dx_expanded;
SELECT d.PatientDurableKey, d.Date_retin_dx, d.icd_retin_dx, d.DisplayString_retin_dx, d.Laterality
INTO #dx_expanded
FROM #long_dx d
JOIN #lat_flags f ON d.PatientDurableKey = f.PatientDurableKey
WHERE d.Laterality IN ('RT', 'LT')
UNION ALL
SELECT d.PatientDurableKey, d.Date_retin_dx, d.icd_retin_dx, d.DisplayString_retin_dx, 'RT' AS Laterality
FROM #long_dx d
JOIN #lat_flags f ON d.PatientDurableKey = f.PatientDurableKey
WHERE d.Laterality = 'Unspecified' AND f.has_RT = 1 AND f.has_LT = 0
UNION ALL
SELECT d.PatientDurableKey, d.Date_retin_dx, d.icd_retin_dx, d.DisplayString_retin_dx, 'LT' AS Laterality
FROM #long_dx d
JOIN #lat_flags f ON d.PatientDurableKey = f.PatientDurableKey
WHERE d.Laterality = 'Unspecified' AND f.has_RT = 0 AND f.has_LT = 1;

DROP TABLE IF EXISTS #first_eye_dx;
WITH ranked AS (
    SELECT PatientDurableKey, Laterality, Date_retin_dx, icd_retin_dx,
        ROW_NUMBER() OVER (PARTITION BY PatientDurableKey, Laterality ORDER BY Date_retin_dx ASC) AS rn
    FROM #dx_expanded
)
SELECT PatientDurableKey, Laterality, Date_retin_dx AS first_dx_date, icd_retin_dx AS first_icd
INTO #first_eye_dx
FROM ranked WHERE rn = 1;

DROP TABLE IF EXISTS #eligible_progression_eyes;
SELECT * INTO #eligible_progression_eyes FROM #first_eye_dx WHERE first_icd LIKE 'H36.81%';

DROP TABLE IF EXISTS #dx_ordered;
SELECT PatientDurableKey, Laterality, Date_retin_dx,
    CASE
        WHEN icd_retin_dx LIKE 'H36.82%' THEN 1
        WHEN icd_retin_dx LIKE 'H36.81%' THEN 0
    END AS is_PDR,
    ROW_NUMBER() OVER (PARTITION BY PatientDurableKey, Laterality ORDER BY Date_retin_dx) AS visit_order
INTO #dx_ordered
FROM #dx_expanded;

DROP TABLE IF EXISTS #dx_progression_cohort;
SELECT d.*
INTO #dx_progression_cohort
FROM #dx_ordered d
JOIN #eligible_progression_eyes e ON d.PatientDurableKey = e.PatientDurableKey AND d.Laterality = e.Laterality;

DROP TABLE IF EXISTS #progression_flags;
WITH seq AS (
    SELECT *,
        LAG(is_PDR, 1) OVER (PARTITION BY PatientDurableKey, Laterality ORDER BY Date_retin_dx) AS prev1,
        LEAD(is_PDR, 1) OVER (PARTITION BY PatientDurableKey, Laterality ORDER BY Date_retin_dx) AS next1
    FROM #dx_progression_cohort
)
SELECT PatientDurableKey, Laterality, Date_retin_dx,
    CASE WHEN is_PDR = 1 AND (prev1 = 1 OR next1 = 1) THEN 1 ELSE 0 END AS confirmed_progression
INTO #progression_flags
FROM seq;

DROP TABLE IF EXISTS #progression_eye;
SELECT p.PatientDurableKey, p.Laterality, MIN(p.Date_retin_dx) AS progression_date
INTO #progression_eye
FROM #progression_flags p
WHERE p.confirmed_progression = 1
GROUP BY p.PatientDurableKey, p.Laterality;

DROP TABLE IF EXISTS #first_npdr;
SELECT PatientDurableKey, Laterality, MIN(Date_retin_dx) AS first_npdr_date
INTO #first_npdr
FROM #dx_ordered
WHERE is_PDR = 0
GROUP BY PatientDurableKey, Laterality;

DROP TABLE IF EXISTS #progression_final;
SELECT n.PatientDurableKey, n.Laterality, n.first_npdr_date, p.progression_date,
    DATEDIFF(day, n.first_npdr_date, p.progression_date) AS days_to_progression,
    CASE WHEN p.progression_date IS NOT NULL THEN 1 ELSE 0 END AS progressed_flag
INTO #progression_final
FROM #first_npdr n
LEFT JOIN #progression_eye p ON n.PatientDurableKey = p.PatientDurableKey AND n.Laterality = p.Laterality;

DROP TABLE IF EXISTS #progression_patient;
SELECT PatientDurableKey, MIN(progression_date) AS patient_progression_date, MIN(days_to_progression) AS patient_days_to_progression, MAX(progressed_flag) AS any_progression
INTO #progression_patient
FROM #progression_final
GROUP BY PatientDurableKey;

INSERT INTO PROJECTS.Project0821712.dbo.progression
SELECT * FROM #progression_final;