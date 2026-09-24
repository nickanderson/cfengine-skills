-- Validation script to test the alert.sql query syntax and schema
-- This validates that the query targets the correct tables and columns

-- First, verify that the target tables exist
-- (Run this manually to check table existence)

\echo 'Table verification:'
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('__hosts', '__promiseexecutions')
ORDER BY table_name;

\echo ''
\echo 'Column verification for __hosts:'
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = '__hosts'
  AND column_name IN ('hostkey', 'ipaddress', 'lastreporttimestamp')
ORDER BY column_name;

\echo ''
\echo 'Column verification for __promiseexecutions:'
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = '__promiseexecutions'
  AND column_name IN ('hostkey', 'promiseoutcome', 'changetimestamp')
ORDER BY column_name;

\echo ''
\echo 'Sample of unique promise outcomes in __promiseexecutions:'
SELECT DISTINCT promiseoutcome
FROM __promiseexecutions
LIMIT 10;

\echo ''
\echo 'Testing the alert query (limit 10 results):'
-- The actual alert query from alert.sql
SELECT DISTINCT
    h.hostkey,
    h.ipaddress,
    h.lastreporttimestamp
FROM __hosts h
WHERE EXISTS (
    SELECT 1
    FROM __promiseexecutions pe
    WHERE pe.hostkey = h.hostkey
      AND pe.promiseoutcome = 'not_kept'
      AND pe.changetimestamp = (
          SELECT MAX(changetimestamp)
          FROM __promiseexecutions
          WHERE hostkey = h.hostkey
      )
)
ORDER BY h.ipaddress
LIMIT 10;
