-- Create temporary test table to validate the alert query logic
CREATE TEMP TABLE hosts (
    hostkey TEXT,
    hostname TEXT
);

-- Test data: simulate CFEngine hosts with duplicate hostnames
INSERT INTO hosts VALUES 
    ('host_abc123', 'prod-web-01.corp.com'),
    ('host_def456', 'prod-web-01.corp.com'),  -- DUPLICATE: same hostname, different host
    ('host_ghi789', 'prod-db-01.corp.com'),
    ('host_jkl012', 'staging-app.corp.com'),
    ('host_mno345', 'staging-app.corp.com'); -- DUPLICATE: same hostname, different host

-- The alert query - returns hosts with duplicate hostnames
SELECT h.hostkey
FROM hosts h
WHERE h.hostname IN (
    SELECT hostname
    FROM hosts
    GROUP BY hostname
    HAVING COUNT(DISTINCT hostkey) > 1
)
ORDER BY h.hostname, h.hostkey;
