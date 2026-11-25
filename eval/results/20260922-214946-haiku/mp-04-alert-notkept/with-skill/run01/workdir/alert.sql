SELECT
  hostkey,
  COUNT(*) AS "Promises not kept"
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
GROUP BY hostkey
