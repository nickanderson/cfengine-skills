#!/bin/bash

# Query CFEngine Enterprise Mission Portal for unhealthy hosts
# Output format: <category>,<hostkey>

python3 << 'EOF'
import asyncio
import os
import re
import sys
from playwright.async_api import async_playwright

async def main():
    mp_url = os.environ.get('MP_URL', '').rstrip('/')
    mp_user = os.environ.get('MP_USER')
    mp_password = os.environ.get('MP_PASSWORD')

    if not all([mp_url, mp_user, mp_password]):
        print("Error: MP_URL, MP_USER, and MP_PASSWORD must be set", file=sys.stderr)
        return

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True, args=['--no-sandbox', '--disable-setuid-sandbox'])
        context = await browser.new_context(ignore_https_errors=True)
        page = await context.new_page()

        try:
            # Navigate to login page
            await page.goto(f"{mp_url}/login/index", timeout=30000)

            # Fill and submit login form
            await page.fill('input[name="username"]', mp_user)
            await page.fill('input[name="password"]', mp_password)

            submit_button = await page.query_selector('button[type="submit"]')
            if not submit_button:
                submit_button = await page.query_selector('input[type="submit"]')

            if submit_button:
                await submit_button.click()

                # Wait for login to complete
                try:
                    await page.wait_for_url('**', timeout=15000)
                except:
                    pass

            # Try to access different pages that might show health information
            # First try the dashboard which might show unhealthy hosts
            await page.goto(f"{mp_url}/dashboard", timeout=15000)

            try:
                await page.wait_for_load_state('networkidle', timeout=10000)
            except:
                pass

            # Execute JavaScript to get any health data from Angular scope
            health_data = await page.evaluate('''
                () => {
                    // Try to find health information from various sources
                    const results = [];

                    // Look for any elements with unhealthy/error class
                    document.querySelectorAll('[class*="unhealthy"], [class*="error"], [class*="critical"]').forEach(el => {
                        const text = el.textContent || el.innerText || '';
                        if (text.includes('SHA=') || text.match(/SHA=[A-Fa-f0-9]+/)) {
                            results.push(text);
                        }
                    });

                    // Look for data in table cells or list items
                    document.querySelectorAll('td, li, div').forEach(el => {
                        const text = el.textContent;
                        if ((text.toLowerCase().includes('unhealthy') ||
                             text.toLowerCase().includes('critical') ||
                             text.toLowerCase().includes('error')) &&
                            (text.includes('SHA=') || text.match(/SHA=[A-Fa-f0-9]+/))) {
                            results.push(text.trim());
                        }
                    });

                    return results;
                }
            ''')

            # Process results
            for item in health_data:
                # Look for patterns of status followed by SHA
                pattern = r'(unhealthy|critical|error|warning|failed)[:\s]*(SHA=[A-Fa-f0-9]+)'
                matches = re.findall(pattern, item, re.IGNORECASE)
                for status, hostkey in matches:
                    print(f"{status},{hostkey}")

            # If no health data found, try the reports/health page
            if not health_data:
                await page.goto(f"{mp_url}/reports/health", timeout=15000)

                try:
                    await page.wait_for_load_state('networkidle', timeout=10000)
                except:
                    pass

                # Get content and parse
                content = await page.content()

                # Look for any JSON-like data with hostkey and health status
                # Try various patterns that might contain health information
                patterns = [
                    r'"hostkey"\s*:\s*"([^"]+)"[^}]*"health"\s*:\s*"([^"]+)"',
                    r'"hostkey"\s*:\s*"([^"]+)"[^}]*"status"\s*:\s*"([^"]+)"',
                    r'SHA=([A-Fa-f0-9]+)[^}]*(?:unhealthy|critical|error|failed|warning)',
                    r'(?:unhealthy|critical|error|failed|warning)[^}]*(SHA=[A-Fa-f0-9]+)'
                ]

                for pattern in patterns:
                    matches = re.findall(pattern, content, re.IGNORECASE)
                    if matches:
                        for item in matches:
                            if isinstance(item, tuple):
                                hostkey, status = item
                                if status.lower() not in ['ok', 'healthy', 'normal']:
                                    print(f"{status},{hostkey}")
                            else:
                                # Single item - probably a hostkey from an unhealthy context
                                if item.startswith('SHA='):
                                    # Try to find the status from context
                                    hostkey_pattern = f"{item}[^}}]*(?:unhealthy|error|critical|warning|failed)"
                                    if re.search(hostkey_pattern, content, re.IGNORECASE):
                                        # Found this host in context with a status keyword
                                        status_match = re.search(r'(unhealthy|error|critical|warning|failed)[^}}]*' + re.escape(item), content, re.IGNORECASE)
                                        if status_match:
                                            print(f"{status_match.group(1)},{item}")

        finally:
            await browser.close()

asyncio.run(main())
EOF
