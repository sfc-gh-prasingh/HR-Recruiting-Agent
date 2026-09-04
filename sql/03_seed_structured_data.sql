-- =====================================================================
-- Recruiting Candidate Review Agent Demo
-- Step 3: Seed deterministic structured data
--   5 requisitions, ~400 candidates (R-3183 = 150), applications,
--   employment history, education, application questions, rubric.
-- Long prose (resume_text, application answers) is populated in step 4.
-- Deterministic via HASH() so re-runs are reproducible.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH;
USE DATABASE RECRUITING_DEMO;
USE SCHEMA RECRUITING;

-- ---------------------------------------------------------------------
-- 3.1 RATING_RUBRIC (Acme Health 1-4 fit scale)
-- ---------------------------------------------------------------------
INSERT INTO RATING_RUBRIC (rating, label, definition) VALUES
(1, 'Strong No',  'Does not meet the core qualifications for the role; significant gaps against required criteria.'),
(2, 'No',         'Meets few required qualifications; notable gaps that would likely not advance.'),
(3, 'Yes',        'Meets most required qualifications and some preferred ones; worth a closer look.'),
(4, 'Strong Yes', 'Meets the required criteria and most preferred criteria; a strong match to prioritize for review.');

-- ---------------------------------------------------------------------
-- 3.2 REQUISITIONS (5 Acme Health-realistic reqs)
-- ---------------------------------------------------------------------
INSERT INTO REQUISITIONS
(rec_id, title, department, location, employment_type, hiring_manager, recruiter, target_headcount, open_date, status, job_description, required_criteria, nice_to_have_criteria)
VALUES
('R-3183','RN Care Manager','Clinical','Remote (MA)','Full-time','Morgan Reeves','Devin Cole',40,DATE '2026-06-15','Open',
 'Acme Health is hiring Registered Nurse Care Managers to support Medicare Advantage members through telephonic care management. You will own a panel of high and rising-risk members, build individualized care plans, coordinate transitions of care, close gaps in care, and collaborate with PCPs and interdisciplinary teams. This is a fast-moving, member-first environment where you will help shape workflows as we scale.',
 'Active unrestricted RN license; 3+ years of care management or case management experience; experience with Medicare or Medicare Advantage populations; strong telephonic communication; comfort documenting in an EHR.',
 'Bilingual English/Spanish; experience with Epic; startup or high-growth healthcare experience; comfort operating with ambiguity and minimal playbook; transitions-of-care experience.'),
('R-3184','Clinical Care Guide','Member Care','Remote','Full-time','Morgan Reeves','Priya Raman',60,DATE '2026-06-20','Open',
 'Clinical Care Guides help Acme Health members navigate their healthcare journey: coordinating appointments, explaining benefits, and connecting members to clinical resources. You are the empathetic first point of contact for members who need help getting the care they deserve.',
 '2+ years in healthcare, member support, or patient services; strong empathy and communication; comfort in a high-volume phone environment; basic understanding of health benefits.',
 'Medicare Advantage experience; bilingual English/Spanish; experience with care coordination tools.'),
('R-3185','Member Service Guide','Member Operations','Tampa, FL','Full-time','Andre Lopez','Priya Raman',80,DATE '2026-06-10','Open',
 'Member Service Guides are the front line for Acme Health members, answering questions about benefits, claims, coverage, and providers with warmth and accuracy. You will resolve member issues end to end and document interactions clearly.',
 '1+ year in a call center or customer service role; clear written and verbal communication; ability to work onsite in Tampa, FL.',
 'Healthcare or insurance experience; Medicare knowledge; bilingual English/Spanish.'),
('R-3186','Data Engineer','Technology','Remote','Full-time','Sanjay Iyer','Devin Cole',8,DATE '2026-06-25','Open',
 'Acme Health is hiring Data Engineers to build and operate the data pipelines that power our clinical, actuarial, and member analytics on Snowflake. You will design robust ELT, model data for analytics, and partner with data scientists and actuaries.',
 '3+ years of data engineering; strong SQL and Python; experience with a cloud data warehouse; building production ELT pipelines.',
 'Snowflake experience; healthcare or claims data experience; dbt; startup or high-growth experience.'),
('R-3187','Provider Network Analyst','Network','Remote','Full-time','Sanjay Iyer','Priya Raman',12,DATE '2026-06-18','Open',
 'Provider Network Analysts analyze network adequacy, provider contracts, and access for Acme Health''s Medicare Advantage plans. You will turn provider and claims data into insights that shape network strategy.',
 '2+ years in analytics; strong Excel and SQL; ability to communicate findings to non-technical stakeholders.',
 'Medicare Advantage experience; provider contracting or network adequacy experience; healthcare data.');

-- ---------------------------------------------------------------------
-- 3.3 APPLICATION_QUESTIONS (shared ambiguity question + role-specific)
-- ---------------------------------------------------------------------
INSERT INTO APPLICATION_QUESTIONS (question_id, rec_id, question_text) VALUES
('R-3183-Q1','R-3183','Describe a time you were dropped into a highly ambiguous, fast-moving situation with no playbook. What did you do?'),
('R-3183-Q2','R-3183','Tell us about your experience managing care for Medicare or Medicare Advantage members.'),
('R-3184-Q1','R-3184','Describe a time you were dropped into a highly ambiguous, fast-moving situation with no playbook. What did you do?'),
('R-3184-Q2','R-3184','Tell us about a time you helped a member or patient navigate a difficult healthcare situation.'),
('R-3185-Q1','R-3185','Describe a time you were dropped into a highly ambiguous, fast-moving situation with no playbook. What did you do?'),
('R-3185-Q2','R-3185','Describe how you handle a high volume of member or customer contacts while staying accurate and empathetic.'),
('R-3186-Q1','R-3186','Describe a time you were dropped into a highly ambiguous, fast-moving situation with no playbook. What did you do?'),
('R-3186-Q2','R-3186','Tell us about a production data pipeline you built and the impact it had.'),
('R-3187-Q1','R-3187','Describe a time you were dropped into a highly ambiguous, fast-moving situation with no playbook. What did you do?'),
('R-3187-Q2','R-3187','Tell us about an analysis you delivered that changed a business decision.');

-- ---------------------------------------------------------------------
-- 3.4 GEN_CANDIDATE_SEED: deterministic helper (drives candidates,
--     applications, and step-4 text generation). HASH-based so re-runs
--     are reproducible. Counts: R-3183=150, R-3184=80, R-3185=90,
--     R-3186=40, R-3187=40 (400 total). target_fit spreads ratings 1-4.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE GEN_CANDIDATE_SEED AS
WITH g AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ8()) AS rn
  FROM TABLE(GENERATOR(ROWCOUNT => 400))
),
base AS (
  SELECT
    rn,
    'C-' || (100000 + rn)::VARCHAR AS candidate_id,
    'A-' || (500000 + rn)::VARCHAR AS application_id,
    CASE WHEN rn <= 150 THEN 'R-3183'
         WHEN rn <= 230 THEN 'R-3184'
         WHEN rn <= 320 THEN 'R-3185'
         WHEN rn <= 360 THEN 'R-3186'
         ELSE 'R-3187' END AS rec_id,
    CASE WHEN MOD(ABS(HASH(rn, 'fit')), 100) < 15 THEN 4
         WHEN MOD(ABS(HASH(rn, 'fit')), 100) < 40 THEN 3
         WHEN MOD(ABS(HASH(rn, 'fit')), 100) < 70 THEN 2
         ELSE 1 END AS target_fit,
    MOD(ABS(HASH(rn, 'fn')), 24) AS fn_idx,
    MOD(ABS(HASH(rn, 'ln')), 24) AS ln_idx,
    MOD(ABS(HASH(rn, 'loc')), 12) AS loc_idx,
    MOD(ABS(HASH(rn, 'src')), 8)  AS src_idx,
    MOD(ABS(HASH(rn, 'stg')), 100) AS stg_b,
    MOD(ABS(HASH(rn, 'ai')), 10)  AS ai_b,
    MOD(ABS(HASH(rn, 'sc')), 20)  AS sc_r,
    MOD(ABS(HASH(rn, 'dt')), 25)  AS dt_off
  FROM g
)
SELECT
  b.rn, b.candidate_id, b.application_id, b.rec_id, r.title AS role_title, b.target_fit,
  CASE WHEN b.target_fit >= 4 THEN 'senior' WHEN b.target_fit = 3 THEN 'mid'
       WHEN b.target_fit = 2 THEN 'junior' ELSE 'entry' END AS seniority,
  GET(ARRAY_CONSTRUCT('Maria','James','Priya','Devin','Sarah','Luis','Aisha','Michael','Chen','Fatima','Robert','Elena','David','Grace','Omar','Nicole','Kevin','Ana','Tyler','Rosa','Daniel','Leah','Marcus','Sofia'), b.fn_idx)::VARCHAR AS first_name,
  GET(ARRAY_CONSTRUCT('Alvarez','Okafor','Natarajan','Walsh','Chen','Mendez','Khan','OBrien','Nguyen','Haddad','Johnson','Petrov','Kim','Sullivan','Diallo','Rossi','Murphy','Garcia','Brooks','Santos','Cohen','Flynn','Reyes','Bauer'), b.ln_idx)::VARCHAR AS last_name,
  GET(ARRAY_CONSTRUCT('Boston','Lowell','Worcester','Tampa','Orlando','Manchester','Providence','Hartford','Remote','Cambridge','Springfield','Portland'), b.loc_idx)::VARCHAR AS city,
  GET(ARRAY_CONSTRUCT('MA','MA','MA','FL','FL','NH','RI','CT','MA','MA','MA','ME'), b.loc_idx)::VARCHAR AS state,
  GET(ARRAY_CONSTRUCT('Referral','LinkedIn','Indeed','Company Site','Agency','LinkedIn','Indeed','Company Site'), b.src_idx)::VARCHAR AS source,
  CASE WHEN b.target_fit >= 4 THEN 6 + MOD(ABS(HASH(b.rn,'ye')),10)
       WHEN b.target_fit = 3 THEN 3 + MOD(ABS(HASH(b.rn,'ye')),7)
       WHEN b.target_fit = 2 THEN 1 + MOD(ABS(HASH(b.rn,'ye')),5)
       ELSE MOD(ABS(HASH(b.rn,'ye')),3) END AS years_experience,
  CASE b.rec_id
    WHEN 'R-3183' THEN CASE WHEN b.stg_b<65 THEN 'Review' WHEN b.stg_b<75 THEN 'Screen' WHEN b.stg_b<85 THEN 'New' WHEN b.stg_b<92 THEN 'Interview' WHEN b.stg_b<96 THEN 'Offer' ELSE 'Rejected' END
    ELSE CASE WHEN b.stg_b<35 THEN 'Review' WHEN b.stg_b<55 THEN 'New' WHEN b.stg_b<70 THEN 'Screen' WHEN b.stg_b<82 THEN 'Interview' WHEN b.stg_b<90 THEN 'Offer' ELSE 'Rejected' END
  END AS stage,
  DATEADD(day, -b.dt_off, DATE '2026-07-15') AS applied_date,
  (b.src_idx = 0) AS referral_flag,
  CASE WHEN b.ai_b < 8 THEN 'Completed' WHEN b.ai_b = 8 THEN 'In Progress' ELSE 'Not Started' END AS ai_screen_status,
  CASE WHEN b.ai_b < 8 THEN LEAST(99, 45 + b.target_fit*8 + b.sc_r) ELSE NULL END AS ai_screen_score
FROM base b
JOIN REQUISITIONS r ON r.rec_id = b.rec_id;

-- 3.5 Populate CANDIDATES and APPLICATIONS from the seed
INSERT INTO CANDIDATES (candidate_id, full_name, city, state, email, source, years_experience)
SELECT candidate_id, first_name || ' ' || last_name, city, state,
       LOWER(first_name || '.' || last_name || '.' || SUBSTR(candidate_id,3) || '@example.com'),
       source, years_experience
FROM GEN_CANDIDATE_SEED;

INSERT INTO APPLICATIONS (application_id, candidate_id, rec_id, stage, applied_date, referral_flag, ai_screen_status, ai_screen_score)
SELECT application_id, candidate_id, rec_id, stage, applied_date, referral_flag, ai_screen_status, ai_screen_score
FROM GEN_CANDIDATE_SEED;

-- 3.6 EMPLOYMENT_HISTORY (2-4 role-aligned roles per candidate)
INSERT INTO EMPLOYMENT_HISTORY (employment_id, candidate_id, company, title, start_date, end_date, description)
WITH nums AS (SELECT 1 AS e UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4)
SELECT s.candidate_id || '-E' || n.e,
  s.candidate_id,
  GET(ARRAY_CONSTRUCT('Bright Health','Tufts Medical Center','CVS Health','Oscar Health','Humana','UnitedHealth','Mass General Brigham','Cigna','Clover Health','Optum','Aetna','Steward Health'), MOD(ABS(HASH(s.candidate_id, n.e, 'co')), 12))::VARCHAR,
  GET(CASE WHEN s.rec_id IN ('R-3183','R-3184') THEN ARRAY_CONSTRUCT('RN Care Manager','Case Manager','Staff RN','Care Coordinator','Utilization Review Nurse')
           WHEN s.rec_id = 'R-3185' THEN ARRAY_CONSTRUCT('Member Service Representative','Customer Service Associate','Call Center Agent','Patient Access Representative','Benefits Specialist')
           WHEN s.rec_id = 'R-3186' THEN ARRAY_CONSTRUCT('Data Engineer','Analytics Engineer','Software Engineer','Data Analyst','ETL Developer')
           ELSE ARRAY_CONSTRUCT('Network Analyst','Provider Data Analyst','Contracts Analyst','Business Analyst','Reporting Analyst') END,
      MOD(ABS(HASH(s.candidate_id, n.e, 'ti')), 5))::VARCHAR,
  DATEADD(year, -2, DATEADD(month, -((n.e-1)*30), DATE '2026-05-01')),
  DATEADD(month, -((n.e-1)*30), DATE '2026-05-01'),
  'Worked as part of the team supporting healthcare operations and members.'
FROM GEN_CANDIDATE_SEED s
JOIN nums n ON n.e <= 2 + MOD(ABS(HASH(s.candidate_id, 'empcnt')), 3);

-- 3.7 EDUCATION (1-2 role-aligned degrees per candidate)
INSERT INTO EDUCATION (education_id, candidate_id, school, degree, field_of_study, grad_year)
WITH nums AS (SELECT 1 AS d UNION ALL SELECT 2)
SELECT s.candidate_id || '-D' || n.d,
  s.candidate_id,
  GET(ARRAY_CONSTRUCT('UMass Amherst','Northeastern University','Boston College','University of Florida','UMass Lowell','Southern NH University','Bunker Hill CC','University of Central Florida','Salem State','Bentley University'), MOD(ABS(HASH(s.candidate_id, n.d, 'sch')), 10))::VARCHAR,
  GET(CASE WHEN s.rec_id IN ('R-3183','R-3184') THEN ARRAY_CONSTRUCT('BSN','ADN','BS','MSN')
           WHEN s.rec_id = 'R-3185' THEN ARRAY_CONSTRUCT('BA','Associate','BS','High School Diploma')
           WHEN s.rec_id = 'R-3186' THEN ARRAY_CONSTRUCT('BS','MS','BS','BA')
           ELSE ARRAY_CONSTRUCT('BS','BA','MBA','BS') END,
      MOD(ABS(HASH(s.candidate_id, n.d, 'deg')), 4))::VARCHAR,
  GET(CASE WHEN s.rec_id IN ('R-3183','R-3184') THEN ARRAY_CONSTRUCT('Nursing','Nursing','Health Sciences','Public Health')
           WHEN s.rec_id = 'R-3185' THEN ARRAY_CONSTRUCT('Communications','General Studies','Business','Liberal Arts')
           WHEN s.rec_id = 'R-3186' THEN ARRAY_CONSTRUCT('Computer Science','Data Science','Information Systems','Mathematics')
           ELSE ARRAY_CONSTRUCT('Health Administration','Economics','Business Analytics','Statistics') END,
      MOD(ABS(HASH(s.candidate_id, n.d, 'fld')), 4))::VARCHAR,
  2024 - MOD(ABS(HASH(s.candidate_id, n.d, 'yr')), 16)
FROM GEN_CANDIDATE_SEED s
JOIN nums n ON n.d <= 1 + MOD(ABS(HASH(s.candidate_id, 'educnt')), 2);

-- ---------------------------------------------------------------------
-- 3.8 Funnel + bilingual signals (deterministic via HASH). Supports
--     rec-level analytics: no-show rate, offer-to-start attrition,
--     bilingual splits. Derived from application_id so re-runs match.
-- ---------------------------------------------------------------------
-- Bilingual ~30% of candidates
UPDATE CANDIDATES
   SET bilingual = (MOD(ABS(HASH(candidate_id, 'biling')), 100) < 30);

-- No-show (~10% of mid/late-funnel), offers (Offer stage), disposition (Rejected)
UPDATE APPLICATIONS
   SET no_show_flag = (stage IN ('Screen','Interview','Offer','Rejected')
                       AND MOD(ABS(HASH(application_id, 'noshow')), 100) < 10),
       offer_date = IFF(stage = 'Offer',
                        DATEADD(day, 20 + MOD(ABS(HASH(application_id, 'off')), 12), applied_date),
                        NULL),
       disposition_reason = IFF(stage = 'Rejected',
            GET(ARRAY_CONSTRUCT('Did not meet minimum qualifications','No-show to screen',
                                'Failed background/verification','Declined to proceed','Position filled'),
                MOD(ABS(HASH(application_id, 'disp')), 5))::VARCHAR,
            NULL);

-- Start date for ~80% of offers (=> ~20% offer-to-start attrition)
UPDATE APPLICATIONS
   SET start_date = IFF(offer_date IS NOT NULL
                        AND MOD(ABS(HASH(application_id, 'start')), 100) < 80,
                        DATEADD(day, 15 + MOD(ABS(HASH(application_id, 'st2')), 14), offer_date),
                        NULL)
 WHERE offer_date IS NOT NULL;
