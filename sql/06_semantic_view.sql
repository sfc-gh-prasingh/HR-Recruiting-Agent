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
