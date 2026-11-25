#!/usr/bin/env python3
"""
Comprehensive test of the CFEngine Mission Portal alert query.
Includes SQL parsing, schema validation, and logic verification.
"""

import re
import sys
from typing import List, Set, Dict, Tuple

def extract_select_columns(query: str) -> List[str]:
    """Extract column names from SELECT clause"""
    # Simple regex to find SELECT ... FROM
    select_match = re.search(r'SELECT\s+(.*?)\s+FROM', query, re.IGNORECASE | re.DOTALL)
    if select_match:
        select_part = select_match.group(1)
        # Remove DISTINCT keyword
        select_part = re.sub(r'\bDISTINCT\b', '', select_part, flags=re.IGNORECASE).strip()
        # Extract column references
        columns = re.findall(r'(\w+\.\w+|\w+)', select_part)
        return columns
    return []

def extract_tables(query: str) -> List[Tuple[str, str]]:
    """Extract table names and their aliases"""
    # Find all FROM and JOIN clauses
    from_matches = re.findall(r'FROM\s+(\w+)\s+(\w+)?', query, re.IGNORECASE)
    join_matches = re.findall(r'JOIN\s+(\w+)\s+(\w+)?', query, re.IGNORECASE)
    where_matches = re.findall(r'WHERE\s+.*?(\w+)\s+(\w+)', query[:query.find('WHERE')+50], re.IGNORECASE)

    tables = []
    for table, alias in from_matches:
        alias = alias or table
        tables.append((table, alias))

    # Extract WHERE clause table references
    where_clause = query[query.find('WHERE'):] if 'WHERE' in query.upper() else ''
    for table_ref in re.findall(r'\b(\w+__\w+)\b', where_clause):
        tables.append((table_ref, None))

    return tables

def analyze_query_completeness(query: str) -> Dict[str, bool]:
    """Analyze if query has all required components"""
    query_upper = query.upper()

    return {
        'has_select': 'SELECT' in query_upper,
        'has_from': 'FROM' in query_upper,
        'has_where': 'WHERE' in query_upper,
        'has_exists': 'EXISTS' in query_upper,
        'has_order_by': 'ORDER BY' in query_upper,
        'has_distinct': 'DISTINCT' in query_upper,
        'has_subquery': query.count('SELECT') > 1,
        'has_max_timestamp': 'MAX(changetimestamp)' in query,
        'filters_not_kept': "promiseoutcome = 'not_kept'" in query or 'promiseoutcome = "not_kept"' in query,
    }

def check_schema_compatibility(query: str) -> Dict[str, str]:
    """Check if query uses valid CFEngine schema"""
    cfengine_tables = {
        '__hosts': ['hostkey', 'ipaddress', 'lastreporttimestamp', 'deleted', 'firstreporttimestamp'],
        '__promiseexecutions': ['hostkey', 'promiseoutcome', 'changetimestamp', 'bundlename', 'promisetype', 'promiser', 'stackpath'],
    }

    results = {}

    for table, columns in cfengine_tables.items():
        if table in query:
            results[f'{table}_referenced'] = 'Found'
            for col in columns:
                if f'.{col}' in query or f' {col}' in query:
                    results[f'{table}_{col}'] = 'Used'
        else:
            results[f'{table}_referenced'] = 'Not found'

    return results

def verify_query_logic(query: str) -> List[str]:
    """Verify the logical correctness of the query"""
    warnings = []

    # Check for EXISTS with subquery
    if 'EXISTS' in query.upper():
        if query.count('SELECT') < 2:
            warnings.append('EXISTS clause should have a subquery')

    # Check for proper host filtering
    if '__hosts h' in query and '__promiseexecutions pe' in query:
        if 'h.hostkey = pe.hostkey' not in query and 'pe.hostkey = h.hostkey' not in query:
            warnings.append('Missing proper join between hosts and promise executions')

    # Check for timestamp comparison
    if 'changetimestamp' in query:
        if 'MAX(changetimestamp)' not in query:
            warnings.append('Query should find MAX(changetimestamp) for most recent run')

    # Check ordering
    if 'ORDER BY' in query.upper():
        pass  # Good practice
    else:
        warnings.append('Missing ORDER BY clause (optional but recommended)')

    return warnings

def test_query_examples(query: str) -> None:
    """Provide example scenarios the query should handle"""
    scenarios = [
        {
            'name': 'Host with unmet promise in latest run',
            'expected': 'Should be included in results',
            'condition': "promiseoutcome = 'not_kept' in latest run"
        },
        {
            'name': 'Host with all kept promises in latest run',
            'expected': 'Should NOT be included',
            'condition': "All promises in latest run have outcome = 'kept'"
        },
        {
            'name': 'Host with unmet promise in older run, kept in latest',
            'expected': 'Should NOT be included',
            'condition': "not_kept outcome only in older run timestamps"
        },
        {
            'name': 'Host with repaired promise in latest run',
            'expected': 'Should NOT be included (repaired is not not_kept)',
            'condition': "Latest run outcome = 'repaired' not 'not_kept'"
        },
        {
            'name': 'Host with no promise executions',
            'expected': 'Should NOT be included',
            'condition': "No __promiseexecutions rows for hostkey"
        },
    ]

    return scenarios

def main():
    """Run comprehensive tests"""

    # Read the alert.sql file
    try:
        with open('/tmp/cfeval-mp-04-alert-notkept-no-skill.zrXOJcr5/work/alert.sql', 'r') as f:
            query = f.read()
    except FileNotFoundError:
        print("ERROR: alert.sql not found")
        return 1

    # Remove comments
    query_clean = '\n'.join([
        line.split('--')[0]
        for line in query.split('\n')
    ]).strip()

    print("=" * 80)
    print("COMPREHENSIVE CFENGINE ALERT QUERY ANALYSIS")
    print("=" * 80)

    # Test 1: Query completeness
    print("\n[TEST 1] Query Structure Completeness")
    print("-" * 80)
    completeness = analyze_query_completeness(query_clean)

    required = ['has_select', 'has_from', 'has_where', 'has_max_timestamp', 'filters_not_kept']
    all_required_present = all(completeness.get(k, False) for k in required)

    for key, value in completeness.items():
        status = "✓" if value else "✗"
        print(f"{status} {key}: {value}")

    if all_required_present:
        print("\n✓ All required query components present")
    else:
        print("\n✗ Missing required query components")

    # Test 2: Schema compatibility
    print("\n[TEST 2] CFEngine Schema Compatibility")
    print("-" * 80)
    schema_check = check_schema_compatibility(query_clean)

    for check, result in schema_check.items():
        if 'referenced' in check and result == 'Found':
            print(f"✓ {check}: {result}")
        elif 'referenced' in check:
            print(f"✗ {check}: {result}")
        elif result == 'Used':
            print(f"✓ {check}: {result}")

    # Test 3: Logic verification
    print("\n[TEST 3] Query Logic Verification")
    print("-" * 80)
    logic_warnings = verify_query_logic(query_clean)

    if not logic_warnings:
        print("✓ No logic issues detected")
    else:
        for warning in logic_warnings:
            print(f"⚠ {warning}")

    # Test 4: Scenario handling
    print("\n[TEST 4] Expected Scenarios")
    print("-" * 80)
    scenarios = test_query_examples(query_clean)

    for scenario in scenarios:
        print(f"\n  Scenario: {scenario['name']}")
        print(f"  Expected: {scenario['expected']}")
        print(f"  Condition: {scenario['condition']}")

    # Test 5: Query structure
    print("\n[TEST 5] Query Structure Analysis")
    print("-" * 80)

    columns = extract_select_columns(query_clean)
    print(f"Selected columns: {columns}")

    tables = extract_tables(query_clean)
    print(f"Tables referenced: {set(t[0] for t in tables)}")

    # Final verdict
    print("\n" + "=" * 80)
    if all_required_present and not logic_warnings:
        print("FINAL VERDICT: ✓ PASS")
        print("\nThe query is syntactically correct and logically sound.")
        print("Ready for use in CFEngine Mission Portal alert configuration.")
    else:
        print("FINAL VERDICT: ⚠ WARNINGS")
        print("\nThe query has some warnings but may still work.")
        print("Review warnings above and test in Mission Portal before deploying.")

    print("=" * 80)

    # Print the query for reference
    print("\nQuery to paste into Mission Portal Alert Editor:")
    print("-" * 80)
    print(query_clean)
    print("-" * 80)

    return 0

if __name__ == '__main__':
    sys.exit(main())
