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
