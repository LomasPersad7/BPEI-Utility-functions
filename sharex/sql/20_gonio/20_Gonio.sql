-- IRIS

DROP TABLE IF EXISTS #all_cpt; --306,049
CREATE TABLE #all_cpt AS
SELECT
    patient_guid,
    birth_year,
    AgeAtSx,
    procedure_date,
    procedure_code,
    procedure_code_description,
    laterality_code,
    laterality_code_description
FROM (
    SELECT
        p.patient_guid,
        pt.birth_year,
        EXTRACT(YEAR FROM p.procedure_date) - pt.birth_year as AgeAtSx,
        p.procedure_date,
        p.procedure_code,
        p.procedure_code_description,
        p.laterality_code,
        p.laterality_code_description,
        ROW_NUMBER() OVER (
            PARTITION BY p.patient_guid, p.laterality_code
            ORDER BY p.procedure_date
        ) AS row_num
    FROM "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_procedure" p
    LEFT JOIN
        (SELECT patient_guid, birth_year
         FROM iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient) pt
        ON pt.patient_guid = p.patient_guid
    WHERE p.laterality_code <> 4
        AND p.procedure_code IN ('66174','65820')
) ranked
-- WHERE row_num = 1
;


DROP TABLE IF EXISTS #alldx; --
CREATE TABLE #alldx AS
with all_dx as (
SELECT
    c.patient_guid,
    pt.birth_year,
    c.condition_date,
    c.condition_code,
    c.condition_code_description,
    c.laterality_code,
    c.laterality_code_description,
    p.practice_state,
    p.practice_zip5,
    prov.provider_type,
    prov.provider_subspecialty_1,
    prov.provider_subspecialty_2,
    prov.provider_subspecialty_3,
    EXTRACT(YEAR FROM c.condition_date) - pt.birth_year as AgeAtDx
FROM
    iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_condition c
inner join #all_cpt cpt on cpt.patient_guid= c.patient_guid
LEFT JOIN
    (SELECT patient_guid, birth_year FROM iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient) pt
    ON pt.patient_guid = c.patient_guid
left join iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.practice p
    on p.practice_guid=c.practice_guid
left join iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.provider prov
    on prov.provider_guid=c.provider_guid
WHERE
    -- Inclusion criteria: macular hole diagnosis for patients under 18
    c.condition_code like 'H40.1%'
    AND (EXTRACT(YEAR FROM c.condition_date) - pt.birth_year) >= 18
),
specified_dx as (
Select distinct patient_guid,condition_date,laterality_code
from all_dx
where laterality_code <> '4'
),
unspecified_dx as (
Select distinct patient_guid,condition_date,laterality_code
from all_dx
where laterality_code ='4'
),
-- extract unspecified dx that have specified dx on the same day (these recolds should be removed)
unspec_same_day_as_spec_dx as (
   SELECT DISTINCT
    unspecified.patient_guid,
    unspecified.condition_date,
    unspecified.laterality_code
  FROM unspecified_dx as unspecified
  JOIN specified_dx as specified
  ON
    unspecified.patient_guid = specified.patient_guid AND
    unspecified.condition_date = specified.condition_date
),
removed_unspec as(
select distinct
      alldx.patient_guid,
      alldx.birth_year,
      alldx.condition_date,
      alldx.condition_code,
      alldx.condition_code_description,
      alldx.laterality_code, -- as prioritized_laterality_code,
    alldx.laterality_code_description,
    alldx.practice_state,
    alldx.practice_zip5,
    alldx.provider_type,
    alldx.provider_subspecialty_1,
    alldx.provider_subspecialty_2,
    alldx.provider_subspecialty_3,
    AgeAtDx,
    ROW_NUMBER () over(PARTITION by alldx.patient_guid,alldx.laterality_code order by  alldx.condition_date ASC) as first_dx
from (select * from all_dx ) as alldx
 WHERE NOT EXISTS
   (
      SELECT 1 FROM unspec_same_day_as_spec_dx  unspec_spec
      WHERE alldx.patient_guid=unspec_spec.patient_guid
        and alldx.condition_date=unspec_spec.condition_date
        and alldx.laterality_code=unspec_spec.laterality_code
   )
)
SELECT *
FROM removed_unspec;



DROP TABLE IF EXISTS #glaucoma_codes;
CREATE TABLE #glaucoma_codes AS
with allcodes as (
select distinct condition_code from #alldx
)
SELECT
    condition_code,
    -- Glaucoma Type Classification
    CASE
        WHEN condition_code LIKE 'H40.10%' THEN 'Unspecified open-angle glaucoma'
        WHEN condition_code LIKE 'H40.11%' THEN 'Primary open-angle glaucoma'
        WHEN condition_code LIKE 'H40.12%' THEN 'Low-tension glaucoma'
        WHEN condition_code LIKE 'H40.13%' THEN 'Pigmentary glaucoma'
        WHEN condition_code LIKE 'H40.14%' THEN 'Capsular glaucoma with pseudo-exfoliation of lens'
        WHEN condition_code LIKE 'H40.15%' THEN 'Residual stage of open-angle glaucoma'
        ELSE 'Other glaucoma'
    END AS glaucoma_type,

    -- Laterality Classification
    CASE
        WHEN condition_code LIKE 'H40.10%' THEN 'Unspecified'
        WHEN SUBSTRING(condition_code, 7, 1) = '1' THEN 'Right'
        WHEN SUBSTRING(condition_code, 7, 1) = '2' THEN 'Left'
        WHEN SUBSTRING(condition_code, 7, 1) = '3' THEN 'Bilateral'
        ELSE 'Unspecified'
    END AS laterality,

    -- Severity Staging
    CASE
        -- Handle residual glaucoma first (no staging)
        WHEN condition_code LIKE 'H40.15%' THEN 'No stage indicated'

        -- For other types with complete 7-character codes
        WHEN LEN(condition_code) = 8 THEN
            CASE SUBSTRING(condition_code, 8, 1)
                WHEN '0' THEN 'Stage unspecified'
                WHEN '1' THEN 'Mild stage'
                WHEN '2' THEN 'Moderate stage'
                WHEN '3' THEN 'Severe stage'
                WHEN '4' THEN 'Indeterminate stage'
                ELSE 'Invalid stage'
            END
         -- Missing stage character
        ELSE 'Stage missing'
    END AS severity
FROM allcodes
;


DROP TABLE IF EXISTS #qualified_cases;
CREATE TABLE #qualified_cases AS
with known_lat as (
select cpt.patient_guid,
       cpt.laterality_code,
       cpt.laterality_code_description,
       cpt.birth_year,
       cpt.AgeAtSx,
       cpt.procedure_date,
       cpt.procedure_code,
       f.condition_date,
       f.condition_code,
       f.laterality_code as laterality_code_dx,
       f.ageatdx,
       DATEDIFF(DAY, cpt.procedure_date, f.condition_date) AS dx_sx_interval,
       ROW_NUMBER () over(PARTITION by cpt.patient_guid,cpt.laterality_code order by  ABS(DATEDIFF(DAY, cpt.procedure_date, f.condition_date)) ASC) as Closest_dx --closest dx to goniometry
from #all_cpt cpt
left join (select * from #alldx) f
    on f.patient_guid=cpt.patient_guid and f.laterality_code=cpt.laterality_code
where  f.condition_date BETWEEN cpt.procedure_date - INTERVAL '90 days'  -- TODO: recheck this line
                          AND cpt.procedure_date - INTERVAL '1 days'
),
unknown_lat as(
 select cpt.patient_guid,
       cpt.laterality_code,
       cpt.laterality_code_description,
       cpt.birth_year,
       cpt.AgeAtSx,
       cpt.procedure_date,
       cpt.procedure_code,
       f.condition_date,
       f.condition_code,
       f.laterality_code as laterality_code_dx,
       f.ageatdx,
       DATEDIFF(DAY, cpt.procedure_date, f.condition_date) AS dx_sx_interval,
       ROW_NUMBER () over(PARTITION by cpt.patient_guid,cpt.laterality_code order by  ABS(DATEDIFF(DAY, cpt.procedure_date, f.condition_date)) ASC) as Closest_dx --closest dx to goniometry
from (select * from #all_cpt c1
        where not exists (
            select 1
            from known_lat c2
            where c2.patient_guid=c1.patient_guid and c2.laterality_code=c1.laterality_code
        ))  cpt

left join (select * from #alldx where laterality_code='4') f
    on f.patient_guid=cpt.patient_guid
where  f.condition_date BETWEEN cpt.procedure_date - INTERVAL '90 days'  -- TODO: recheck this line
                          AND cpt.procedure_date - INTERVAL '1 days'
),
combined as (

  SELECT * FROM known_lat  WHERE Closest_dx = 1
  UNION ALL
  SELECT * FROM unknown_lat  WHERE Closest_dx = 1

)
select patient_guid,
    laterality_code,
     laterality_code_description,
     birth_year,
    condition_date,
    procedure_date as Gonio_sx_date,
    procedure_code as Gonio_sx_code,
    c.condition_code,
    glaucoma_type,
    laterality as glaucoma_laterality,
    severity as glaucoma_severity,
    ageAtdx as glaucoma_Age,
    -- AgeAtSx as Gonio_sx_Age,
    dx_sx_interval

from combined c
left join #glaucoma_codes gc on gc.condition_code=c.condition_code
;



DROP TABLE IF EXISTS #cohort_with_followup_procedures;
CREATE TABLE #cohort_with_followup_procedures AS
with allSx as (
SELECT
    qc.*,
    fp.procedure_code AS PostOP_treatment_cpt,
    fp.procedure_date AS PostOP_treatment_date,
    DATEDIFF(DAY, qc.Gonio_sx_date, fp.procedure_date) AS days_post_op,
    CASE
        when fp.procedure_code in ('65815', '65930') then 'Anterior chamber washout'
        when fp.procedure_code in ('66179', '66180') then 'Aqueous shunt'
        when fp.procedure_code in ('66170', '66172') then 'Trabeculectomy'
        when fp.procedure_code in ('0449T', '0450T','66183') then 'Xen implantation'
    end as PostOP_treatment
FROM #qualified_cases qc
INNER JOIN "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_procedure" fp
    ON qc.patient_guid = fp.patient_guid
    AND qc.laterality_code = fp.laterality_code  -- Match eye laterality
    AND fp.procedure_date BETWEEN DATEADD(DAY, 1, qc.Gonio_sx_date)
                              AND DATEADD(DAY, 42, qc.Gonio_sx_date)  -- 6-week window
WHERE fp.procedure_code IN (
    '65815', '65930',      -- Laser procedures
    '66179', '66180',  -- Aqueous shunt revisions
    '66170', '66172',       -- Other glaucoma procedures
    '0449T','0450T', '66183' )  -- Xen cases
),
ranked as (
    select *,
    ROW_NUMBER () over(PARTITION by patient_guid,laterality_code,PostOP_treatment order by PostOP_treatment_date ASC) as PostOP_treatment_rank
    from allSx
)
select * from ranked
where PostOP_treatment_rank=1
;



DROP TABLE IF EXISTS #Eyedata_IOP_all;
CREATE TABLE #Eyedata_IOP_all AS
select iop.patient_guid,
    iop.laterality_code,
    iop.result_date as IOP_date,
    iop.result_value as IOP,
    iop.result_unit,
    iop.practice_guid,
    iop.provider_guid
from (select distinct patient_guid from #qualified_cases) cohort
inner join "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_iop" iop
    on iop.patient_guid=cohort.patient_guid
;

-- select * from #Eyedata_IOP_all

-- select dates AND cols of Interest
DROP TABLE IF EXISTS #Baseline_IOP;
CREATE TABLE #Baseline_IOP AS
with all_iop as (
select e.patient_guid,e.laterality_code,condition_date, gonio_sx_date,IOP_date,IOP,result_unit,
DATEDIFF(DAY, gonio_sx_date, IOP_date) as interval_sx_iop,
    ROW_NUMBER () over(PARTITION by e.patient_guid,e.laterality_code order by  ABS(DATEDIFF(DAY, gonio_sx_date, IOP_date)) ASC) as Closest_IOP_rank

from #qualified_cases  c
join #Eyedata_IOP_all  e
    on e.patient_guid=c.patient_guid and e.laterality_code=c.laterality_code --and c.condition_date =e.IOP_date
where IOP_date BETWEEN DATEADD(DAY, -30, gonio_sx_date)
                              AND gonio_sx_date
)
select * from all_iop where Closest_IOP_rank=1
;



-- select dates an cols of interest
DROP TABLE IF EXISTS #IOP_followup_sx;
CREATE TABLE #IOP_followup_sx AS
with all_iop as (
select e.patient_guid,e.laterality_code,PostOP_treatment_date,PostOP_treatment_cpt,PostOP_treatment,days_post_op,IOP_date,IOP,result_unit,
DATEDIFF(DAY, PostOP_treatment_date, IOP_date) as interval_PostOp_iop,
    ROW_NUMBER () over(PARTITION by e.patient_guid,e.laterality_code order by  ABS(DATEDIFF(DAY, PostOP_treatment_date, IOP_date)) ASC) as Closest_IOP_rank

from #cohort_with_followup_procedures  c
join #Eyedata_IOP_all  e
    on e.patient_guid=c.patient_guid and e.laterality_code=c.laterality_code --and c.condition_date =e.IOP_date
--where IOP_date < PostOP_treatment_date
where IOP_date BETWEEN DATEADD(DAY, 1, gonio_sx_date)
                              AND DATEADD(DAY, -1, PostOP_treatment_date)
)
select * from all_iop where Closest_IOP_rank=1
;


DROP TABLE IF EXISTS #final_cohort;
CREATE TABLE #final_cohort AS
select q.*,
biop.iop_date as baselinge_iop_date,
biop.iop as baseline_iop,
biop.interval_sx_iop as baseline_interval_sx_iop,
c.PostOP_treatment_date,c.PostOP_treatment_cpt,c.PostOP_treatment,c.days_post_op,
i.IOP_date as IOP_date_pre_treatment,
i.IOP as IOP_pre_pre_treatment,
i.interval_PostOp_iop
from #qualified_cases q
left join #Baseline_IOP biop on biop.patient_guid=q.patient_guid and biop.laterality_code=q.laterality_code
left join #cohort_with_followup_procedures c on c.patient_guid=q.patient_guid and c.laterality_code=q.laterality_code
left join #IOP_followup_sx i on i.patient_guid=q.patient_guid and i.laterality_code=q.laterality_code
;


-- select * from  #final_cohort;

-- concurrent cataract sx

DROP TABLE IF EXISTS #all_cataract;
CREATE TABLE #all_cataract AS
SELECT  distinct
    proc.patient_guid,
    -- proc.patient_visit_id,
    proc.procedure_date as cataract_date,
    proc.procedure_code as cataract_code,
    -- proc.procedure_code_system as,
    -- proc.procedure_code_description as exclusion_sx_code_desc,
    -- proc.modifier_1_code,
    -- proc.modifier_2_code,
    -- proc.modifier_3_code,
    -- proc.modifier_4_code,
    proc.laterality_code as laterality_code
    -- proc.laterality_code_description as exclusion_sx_laterality_code_desc,

FROM (select distinct patient_guid from #final_cohort) fdx
 join   iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_procedure proc
    on proc.patient_guid=fdx.patient_guid
WHERE
proc.procedure_code IN ('66984','66982') and proc.laterality_code<>'4' -- there are no bilateral cases
;

DROP TABLE IF EXISTS #final_cohort_cataract;
CREATE TABLE #final_cohort_cataract AS
with concurrent_cataract_gonio as (

select f.patient_guid,
       f.laterality_code,
       cataract_date as concurrent_cataract_gonio_date,
       cataract_code as concurrent_cataract_gonio_code,
       ROW_NUMBER () over(PARTITION by f.patient_guid,f.laterality_code order by cataract_date ASC) as rank

from #final_cohort f
join #all_cataract ac
    on f.patient_guid=ac.patient_guid and f.laterality_code=ac.laterality_code and f.gonio_sx_date=ac.cataract_date
),
concurrent_catract_PostOp as(

select f.patient_guid,
       f.laterality_code,
       cataract_date as concurrent_cataract_PostOp_date,
       cataract_code as concurrent_cataract_PostOp_code,
       ROW_NUMBER () over(PARTITION by f.patient_guid,f.laterality_code order by cataract_date ASC) as rank

from #final_cohort f
join #all_cataract ac
    on f.patient_guid=ac.patient_guid and f.laterality_code=ac.laterality_code and f.PostOP_treatment_date=ac.cataract_date
)
select f.*,
concurrent_cataract_gonio_date,
concurrent_cataract_gonio_code,
concurrent_cataract_PostOp_date,
concurrent_cataract_PostOp_code

from #final_cohort f
left join ( select * from concurrent_cataract_gonio where rank =1) g on f.patient_guid=g.patient_guid and g.laterality_code=f.laterality_code
left join (select * from concurrent_catract_PostOp where rank=1) c on f.patient_guid=c.patient_guid and g.laterality_code=c.laterality_code
;



-------------------------------------- save progress

-- 2/26/2026 - Xen cases as 66183
-- 12/31/2025 - Using new IRIS db . nb no 'Xen cases'
-- 10/29/2025- fix date filter on IOP pre treatment

DROP TABLE IF EXISTS public.Gonio_final_cohort_cataract;
create table public.Gonio_final_cohort_cataract (like #final_cohort_cataract);
insert into public.Gonio_final_cohort_cataract
select * from #final_cohort_cataract;

-- select * from Gonio_final_cohort_cataract

-- select PostOP_treatment, count(*)as n from Gonio_final_cohort_cataract group by PostOP_treatment;


-- select PostOP_treatment, count(*)as n from #final_cohort_cataract group by PostOP_treatment;


---------------------------------------------------------


-- Part 2

-- SELECT
--     distinct vh_generic_name,vh_class_name,vh_rxcui

-- FROM
--     "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_medication"
-- --   where  ndc_id= '7072749725'
-- -- where medication_class like '%netarsudil%' or vh_brand_name like '%netarsudil%' or vh_generic_name like '%netarsudil%'
-- where
-- vh_generic_name  ILIKE '%Aspirin%'

-- select * from "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_medication"
-- -- where vh_generic_name like '%bivalirudin%'
--  where vh_class_name= 'Thrombin Inhibitor - Selective Direct and Reversible'
-- ;



DROP TABLE IF EXISTS #meds_antiplatelet;
CREATE TABLE #meds_antiplatelet AS
SELECT
    distinct vh_generic_name,vh_class_name,vh_rxcui,ndc_id --vh_medication_code

FROM
    "iris_registry_data_ccl_images_filtered"."iris_registry_data_ccl_images_filtered"."patient_medication"

where
(vh_generic_name  ILIKE '%Aspirin%' OR vh_generic_name  ILIKE '%clopidogrel%' OR
vh_generic_name  ILIKE '%Ticagrelor%' OR vh_generic_name  ILIKE '%prasugrel%')
AND vh_class_name ILIKE 'Platelet%'
;


DROP TABLE IF EXISTS #meds_anticoagulant;
CREATE TABLE #meds_anticoagulant AS
SELECT
    distinct vh_generic_name,vh_class_name,vh_rxcui,ndc_id

FROM
    "iris_registry_data_ccl_images_filtered"."iris_registry_data_ccl_images_filtered"."patient_medication"
where
(vh_generic_name  ILIKE '%Warfarin%' OR vh_generic_name  ILIKE '%Apixaban%'  OR
vh_generic_name  ILIKE '%Enoxaparin%' OR vh_generic_name  ILIKE '%Dabigatran%' OR
vh_generic_name  ILIKE '%Rivaroxaban%' OR vh_generic_name  ILIKE '%edoxaban%'OR
vh_generic_name  ILIKE '%dalteparin%' OR vh_generic_name  ILIKE '%fondaparinux%' OR
vh_generic_name  ILIKE '%argatroban%' OR vh_generic_name  ILIKE '%bivalirudin%' OR
vh_generic_name  ILIKE '%argatroban%' OR vh_generic_name  ILIKE '%bivalirudin%' OR
vh_generic_name  ILIKE '%desirudin%'
)
-- AND vh_class_name ILIKE 'anticoagulants%'
;



DROP TABLE IF EXISTS #meds_combined;
CREATE TABLE #meds_combined AS
with anti_p AS
(
    select *,
            'Antiplatelet' as grp
    from #meds_antiplatelet
),
anti_c as
(
    select *,
            'Anticoagulant' as grp
    from #meds_anticoagulant
),
combined AS
(
    select * from anti_p --where vh_rxcui is not NULL

    union ALL

    select * from anti_c --where vh_rxcui is not NULL
)
select * from combined
;



DROP TABLE IF EXISTS #med_history;
CREATE TABLE #med_history AS
with outerOrders as
(
select pt.patient_guid,
       pt.laterality_code,
        pt.gonio_sx_date,
        meds.grp,
        m.start_date,m.stop_date,m.dispense_date,m.effective_date,m.expiration_date,m.anatomical_location,m.vh_route,
        ROW_NUMBER () over(PARTITION by pt.patient_guid,pt.laterality_code,meds.grp order by m.start_date DESC) as rank

from ( select patient_guid,laterality_code,gonio_sx_date from Gonio_final_cohort_cataract) pt
join
   "iris_registry_data_ccl_images_filtered"."iris_registry_data_ccl_images_filtered"."patient_medication" m
   --"iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_medication" m
    on m.patient_guid=pt.patient_guid
join #meds_combined meds
    on meds.vh_rxcui=m.vh_rxcui
    -- on meds.ndc_id=m.ndc_id

where m.start_date<pt.gonio_sx_date
)
select * from outerOrders where rank=1
;

---------------------------------------------



-- select count(*) from #med_history; --17187

-- select * from #med_history;

-- DROP TABLE IF EXISTS #med_history_wide;
-- CREATE TABLE #med_history_wide AS
-- select patient_guid,
--   MAX(CASE WHEN grp = 'Antiplatelet' THEN 1 ELSE 0 END) AS has_antiplatelet,
--   MAX(CASE WHEN grp = 'Anticoagulant' THEN 1 ELSE 0 END) AS has_anticoagulant
-- FROM #med_history
-- GROUP BY patient_guid;

-- select count(*) from #med_history_wide; -- 15196
-- select count(distinct patient_guid) from #med_history_wide; --15196

-- select * from #med_history_wide;


DROP TABLE IF EXISTS #final_cohort_cataract_meds;
CREATE TABLE #final_cohort_cataract_meds AS
SELECT
  e.*,
  antiplatelet_date,
  anticoagulant_date
FROM Gonio_final_cohort_cataract e
LEFT JOIN (select patient_guid,
                MAX(CASE WHEN grp = 'Antiplatelet' THEN start_date ELSE null END) AS antiplatelet_date,
                MAX(CASE WHEN grp = 'Anticoagulant' THEN start_date ELSE null END) AS anticoagulant_date
        FROM #med_history
GROUP BY patient_guid) m
on m.patient_guid= e.patient_guid
;

-- select count(*) from Gonio_final_cohort_cataract where PostOp_treatment_date is not null;

-- select patient_guid, laterality_code,antiplatelet_date,anticoagulant_date from #final_cohort_cataract_meds order by patient_guid, laterality_code

-- SELECT COUNT(*)  from #final_cohort_cataract_meds ; --237522
-- select count(distinct patient_guid) from #final_cohort_cataract_meds; --159040
-- SELECT COUNT(DISTINCT patient_guid || '-' || laterality_code)  from #final_cohort_cataract_meds;--237459

-- select laterality_code, count(laterality_code) as n from #final_cohort_cataract_meds group by laterality_code;
-- 1	118704
-- 2	118818


-- select count(*) as N from #final_cohort_cataract_meds where antiplatelet_date is not null; --13999
-- select count(*) as N from #final_cohort_cataract_meds where anticoagulant_date is not null; --9099

------------------- failure



-- These use 2 consecutive visits

DROP TABLE IF EXISTS #iop_fail_high ;
CREATE TABLE #iop_fail_high  AS
WITH second_sx_pt AS (
    SELECT *
    FROM Gonio_final_cohort_cataract
    WHERE PostOp_treatment_date IS NOT NULL
),
all_iop as(
select patient_guid,laterality_code,result_date, AVG(result_value) as daily_mean_iop
from "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_iop" iop
where patient_guid in (select patient_guid from second_sx_pt )
group by patient_guid,laterality_code,result_date
),
iop_after_sx AS (
    SELECT
        pt.patient_guid,
        pt.laterality_code,
        pt.PostOp_treatment_date,
        iop.result_date,
        iop.daily_mean_iop,
        LAG(iop.daily_mean_iop) OVER (
            PARTITION BY pt.patient_guid, pt.laterality_code
            ORDER BY iop.result_date
        ) AS prev_iop_value
    FROM second_sx_pt pt
    JOIN all_iop iop
        ON pt.patient_guid = iop.patient_guid
        AND pt.laterality_code = iop.laterality_code
    WHERE iop.result_date >= DATEADD(DAY, 90, pt.PostOp_treatment_date)
),

high_iop_failures AS (
    SELECT *,
        CASE
            WHEN daily_mean_iop > 21 AND prev_iop_value > 21 THEN 1
            ELSE 0
        END AS high_iop_failure
    FROM iop_after_sx
),
ranked as(
-- Return only the second visit where failure occurred
SELECT
    patient_guid,
    laterality_code,
    PostOp_treatment_date,
    result_date,
    daily_mean_iop,
    -- high_iop_failure,
    DATEDIFF(DAY, PostOp_treatment_date, result_date) AS high_iop_failure_days,
    ROW_NUMBER () over(PARTITION by patient_guid,laterality_code order by result_date) as rank
FROM high_iop_failures
WHERE high_iop_failure = 1
)
select * from ranked where rank=1
;




DROP TABLE IF EXISTS #iop_fail_low ;
CREATE TABLE #iop_fail_low  AS
WITH second_sx_pt AS (
    SELECT *
    FROM Gonio_final_cohort_cataract
    WHERE PostOp_treatment_date IS NOT NULL
),
all_iop as(
select patient_guid,laterality_code,result_date, AVG(result_value) as daily_mean_iop
from "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_iop" iop
where patient_guid in (select patient_guid from second_sx_pt )
group by patient_guid,laterality_code,result_date
),
iop_after_sx AS (
    SELECT
        pt.patient_guid,
        pt.laterality_code,
        pt.PostOp_treatment_date,
        iop.result_date,
        iop.daily_mean_iop,
        LAG(iop.daily_mean_iop) OVER (
            PARTITION BY pt.patient_guid, pt.laterality_code
            ORDER BY iop.result_date
        ) AS prev_iop_value
    FROM second_sx_pt pt
    JOIN all_iop iop
        ON pt.patient_guid = iop.patient_guid
        AND pt.laterality_code = iop.laterality_code
    WHERE iop.result_date >= DATEADD(DAY, 90, pt.PostOp_treatment_date)
),

iop_failures AS (
    SELECT *,
        CASE
            WHEN daily_mean_iop < 6 AND prev_iop_value < 6 THEN 1
            ELSE 0
        END AS low_iop_failure
    FROM iop_after_sx
),
ranked as(
-- Return only the second visit where failure occurred
SELECT
    patient_guid,
    laterality_code,
    PostOp_treatment_date,
    result_date,
    daily_mean_iop,
    -- high_iop_failure,
    DATEDIFF(DAY, PostOp_treatment_date, result_date) AS low_iop_failure_days,
    ROW_NUMBER () over(PARTITION by patient_guid,laterality_code order by result_date) as rank
FROM iop_failures
WHERE low_iop_failure = 1
)
select * from ranked where rank=1
;


DROP TABLE IF EXISTS #iop_fail_reduction ;
CREATE TABLE #iop_fail_reduction  AS
WITH second_sx_pt AS (
    SELECT *
    FROM Gonio_final_cohort_cataract
    WHERE PostOp_treatment_date IS NOT NULL
),
all_iop as(
select patient_guid,laterality_code,result_date, AVG(result_value) as daily_mean_iop
from "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_iop" iop
where patient_guid in (select patient_guid from second_sx_pt )
group by patient_guid,laterality_code,result_date
),
iop_after_sx AS (
    SELECT
        pt.patient_guid,
        pt.laterality_code,
        pt.PostOp_treatment_date,
        iop.result_date,
        iop.daily_mean_iop,
        DATEDIFF(DAY, PostOp_treatment_date,result_date) AS failure_days,
        ((pt.IOP_pre_pre_treatment - iop.daily_mean_iop) * 1.0) / NULLIF(pt.IOP_pre_pre_treatment, 0) AS reduction
    FROM second_sx_pt pt
    JOIN all_iop iop
        ON pt.patient_guid = iop.patient_guid
        AND pt.laterality_code = iop.laterality_code
    WHERE
        --  iop.result_date > pt.PostOp_treatment_date --DATEADD(DAY, 90, pt.PostOp_treatment_date)
          iop.result_date >= DATEADD(DAY, 90, pt.PostOp_treatment_date)
      and ((pt.IOP_pre_pre_treatment - iop.daily_mean_iop) * 1.0) / NULLIF(pt.IOP_pre_pre_treatment, 0)  < 0.20
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY patient_guid, laterality_code
            ORDER BY result_date
        ) AS rank
    FROM iop_after_sx
)
SELECT *
FROM ranked
WHERE rank = 1;



-- select i.*, g.IOP_pre_pre_treatment, g.IOP_pre_pre_treatment*0.8 as target_iop from #iop_fail_reduction i
-- join Gonio_final_cohort_cataract g on i.patient_guid=g.patient_guid and i.laterality_code=g.laterality_code
--     WHERE g.PostOp_treatment_date IS NOT NULL
-- order by patient_guid, laterality_code, result_date



DROP TABLE IF EXISTS #va_fail_nlp;
CREATE TABLE #va_fail_nlp AS
WITH second_sx_pt AS (
    SELECT *
    FROM Gonio_final_cohort_cataract
    WHERE PostOp_treatment_date IS NOT NULL
),
va_matches AS (
    SELECT
        va.patient_guid,
        va.laterality_code,
        va.result_date,
        va.result_value,
        va.calculated_logmar,
        pt.PostOp_treatment_date,
          LAG(va.calculated_logmar) OVER (
            PARTITION BY va.patient_guid, va.laterality_code
            ORDER BY va.result_date
        ) AS prev_va_value
    FROM iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_va va
    join second_sx_pt pt on pt.patient_guid=va.patient_guid and pt.laterality_code=va.laterality_code
    and va.calculated_logmar =4
    and va.result_date > pt.PostOp_treatment_date
),
NLP_failures as (
    SELECT *,
        CASE
            WHEN calculated_logmar = 4 AND prev_va_value=  4 THEN 1
            ELSE 0
        END AS nlp_failure
    FROM va_matches
),
ranked AS (
    SELECT
        patient_guid,
        laterality_code,
        PostOp_treatment_date,
        result_date AS failure_date,
        calculated_logmar,
        result_value,
        DATEDIFF(DAY, PostOp_treatment_date, result_date) AS failure_days,
        ROW_NUMBER() OVER (
            PARTITION BY patient_guid, laterality_code
            ORDER BY result_date
        ) AS rank
    FROM NLP_failures
    WHERE nlp_failure = 1
)
SELECT *
FROM ranked
WHERE rank = 1;

-- select * from #va_fail_nlp order by patient_guid, laterality_code, failure_date


DROP TABLE IF EXISTS #reop_fail;
CREATE TABLE #reop_fail AS
WITH second_sx_pt AS (
    SELECT *
    FROM Gonio_final_cohort_cataract
    WHERE PostOp_treatment_date IS NOT NULL
),
reop_proc as (
SELECT
    proc.patient_guid,
    proc.laterality_code,
    -- proc.patient_visit_id,
    proc.procedure_date,
    proc.procedure_code,
    -- proc.laterality_code_description as exclusion_sx_laterality_code_desc,
    Case
        when proc.procedure_code  in ('66179', '66180') then 'Aqueous Shunt' -- '66183'
        When proc.procedure_code  in ('66170', '66172') then 'Trabeculectomy'
        When proc.procedure_code  in ('66710', '66711', '66987', '66988') then 'Cyclophotocoagulation'
        when proc.procedure_code in ('0449T', '0450T','66183') then 'Xen implantation'
        else 'Revision surgery'
    end as reoperation_grp

FROM iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_procedure proc
join second_sx_pt pt on pt.patient_guid=proc.patient_guid and pt.laterality_code=proc.laterality_code
WHERE
proc.procedure_code IN ('66179', '66180', '66183',
                        '66170', '66172',
                        '66710', '66711', '66987', '66988','66250','0449T', '0450T') and proc.laterality_code<>'4'
),
reop_after_sx AS (
    SELECT
        pt.patient_guid,
        pt.laterality_code,
        pt.PostOp_treatment_date,
        proc.procedure_date AS failure_date,
         proc.procedure_code  as failure_code,
         reoperation_grp
    FROM second_sx_pt pt
    JOIN reop_proc proc
        ON pt.patient_guid = proc.patient_guid
        AND pt.laterality_code = proc.laterality_code
    WHERE proc.procedure_date > pt.PostOp_treatment_date
),
ranked AS (
    SELECT *,
        DATEDIFF(DAY, PostOp_treatment_date, failure_date) AS failure_days,
        ROW_NUMBER() OVER (
            PARTITION BY patient_guid, laterality_code, reoperation_grp
            ORDER BY failure_date
        ) AS rank_grp,
        ROW_NUMBER() OVER (
            PARTITION BY patient_guid, laterality_code
            ORDER BY failure_date
        ) AS rank
    FROM reop_after_sx
)
SELECT *
FROM ranked
WHERE rank_grp = 1;


-- select count(distinct patient_guid) from "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_procedure" where  procedure_code='66183' and patient_guid in (select patient_guid from #qualified_cases )
-- select reoperation_grp, count(*) as n from #reop_fail group by reoperation_grp;


DROP TABLE IF EXISTS #reop_fail_r;
CREATE TABLE #reop_fail_r AS
SELECT  patient_guid,
    laterality_code,
    failure_date AS reop_failure_date,
    failure_code AS reop_failure_code,
    reoperation_grp,
    failure_days as reop_failure_days,
    rank_grp AS reop_rank_grp,
    rank AS reop_rank
from #reop_fail;




-- add IOP criteria 11/24/2025-- wrong interpretation
-- DROP TABLE IF EXISTS #reop_fail_r_iop ;
-- CREATE TABLE #reop_fail_r_iop  AS
-- WITH reop_pts  AS (
--     SELECT *
--     FROM #reop_fail_r
-- ),
-- all_iop as(
-- select patient_guid,laterality_code,result_date, AVG(result_value) as daily_mean_iop
-- from "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_iop" iop
-- where patient_guid in (select patient_guid from reop_pts  )
-- group by patient_guid,laterality_code,result_date
-- ),
-- iop_after_sx AS (
--     SELECT
--         pt.*,
--         iop.result_date,
--         iop.daily_mean_iop,
--         DATEDIFF(DAY, reop_failure_date,result_date) AS failure_days_iop
--     FROM reop_pts  pt
--     JOIN all_iop iop
--         ON pt.patient_guid = iop.patient_guid
--         AND pt.laterality_code = iop.laterality_code
--     WHERE
--         --  iop.result_date > pt.PostOp_treatment_date --DATEADD(DAY, 90, pt.PostOp_treatment_date)
--          iop.result_date between DATEADD(DAY, -7, pt.reop_failure_date) and pt.reop_failure_date
--          AND iop.daily_mean_iop > 21
--   ),
-- ranked AS (
--     SELECT *,
--         ROW_NUMBER() OVER (
--             PARTITION BY patient_guid, laterality_code
--             ORDER BY result_date DESC
--         ) AS rank
--     FROM iop_after_sx
-- )
-- SELECT *
-- FROM ranked
-- WHERE rank = 1;


-- select * from #reop_fail_r

-- select count(*) from #reop_fail_r_iop;

---combine failures

-- Select * from #iop_fail_high ;
-- Select * from #iop_fail_low;
-- Select * from #iop_fail_reduction ;
-- Select * from #va_fail_nlp;
-- Select * from #reop_fail order by patient_guid,laterality_code,rank;



DROP TABLE IF EXISTS #final_failures;
CREATE TABLE #final_failures AS
select f.*,
       h.high_iop_failure_days,
       l.low_iop_failure_days,
       r.failure_days as reduction_failure_days,
       n.failure_days as nlp_failure_days
from (select distinct patient_guid, laterality_code  from #final_cohort_cataract_meds where PostOp_treatment_date is not null)  f
left join #iop_fail_high h on h.patient_guid=f.patient_guid and h.laterality_code=f.laterality_code
left join #iop_fail_low l on l.patient_guid=f.patient_guid and l.laterality_code=f.laterality_code
left join #iop_fail_reduction r on r.patient_guid=f.patient_guid and r.laterality_code=f.laterality_code
left join #va_fail_nlp n on n.patient_guid=f.patient_guid and n.laterality_code=f.laterality_code
;




----------------------------------------------------patients
DROP TABLE IF EXISTS #final_cohort_cataract_meds_fu; --
CREATE TABLE #final_cohort_cataract_meds_fu AS
WITH latest_visits AS (
    SELECT
        v.patient_guid,
        MAX(v.visit_date) AS follow_up_date  -- Get the latest visit date per patient
    FROM iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_visit_location v
    where patient_guid in (SELECT distinct patient_guid FROM #final_cohort_cataract_meds)
    GROUP BY v.patient_guid
)
select c.*,
      v.follow_up_date,
(v.follow_up_date - c.condition_date ) AS FU

from #final_cohort_cataract_meds c
join latest_visits v on v.patient_guid=c.patient_guid;


-- select count(*) from #final_cohort_cataract_meds_fu; -- 237522
-- select count(distinct patient_guid) from #final_cohort_cataract_meds_fu; --159040
-- SELECT COUNT(DISTINCT CONCAT(patient_guid, laterality_code)) from #final_cohort_cataract_meds_fu; -- 237459
-- select laterality_code, count(laterality_code) as N from #final_cohort_cataract_meds_fu group by laterality_code;
-- 2	118818
-- 1	118704



DROP TABLE IF EXISTS #patients;
CREATE TABLE #patients AS
SELECT
    *
FROM
    iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient
    where patient_guid IN (SELECT distinct patient_guid FROM #final_cohort_cataract_meds);



DROP TABLE IF EXISTS public.Gonio_pt_demo;
create table public.Gonio_pt_demo (like #patients);
insert into public.Gonio_pt_demo
select * from #patients;


-- WITH duplicated AS (
--             SELECT patient_guid, laterality_code
--             FROM #final_cohort_cataract_meds_failures
--             GROUP BY patient_guid, laterality_code
--             HAVING COUNT(*) > 1
-- )
--         SELECT *
--         FROM #final_cohort_cataract_meds_failures
--         WHERE patient_guid IN (SELECT patient_guid FROM duplicated);
--        order by patient_guid,laterality_code


-- select count(*) from #final_failures; -- 1134
-- select count(distinct patient_guid) from #final_failures; --1123
-- SELECT COUNT(DISTINCT CONCAT(patient_guid, laterality_code)) from #final_failures; -- 1134
-- select laterality_code, count(laterality_code) as N from #final_failures group by laterality_code;
-- 2	557
-- 1	577

DROP TABLE IF EXISTS public.Gonio_final_cohort_cataract_meds_fu;
create table public.Gonio_final_cohort_cataract_meds_fu (like #final_cohort_cataract_meds_fu);
insert into public.Gonio_final_cohort_cataract_meds_fu
select * from #final_cohort_cataract_meds_fu;


DROP TABLE IF EXISTS public.Gonio_final_failures;
create table public.Gonio_final_failures (like #final_failures);
insert into public.Gonio_final_failures
select * from #final_failures;


DROP TABLE IF EXISTS public.Gonio_reop_fail;
create table public.Gonio_reop_fail (like #reop_fail_r);
insert into public.Gonio_reop_fail
select * from #reop_fail_r;

-- select count(*) from #reop_fail_r; -- 262
-- select count(distinct patient_guid) from #reop_fail_r; --229
-- SELECT COUNT(DISTINCT CONCAT(patient_guid, laterality_code)) from #reop_fail_r; -- 231








--- 10/27/2025


DROP TABLE IF EXISTS #rapid_reop_eyes;
CREATE TABLE #rapid_reop_eyes AS
select * from Gonio_final_cohort_cataract_meds_fu
where postop_treatment_date is not null
qualify (ROW_NUMBER() OVER (PARTITION BY patient_guid,laterality_code ORDER BY days_post_op ASC))=1;


-- select count(*) from #rapid_reop_eyes; -- 1081
-- select count(distinct patient_guid) from #rapid_reop_eyes; --1070
-- SELECT COUNT(DISTINCT CONCAT(patient_guid, laterality_code)) from #rapid_reop_eyes; -- 1081



-- WITH duplicated AS (
--             SELECT patient_guid, laterality_code
--             FROM #rapid_reop_eyes
--             GROUP BY patient_guid, laterality_code
--             HAVING COUNT(*) > 1
-- )
--         SELECT *
--         FROM #rapid_reop_eyes
--         WHERE patient_guid IN (SELECT patient_guid FROM duplicated)
--        order by patient_guid,laterality_code
--        ;

DROP TABLE IF EXISTS #rapid_reop_eyes_Hyphema;
CREATE TABLE #rapid_reop_eyes_Hyphema AS
with alldx as (
    SELECT
    pt.patient_guid,
    c.laterality_code,
    c.condition_date,
    c.condition_code,
    c.condition_code_description
  FROM (SELECT patient_guid FROM #rapid_reop_eyes) pt
left join iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_condition c
    on pt.patient_guid=c.patient_guid
where  (  c.condition_code LIKE 'H21.0%'
       )
),
specified AS (
    SELECT DISTINCT patient_guid, laterality_code, condition_date, condition_code,condition_code_description
    FROM alldx
    WHERE laterality_code IS NOT NULL AND laterality_code <> '4'
),
unspecified AS (
    SELECT DISTINCT patient_guid, laterality_code, condition_date, condition_code,condition_code_description
    FROM alldx
    WHERE laterality_code IS NULL OR laterality_code = '4'
),
-- unspecified records that have a specified same-day for same patient (drop these)
unspec_with_spec_same_day AS (
    SELECT u.patient_guid, u.condition_date
    FROM unspecified u
    JOIN specified s
      ON s.patient_guid = u.patient_guid
     AND s.condition_date = u.condition_date
    GROUP BY u.patient_guid, u.condition_date
),
kept_unspecified AS (
    SELECT u.*
    FROM unspecified u
    LEFT JOIN unspec_with_spec_same_day dropme
      ON dropme.patient_guid = u.patient_guid
     AND dropme.condition_date = u.condition_date
    WHERE dropme.patient_guid IS NULL
),
all_kept AS (
    SELECT * FROM specified
    UNION ALL
    SELECT * FROM kept_unspecified
),
join_all as (
    select e.*,k.condition_date,k.condition_code,k.condition_code_description,k.laterality_code as hyphema_laterality_code,

    ABS(DATEDIFF(DAY, e.postop_treatment_date, k.condition_date)) AS days_to_dx

    from  (select patient_guid,laterality_code,gonio_sx_date,postop_treatment_date,postop_treatment_cpt,postop_treatment from #rapid_reop_eyes) e
    join all_kept k
        on k.patient_guid=e.patient_guid
    where k.laterality_code=e.laterality_code OR k.laterality_code='4'
)
SELECT *
FROM join_all
where patient_guid is not null
QUALIFY (ROW_NUMBER() OVER (
  PARTITION BY patient_guid, laterality_code
  ORDER BY days_to_dx ASC
)) = 1
;


-- select count(*) from #rapid_reop_eyes_Hyphema; -- 322
-- select count(distinct patient_guid) from #rapid_reop_eyes_Hyphema; --322
-- SELECT COUNT(DISTINCT CONCAT(patient_guid, laterality_code)) from #rapid_reop_eyes_Hyphema; -- 322

-- select hyphema_laterality_code, count(*)as n from #rapid_reop_eyes_Hyphema group by hyphema_laterality_code;


DROP TABLE IF EXISTS #rapid_reop_eyes_Hyphema_r; -- reduced to only those within the timeframe
CREATE TABLE #rapid_reop_eyes_Hyphema_r AS
select * from #rapid_reop_eyes_Hyphema where days_to_dx=0 OR condition_date between gonio_sx_date and postop_treatment_date
;

-- select count(*) from #rapid_reop_eyes_Hyphema_r; -- 257
-- select count(distinct patient_guid) from #rapid_reop_eyes_Hyphema_r; --257
-- SELECT COUNT(DISTINCT CONCAT(patient_guid, laterality_code)) from #rapid_reop_eyes_Hyphema_r; -- 257



DROP TABLE IF EXISTS public.Gonio_rapid_reop_eyes_Hyphema;
create table public.Gonio_rapid_reop_eyes_Hyphema (like #rapid_reop_eyes_Hyphema_r);
insert into public.Gonio_rapid_reop_eyes_Hyphema
select * from #rapid_reop_eyes_Hyphema_r;


------------- export 8/11/2025

-- 10/29/2025 redo all to account for IOP reduction miscalculation

--11/24/2025 rerun to get iop beween gonio and rapid reop (exlcusive) + add 66250 as failure reop

-- 06/16/2026 correct Xen cpt 0499T to 0449T

CALL unload_to_s3_folder('Gonio_final_cohort_cataract_meds_fu','20_Goniotomy');
CALL unload_to_s3_folder('Gonio_pt_demo','20_Goniotomy');
CALL unload_to_s3_folder('Gonio_final_failures','20_Goniotomy');
CALL unload_to_s3_folder('Gonio_reop_fail','20_Goniotomy');

--10/27/2025
CALL unload_to_s3_folder('Gonio_rapid_reop_eyes_Hyphema','20_Goniotomy');


--revisions


------------------- redo IOP data



DROP TABLE IF EXISTS #Baseline_IOP;
CREATE TABLE #Baseline_IOP AS
with reduced_cohort as ( -- filter out missing data patient
select c.*,pt.race,pt.sex,pt.ethnicity,

case
    when postop_treatment_date is null then 0
    else 1
    end as had_second_sx

from Gonio_final_cohort_cataract_meds_fu  c
join Gonio_pt_demo pt
on c.patient_guid=pt.patient_guid

where (pt.race<>'Unknown' and pt.ethnicity<>'Unknown' and pt.sex<>'Unknown')
and ( (postop_treatment_date is null and FU>90) or  (postop_treatment_date is not null and iop_pre_pre_treatment is not null) )

),
Eyedata_IOP_all as (
select iop.patient_guid,
    iop.laterality_code,
    iop.result_date as IOP_date,
    iop.result_value as IOP,
    iop.result_unit,
    iop.practice_guid,
    iop.provider_guid
from (select distinct patient_guid from reduced_cohort) cohort
inner join "iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_iop" iop
    on iop.patient_guid=cohort.patient_guid
),
all_iop as (
select e.patient_guid,e.laterality_code,condition_date, gonio_sx_date,IOP_date,IOP,result_unit,
DATEDIFF(DAY, gonio_sx_date, IOP_date) as interval_sx_iop,
    ROW_NUMBER () over(PARTITION by e.patient_guid,e.laterality_code order by  ABS(DATEDIFF(DAY, gonio_sx_date, IOP_date)) ASC) as Closest_IOP_rank

from reduced_cohort  c
join Eyedata_IOP_all  e
    on e.patient_guid=c.patient_guid and e.laterality_code=c.laterality_code --and c.condition_date =e.IOP_date
where IOP_date BETWEEN DATEADD(DAY, -90, gonio_sx_date)
                              AND gonio_sx_date

)
select pt.patient_guid,pt.laterality_code,pt.condition_date,pt.gonio_sx_date,
       iop.IOP_date,iop.IOP,iop.result_unit,iop.interval_sx_iop
from reduced_cohort pt
left join (select * from all_iop where Closest_IOP_rank=1) iop
on pt.patient_guid=iop.patient_guid and pt.laterality_code=iop.laterality_code
;

--- unload

CALL unload_to_s3_folder_sql_to_parquet(
    $$
    select *
from #Baseline_IOP
    $$,
    '20_Goniotomy',
    'update_baseline_iop'
);



------ sensitivity analysis


-- 3--- find repeat gonio
DROP TABLE IF EXISTS #repeat_gonio;
CREATE TABLE #repeat_gonio AS
WITH repeat_gonio AS (

SELECT
    i.patient_guid,
    i.laterality_code,
    i.gonio_sx_date AS index_date,

    MAX(
        CASE
            WHEN p.procedure_date > i.gonio_sx_date
             AND p.procedure_date <= DATEADD(day, 42, i.gonio_sx_date)
            THEN 1 ELSE 0
        END
    ) AS repeat_gonio_6wk,

    MAX(
        CASE
            WHEN p.procedure_date > i.gonio_sx_date
            THEN 1 ELSE 0
        END
    ) AS repeat_gonio_ever,

    MIN(
        CASE
            WHEN p.procedure_date > i.gonio_sx_date
            THEN p.procedure_date
        END
    ) AS first_repeat_date

FROM Gonio_final_cohort_cataract_meds_fu i

LEFT JOIN iris_registry_data_ccl_filtered_10_2025
    .iris_registry_data_ccl_filtered_10_2025.patient_procedure p
ON i.patient_guid = p.patient_guid
AND i.laterality_code = p.laterality_code
AND p.procedure_code IN ('65820','66174')

GROUP BY
    i.patient_guid,
    i.laterality_code,
    i.gonio_sx_date

)
select * from repeat_gonio
;

-- select * from #repeat_gonio;


SELECT
    SUM(repeat_gonio_6wk) AS repeat_within_6wk,
    SUM(repeat_gonio_ever) AS repeat_ever,
    COUNT(*) AS total_cases
FROM #repeat_gonio;



CALL unload_to_s3_folder_sql_to_parquet(
    $$
    select *
from #repeat_gonio
    $$,
    '20_Goniotomy',
    'reop_gonio'
);



----------------4 -- get missing laterality patients

-- select distinct laterality_code from iris_registry_data_ccl_filtered_10_2025
--     .iris_registry_data_ccl_filtered_10_2025.patient_procedure

-- select * from iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient ;

DROP TABLE IF EXISTS #excluded_missing_laterality;
CREATE TABLE #excluded_missing_laterality AS
with all_pt as (
SELECT
    p.patient_guid,
    pt.birth_year,
    EXTRACT(YEAR FROM p.procedure_date) - pt.birth_year AS age,
    pt.sex,pt.race,pt.ethnicity,
    p.procedure_date,
    p.procedure_code,
    p.laterality_code,
    p.laterality_code_description
FROM iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_procedure p
LEFT JOIN iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient pt
    ON pt.patient_guid = p.patient_guid
WHERE p.procedure_code IN ('66174','65820')
  AND p.laterality_code = 4
qualify (ROW_NUMBER() OVER (PARTITION BY p.patient_guid,laterality_code ORDER BY procedure_date ASC))=1
),
all_cataract as (
SELECT  distinct
    proc.patient_guid,
    -- proc.patient_visit_id,
    proc.procedure_date as cataract_date,
    proc.procedure_code as cataract_code,
    -- proc.procedure_code_system as,
    -- proc.procedure_code_description as exclusion_sx_code_desc,
    -- proc.modifier_1_code,
    -- proc.modifier_2_code,
    -- proc.modifier_3_code,
    -- proc.modifier_4_code,
    proc.laterality_code as laterality_code
    -- proc.laterality_code_description as exclusion_sx_laterality_code_desc,

FROM (select distinct patient_guid from all_pt) fdx
 join   iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_procedure proc
    on proc.patient_guid=fdx.patient_guid
WHERE
proc.procedure_code IN ('66984','66982')  -- there are no bilateral cases
),
join_tables as (
select a.*,c.cataract_date,c.cataract_code

from all_pt a
inner join all_cataract c
     on c.patient_guid=a.patient_guid
where c.cataract_date=a.procedure_date
qualify (ROW_NUMBER() OVER (PARTITION BY a.patient_guid,a.laterality_code ORDER BY c.laterality_code ASC))=1
)
select a.*,c.cataract_date,c.cataract_code

from all_pt a
left join join_tables c
on c.patient_guid=a.patient_guid
and a.laterality_code=c.laterality_code
;

-- select * from #excluded_missing_laterality ;

-- select count(*) from #excluded_missing_laterality; --23319
-- select count(distinct patient_guid) from #excluded_missing_laterality; --23319



DROP TABLE IF EXISTS #alldx; --
CREATE TABLE #alldx AS
with all_dx as (
SELECT
    c.patient_guid,
    pt.birth_year,
    c.condition_date,
    c.condition_code,
    c.condition_code_description,
    c.laterality_code,
    c.laterality_code_description,
    p.practice_state,
    p.practice_zip5,
    prov.provider_type,
    prov.provider_subspecialty_1,
    prov.provider_subspecialty_2,
    prov.provider_subspecialty_3,
    EXTRACT(YEAR FROM c.condition_date) - pt.birth_year as AgeAtDx
FROM
    iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient_condition c
inner join #excluded_missing_laterality cpt on cpt.patient_guid= c.patient_guid
LEFT JOIN
    (SELECT patient_guid, birth_year FROM iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.patient) pt
    ON pt.patient_guid = c.patient_guid
left join iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.practice p
    on p.practice_guid=c.practice_guid
left join iris_registry_data_ccl_filtered_10_2025.iris_registry_data_ccl_filtered_10_2025.provider prov
    on prov.provider_guid=c.provider_guid
WHERE
    -- Inclusion criteria: macular hole diagnosis for patients under 18
    c.condition_code like 'H40.1%'
    AND (EXTRACT(YEAR FROM c.condition_date) - pt.birth_year) >= 18
)
select e.*,a.condition_date,a.condition_code

from #excluded_missing_laterality e
inner join all_dx a on e.patient_guid=a.patient_guid
where a.condition_date between DATEADD(DAY, -90, a.condition_date )
                    AND  a.condition_date
qualify (ROW_NUMBER() OVER (PARTITION BY e.patient_guid ORDER BY procedure_date DESC ))=1
;


-- select count(*) from #alldx; --21104

-- select count(distinct patient_guid) from #alldx;     --21104



DROP TABLE IF EXISTS #glaucoma_codes;
CREATE TABLE #glaucoma_codes AS
with allcodes as (
select distinct condition_code from #alldx
)
SELECT
    condition_code,
    -- Glaucoma Type Classification
    CASE
        WHEN condition_code LIKE 'H40.10%' THEN 'Unspecified open-angle glaucoma'
        WHEN condition_code LIKE 'H40.11%' THEN 'Primary open-angle glaucoma'
        WHEN condition_code LIKE 'H40.12%' THEN 'Low-tension glaucoma'
        WHEN condition_code LIKE 'H40.13%' THEN 'Pigmentary glaucoma'
        WHEN condition_code LIKE 'H40.14%' THEN 'Capsular glaucoma with pseudo-exfoliation of lens'
        WHEN condition_code LIKE 'H40.15%' THEN 'Residual stage of open-angle glaucoma'
        ELSE 'Other glaucoma'
    END AS glaucoma_type,

    -- Laterality Classification
    CASE
        WHEN condition_code LIKE 'H40.10%' THEN 'Unspecified'
        WHEN SUBSTRING(condition_code, 7, 1) = '1' THEN 'Right'
        WHEN SUBSTRING(condition_code, 7, 1) = '2' THEN 'Left'
        WHEN SUBSTRING(condition_code, 7, 1) = '3' THEN 'Bilateral'
        ELSE 'Unspecified'
    END AS laterality,

    -- Severity Staging
    CASE
        -- Handle residual glaucoma first (no staging)
        WHEN condition_code LIKE 'H40.15%' THEN 'No stage indicated'

        -- For other types with complete 7-character codes
        WHEN LEN(condition_code) = 8 THEN
            CASE SUBSTRING(condition_code, 8, 1)
                WHEN '0' THEN 'Stage unspecified'
                WHEN '1' THEN 'Mild stage'
                WHEN '2' THEN 'Moderate stage'
                WHEN '3' THEN 'Severe stage'
                WHEN '4' THEN 'Indeterminate stage'
                ELSE 'Invalid stage'
            END
         -- Missing stage character
        ELSE 'Stage missing'
    END AS severity
FROM allcodes
;
-- select * from #glaucoma_codes;


DROP TABLE IF EXISTS #qualified_cases;
CREATE TABLE #qualified_cases AS
select a.*,g.glaucoma_type,g.laterality,g.severity

from #alldx a
left join #glaucoma_codes g
    on g.condition_code=a.condition_code
    ;



--add meds



DROP TABLE IF EXISTS #meds_antiplatelet;
CREATE TABLE #meds_antiplatelet AS
SELECT
    distinct vh_generic_name,vh_class_name,vh_rxcui,ndc_id --vh_medication_code

FROM
    "iris_registry_data_ccl_images_filtered"."iris_registry_data_ccl_images_filtered"."patient_medication"

where
(vh_generic_name  ILIKE '%Aspirin%' OR vh_generic_name  ILIKE '%clopidogrel%' OR
vh_generic_name  ILIKE '%Ticagrelor%' OR vh_generic_name  ILIKE '%prasugrel%')
AND vh_class_name ILIKE 'Platelet%'
;


DROP TABLE IF EXISTS #meds_anticoagulant;
CREATE TABLE #meds_anticoagulant AS
SELECT
    distinct vh_generic_name,vh_class_name,vh_rxcui,ndc_id

FROM
    "iris_registry_data_ccl_images_filtered"."iris_registry_data_ccl_images_filtered"."patient_medication"
where
(vh_generic_name  ILIKE '%Warfarin%' OR vh_generic_name  ILIKE '%Apixaban%'  OR
vh_generic_name  ILIKE '%Enoxaparin%' OR vh_generic_name  ILIKE '%Dabigatran%' OR
vh_generic_name  ILIKE '%Rivaroxaban%' OR vh_generic_name  ILIKE '%edoxaban%'OR
vh_generic_name  ILIKE '%dalteparin%' OR vh_generic_name  ILIKE '%fondaparinux%' OR
vh_generic_name  ILIKE '%argatroban%' OR vh_generic_name  ILIKE '%bivalirudin%' OR
vh_generic_name  ILIKE '%argatroban%' OR vh_generic_name  ILIKE '%bivalirudin%' OR
vh_generic_name  ILIKE '%desirudin%'
)
-- AND vh_class_name ILIKE 'anticoagulants%'
;



DROP TABLE IF EXISTS #meds_combined;
CREATE TABLE #meds_combined AS
with anti_p AS
(
    select *,
            'Antiplatelet' as grp
    from #meds_antiplatelet
),
anti_c as
(
    select *,
            'Anticoagulant' as grp
    from #meds_anticoagulant
),
combined AS
(
    select * from anti_p --where vh_rxcui is not NULL

    union ALL

    select * from anti_c --where vh_rxcui is not NULL
)
select * from combined
;



DROP TABLE IF EXISTS #med_history;
CREATE TABLE #med_history AS
with outerOrders as
(
select pt.patient_guid,
       pt.laterality_code,
        pt.gonio_sx_date,
        meds.grp,
        m.start_date,m.stop_date,m.dispense_date,m.effective_date,m.expiration_date,m.anatomical_location,m.vh_route,
        ROW_NUMBER () over(PARTITION by pt.patient_guid,pt.laterality_code,meds.grp order by m.start_date DESC) as rank

from ( select patient_guid,laterality_code, procedure_date as gonio_sx_date from #qualified_cases) pt
join
   "iris_registry_data_ccl_images_filtered"."iris_registry_data_ccl_images_filtered"."patient_medication" m
   --"iris_registry_data_ccl_filtered_10_2025"."iris_registry_data_ccl_filtered_10_2025"."patient_medication" m
    on m.patient_guid=pt.patient_guid
join #meds_combined meds
    on meds.vh_rxcui=m.vh_rxcui
    -- on meds.ndc_id=m.ndc_id

where m.start_date<pt.gonio_sx_date
)
select * from outerOrders where rank=1
;



DROP TABLE IF EXISTS #final_cohort_cataract_meds;
CREATE TABLE #final_cohort_cataract_meds AS
SELECT
  e.*,
  antiplatelet_date,
  anticoagulant_date
FROM #qualified_cases e
LEFT JOIN (select patient_guid,
                MAX(CASE WHEN grp = 'Antiplatelet' THEN start_date ELSE null END) AS antiplatelet_date,
                MAX(CASE WHEN grp = 'Anticoagulant' THEN start_date ELSE null END) AS anticoagulant_date
        FROM #med_history
GROUP BY patient_guid) m
on m.patient_guid= e.patient_guid
;


CALL unload_to_s3_folder_sql_to_parquet(
    $$
    select *
from #final_cohort_cataract_meds
    $$,
    '20_Goniotomy',
    'missint_lat_cohort'
);
