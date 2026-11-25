SELECT DISTINCT h.hostname
FROM hosts h
INNER JOIN "__promiselog_NOTKEPT_2026-09-23" nk ON h.hostkey = nk.hostkey
WHERE nk.changetimestamp = (
    SELECT MAX(changetimestamp)
    FROM "__promiselog_NOTKEPT_2026-09-23"
    WHERE hostkey = h.hostkey
)
ORDER BY h.hostname
