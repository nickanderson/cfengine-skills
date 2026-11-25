#!/usr/bin/env python3
import os
import sys
import psycopg2
from urllib.parse import urlparse

# Parse Mission Portal URL
mp_url = os.getenv('MP_URL', 'https://192.168.56.2')
parsed = urlparse(mp_url)
mp_host = parsed.hostname or '192.168.56.2'

mp_user = os.getenv('MP_USER', 'admin')
mp_password = os.getenv('MP_PASSWORD', '')
mp_db = os.getenv('MP_DB', 'cfmp')

print(f"Attempting to connect to PostgreSQL on {mp_host}...")
print(f"User: {mp_user}, Database: {mp_db}")

try:
    conn = psycopg2.connect(
        host=mp_host,
        user=mp_user,
        password=mp_password,
        database=mp_db,
        sslmode='require' if 'https' in mp_url else 'prefer'
    )
    cur = conn.cursor()

    # Get all tables
    print("\n=== Tables in database ===")
    cur.execute("""
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public'
    ORDER BY table_name;
    """)
    tables = cur.fetchall()
    for table in tables:
        print(f"  {table[0]}")

    # Get promiselog table structure if it exists
    print("\n=== promiselog table structure ===")
    try:
        cur.execute("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name='promiselog'
        ORDER BY ordinal_position;
        """)
        cols = cur.fetchall()
        for col in cols:
            print(f"  {col[0]:<30} {col[1]:<20} nullable={col[2]}")
    except:
        pass

    # Sample data from promiselog
    print("\n=== Sample promiselog data (last 5 rows) ===")
    try:
        cur.execute("""
        SELECT
            hostname,
            promisetype,
            promiseoutcome,
            MAX(timestamp) as ts
        FROM promiselog
        GROUP BY hostname, promisetype, promiseoutcome
        ORDER BY ts DESC
        LIMIT 5;
        """)
        rows = cur.fetchall()
        for row in rows:
            print(f"  {row}")
    except Exception as e:
        print(f"  Error: {e}")

    # Check for hosts with notkept promises in most recent run
    print("\n=== Testing sample query ===")
    try:
        cur.execute("""
        WITH latest_runs AS (
            SELECT hostname, MAX(timestamp) as latest_ts
            FROM promiselog
            GROUP BY hostname
        )
        SELECT DISTINCT pl.hostname
        FROM promiselog pl
        JOIN latest_runs lr ON pl.hostname = lr.hostname
            AND pl.timestamp = lr.latest_ts
        WHERE pl.promiseoutcome = 'notkept'
        LIMIT 5;
        """)
        rows = cur.fetchall()
        print(f"  Hosts with notkept promises: {[row[0] for row in rows]}")
    except Exception as e:
        print(f"  Error: {e}")

    conn.close()

except psycopg2.Error as e:
    print(f"Database connection error: {e}")
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
