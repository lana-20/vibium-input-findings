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
export HOME=$WORK/F/h-$B-$E VIBIUM_CONFIG_DIR=$WORK/F/h-$B-$E/.config/vibium
export VIBIUM_CACHE_DIR="$CACHE_DIR" VIBIUM_SESSION=f$B$E VIBIUM_ENGINE=$E
mkdir -p "$VIBIUM_CONFIG_DIR"; $V stop >/dev/null 2>&1
t(){ # label html selector value
  $V go "data:text/html,$2" >/dev/null 2>&1
  err=$($V fill "$3" "$4" --timeout 3000 2>&1 >/dev/null); rc=$?
  printf '%s|%s|%s|%s|%s|%s\n' "$B" "$E" "$1" "$4" "$($V value "$3")" "$rc"
}
# legitimate values the browser NORMALISES — a naive equality check errors on these
t range.step        '<input id=x type=range min=0 max=100 step=10 value=0>'        '#x' '55'
t range.inrange     '<input id=x type=range min=0 max=100 step=10 value=0>'        '#x' '60'
t range.clamp.high  '<input id=x type=range min=0 max=100 value=0>'                '#x' '150'
t dtl.space         '<input id=x type=datetime-local value="">'                    '#x' '2020-01-02 10:30'
t dtl.T             '<input id=x type=datetime-local value="">'                    '#x' '2020-01-02T10:30'
t dtl.seconds       '<input id=x type=datetime-local value="">'                    '#x' '2020-01-02T10:30:00'
t time.seconds      '<input id=x type=time value="">'                              '#x' '10:30:45'
t time.zeroes       '<input id=x type=time value="">'                              '#x' '10:30:00'
t number.plus       '<input id=x type=number value="">'                            '#x' '+5'
t number.leaddot    '<input id=x type=number value="">'                            '#x' '.5'
t number.trailzero  '<input id=x type=number value="">'                            '#x' '5.00'
t number.step       '<input id=x type=number step=10 value="">'                    '#x' '55'
t color.upper       '<input id=x type=color value=%23aabbcc>'                      '#x' '#ABCDEF'
t color.short       '<input id=x type=color value=%23aabbcc>'                      '#x' '#abc'
t date.min          '<input id=x type=date min=2020-01-01 max=2020-12-31 value="">' '#x' '2019-05-05'
t week.noPad        '<input id=x type=week value="">'                              '#x' '2020-W2'
$V stop >/dev/null 2>&1
