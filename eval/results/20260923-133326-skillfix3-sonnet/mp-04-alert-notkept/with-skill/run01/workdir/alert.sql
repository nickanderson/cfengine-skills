SELECT hostkey, COUNT(*) AS "Not kept promises"
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
GROUP BY hostkey
