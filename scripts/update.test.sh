#!/usr/bin/env bash
# Tests for update.sh, run against stand-ins for curl and rmail-parser.
# Run: bash scripts/update.test.sh
#
# R-Forge is being retired, so the case that matters most is the one where it
# no longer answers: the run must finish promptly, keep every archived file,
# and still re-parse and re-index what it has.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; fail=1; }

mkdir -p "$TMP/bin"
# Stand-in parser: writes the stats files update.sh moves into place.
cat > "$TMP/bin/rmail-parser" <<'PARSER'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do case "$1" in --output) out="$2"; shift ;; esac; shift; done
echo '{"total_messages": 3, "total_threads": 2, "first_message": "2010-01-01T00:00:00Z", "last_message": "2010-02-01T00:00:00Z"}' > "$out/meta.json"
for f in index.json message-order.json contributors.json; do echo '[]' > "$out/$f"; done
PARSER
# Stand-in curl: logs the URL it was asked for, then behaves as $CURL_MODE says.
cat > "$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift ;; http*) url="$1" ;; esac; shift; done
echo "$url" >> "$CURL_LOG"
case "$CURL_MODE" in
  down) exit 28 ;;                                    # connection timed out
  gone-list) case "$url" in */alpha-list/) exit 22 ;; esac ;;   # HTTP 404 for one list only
  bad-file) case "$url" in *.txt.gz|*.txt) exit 56 ;; esac ;;   # index fine, download fails
esac
case "$url" in
  */) echo '<A href="2010-January.txt">[ Text 1 KB ]</a> <A href="2010-March.txt">[ Text 1 KB ]</a>' ;;
  *)  echo "From a at b  Mon Jan  4 10:00:00 2010" > "$out" ;;
esac
CURL
chmod +x "$TMP/bin/rmail-parser" "$TMP/bin/curl"

# scenario NAME MODE -> a fresh two-list archive, run update.sh against it
scenario() {
  ROOT="$TMP/$1"; export CURL_MODE="$2" CURL_LOG="$TMP/$1/curl.log"
  mkdir -p "$ROOT/scripts"
  cp "$DIR/update.sh" "$ROOT/scripts/"
  for list in alpha-list beta-list; do
    mkdir -p "$ROOT/$list/raw"
    echo "{\"list\": \"$list\", \"description\": \"d\", \"source_url\": \"https://lists.example.org/pipermail/$list/\"}" > "$ROOT/$list/config.json"
    echo "archived january for $list" > "$ROOT/$list/raw/2010-January.mbox"
  done
  : > "$CURL_LOG"
  PATH="$TMP/bin:$PATH" RMAIL_PARSER="$TMP/bin/rmail-parser" bash "$ROOT/scripts/update.sh" "${@:3}" > "$ROOT/out.log" 2>&1
  STATUS=$?
}
calls() { grep -c . "$CURL_LOG"; }
kept() { [ "$(cat "$ROOT/$1/raw/2010-January.mbox")" = "archived january for $1" ]; }

scenario source-down down
[ "$STATUS" = "0" ] && pass "an unreachable source is not a failure" || { bad "an unreachable source is not a failure: exit $STATUS"; sed 's/^/        /' "$ROOT/out.log"; }
kept alpha-list && kept beta-list && pass "and every archived file is kept" || bad "and every archived file is kept"
[ "$(calls)" = "1" ] && pass "and it stops asking after the first list times out" || bad "and it stops asking after the first list times out: $(calls) requests"
[ "$(($(wc -l < "$ROOT/lists.tsv") - 1))" = "2" ] && pass "and the lists are still parsed and indexed" || bad "and the lists are still parsed and indexed"

scenario one-list-gone gone-list
grep -q "beta-list/2010-March.txt" "$CURL_LOG" && pass "a single list answering 404 does not stop the others" || bad "a single list answering 404 does not stop the others"
[ ! -e "$ROOT/alpha-list/raw/2010-March.mbox" ] && kept alpha-list && pass "and that list keeps what it had" || bad "and that list keeps what it had"

scenario download-fails bad-file --force
[ "$STATUS" = "0" ] && kept alpha-list && kept beta-list && pass "a failed download never replaces an archived file, even when forced" || bad "a failed download never replaces an archived file, even when forced"

scenario all-well ok
[ -s "$ROOT/alpha-list/raw/2010-March.mbox" ] && kept alpha-list && pass "a new period is downloaded and a finished one is left alone" || bad "a new period is downloaded and a finished one is left alone"
grep -q -- "--connect-timeout" "$DIR/update.sh" && grep -q -- "--max-time" "$DIR/update.sh" && pass "every request has a connect and a total time limit" || bad "every request has a connect and a total time limit"

exit "$fail"
