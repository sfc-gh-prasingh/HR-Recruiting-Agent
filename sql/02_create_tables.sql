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
