SELECT hostkey, count(*) AS "Promises not kept"
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
GROUP BY hostkey
