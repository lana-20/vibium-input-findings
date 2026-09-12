#!/bin/bash
# 24 elements x 2 widths x 2 actions = 96 cells
# Paths come from the environment so this runs anywhere:
#   VIBIUM_TREES      dir holding the built worktrees, each with clicker/bin/vibium
#   VIBIUM_WORK       scratch dir for sandboxed HOMEs (default: $TMPDIR/vibium-repro)
#   VIBIUM_CACHE_DIR  browser cache (default: ~/Library/Caches/vibium)
: "${VIBIUM_TREES:?set VIBIUM_TREES to the directory holding the built worktrees}"
REAL_HOME="$HOME"
SP="$VIBIUM_TREES"
WORK="${VIBIUM_WORK:-${TMPDIR:-/tmp}/vibium-repro}"
CACHE_DIR="${VIBIUM_CACHE_DIR:-$REAL_HOME/Library/Caches/vibium}"
B=$1; E=$2; V=$SP/$B/clicker/bin/vibium
export HOME=$WORK/T/h-$B-$E VIBIUM_CONFIG_DIR=$WORK/T/h-$B-$E/.config/vibium
export VIBIUM_CACHE_DIR="$CACHE_DIR" VIBIUM_SESSION=b$B$E VIBIUM_ENGINE=$E
mkdir -p "$VIBIUM_CONFIG_DIR"; $V stop >/dev/null 2>&1
TYPES="text search tel url password email number date time month week datetime-local color range checkbox radio file hidden button submit reset image"
seed(){ case $1 in date) echo 2020-01-02;; time) echo 10:30;; month) echo 2020-01;; week) echo 2020-W02;;
  datetime-local) echo 2020-01-02T10:30;; color) echo %23aabbcc;; range) echo 50;; email|url) echo abcdefghij;; *) echo 1234567890;; esac; }
cell(){ printf '%s|%s|%s|%s|%s|%s|%s\n' "$B" "$E" "$1" "$2" "$3" "$4" "$5"; }
for wname in def w100; do
  [ $wname = w100 ] && STY='style="width:100px"' || STY=''
  for t in $TYPES; do
    s=$(seed $t)
    # action: type
    $V go "data:text/html,<input id=x type=$t value=\"$s\" $STY>" >/dev/null 2>&1
    $V type "#x" "99" --timeout 2000 >/dev/null 2>&1; rc=$?
    cell "$wname" "$t" type "$($V value '#x' 2>/dev/null)" "$rc"
    # action: press Backspace  (press takes no --timeout; hidden costs the full wait)
    $V go "data:text/html,<input id=x type=$t value=\"$s\" $STY>" >/dev/null 2>&1
    $V press Backspace "#x" >/dev/null 2>&1; rc=$?
    cell "$wname" "$t" press "$($V value '#x' 2>/dev/null)" "$rc"
  done
  # textarea + contenteditable
  $V go "data:text/html,<textarea id=x $STY>1234567890</textarea>" >/dev/null 2>&1
  $V type "#x" "99" --timeout 2000 >/dev/null 2>&1; rc=$?; cell "$wname" textarea type "$($V value '#x' 2>/dev/null)" "$rc"
  $V go "data:text/html,<textarea id=x $STY>1234567890</textarea>" >/dev/null 2>&1
  $V press Backspace "#x" >/dev/null 2>&1; rc=$?; cell "$wname" textarea press "$($V value '#x' 2>/dev/null)" "$rc"
  $V go "data:text/html,<div id=x contenteditable $STY>1234567890</div>" >/dev/null 2>&1
  $V type "#x" "99" --timeout 2000 >/dev/null 2>&1; rc=$?; cell "$wname" contenteditable type "$($V eval 'document.getElementById("x").textContent' 2>/dev/null)" "$rc"
  $V go "data:text/html,<div id=x contenteditable $STY>1234567890</div>" >/dev/null 2>&1
  $V press Backspace "#x" >/dev/null 2>&1; rc=$?; cell "$wname" contenteditable press "$($V eval 'document.getElementById("x").textContent' 2>/dev/null)" "$rc"
done
$V stop >/dev/null 2>&1
