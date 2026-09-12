#!/bin/bash
# Paths come from the environment so this runs on any machine:
#   VIBIUM_TREES  directory holding the built worktrees, each with clicker/bin/vibium
#   VIBIUM_WORK   scratch dir for sandboxed HOMEs (default: $TMPDIR/vibium-evidence)
#   VIBIUM_CACHE_DIR  browser cache (default: the real ~/Library/Caches/vibium)
: "${VIBIUM_TREES:?set VIBIUM_TREES to the directory holding the built worktrees}"
REAL_HOME="$HOME"
SP="$VIBIUM_TREES"
WORK="${VIBIUM_WORK:-${TMPDIR:-/tmp}/vibium-evidence}"
CACHE_DIR="${VIBIUM_CACHE_DIR:-$REAL_HOME/Library/Caches/vibium}"
build=$1; T=$2; eng=$3
V="$SP/$T/clicker/bin/vibium"
export HOME=$WORK/ht-$build-$eng VIBIUM_CONFIG_DIR=$WORK/ht-$build-$eng/.config/vibium
export VIBIUM_CACHE_DIR="$CACHE_DIR" VIBIUM_SESSION=t$build$eng VIBIUM_ENGINE=$eng
mkdir -p "$VIBIUM_CONFIG_DIR"; $V stop >/dev/null 2>&1
W='style="width:100px"'
row() { # type seed
  $V go "data:text/html,<input id=x type=$1 value=\"$2\" $W>" >/dev/null 2>&1
  err=$($V type "#x" "99" --timeout 3000 2>&1 >/dev/null)
  printf '%s|%s|%s|%s|%s\n' "$build" "$eng" "$1" "$($V value '#x' 2>/dev/null)" "$(echo "$err"|head -1)"
}
row text 1234567890; row password 1234567890; row number 1234567890; row email abcdefghij
row date 2020-01-02; row time 10:30; row month 2020-01; row week 2020-W02
row datetime-local 2020-01-02T10:30
$V stop >/dev/null 2>&1
