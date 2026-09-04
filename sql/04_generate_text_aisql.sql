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
