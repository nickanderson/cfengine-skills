#!/usr/bin/env bash
# Tests for scripts/mp-api.sh.
#
# The contract that matters most is negative: the password never appears in
# anything the script prints, whatever goes wrong. Hermetic -- a local fake hub
# (plain HTTP, Basic auth, the real API's 406-on-Accept quirk) stands in for
# Mission Portal, so no network and no CFEngine.
set -uo pipefail

unset MP_URL MP_NETRC MP_CACERT MP_INSECURE MP_CONFIG  # only what each test sets
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../scripts/mp-api.sh"
PASS=0 FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
contains(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1" "missing [$3] in: $(printf '%s' "$2" | head -c 200)";; esac; }
absent(){ case "$2" in *"$3"*) bad "$1" "unexpected [$3]";; *) ok "$1";; esac; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mp-api-test.XXXXXX")
SECRET="s3cret-Pa55-$$"

# --- fake hub -----------------------------------------------------------------
cat > "$ROOT/hub.py" <<'PY'
import base64, json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
SECRET = sys.argv[1]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body):
        b = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def handle_any(self):
        if "application/json" in self.headers.get("Accept", ""):
            return self.reply(406, "Unsupported format or version requested")
        want = "Basic " + base64.b64encode(("apiuser:" + SECRET).encode()).decode()
        if self.headers.get("Authorization") != want:
            return self.reply(401, "Unauthorized")
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode() if n else ""
        if self.path == "/api/":
            return self.reply(200, {"data": [{"enterpriseVersion": "3.27.1"}], "meta": {}})
        if self.path in ("/api/echo", "/api/query"):
            return self.reply(200, {"method": self.command, "body": body,
                                    "ctype": self.headers.get("Content-Type", "")})
        self.reply(404, 'A resource matching URI "%s" was not found' % self.path)
    do_GET = do_POST = do_PUT = do_DELETE = handle_any
srv = HTTPServer(("127.0.0.1", 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
PY
coproc HUB { python3 "$ROOT/hub.py" "$SECRET"; }
read -r PORT <&"${HUB[0]}"
trap 'kill $HUB_PID 2>/dev/null; rm -rf "$ROOT"' EXIT
URL="http://127.0.0.1:$PORT"

printf 'machine other.example login someone password x\n' > "$ROOT/netrc"
# Multi-line entry: netrc is tokens, not lines.
printf 'machine 127.0.0.1\n  login apiuser\n  password %s\n' "$SECRET" >> "$ROOT/netrc"
chmod 600 "$ROOT/netrc"

run() {  # run <args...> with the good setup -> OUT (stdout+stderr), RC
  OUT=$(MP_CONFIG="$ROOT/none.conf" MP_URL="$URL" MP_NETRC="$ROOT/netrc" \
        bash "$SCRIPT" "$@" 2>&1); RC=$?
}
ALL=""

echo "1. --check"
run --check;          ALL+=$OUT
check    "exits 0"                  "$RC" "0"
contains "names hub, login, version" "$OUT" "as apiuser (CFEngine Enterprise 3.27.1)"

echo "2. GET and POST"
run GET /api/echo;    ALL+=$OUT
check    "GET exits 0"              "$RC" "0"
contains "GET reaches the hub"      "$OUT" '"method": "GET"'
run post /api/query '{"query":"SELECT 1"}'; ALL+=$OUT
contains "method is upper-cased"    "$OUT" '"method": "POST"'
contains "body is forwarded"        "$OUT" 'SELECT 1'
contains "body is sent as JSON"     "$OUT" '"ctype": "application/json"'
OUT=$(echo '{"from":"stdin"}' | MP_CONFIG="$ROOT/none.conf" MP_URL="$URL" MP_NETRC="$ROOT/netrc" \
      bash "$SCRIPT" POST /api/query - 2>&1)
contains "body - reads stdin"       "$OUT" 'from'

echo "3. errors"
run GET /api/nope;    ALL+=$OUT
check    "HTTP error exits 2"       "$RC" "2"
contains "names the status"         "$OUT" "HTTP 404"
run GET api/host
check    "relative path rejected"   "$RC" "1"
OUT=$(MP_CONFIG="$ROOT/none.conf" MP_URL="http://127.0.0.1:1" MP_NETRC="$ROOT/netrc" \
      bash "$SCRIPT" GET /api/ 2>&1); RC=$?; ALL+=$OUT
check    "transport failure exits 3" "$RC" "3"

echo "3b. read-only unless --write"
run DELETE /api/echo;  ALL+=$OUT
check    "DELETE refused"           "$RC" "1"
contains "says why and how"         "$OUT" "rerun with --write"
absent   "hub never contacted"      "$OUT" '"method"'
run POST /api/settings '{"x":1}'
check    "POST to a write endpoint refused" "$RC" "1"
run POST /api/health-diagnostic/report/nope '{"limit":1}'
check    "POST to a health report allowed (reaches hub: 404)" "$RC" "2"
run --write DELETE /api/echo; ALL+=$OUT
check    "--write DELETE exits 0"   "$RC" "0"
contains "--write reaches the hub"  "$OUT" '"method": "DELETE"'

echo "4. wrong password"
printf 'machine 127.0.0.1 login apiuser password wrong-%s\n' "$SECRET" > "$ROOT/netrc-bad"
OUT=$(MP_CONFIG="$ROOT/none.conf" MP_URL="$URL" MP_NETRC="$ROOT/netrc-bad" \
      bash "$SCRIPT" --check 2>&1); ALL+=$OUT
contains "--check reports 401"      "$OUT" "login rejected (HTTP 401)"
OUT=$(MP_CONFIG="$ROOT/none.conf" MP_URL="$URL" MP_NETRC="$ROOT/netrc-bad" \
      bash "$SCRIPT" GET /api/echo 2>&1); RC=$?; ALL+=$OUT
check    "request exits 2"          "$RC" "2"

echo "5. not configured"
OUT=$(MP_CONFIG="$ROOT/none.conf" MP_URL="" bash "$SCRIPT" --check 2>&1); RC=$?
check    "--check still exits 0"    "$RC" "0"
contains "says what is missing"     "$OUT" "no hub URL"
OUT=$(MP_CONFIG="$ROOT/none.conf" MP_URL="http://unlisted.example" MP_NETRC="$ROOT/netrc" \
      bash "$SCRIPT" --check 2>&1)
contains "missing netrc entry"      "$OUT" "no entry for unlisted.example"
contains "shows the setup"          "$OUT" "machine unlisted.example login <your-login>"

echo "6. config file"
printf 'url = %s/\ninsecure=0\n' "$URL" > "$ROOT/mp.conf"
OUT=$(MP_CONFIG="$ROOT/mp.conf" MP_NETRC="$ROOT/netrc" bash "$SCRIPT" --check 2>&1); ALL+=$OUT
contains "url= is read, trailing / ok" "$OUT" "as apiuser"
printf 'url=$(touch %s/pwned)\n' "$ROOT" > "$ROOT/evil.conf"
MP_CONFIG="$ROOT/evil.conf" MP_NETRC="$ROOT/netrc" bash "$SCRIPT" --check >/dev/null 2>&1
if [ -e "$ROOT/pwned" ]; then bad "config is parsed, never sourced"; else ok "config is parsed, never sourced"; fi

echo "7. the password never appears"
absent   "in any output above"      "$ALL" "$SECRET"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
