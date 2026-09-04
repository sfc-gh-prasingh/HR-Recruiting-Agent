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
