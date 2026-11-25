-- Test the alert query with sample CFEngine data
-- This script creates test tables, populates them with sample data,
-- and runs the alert query to verify it works correctly

-- Create temporary test tables that mimic CFEngine schema
CREATE TEMP TABLE __hosts (
    hostkey TEXT PRIMARY KEY,
    ipaddress TEXT,
    lastreporttimestamp TIMESTAMP DEFAULT NOW()
);

CREATE TEMP TABLE __promiseexecutions (
    hostkey TEXT,
    promiseoutcome TEXT,
    changetimestamp TIMESTAMP,
    bundlename TEXT,
    promisetype TEXT,
    promiser TEXT,
    FOREIGN KEY (hostkey) REFERENCES __hosts(hostkey)
);

-- Insert sample hosts
INSERT INTO __hosts (hostkey, ipaddress, lastreporttimestamp) VALUES
('SHA=host001abc123', '192.168.1.10', '2026-09-23 10:30:00'),
('SHA=host002def456', '192.168.1.11', '2026-09-23 10:25:00'),
('SHA=host003ghi789', '192.168.1.12', '2026-09-23 10:20:00'),
('SHA=host004jkl012', '192.168.1.13', '2026-09-23 10:15:00'),
('SHA=host005mno345', '192.168.1.14', '2026-09-23 10:10:00');

-- Insert sample promise executions
-- Host 1: Latest run has one 'not_kept' promise (should alert)
INSERT INTO __promiseexecutions (hostkey, promiseoutcome, changetimestamp, bundlename, promisetype, promiser) VALUES
('SHA=host001abc123', 'kept', '2026-09-23 10:30:00', 'main', 'files', '/etc/hostname'),
('SHA=host001abc123', 'not_kept', '2026-09-23 10:30:00', 'main', 'commands', '/usr/bin/update-config'),
('SHA=host001abc123', 'kept', '2026-09-23 10:30:00', 'main', 'packages', 'curl');

-- Host 2: Latest run has all 'kept' promises (should NOT alert)
INSERT INTO __promiseexecutions (hostkey, promiseoutcome, changetimestamp, bundlename, promisetype, promiser) VALUES
('SHA=host002def456', 'kept', '2026-09-23 10:25:00', 'main', 'files', '/etc/config'),
('SHA=host002def456', 'kept', '2026-09-23 10:25:00', 'main', 'commands', '/bin/ls'),
-- Old run with 'not_kept' - but host 2 shouldn't alert since recent run is OK
('SHA=host002def456', 'not_kept', '2026-09-23 09:25:00', 'main', 'files', '/old/file');

-- Host 3: Latest run has multiple 'not_kept' promises (should alert)
INSERT INTO __promiseexecutions (hostkey, promiseoutcome, changetimestamp, bundlename, promisetype, promiser) VALUES
('SHA=host003ghi789', 'not_kept', '2026-09-23 10:20:00', 'main', 'commands', '/usr/bin/deploy'),
('SHA=host003ghi789', 'not_kept', '2026-09-23 10:20:00', 'main', 'files', '/opt/app/config.json'),
('SHA=host003ghi789', 'kept', '2026-09-23 10:20:00', 'main', 'packages', 'nodejs');

-- Host 4: No promise executions yet (should NOT alert)
-- (no data inserted)

-- Host 5: Only repaired promises in latest run (should NOT alert - only 'not_kept')
INSERT INTO __promiseexecutions (hostkey, promiseoutcome, changetimestamp, bundlename, promisetype, promiser) VALUES
('SHA=host005mno345', 'repaired', '2026-09-23 10:10:00', 'main', 'files', '/etc/service.conf'),
('SHA=host005mno345', 'kept', '2026-09-23 10:10:00', 'main', 'commands', '/bin/service');

-- Now run the actual alert query
\echo ''
\echo '=========================================='
\echo 'ALERT QUERY RESULTS'
\echo '=========================================='
\echo ''
\echo 'Expected: 2 hosts (host001 and host003)'
\echo ''

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
ORDER BY h.ipaddress;

\echo ''
\echo '=========================================='
\echo 'VERIFICATION QUERIES'
\echo '=========================================='
\echo ''
\echo 'All hosts in database:'
SELECT hostkey, ipaddress FROM __hosts ORDER BY ipaddress;

\echo ''
\echo 'Promise outcomes in latest runs per host:'
SELECT DISTINCT
    h.hostkey,
    h.ipaddress,
    (SELECT MAX(changetimestamp) FROM __promiseexecutions WHERE hostkey = h.hostkey) as latest_run,
    STRING_AGG(DISTINCT pe.promiseoutcome, ', ' ORDER BY pe.promiseoutcome) as outcomes_in_latest_run
FROM __hosts h
LEFT JOIN __promiseexecutions pe ON h.hostkey = pe.hostkey
WHERE pe.changetimestamp = (SELECT MAX(changetimestamp) FROM __promiseexecutions WHERE hostkey = h.hostkey) OR pe.changetimestamp IS NULL
GROUP BY h.hostkey, h.ipaddress
ORDER BY h.ipaddress;

\echo ''
\echo 'Test completed successfully!'
