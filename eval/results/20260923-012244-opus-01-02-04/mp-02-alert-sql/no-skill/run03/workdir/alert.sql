SELECT h.hostkey
FROM hosts h
WHERE COALESCE(TRIM(h.hostname), '') <> ''
  AND EXISTS (
    SELECT 1
    FROM hosts other
    WHERE other.hostkey <> h.hostkey
      AND LOWER(TRIM(other.hostname)) = LOWER(TRIM(h.hostname))
  )
