# Mission Portal Alert SQL Validation Guide

## Alert SQL Overview

The `alert.sql` file contains a SQL query that identifies hosts where promises were **not kept** in their most recent agent execution. This query is ready to be pasted into the Mission Portal alert editor.

## How to Validate and Deploy

### Option 1: Using psql Command Line (Recommended for Production)

```bash
# Connect to the CFEngine reporting database
psql -h localhost -U cfpostgres -d cfdb < alert.sql

# Or with explicit password:
PGPASSWORD="your_db_password" psql -h localhost -U cfpostgres -d cfdb < alert.sql
```

Expected output: A list of hostnames that have not-kept promises in their latest execution.

### Option 2: Using Mission Portal Web Interface

1. Log into Mission Portal (https://your-hub-ip)
2. Navigate to: **Alerts** → **Create New Alert** or **Manage Alerts**
3. Select alert type: **Custom SQL Query** or **Database Alert**
4. Paste the SQL from `alert.sql` into the query editor
5. Click **Test Query** or **Validate**
6. Set alert conditions (e.g., "Alert if returns 1 or more rows")
7. Configure notification channels (email, webhook, etc.)
8. Save the alert

### Option 3: Command-line Validation

```bash
# Validate SQL syntax and preview results
sudo -u postgres psql -d cfdb << 'EOF'
SELECT query here
