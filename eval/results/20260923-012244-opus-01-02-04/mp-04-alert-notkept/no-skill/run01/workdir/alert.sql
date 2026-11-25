SELECT DISTINCT pe.hostkey
FROM promiseexecutions AS pe
JOIN hosts AS h ON h.hostkey = pe.hostkey
WHERE pe.promiseoutcome = 'NOTKEPT'
