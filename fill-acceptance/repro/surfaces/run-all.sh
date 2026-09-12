#!/bin/bash
# Drives the CLI, MCP and the JS, Python and Java clients over the same cases,
# against a stock and a patched build, on both engines.
#
# Required:
#   VIBIUM_TREES    directory holding the built worktrees
#   VIBIUM_STOCK    tree dir name of the stock build      (default: stock)
#   VIBIUM_PATCHED  tree dir name of the patched build    (default: patched)
# Optional:
#   VIBIUM_WORK        scratch dir (default: $TMPDIR/vibium-evidence)
#   VIBIUM_CACHE_DIR   browser cache (default: the real ~/Library/Caches/vibium)
#   VIBIUM_JAR / VIBIUM_GSON   Java client jar and gson jar; both are discovered
#                              from VIBIUM_TREES and ~/.gradle if unset
#
# Prerequisites, per surfaces/README.md: build the JS client
# (npm install && npm -w clients/javascript run build) and the Java jar
# (cd clients/java && ./gradlew jar) in the STOCK tree; both are transport-only,
# so one build of each serves both binaries.
: "${VIBIUM_TREES:?set VIBIUM_TREES to the directory holding the built worktrees}"
REAL_HOME="$HOME"
SP="$VIBIUM_TREES"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${VIBIUM_WORK:-${TMPDIR:-/tmp}/vibium-evidence}"
CACHE_DIR="${VIBIUM_CACHE_DIR:-$REAL_HOME/Library/Caches/vibium}"
STOCK_TREE="${VIBIUM_STOCK:-stock}"
PATCHED_TREE="${VIBIUM_PATCHED:-patched}"
JAR="${VIBIUM_JAR:-$(ls "$SP/$STOCK_TREE"/clients/java/build/libs/vibium-*.jar 2>/dev/null | head -1)}"
GSON="${VIBIUM_GSON:-$(find "$REAL_HOME/.gradle/caches" -name 'gson-*.jar' 2>/dev/null | head -1)}"
[ -n "$JAR" ]  || echo "warning: no Java client jar found; the java rows will be missing" >&2
[ -n "$GSON" ] || echo "warning: no gson jar found; the java rows will be missing" >&2
CP="$JAR:$GSON"
if [ -n "$JAR" ] && [ -n "$GSON" ]; then
  mkdir -p "$WORK/javaout"
  javac -cp "$CP" -d "$WORK/javaout" "$HERE/Drive.java" || echo "warning: Drive.java did not compile" >&2
fi
# Fail fast rather than emit rows full of "No such file": a harness that keeps
# going with a missing binary reports absence as agreement.
for t in "$STOCK_TREE" "$PATCHED_TREE"; do
  [ -x "$SP/$t/clicker/bin/vibium" ] || { echo "no vibium binary at $SP/$t/clicker/bin/vibium" >&2; exit 2; }
done

for build in stock patched; do
  case $build in stock) T="$STOCK_TREE";; patched) T="$PATCHED_TREE";; esac
  V="$SP/$T/clicker/bin/vibium"
  for eng in chrome firefox; do
    export HOME=$WORK/h-$build-$eng VIBIUM_CONFIG_DIR=$WORK/h-$build-$eng/.config/vibium
    export VIBIUM_CACHE_DIR="$CACHE_DIR"
    export VIBIUM_SESSION=s$build$eng VIBIUM_ENGINE=$eng VIBIUM_BIN_PATH=$V
    mkdir -p "$VIBIUM_CONFIG_DIR"
    $V stop >/dev/null 2>&1
    # CLI
    for c in "number-abc|<input id=n type=number value=\"\">|#n|abc" \
             "date-bad|<input id=d type=date value=\"\">|#d|not-a-date" \
             "number-42|<input id=n type=number value=\"\">|#n|42"; do
      IFS='|' read -r cid html sel val <<< "$c"
      $V go "data:text/html,$html" >/dev/null 2>&1
      err=$($V fill "$sel" "$val" 2>&1 >/dev/null); rc=$?
      printf 'cli|%s|%s|%s|%s|%s\n' "$cid" "$($V value "$sel" 2>/dev/null)" "$(echo "$err"|head -1)" "$build" "$eng"
    done
    $V stop >/dev/null 2>&1
    node $HERE/mcp.mjs 2>/dev/null | sed "s|\$|\|$build\|$eng|"
    $V stop >/dev/null 2>&1
    node $HERE/js.mjs 2>/dev/null | sed "s|\$|\|$build\|$eng|"
    $V stop >/dev/null 2>&1
    PYTHONPATH="$SP/$STOCK_TREE/clients/python/src" python3 $HERE/py.py 2>/dev/null | sed "s|\$|\|$build\|$eng|"
    $V stop >/dev/null 2>&1
    java -cp "$WORK/javaout:$CP" Drive 2>/dev/null | sed "s|\$|\|$build\|$eng|"
    $V stop >/dev/null 2>&1
  done
done
