#!/bin/bash
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
export HOME=$WORK/F/hg-$B-$E VIBIUM_CONFIG_DIR=$WORK/F/hg-$B-$E/.config/vibium
export VIBIUM_CACHE_DIR="$CACHE_DIR" VIBIUM_SESSION=g$B$E VIBIUM_ENGINE=$E
mkdir -p "$VIBIUM_CONFIG_DIR"; $V stop >/dev/null 2>&1
o(){ printf '%s|%s|%s|%s|%s\n' "$B" "$E" "$1" "$2" "$3"; }
f(){ $V go "data:text/html,$2" >/dev/null 2>&1; $V fill "$3" "$4" --timeout 3000 >/dev/null 2>&1; local rc=$?; o "$1" "$($V value "$3")" "$rc"; }   # capture rc BEFORE running `value`
# the eight true-positive rows
f number  '<input id=x type=number value="">'         '#x' 'abc'
f date    '<input id=x type=date value="">'           '#x' 'not-a-date'
f time    '<input id=x type=time value="">'           '#x' '99'
f month   '<input id=x type=month value="">'          '#x' '2020-13'
f week    '<input id=x type=week value="">'           '#x' '2020-W99'
f dtl     '<input id=x type=datetime-local value="">' '#x' 'junk'
f color   '<input id=x type=color value=%23aabbcc>'   '#x' 'notacolor'
f range   '<input id=x type=range value=50>'          '#x' 'abc'
# valid controls must still succeed
f ok.number '<input id=x type=number value="">'       '#x' '42'
f ok.date   '<input id=x type=date value="">'         '#x' '2020-01-02'
f ok.color  '<input id=x type=color value=%23aabbcc>' '#x' '#00ff00'
f ok.range  '<input id=x type=range value=0>'         '#x' '75'
# normalization must not error
f n.text  '<input id=x type=text value="">'           '#x' 'a
b'
f n.email '<input id=x type=email value="">'          '#x' '  a@b.com  '
f n.color '<input id=x type=color value=%23aabbcc>'   '#x' '#00FF00'
# clear semantics (#187)
f clear.text  '<input id=x type=text value="hello">'  '#x' ''
f clear.color '<input id=x type=color value=%23aabbcc>' '#x' ''
f clear.range '<input id=x type=range value=75>'      '#x' ''
$V stop >/dev/null 2>&1
