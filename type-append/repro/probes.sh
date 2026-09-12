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
export HOME=$WORK/T/ha-$B-$E VIBIUM_CONFIG_DIR=$WORK/T/ha-$B-$E/.config/vibium
export VIBIUM_CACHE_DIR="$CACHE_DIR" VIBIUM_SESSION=a$B$E VIBIUM_ENGINE=$E
mkdir -p "$VIBIUM_CONFIG_DIR"; $V stop >/dev/null 2>&1
W='style="width:100px"'
r(){ printf '  %-3s %-8s %-30s %s\n' "$B" "$E" "$1" "$2"; }
# 1. min/max/step preserved across the swap, and validity after typing
$V go "data:text/html,<input id=x type=number value=5 min=1 max=10 step=1 $W>" >/dev/null 2>&1
$V type "#x" "9" >/dev/null 2>&1
r "min/max/step + type 9" "$($V eval '(function(){var e=document.getElementById("x");return "value="+e.value+" min="+e.min+" max="+e.max+" step="+e.step+" valid="+e.checkValidity()+" asNumber="+e.valueAsNumber})()')"
# 2. valueAsNumber survives
$V go "data:text/html,<input id=x type=number value=1234567890 $W>" >/dev/null 2>&1
$V type "#x" "99" >/dev/null 2>&1
r "valueAsNumber after type" "$($V eval 'String(document.getElementById("x").valueAsNumber)')"
# 3. does the swap itself fire input/change/keydown noise?
$V go "data:text/html,<input id=x type=number value=1234567890 $W><script>window.__k=[];for(const n of ['input','change','keydown','keyup','keypress'])document.getElementById('x').addEventListener(n,()=>window.__k.push(n));</script>" >/dev/null 2>&1
$V type "#x" "9" >/dev/null 2>&1
r "events fired by type" "$($V eval 'window.__k.join(",")')"
# 4. empty field
$V go "data:text/html,<input id=x type=number value=\"\" $W>" >/dev/null 2>&1
$V type "#x" "42" >/dev/null 2>&1; r "empty number + type 42" "[$($V value '#x')]"
# 5. decimal / leading zero preserved
$V go "data:text/html,<input id=x type=number value=1.50 $W>" >/dev/null 2>&1
$V type "#x" "9" >/dev/null 2>&1; r "value 1.50 + type 9" "[$($V value '#x')]"
# 6. inside a form: does the swap disturb form state / submit value?
$V go "data:text/html,<form id=f onsubmit=\"window.__s=1;return false\"><input id=x name=q type=number value=1234567890 $W></form>" >/dev/null 2>&1
$V type "#x" "99" >/dev/null 2>&1
r "in form, type attr after" "$($V eval '(function(){var e=document.getElementById("x");return "type="+e.type+" name="+e.name+" formEl="+(e.form?e.form.id:"none")})()')"
# 7. MutationObserver on attributes: how many type mutations does the caller see?
$V go "data:text/html,<input id=x type=number value=1234567890 $W><script>window.__m=[];new MutationObserver(ms=>{for(const m of ms)window.__m.push(m.attributeName)}).observe(document.getElementById('x'),{attributes:true});</script>" >/dev/null 2>&1
$V type "#x" "9" >/dev/null 2>&1
r "attribute mutations seen" "[$($V eval 'window.__m.join(",")')]"
# 8. email[multiple] validity after append
$V go "data:text/html,<input id=x type=email multiple value=\"aa@b.co,cc@d.co\" $W>" >/dev/null 2>&1
$V type "#x" ",ee@f.co" >/dev/null 2>&1
r "email[multiple] valid?" "$($V eval '(function(){var e=document.getElementById("x");return "value="+e.value+" valid="+e.checkValidity()})()')"
$V stop >/dev/null 2>&1
