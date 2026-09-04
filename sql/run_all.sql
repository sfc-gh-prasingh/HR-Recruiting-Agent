-- =====================================================================
-- Recruiting Candidate Review Agent - ONE-SHOT DEMO BUILD
-- =====================================================================
-- Runs the entire demo end to end (steps 01-07) and creates the agent.
-- Usage:  snow sql -c <your_connection> -f sql/run_all.sql
--
-- This builds the SYNTHETIC "Acme Health" demo (steps 03-04 fabricate
-- candidates and use AI credits). For a real deployment, do NOT run this
-- file: run 01, 02, 05, 06, 07 individually, skip 03/04, and point the
-- objects at your HRIS/Workday feed (see README "Repoint to your real data").
--
-- This file is a concatenation of the numbered scripts; edit those, not this.
-- Requires: Cortex (Analyst, Search, Agents) enabled; a role that can create
-- databases, roles, warehouses, and agents (e.g. ACCOUNTADMIN).
-- =====================================================================


-- ############################################################
-- ### 01_setup_database_rbac.sql
-- ############################################################

-- =====================================================================
-- Recruiting Candidate Review Agent Demo
-- Step 1: Database, schema, warehouse context, and confidential RBAC
-- =====================================================================
-- Mirrors the customer requirement: a confidential area that only the
-- right people can reach. We create a dedicated role and grant it
-- least-privilege access; PUBLIC is never granted.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- Runtime warehouse for the agent + queries. Snowflake Intelligence usually
-- provisions SNOWFLAKE_INTELLIGENCE_WH automatically; create it here so the
-- template is self-contained on a fresh account. Adjust size as needed.
CREATE WAREHOUSE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_WH
  WITH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Runtime for the recruiting agent, Cortex Search, and analyst queries.';

-- Demo database + confidential recruiting schema
CREATE DATABASE IF NOT EXISTS RECRUITING_DEMO
  COMMENT = 'Acme Health recruiting agent demo (synthetic data, no real PII).';

CREATE SCHEMA IF NOT EXISTS RECRUITING_DEMO.RECRUITING
  COMMENT = 'Confidential recruiting data: requisitions, candidates, applications, resumes.';

-- Dedicated confidential role for recruiting access
CREATE ROLE IF NOT EXISTS RECRUITING_CONFIDENTIAL_RL
  COMMENT = 'Least-privilege access to confidential recruiting demo data and agent.';

-- Warehouse access for the role (agent runtime + queries)
GRANT USAGE ON WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH TO ROLE RECRUITING_CONFIDENTIAL_RL;

-- Database + schema usage (no PUBLIC grants)
GRANT USAGE ON DATABASE RECRUITING_DEMO TO ROLE RECRUITING_CONFIDENTIAL_RL;
GRANT USAGE ON SCHEMA RECRUITING_DEMO.RECRUITING TO ROLE RECRUITING_CONFIDENTIAL_RL;

-- Read access on existing and future objects in the confidential schema
GRANT SELECT ON ALL TABLES IN SCHEMA RECRUITING_DEMO.RECRUITING TO ROLE RECRUITING_CONFIDENTIAL_RL;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RECRUITING_DEMO.RECRUITING TO ROLE RECRUITING_CONFIDENTIAL_RL;
GRANT SELECT ON ALL VIEWS IN SCHEMA RECRUITING_DEMO.RECRUITING TO ROLE RECRUITING_CONFIDENTIAL_RL;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA RECRUITING_DEMO.RECRUITING TO ROLE RECRUITING_CONFIDENTIAL_RL;

-- Allow the role to use the Cortex Search service(s) created later
GRANT USAGE ON ALL CORTEX SEARCH SERVICES IN SCHEMA RECRUITING_DEMO.RECRUITING TO ROLE RECRUITING_CONFIDENTIAL_RL;
GRANT USAGE ON FUTURE CORTEX SEARCH SERVICES IN SCHEMA RECRUITING_DEMO.RECRUITING TO ROLE RECRUITING_CONFIDENTIAL_RL;

-- Make the role assumable by the demo operator (adjust as needed)
GRANT ROLE RECRUITING_CONFIDENTIAL_RL TO ROLE ACCOUNTADMIN;

-- Build everything under a consistent context
USE WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH;
USE DATABASE RECRUITING_DEMO;
USE SCHEMA RECRUITING;

-- ############################################################
-- ### 02_create_tables.sql
-- ############################################################

-- =====================================================================
-- Recruiting Candidate Review Agent Demo
-- Step 2: Data model (9 tables mirroring the Workday report fields)
-- =====================================================================
-- All text fields (resume_text, answers, employment descriptions) are
-- plain text that Workday extracts upstream. No PDFs / document parsing.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH;
USE DATABASE RECRUITING_DEMO;
USE SCHEMA RECRUITING;

-- ---------------------------------------------------------------------
-- REQUISITIONS: one row per open rec. job_description + required_criteria
-- are the text the agent reasons candidates against.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE REQUISITIONS (
    rec_id              VARCHAR        NOT NULL,   -- e.g. R-3183
    title               VARCHAR        NOT NULL,
    department          VARCHAR,
    location            VARCHAR,
    employment_type     VARCHAR,                   -- Full-time / Part-time
    hiring_manager      VARCHAR,
    recruiter           VARCHAR,
    target_headcount    NUMBER,                    -- number of openings on this rec
    open_date           DATE,
    status              VARCHAR,                   -- Open / Closed
    job_description     VARCHAR,                   -- long text
    required_criteria   VARCHAR,                   -- must-have qualifications
    nice_to_have_criteria VARCHAR,                 -- preferred qualifications
    CONSTRAINT pk_requisitions PRIMARY KEY (rec_id)
)
COMMENT = 'Open job requisitions with job description and screening criteria.';

-- ---------------------------------------------------------------------
-- CANDIDATES: one row per applicant (synthetic identity, no real PII).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CANDIDATES (
    candidate_id        VARCHAR        NOT NULL,   -- e.g. C-100294
    full_name           VARCHAR,
    city                VARCHAR,
    state               VARCHAR,
    email               VARCHAR,
    source              VARCHAR,                   -- Referral / LinkedIn / Indeed / Company Site / Agency
    years_experience    NUMBER,
    bilingual           BOOLEAN,                   -- English/Spanish (meaningful signal at Acme Health)
    CONSTRAINT pk_candidates PRIMARY KEY (candidate_id)
)
COMMENT = 'Synthetic candidate identities.';

-- ---------------------------------------------------------------------
-- APPLICATIONS: a candidate applying to a rec, with pipeline stage and
-- the result of Acme Health's existing bilateral AI interview screen.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE APPLICATIONS (
    application_id      VARCHAR        NOT NULL,   -- e.g. A-500011
    candidate_id        VARCHAR        NOT NULL,
    rec_id              VARCHAR        NOT NULL,
    stage               VARCHAR,                   -- New / Review / Screen / Interview / Offer / Rejected
    applied_date        DATE,
    referral_flag       BOOLEAN,
    ai_screen_status    VARCHAR,                   -- Not Started / In Progress / Completed
    ai_screen_score     NUMBER,                    -- 0-100 from the existing AI interview agent (context only)
    no_show_flag        BOOLEAN,                   -- no-showed to the screen/interview
    offer_date          DATE,                      -- date an offer was extended (Offer stage)
    start_date          DATE,                      -- date the hire started (NULL => offer-to-start attrition)
    disposition_reason  VARCHAR,                   -- why a Rejected candidate was dispositioned
    CONSTRAINT pk_applications PRIMARY KEY (application_id),
    CONSTRAINT fk_app_candidate FOREIGN KEY (candidate_id) REFERENCES CANDIDATES (candidate_id),
    CONSTRAINT fk_app_rec FOREIGN KEY (rec_id) REFERENCES REQUISITIONS (rec_id)
)
COMMENT = 'Candidate applications to requisitions with pipeline stage.';

-- ---------------------------------------------------------------------
-- RESUMES: resume text already extracted by Workday (plain text).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE RESUMES (
    candidate_id        VARCHAR        NOT NULL,
    resume_text         VARCHAR,                   -- extracted text, not a document
    CONSTRAINT pk_resumes PRIMARY KEY (candidate_id),
    CONSTRAINT fk_resume_candidate FOREIGN KEY (candidate_id) REFERENCES CANDIDATES (candidate_id)
)
COMMENT = 'Extracted resume text per candidate (from Workday).';

-- ---------------------------------------------------------------------
-- EMPLOYMENT_HISTORY: prior roles per candidate.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE EMPLOYMENT_HISTORY (
    employment_id       VARCHAR        NOT NULL,
    candidate_id        VARCHAR        NOT NULL,
    company             VARCHAR,
    title               VARCHAR,
    start_date          DATE,
    end_date            DATE,
    description         VARCHAR,
    CONSTRAINT pk_employment PRIMARY KEY (employment_id),
    CONSTRAINT fk_emp_candidate FOREIGN KEY (candidate_id) REFERENCES CANDIDATES (candidate_id)
)
COMMENT = 'Candidate prior employment history.';

-- ---------------------------------------------------------------------
-- EDUCATION: degrees per candidate.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE EDUCATION (
    education_id        VARCHAR        NOT NULL,
    candidate_id        VARCHAR        NOT NULL,
    school              VARCHAR,
    degree              VARCHAR,
    field_of_study      VARCHAR,
    grad_year           NUMBER,
    CONSTRAINT pk_education PRIMARY KEY (education_id),
    CONSTRAINT fk_edu_candidate FOREIGN KEY (candidate_id) REFERENCES CANDIDATES (candidate_id)
)
COMMENT = 'Candidate education history.';

-- ---------------------------------------------------------------------
-- APPLICATION_QUESTIONS: rec-specific screening questions.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE APPLICATION_QUESTIONS (
    question_id         VARCHAR        NOT NULL,
    rec_id              VARCHAR        NOT NULL,
    question_text       VARCHAR,
    CONSTRAINT pk_questions PRIMARY KEY (question_id),
    CONSTRAINT fk_q_rec FOREIGN KEY (rec_id) REFERENCES REQUISITIONS (rec_id)
)
COMMENT = 'Job-specific application questions per requisition.';

-- ---------------------------------------------------------------------
-- APPLICATION_ANSWERS: candidate answers to the rec questions.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE APPLICATION_ANSWERS (
    answer_id           VARCHAR        NOT NULL,
    application_id      VARCHAR        NOT NULL,
    question_id         VARCHAR        NOT NULL,
    answer_text         VARCHAR,                   -- long text
    CONSTRAINT pk_answers PRIMARY KEY (answer_id),
    CONSTRAINT fk_ans_app FOREIGN KEY (application_id) REFERENCES APPLICATIONS (application_id),
    CONSTRAINT fk_ans_q FOREIGN KEY (question_id) REFERENCES APPLICATION_QUESTIONS (question_id)
)
COMMENT = 'Candidate answers to job-specific application questions.';

-- ---------------------------------------------------------------------
-- RATING_RUBRIC: Acme Health's 1-4 fit scale the agent cites for explainable,
-- consistent ratings (1 = strong no ... 4 = strong yes).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE RATING_RUBRIC (
    rating              NUMBER         NOT NULL,
    label               VARCHAR,
    definition          VARCHAR,
    CONSTRAINT pk_rubric PRIMARY KEY (rating)
)
COMMENT = 'Recruiter 1-4 fit rating rubric definitions.';

-- ############################################################
-- ### 03_seed_structured_data.sql
-- ############################################################

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

-- ############################################################
-- ### 04_generate_text_aisql.sql
-- ############################################################

-- =====================================================================
-- Recruiting Candidate Review Agent Demo
-- Step 4: Generate candidate prose (hybrid AISQL)
--   R-3183 (150 candidates, the demo rec): AI_COMPLETE-generated resume
--     text + application answers, tuned to each candidate's target_fit
--     so 1-4 ratings spread realistically.
--   Other recs (~250): deterministic templated text (fast, no AI cost).
-- NOTE: In production this text arrives pre-extracted from Workday. We
--   generate it here only because there are no real candidates.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH;   -- scale up for faster AI throughput on large pools
USE DATABASE RECRUITING_DEMO;
USE SCHEMA RECRUITING;

-- ---------------------------------------------------------------------
-- 4.1 Per-candidate helper: assemble employment + education summaries
--     and a fit-guidance string used to steer the generated prose.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE GEN_TEXT_INPUT AS
WITH emp AS (
  SELECT candidate_id,
         LISTAGG(title || ' at ' || company, '; ') WITHIN GROUP (ORDER BY end_date DESC) AS emp_summary
  FROM EMPLOYMENT_HISTORY GROUP BY candidate_id
),
edu AS (
  SELECT candidate_id,
         LISTAGG(degree || ' in ' || field_of_study || ' (' || school || ')', '; ') WITHIN GROUP (ORDER BY grad_year DESC) AS edu_summary
  FROM EDUCATION GROUP BY candidate_id
)
SELECT
  s.candidate_id, s.application_id, s.rec_id, s.role_title, s.target_fit,
  s.first_name, s.years_experience,
  COALESCE(emp.emp_summary,'') AS emp_summary,
  COALESCE(edu.edu_summary,'') AS edu_summary,
  CASE s.target_fit
    WHEN 4 THEN 'STRONG match. Clearly meets required and preferred criteria for this exact role. Weave in the required licenses/skills and the preferred extras naturally.'
    WHEN 3 THEN 'GOOD match. Meets most required criteria and a couple preferred ones, with one or two minor gaps.'
    WHEN 2 THEN 'WEAK match. Some adjacent experience but missing several required criteria; limited domain depth.'
    ELSE 'POOR match. Background is largely in an unrelated field; does not meet the core required criteria for this role.'
  END AS fit_guidance
FROM GEN_CANDIDATE_SEED s
LEFT JOIN emp ON emp.candidate_id = s.candidate_id
LEFT JOIN edu ON edu.candidate_id = s.candidate_id;

-- ---------------------------------------------------------------------
-- 4.2 AI-generated resume text for R-3183 (RN Care Manager)
-- ---------------------------------------------------------------------
INSERT INTO RESUMES (candidate_id, resume_text)
SELECT
  candidate_id,
  AI_COMPLETE('llama3.1-70b',
    'You are writing a realistic, concise professional resume summary (120-180 words) for a job applicant. '
    || 'Write in first person, no headings, no contact info, no preamble. '
    || 'The applicant (first name ' || first_name || ') is applying to a Registered Nurse (RN) Care Manager role at a Medicare Advantage health plan. '
    || 'The required criteria are: active RN license, 3+ years care/case management, Medicare or Medicare Advantage population experience, telephonic communication, EHR documentation. '
    || 'Preferred: bilingual English/Spanish, Epic EHR, startup or high-growth healthcare experience, comfort with ambiguity, transitions of care. '
    || 'Fit guidance for THIS candidate: ' || fit_guidance || ' '
    || 'Approx years of experience: ' || years_experience || '. Prior roles to reflect: ' || emp_summary || '. Education: ' || edu_summary || '. '
    || 'Vary the wording naturally so it does not read like a template. Return only the resume text.'
  ) AS resume_text
FROM GEN_TEXT_INPUT
WHERE rec_id = 'R-3183';

-- Clean occasional bracketed placeholders from generation
UPDATE RESUMES
SET resume_text = REGEXP_REPLACE(resume_text, '\\[[Ss]tate\\]', 'Massachusetts')
WHERE resume_text ILIKE '%[state]%';

-- ---------------------------------------------------------------------
-- 4.3 AI-generated application answers for R-3183 (2 questions each)
-- ---------------------------------------------------------------------
INSERT INTO APPLICATION_ANSWERS (answer_id, application_id, question_id, answer_text)
SELECT
  g.application_id || '-' || q.question_id,
  g.application_id,
  q.question_id,
  AI_COMPLETE('llama3.1-70b',
    'Write a realistic first-person answer (80-140 words) to a job application question. No preamble, no headings, return only the answer. '
    || 'Role: RN Care Manager at a Medicare Advantage health plan. '
    || 'Candidate first name: ' || g.first_name || '. Candidate fit guidance: ' || g.fit_guidance || ' '
    || 'The answer should be consistent with that fit level (a strong candidate gives a specific, relevant, credible answer; a poor-fit candidate gives a vague or off-target answer). '
    || 'Question: "' || q.question_text || '" Return only the answer text.'
  )
FROM GEN_TEXT_INPUT g
JOIN APPLICATION_QUESTIONS q ON q.rec_id = g.rec_id
WHERE g.rec_id = 'R-3183';

-- ---------------------------------------------------------------------
-- 4.4 Templated resume text for the other four recs (fast, no AI cost)
-- ---------------------------------------------------------------------
INSERT INTO RESUMES (candidate_id, resume_text)
SELECT
  g.candidate_id,
  g.first_name || ' is applying for the ' || g.role_title || ' role at Acme Health, a Medicare Advantage plan. '
  || 'They bring approximately ' || g.years_experience || ' years of experience, including ' || NULLIF(g.emp_summary,'') || '. '
  || 'Education: ' || NULLIF(g.edu_summary,'') || '. '
  || CASE g.target_fit
       WHEN 4 THEN 'Their background strongly matches the role requirements, with directly relevant domain experience and preferred skills.'
       WHEN 3 THEN 'Their background covers most of the role requirements with a few minor gaps.'
       WHEN 2 THEN 'They have some adjacent experience but notable gaps against the core requirements.'
       ELSE 'They have limited experience relevant to this specific role.'
     END
FROM GEN_TEXT_INPUT g
WHERE g.rec_id <> 'R-3183';

-- ---------------------------------------------------------------------
-- 4.5 Templated application answers for the other four recs
-- ---------------------------------------------------------------------
INSERT INTO APPLICATION_ANSWERS (answer_id, application_id, question_id, answer_text)
SELECT
  g.application_id || '-' || q.question_id,
  g.application_id,
  q.question_id,
  CASE
    WHEN q.question_id LIKE '%-Q1' THEN
      CASE g.target_fit
        WHEN 4 THEN g.first_name || ' describes a specific, high-ownership example: stepping into an undefined situation, quickly creating a plan, aligning stakeholders, and delivering a strong outcome for the ' || g.role_title || ' domain.'
        WHEN 3 THEN g.first_name || ' gives a relevant example of handling an ambiguous situation and driving it to a reasonable outcome.'
        WHEN 2 THEN g.first_name || ' gives a general example that only partially addresses operating without a playbook.'
        ELSE g.first_name || ' gives a vague answer that does not clearly demonstrate comfort with ambiguity.'
      END
    ELSE
      CASE g.target_fit
        WHEN 4 THEN g.first_name || ' provides a specific, credible example directly relevant to the ' || g.role_title || ' role and its required criteria.'
        WHEN 3 THEN g.first_name || ' provides a mostly relevant example covering key parts of the role requirements.'
        WHEN 2 THEN g.first_name || ' provides a somewhat relevant example with limited depth.'
        ELSE g.first_name || ' provides an answer with little relevance to the role requirements.'
      END
  END
FROM GEN_TEXT_INPUT g
JOIN APPLICATION_QUESTIONS q ON q.rec_id = g.rec_id
WHERE g.rec_id <> 'R-3183';

-- ############################################################
-- ### 05_candidate_profile_and_search.sql
-- ############################################################

-- =====================================================================
-- Recruiting Candidate Review Agent Demo
-- Step 5: Candidate profile corpus + Cortex Search service
--   CANDIDATE_PROFILE assembles one searchable text block per application
--   (resume + employment + education + application Q&A) with filterable
--   attributes (rec_id, stage, source). The agent uses the search service
--   to find and read the right candidates at scale, scoped to a rec/stage.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH;
USE DATABASE RECRUITING_DEMO;
USE SCHEMA RECRUITING;

-- ---------------------------------------------------------------------
-- 5.1 CANDIDATE_PROFILE view: one row per application, one text block.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW CANDIDATE_PROFILE AS
WITH emp AS (
  SELECT candidate_id,
         LISTAGG(title || ' at ' || company || ' (' || TO_VARCHAR(start_date,'YYYY') || '-' || TO_VARCHAR(end_date,'YYYY') || ')', '; ')
           WITHIN GROUP (ORDER BY end_date DESC) AS emp_summary
  FROM EMPLOYMENT_HISTORY GROUP BY candidate_id
),
edu AS (
  SELECT candidate_id,
         LISTAGG(degree || ' in ' || field_of_study || ', ' || school || ' (' || grad_year || ')', '; ')
           WITHIN GROUP (ORDER BY grad_year DESC) AS edu_summary
  FROM EDUCATION GROUP BY candidate_id
),
qa AS (
  SELECT ans.application_id,
         LISTAGG('Q: ' || q.question_text || '\nA: ' || ans.answer_text, '\n\n')
           WITHIN GROUP (ORDER BY q.question_id) AS qa_summary
  FROM APPLICATION_ANSWERS ans
  JOIN APPLICATION_QUESTIONS q ON q.question_id = ans.question_id
  GROUP BY ans.application_id
)
SELECT
  a.application_id,
  a.candidate_id,
  c.full_name              AS candidate_name,
  a.rec_id,
  r.title                  AS rec_title,
  a.stage,
  c.source,
  c.state,
  a.referral_flag,
  a.ai_screen_status,
  a.ai_screen_score,
  'Candidate: ' || c.full_name || ' (' || c.candidate_id || ')\n'
    || 'Applied to: ' || r.title || ' [' || a.rec_id || '] | Stage: ' || a.stage
    || ' | Source: ' || c.source || ' | Location: ' || c.city || ', ' || c.state || '\n'
    || 'Years of experience: ' || c.years_experience || '\n\n'
    || 'RESUME:\n' || COALESCE(res.resume_text,'(no resume text)') || '\n\n'
    || 'EMPLOYMENT HISTORY:\n' || COALESCE(emp.emp_summary,'(none listed)') || '\n\n'
    || 'EDUCATION:\n' || COALESCE(edu.edu_summary,'(none listed)') || '\n\n'
    || 'APPLICATION QUESTIONS AND ANSWERS:\n' || COALESCE(qa.qa_summary,'(none)')
    AS search_text
FROM APPLICATIONS a
JOIN CANDIDATES c   ON c.candidate_id = a.candidate_id
JOIN REQUISITIONS r ON r.rec_id = a.rec_id
LEFT JOIN RESUMES res ON res.candidate_id = a.candidate_id
LEFT JOIN emp ON emp.candidate_id = a.candidate_id
LEFT JOIN edu ON edu.candidate_id = a.candidate_id
LEFT JOIN qa  ON qa.application_id = a.application_id;

-- ---------------------------------------------------------------------
-- 5.2 Cortex Search service over the candidate profiles.
--   Filterable attributes let the agent scope to a rec and stage.
-- ---------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE CANDIDATE_PROFILE_SEARCH
  ON search_text
  ATTRIBUTES application_id, candidate_id, candidate_name, rec_id, rec_title, stage, source, state, referral_flag, ai_screen_status
  WAREHOUSE = SNOWFLAKE_INTELLIGENCE_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Searchable candidate profiles (resume, employment, education, application answers) for the recruiting agent.'
  AS (
    SELECT
      search_text, application_id, candidate_id, candidate_name,
      rec_id, rec_title, stage, source, state, referral_flag, ai_screen_status
    FROM CANDIDATE_PROFILE
  );

-- ############################################################
-- ### 06_semantic_view.sql
-- ############################################################

-- =====================================================================
-- Recruiting Candidate Review Agent Demo
-- Step 6: Recruiting semantic view (Cortex Analyst tool)
--   Backs structured questions: counts by stage / source, requisition
--   job description + criteria lookup, average screen score, etc.
--   Note: in semantic view DDL, dimension syntax is
--     <table>.<logical_name> AS <physical_column>, and members use
--     COMMENT = '...'.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH;
USE DATABASE RECRUITING_DEMO;
USE SCHEMA RECRUITING;

CREATE OR REPLACE SEMANTIC VIEW RECRUITING_DEMO.RECRUITING.RECRUITING_SEMANTIC_VIEW
  TABLES (
    applications AS RECRUITING_DEMO.RECRUITING.APPLICATIONS
      PRIMARY KEY (application_id) COMMENT = 'One row per candidate application to a requisition',
    candidates AS RECRUITING_DEMO.RECRUITING.CANDIDATES
      PRIMARY KEY (candidate_id) COMMENT = 'Candidate identities',
    requisitions AS RECRUITING_DEMO.RECRUITING.REQUISITIONS
      PRIMARY KEY (rec_id) COMMENT = 'Open job requisitions'
  )
  RELATIONSHIPS (
    app_candidate AS applications (candidate_id) REFERENCES candidates (candidate_id),
    app_requisition AS applications (rec_id) REFERENCES requisitions (rec_id)
  )
  FACTS (
    applications.ai_screen_score AS ai_screen_score,
    applications.is_offer AS IFF(offer_date IS NOT NULL, 1, 0),
    applications.is_start AS IFF(start_date IS NOT NULL, 1, 0),
    applications.is_no_show AS IFF(no_show_flag, 1, 0),
    candidates.years_experience AS years_experience
  )
  DIMENSIONS (
    applications.stage AS stage
      COMMENT = 'Pipeline stage: New, Review, Screen, Interview, Offer, Rejected',
    applications.ai_screen_status AS ai_screen_status
      COMMENT = 'Status of the existing AI interview screen',
    applications.referral_flag AS referral_flag
      COMMENT = 'TRUE if the applicant came through a referral',
    applications.no_show_flag AS no_show_flag
      COMMENT = 'TRUE if the candidate no-showed to the screen or interview',
    applications.disposition_reason AS disposition_reason
      COMMENT = 'Reason a rejected candidate was dispositioned',
    applications.applied_date AS applied_date
      COMMENT = 'Date the application was submitted',
    requisitions.rec_id AS rec_id
      COMMENT = 'Requisition identifier such as R-3183',
    requisitions.title AS title
      COMMENT = 'Requisition job title',
    requisitions.department AS department COMMENT = 'Hiring department',
    requisitions.location AS location COMMENT = 'Requisition location',
    requisitions.req_status AS status COMMENT = 'Requisition status (Open/Closed)',
    requisitions.target_headcount AS target_headcount
      COMMENT = 'Number of openings on the requisition',
    requisitions.job_description AS job_description
      COMMENT = 'Full job description text for the requisition',
    requisitions.required_criteria AS required_criteria
      COMMENT = 'Must-have qualifications for the requisition',
    requisitions.nice_to_have_criteria AS nice_to_have_criteria
      COMMENT = 'Preferred qualifications for the requisition',
    candidates.source AS source
      COMMENT = 'Application source: Referral, LinkedIn, Indeed, Company Site, Agency',
    candidates.state AS state COMMENT = 'Candidate state of residence',
    candidates.bilingual AS bilingual COMMENT = 'TRUE if the candidate is bilingual',
    candidates.candidate_name AS full_name COMMENT = 'Candidate full name'
  )
  METRICS (
    applications.application_count AS COUNT(applications.application_id)
      COMMENT = 'Number of applications',
    applications.offer_count AS SUM(applications.is_offer)
      COMMENT = 'Number of candidates who reached an offer',
    applications.start_count AS SUM(applications.is_start)
      COMMENT = 'Number of candidates who started',
    applications.no_show_count AS SUM(applications.is_no_show)
      COMMENT = 'Number of candidates who no-showed to the screen or interview',
    applications.offer_to_start_rate AS SUM(applications.is_start) / NULLIF(SUM(applications.is_offer), 0)
      COMMENT = 'Share of offers that resulted in a start (1 minus offer-to-start attrition)',
    applications.avg_ai_screen_score AS AVG(applications.ai_screen_score)
      COMMENT = 'Average AI interview screen score (0-100)',
    candidates.avg_years_experience AS AVG(candidates.years_experience)
      COMMENT = 'Average years of candidate experience'
  )
  COMMENT = 'Recruiting analytics over applications, candidates, and requisitions: counts by requisition, stage, and source; pipeline funnel (offers, starts, no-shows, offer-to-start rate); bilingual split; job descriptions and screening criteria.';

-- ---------------------------------------------------------------------
-- Validation queries (analyst-style) using the SEMANTIC_VIEW() function
-- ---------------------------------------------------------------------
-- Applications by stage for R-3183:
-- SELECT * FROM SEMANTIC_VIEW(RECRUITING_DEMO.RECRUITING.RECRUITING_SEMANTIC_VIEW
--   DIMENSIONS applications.stage METRICS applications.application_count
--   WHERE requisitions.rec_id = 'R-3183') ORDER BY 1;

-- ############################################################
-- ### 07_ratings_persistence.sql
-- ############################################################

-- =====================================================================
-- Recruiting Candidate Review Agent Demo
-- Step 7: Ratings persistence + audit trail
-- =====================================================================
-- Answers the common question ("are the ratings stored / can they go
-- back to Workday"). CANDIDATE_RATINGS is the durable, auditable record
-- of every fit rating a recruiter runs: what rating, why (summary +
-- evidence), against which criteria, by whom, and when. It is also the
-- exact payload a future Workday write-back would push (see README
-- phase-2 roadmap). RBAC-locked to the confidential recruiting role.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWFLAKE_INTELLIGENCE_WH;
USE DATABASE RECRUITING_DEMO;
USE SCHEMA RECRUITING;

-- ---------------------------------------------------------------------
-- CANDIDATE_RATINGS: one row per rating event (append-only audit log).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS CANDIDATE_RATINGS (
    rating_id       VARCHAR       DEFAULT UUID_STRING(),  -- unique event id
    rec_id          VARCHAR       NOT NULL,
    application_id  VARCHAR       NOT NULL,
    candidate_id    VARCHAR       NOT NULL,
    rating          NUMBER        NOT NULL,               -- 1-4 (rubric)
    summary         VARCHAR,                              -- one/two-sentence fit summary
    key_evidence    VARCHAR,                              -- supporting phrases cited
    criteria_used   VARCHAR,                              -- required + ad-hoc criteria applied
    rated_by        VARCHAR       DEFAULT CURRENT_USER(), -- recruiter / caller
    rated_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_candidate_ratings PRIMARY KEY (rating_id),
    CONSTRAINT fk_rating_app FOREIGN KEY (application_id) REFERENCES APPLICATIONS (application_id),
    CONSTRAINT fk_rating_rec FOREIGN KEY (rec_id)         REFERENCES REQUISITIONS (rec_id),
    CONSTRAINT fk_rating_cand FOREIGN KEY (candidate_id)  REFERENCES CANDIDATES (candidate_id)
)
COMMENT = 'Auditable log of recruiter fit ratings (rating, evidence, criteria, who, when). Workday write-back payload.';

-- ---------------------------------------------------------------------
-- LOG_CANDIDATE_RATING: persist one rating. Derives rec_id + candidate_id
-- from the application so callers only pass the application and result.
-- EXECUTE AS OWNER so the confidential role needs only USAGE on the proc,
-- not direct INSERT on the audit table (write path stays controlled).
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE LOG_CANDIDATE_RATING(
    P_APPLICATION_ID VARCHAR,
    P_RATING         NUMBER,
    P_SUMMARY        VARCHAR,
    P_KEY_EVIDENCE   VARCHAR,
    P_CRITERIA_USED  VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    v_rec_id       VARCHAR;
    v_candidate_id VARCHAR;
    v_rating_id    VARCHAR;
BEGIN
    IF (P_RATING < 1 OR P_RATING > 4) THEN
        RETURN 'ERROR: rating must be between 1 and 4';
    END IF;

    SELECT rec_id, candidate_id
      INTO :v_rec_id, :v_candidate_id
      FROM APPLICATIONS
     WHERE application_id = :P_APPLICATION_ID;

    IF (v_rec_id IS NULL) THEN
        RETURN 'ERROR: application_id not found: ' || :P_APPLICATION_ID;
    END IF;

    v_rating_id := UUID_STRING();

    INSERT INTO CANDIDATE_RATINGS
        (rating_id, rec_id, application_id, candidate_id, rating, summary, key_evidence, criteria_used)
    VALUES
        (:v_rating_id, :v_rec_id, :P_APPLICATION_ID, :v_candidate_id,
         :P_RATING, :P_SUMMARY, :P_KEY_EVIDENCE, :P_CRITERIA_USED);

    RETURN 'OK: logged rating ' || :v_rating_id;
END;
$$;

-- ---------------------------------------------------------------------
-- RBAC: confidential role can read the audit log (SELECT via FUTURE
-- TABLES grant in step 1) and log ratings through the procedure only.
-- ---------------------------------------------------------------------
GRANT USAGE ON PROCEDURE LOG_CANDIDATE_RATING(VARCHAR, NUMBER, VARCHAR, VARCHAR, VARCHAR)
    TO ROLE RECRUITING_CONFIDENTIAL_RL;

-- ############################################################
-- ### Create the agent from the specification
-- ############################################################

CREATE OR REPLACE AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.RECRUITING_AGENT
  WITH PROFILE='{"display_name":"Recruiting Candidate Review Assistant"}'
  COMMENT='Assists recruiters in triaging applicant pools with 1-4 fit ratings. Human-in-the-loop.'
  FROM SPECIFICATION $$
{
  "models": { "orchestration": "auto" },
  "orchestration": {
    "budget": { "seconds": 900, "tokens": 500000 }
  },
  "instructions": {
    "orchestration": "Use the query_recruiting tool (Cortex Analyst over the recruiting semantic view) for structured questions: counts and breakdowns by requisition, stage, and source, average AI screen score, pipeline funnel and drop-off / no-show / offer-to-start metrics, and to look up a requisition's title, job_description, required_criteria, and nice_to_have_criteria. Use the search_candidates tool to find and read candidate profiles (resume text, employment history, education, and application answers); always pass a filter on rec_id, and on stage when the recruiter specifies one (default to stage = 'Review').\n\nGUIDED INTAKE: If a recruiter asks to review, screen, or triage candidates but has NOT named a requisition, do not guess. Ask them, one question at a time and in this order: (1) Which requisition? (rec_id or title) (2) Which pipeline stage should I look at? (default: Review) (3) Any special or ad-hoc criteria to weigh beyond the job description? (for example Medicare Advantage experience, telehealth background, bilingual ability, comfort with ambiguity). Only proceed to rating once you have the requisition. The 1-4 rating rubric is fixed and defined in the response instructions - never take the rating scale, thresholds, or scoring logic from the recruiter; they may only add criteria to weigh, not change how ratings are computed.\n\nWhen a recruiter names a requisition (for example R-3183) and asks to review, screen, or find best-fit candidates, first fetch that requisition's required_criteria and job_description with query_recruiting, then retrieve the candidates with search_candidates, then produce the rated candidate table described in the response instructions. Use the make_chart tool for stage, source, or funnel breakdowns when a visual helps.",
    "response": "You are the Acme Health Recruiting Assistant. You help recruiters triage large applicant pools for a requisition. You are an assistant only: you never make hiring decisions, and you never automatically reject or advance candidates. A recruiter reviews every candidate and makes all decisions (human in the loop).\n\nStandardized, guided workflow - run the SAME steps for every requisition so every candidate gets a consistent experience:\n0. If the recruiter has not named a requisition, ask for it first (offer to default the stage to 'Review' and to take any special criteria they want weighed). Do not rate anyone until you know the requisition.\n1. Retrieve the requisition's title, job_description, required_criteria, and nice_to_have_criteria.\n2. Retrieve candidate profiles for that requisition, scoped to the requested pipeline stage (default 'Review'), factoring in the required criteria and any ad-hoc criteria the recruiter adds.\n3. For EACH retrieved candidate, assess fit INDEPENDENTLY against the required criteria, the job description, and the recruiter's ad-hoc criteria, and assign a fit rating using this FIXED rubric (never change the scale or take it from the recruiter):\n   - 4 = Strong Yes: meets the required criteria and most preferred criteria; prioritize for review.\n   - 3 = Yes: meets most required criteria and some preferred; worth a closer look.\n   - 2 = No: meets few required criteria; notable gaps.\n   - 1 = Strong No: does not meet the core qualifications.\n4. Present the results as a markdown table sorted by fit rating (highest first) with columns: Candidate (name + candidate_id), Fit (1-4), Summary (one or two sentences), Key evidence (specific phrases from the resume, answers, or employment history). Provide a real Summary AND Key evidence for EVERY candidate at EVERY rating tier - including the 2s (No) and the 1s (Strong No). Never abbreviate or skip the reasoning for low-rated candidates: recruiters must review everyone, and a low rating sometimes turns out to be a strong fit on closer inspection, so always explain WHY a candidate was rated a 1 or 2.\n5. Always close with a brief reminder that these ratings are an assistive prioritization aid, that every candidate should still be reviewed by a person, and that the recruiter makes the final decision.\n\nAcme Health signals to weigh when present in a profile (use as evidence, not as hard filters unless the recruiter asks): Medicare / Medicare Advantage and CMS experience; telehealth or remote care versus in-clinic (Acme Health is 100% remote); comfort with ambiguity and fast-paced / startup environments; prior use of AI tools in the role; and bilingual ability (with certification where relevant). Note: Acme Health does not use Epic - treat a specific EHR product name as a minor signal only, not a core requirement.\n\nRules you must follow:\n- Rate each candidate on their own merits against the criteria. Do not rank candidates competitively against one another beyond sorting by each candidate's individual rating.\n- Apply the same criteria and the same fixed rubric consistently to every candidate for a requisition, so the process is standardized across recruiters and recs.\n- Base ratings ONLY on job-relevant qualifications and evidence. Never use or infer protected characteristics (such as age, race, gender, national origin, disability, religion, or similar). If a request asks you to, decline and explain why.\n- If evidence for a candidate is thin or missing, say so and lower your confidence rather than inventing details.\n- If asked to automatically reject candidates, filter people out, or make a final hiring decision, politely decline: explain that a person must review all candidates and that this assistant only summarizes and prioritizes to save time.\n- Cite candidate_id values so the recruiter can locate each person in Workday.",
    "sample_questions": [
      { "question": "I need to review candidates for a requisition." },
      { "question": "For R-3183, look at everyone in Review and give each a 1-4 fit rating with a summary and evidence." },
      { "question": "For R-3183, also prioritize Medicare Advantage and bilingual experience, and explain the reasons for every rating including the No's." },
      { "question": "Show me the pipeline funnel and drop-off for R-3183." }
    ]
  },
  "tools": [
    {
      "tool_spec": {
        "type": "cortex_analyst_text_to_sql",
        "name": "query_recruiting",
        "description": "Structured recruiting analytics over requisitions, candidates, and applications. Use for counts and breakdowns by requisition, stage, and source, average AI screen score, pipeline funnel and drop-off / no-show / offer-to-start metrics, and to look up a requisition's job description and required/nice-to-have criteria."
      }
    },
    {
      "tool_spec": {
        "type": "cortex_search",
        "name": "search_candidates",
        "description": "Search candidate profiles (resume text, employment history, education, application answers) for a requisition. Filter by rec_id and stage to scope to the right applicant pool, and query with the required and ad-hoc criteria to find the best matches."
      }
    },
    {
      "tool_spec": {
        "type": "data_to_chart",
        "name": "make_chart"
      }
    }
  ],
  "tool_resources": {
    "query_recruiting": {
      "execution_environment": {
        "type": "warehouse",
        "warehouse": "SNOWFLAKE_INTELLIGENCE_WH",
        "query_timeout": 120
      },
      "semantic_view": "RECRUITING_DEMO.RECRUITING.RECRUITING_SEMANTIC_VIEW"
    },
    "search_candidates": {
      "search_service": "RECRUITING_DEMO.RECRUITING.CANDIDATE_PROFILE_SEARCH",
      "id_column": "application_id",
      "title_column": "candidate_name",
      "max_results": 20
    }
  }
}
$$;

GRANT USAGE ON AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.RECRUITING_AGENT TO ROLE RECRUITING_CONFIDENTIAL_RL;
