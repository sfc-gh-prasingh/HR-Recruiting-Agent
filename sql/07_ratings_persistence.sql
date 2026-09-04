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
