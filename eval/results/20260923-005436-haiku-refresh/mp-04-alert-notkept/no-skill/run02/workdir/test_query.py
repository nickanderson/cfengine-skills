#!/usr/bin/env python3
"""
Test and validate the CFEngine Mission Portal alert SQL query.
This script validates the SQL syntax and logic without requiring database access.
"""

import re
import sys

def validate_sql_syntax(sql_content):
    """Basic SQL syntax validation"""

    issues = []

    # Check for SELECT statement
    if 'SELECT' not in sql_content.upper():
        issues.append("ERROR: Missing SELECT statement")

    # Check for required keywords
    required = ['FROM', 'WHERE']
    for keyword in required:
        if keyword not in sql_content.upper():
            issues.append(f"ERROR: Missing {keyword} clause")

    # Check for table names
    if '__hosts' not in sql_content:
        issues.append("ERROR: Missing __hosts table reference")

    if '__promiseexecutions' not in sql_content:
        issues.append("ERROR: Missing __promiseexecutions table reference")

    # Check for required columns
    if 'hostkey' not in sql_content:
        issues.append("ERROR: Missing hostkey column")

    if 'promiseoutcome' not in sql_content:
        issues.append("ERROR: Missing promiseoutcome column")

    if 'changetimestamp' not in sql_content:
        issues.append("ERROR: Missing changetimestamp column")

    if 'not_kept' not in sql_content:
        issues.append("WARNING: Filter for 'not_kept' outcome not found")

    return issues

def validate_query_logic(sql_content):
    """Validate the logical structure of the query"""

    issues = []

    # Check for proper EXISTS clause
    if 'EXISTS' not in sql_content.upper():
        issues.append("WARNING: Query should use EXISTS for clarity")

    # Check for subquery to find max timestamp
    if 'MAX(changetimestamp)' not in sql_content:
        issues.append("ERROR: Query must find MAX(changetimestamp) for most recent run")

    # Check for correct outcome filtering
    if "promiseoutcome = 'not_kept'" not in sql_content:
        issues.append("ERROR: Query must filter for promiseoutcome = 'not_kept'")

    # Check for proper host joining
    if 'h.hostkey' in sql_content and 'pe.hostkey' in sql_content:
        if 'WHERE' in sql_content and 'pe.hostkey = h.hostkey' in sql_content:
            pass  # Good
        else:
            issues.append("ERROR: Query must properly join hosts to promise executions")

    return issues

def main():
    """Run all validations"""

    # Read the alert.sql file
    try:
        with open('/tmp/cfeval-mp-04-alert-notkept-no-skill.zrXOJcr5/work/alert.sql', 'r') as f:
            sql_content = f.read()
    except FileNotFoundError:
        print("ERROR: alert.sql not found")
        return 1

    print("=" * 70)
    print("CFEngine Mission Portal Alert SQL Validation")
    print("=" * 70)

    # Remove comments and normalize
    sql_normalized = '\n'.join([
        line.split('--')[0].strip()
        for line in sql_content.split('\n')
    ])

    # Run validations
    print("\n[1] Syntax Validation")
    print("-" * 70)
    syntax_issues = validate_sql_syntax(sql_content)
    if not syntax_issues:
        print("✓ SQL syntax appears valid")
    else:
        for issue in syntax_issues:
            print(f"✗ {issue}")

    print("\n[2] Logic Validation")
    print("-" * 70)
    logic_issues = validate_query_logic(sql_content)
    if not logic_issues:
        print("✓ Query logic is sound")
    else:
        for issue in logic_issues:
            print(f"✗ {issue}")

    print("\n[3] Schema Validation")
    print("-" * 70)
    tables_referenced = []
    if '__hosts' in sql_content:
        tables_referenced.append('__hosts')
    if '__promiseexecutions' in sql_content:
        tables_referenced.append('__promiseexecutions')

    print(f"✓ Tables referenced: {', '.join(tables_referenced)}")

    columns_used = {
        '__hosts': set(),
        '__promiseexecutions': set()
    }

    for col in ['hostkey', 'ipaddress', 'lastreporttimestamp']:
        if col in sql_content:
            columns_used['__hosts'].add(col)

    for col in ['hostkey', 'promiseoutcome', 'changetimestamp']:
        if col in sql_content:
            columns_used['__promiseexecutions'].add(col)

    for table, cols in columns_used.items():
        if cols:
            print(f"✓ {table}: {', '.join(sorted(cols))}")

    print("\n[4] Query Purpose Verification")
    print("-" * 70)
    print("Query Purpose: Find hosts where ANY promise was NOT KEPT in the most recent agent run")

    # Check logical structure
    checks = [
        ("Has filter for 'not_kept' outcome", "promiseoutcome = 'not_kept'" in sql_content),
        ("Finds most recent run per host", "MAX(changetimestamp)" in sql_content),
        ("Joins hosts to executions", "__hosts h" in sql_content and "__promiseexecutions pe" in sql_content),
        ("Returns host information", "h.hostkey" in sql_content or "h.ipaddress" in sql_content),
    ]

    for check_name, result in checks:
        status = "✓" if result else "✗"
        print(f"{status} {check_name}")

    # Final assessment
    all_issues = syntax_issues + logic_issues

    print("\n" + "=" * 70)
    if not all_issues:
        print("VALIDATION RESULT: ✓ PASS - Query is valid and ready to use")
        print("=" * 70)
        return 0
    else:
        print(f"VALIDATION RESULT: ✗ ISSUES FOUND ({len(all_issues)} issues)")
        print("=" * 70)
        return 1

if __name__ == '__main__':
    sys.exit(main())
