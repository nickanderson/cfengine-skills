-- Clone a real host's reporting rows into :count synthetic hosts.
-- Run by mp-clone-hosts.sh; psql variables: template (fqhost of a live host),
-- count. Every identity the template reports (hostkey, fqhost, uqhost, IP,
-- MACs, system UUID, and the classes derived from them) is replaced
-- consistently in every table, so a clone is the template's real inventory
-- under a new identity. Clone n's hostkey is SHA=sha256('mp-clone:<n>').
-- Clone IPs are in 172.16.0.0/12, which mp-clone-hosts.sh excludes from
-- cf-hub's collection; keep the two in step.
\set ON_ERROR_STOP on
SET client_min_messages = warning;
BEGIN;

CREATE TEMP TABLE tpl AS
SELECT h.hostkey, substr(h.hostkey, 5) AS hex, h.ipaddress AS ip,
       fq.variablevalue AS fqhost,
       (SELECT variablevalue FROM __variables WHERE hostkey = h.hostkey AND comp = 'default.sys.uqhost') AS uqhost,
       (SELECT trim(variablevalue)::text[] FROM __variables WHERE hostkey = h.hostkey AND comp = 'default.sys.hardware_addresses') AS macs,
       (SELECT variablevalue FROM __variables WHERE hostkey = h.hostkey AND comp = 'default.cfe_autorun_inventory_dmidecode.dmi[system-uuid]') AS uuid
FROM __hosts h
JOIN __variables fq ON fq.hostkey = h.hostkey AND fq.comp = 'default.sys.fqhost'
WHERE fq.variablevalue = :'template' AND h.deleted IS NULL;

DO $$ BEGIN
  IF (SELECT count(*) FROM tpl) <> 1 THEN
    RAISE EXCEPTION 'need exactly one live host with that fqhost, found %', (SELECT count(*) FROM tpl);
  END IF;
  IF length((SELECT uqhost FROM tpl)) < 4 THEN
    RAISE EXCEPTION 'template uqhost too short to substitute safely';
  END IF;
END $$;

CREATE FUNCTION pg_temp.sub(s text, f text[], t text[]) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF s IS NULL THEN RETURN NULL; END IF;
  FOR i IN 1 .. coalesce(array_length(f, 1), 0) LOOP
    s := replace(s, f[i], t[i]);
  END LOOP;
  RETURN s;
END $$;

CREATE FUNCTION pg_temp.suba(a text[], f text[], t text[]) RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
  SELECT array_agg(pg_temp.sub(x, f, t) ORDER BY i) FROM unnest(a) WITH ORDINALITY u(x, i)
$$;

-- The first 1, 2 and 3 octets of an IP, as CFEngine's ipv4_* classes spell them.
CREATE FUNCTION pg_temp.oct(ip text, n int) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT array_to_string((string_to_array(ip, '.'))[1:n], '_')
$$;

CREATE TEMP TABLE clones AS
SELECT n, 'SHA=' || hex AS hostkey, hex, uqhost,
       uqhost || '.' || site || '.example.com' AS fqhost,
       '172.' || (16 + s) || '.' || (n / 250) || '.' || (n % 250 + 1) AS ip,
       upper(substr(hex, 1, 8) || '-' || substr(hex, 9, 4) || '-4' || substr(hex, 14, 3)
             || '-a' || substr(hex, 18, 3) || '-' || substr(hex, 21, 12)) AS uuid
FROM (
  SELECT n, encode(sha256(convert_to('mp-clone:' || n, 'UTF8')), 'hex') AS hex,
         (ARRAY['web', 'app', 'db', 'cache', 'queue', 'build', 'log', 'proxy'])[1 + n % 8]
           || '-' || lpad(n::text, 4, '0') AS uqhost,
         -- n / 8, not n: with n % 8 and n % 4 every web host was in ams.
         (ARRAY['ams', 'fra', 'osl', 'nyc'])[1 + (n / 8) % 4] AS site,
         (n / 8) % 4 AS s
  FROM generate_series(1, :count) n
) x;

-- Longest-first, so e.g. the fqhost is replaced before the uqhost inside it
-- and ipv4_a_b_c before ipv4_a_b. The third pair is the fqhost class, which
-- CFEngine canonifies (app-0001.fra -> app_0001_fra).
ALTER TABLE clones ADD f text[], ADD t text[];
UPDATE clones c SET
  f = ARRAY[tpl.hex, tpl.fqhost, replace(tpl.fqhost, '.', '_'),
            tpl.ip, replace(tpl.ip, '.', '_'),
            'ipv4_' || pg_temp.oct(tpl.ip, 3), 'ipv4_' || pg_temp.oct(tpl.ip, 2),
            'ipv4_' || pg_temp.oct(tpl.ip, 1),
            tpl.uqhost, tpl.uuid, lower(tpl.uuid)]
      || (SELECT coalesce(array_agg(m ORDER BY i), '{}') || coalesce(array_agg(replace(m, ':', '_') ORDER BY i), '{}')
          FROM unnest(tpl.macs) WITH ORDINALITY u(m, i)),
  t = ARRAY[c.hex, c.fqhost, regexp_replace(c.fqhost, '[^A-Za-z0-9_]', '_', 'g'),
            c.ip, replace(c.ip, '.', '_'),
            'ipv4_' || pg_temp.oct(c.ip, 3), 'ipv4_' || pg_temp.oct(c.ip, 2),
            'ipv4_' || pg_temp.oct(c.ip, 1),
            c.uqhost, c.uuid, lower(c.uuid)]
      || (SELECT coalesce(array_agg(mac ORDER BY i), '{}') || coalesce(array_agg(replace(mac, ':', '_') ORDER BY i), '{}')
          FROM (SELECT i, '52:54:00:' || substr(c.hex, i::int * 6 + 1, 2) || ':' || substr(c.hex, i::int * 6 + 3, 2)
                          || ':' || substr(c.hex, i::int * 6 + 5, 2) AS mac
                FROM unnest(tpl.macs) WITH ORDINALITY u(m, i)) x)
FROM tpl;

-- Staggered like a fleet on a 5-minute schedule; first seen up to 90 days ago.
INSERT INTO __hosts (hostkey, iscallcollected, lastreporttimestamp, firstreporttimestamp, hostkeycollisions, deleted, ipaddress)
SELECT hostkey, false, now() - (n % 240) * interval '1 second',
       now() - (1 + n % 90) * interval '1 day' - (n % 86400) * interval '1 second', 0, NULL, ip
FROM clones;

INSERT INTO __agentstatus (hostkey, agentexecutioninterval, lastagentlocalexecutiontimestamp, lastagentexecutionstatus)
SELECT hostkey, 300, now() - (n % 240) * interval '1 second' - (20 + n % 40) * interval '1 second', 'OK'
FROM clones;

INSERT INTO __contexts (hostkey, contextname, metatags, changetimestamp)
SELECT c.hostkey, pg_temp.sub(x.contextname, c.f, c.t), pg_temp.suba(x.metatags, c.f, c.t), x.changetimestamp
FROM __contexts x, tpl, clones c WHERE x.hostkey = tpl.hostkey;

INSERT INTO contextcache (hostkey, contextvector)
SELECT c.hostkey, pg_temp.sub(x.contextvector::text, c.f, c.t)::tsvector
FROM contextcache x, tpl, clones c WHERE x.hostkey = tpl.hostkey;

INSERT INTO __variables (hostkey, namespace, bundle, variablename, variablevalue, variabletype, comp, metatags, changetimestamp)
SELECT c.hostkey, x.namespace, x.bundle, pg_temp.sub(x.variablename, c.f, c.t), pg_temp.sub(x.variablevalue, c.f, c.t),
       x.variabletype, pg_temp.sub(x.comp, c.f, c.t), pg_temp.suba(x.metatags, c.f, c.t), x.changetimestamp
FROM __variables x, tpl, clones c WHERE x.hostkey = tpl.hostkey;

INSERT INTO __inventory (hostkey, values)
SELECT c.hostkey, pg_temp.sub(x.values::text, c.f, c.t)::jsonb
FROM __inventory x, tpl, clones c WHERE x.hostkey = tpl.hostkey;

INSERT INTO __lastseenhosts (hostkey, compo, lastseendirection, remotehostkey, remotehostip, lastseentimestamp, lastseeninterval)
SELECT c.hostkey, x.compo, x.lastseendirection, x.remotehostkey, x.remotehostip,
       now() - (c.n % 240) * interval '1 second', 300
FROM __lastseenhosts x, tpl, clones c WHERE x.hostkey = tpl.hostkey;

INSERT INTO __software (hostkey, compo, softwarename, softwareversion, softwarearchitecture, changetimestamp)
SELECT c.hostkey, x.compo, x.softwarename, x.softwareversion, x.softwarearchitecture, x.changetimestamp
FROM __software x, tpl, clones c WHERE x.hostkey = tpl.hostkey;

INSERT INTO __softwareupdates (hostkey, compo, patchname, patchversion, patcharchitecture, patchreporttype, changetimestamp)
SELECT c.hostkey, x.compo, x.patchname, x.patchversion, x.patcharchitecture, x.patchreporttype, x.changetimestamp
FROM __softwareupdates x, tpl, clones c WHERE x.hostkey = tpl.hostkey;

INSERT INTO __promiseexecutions (hostkey, policyfile, releaseid, promisehash, namespace, bundlename, promisetype, promiser,
                                 stackpath, promisehandle, promiseoutcome, linenumber, policyfilehash, logmessages,
                                 promisees, metatags, changetimestamp)
SELECT c.hostkey, x.policyfile, x.releaseid, x.promisehash, x.namespace, x.bundlename, x.promisetype,
       pg_temp.sub(x.promiser, c.f, c.t), x.stackpath, x.promisehandle, x.promiseoutcome, x.linenumber,
       x.policyfilehash, pg_temp.suba(x.logmessages, c.f, c.t), x.promisees, x.metatags, x.changetimestamp
FROM __promiseexecutions x, tpl, clones c WHERE x.hostkey = tpl.hostkey;

-- Anything the substitution missed still names the template.
DO $$ DECLARE leaks int; BEGIN
  SELECT count(*) INTO leaks FROM __variables v, tpl, clones c
   WHERE v.hostkey = c.hostkey AND (v.variablevalue LIKE '%' || tpl.ip || '%' OR v.variablevalue LIKE '%' || tpl.uqhost || '%');
  IF leaks > 0 THEN RAISE EXCEPTION '% cloned variables still name the template', leaks; END IF;
END $$;

SELECT count(*) || ' clones of ' || (SELECT fqhost FROM tpl) FROM clones;
COMMIT;
