SELECT h.hostkey AS hostkey
FROM hosts h
WHERE NULLIF(TRIM(h.hostname), '') IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM hosts other
    WHERE other.hostkey <> h.hostkey
      AND LOWER(TRIM(other.hostname)) = LOWER(TRIM(h.hostname))
  )
