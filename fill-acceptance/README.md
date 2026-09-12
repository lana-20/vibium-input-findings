# `fill` reports success for a value the field cannot hold

`buildSetValueScript` writes through the native `value` setter and returns `'ok'`
without reading anything back. Assigning through that setter runs the type's value
sanitization algorithm, which can discard the string outright while throwing
nothing — so the command reports success for a value the field never took.

`ISSUE.md` is the report. The same results are rendered as **[a single page](https://lana-20.github.io/vibium-input-findings/fill-acceptance/)**,
which needs no server and fetches nothing but a webfont.

## See it in five seconds

```sh
vibium go 'data:text/html,<input id="d" type="date"><input id="n" type="number">'
vibium fill "#d" "not-a-date"     # Filled "not-a-date" into #d
echo $?                           # 0
vibium value "#d"                 # empty
vibium fill "#n" "abc"            # Filled "abc" into #n
vibium value "#n"                 # empty
```

`color` and `range` fail the same way but land on a substitute instead of empty:
`notacolor` becomes `#000000`, `abc` on a slider becomes `50`. An empty required
field usually surfaces at submit; a plausible substitute does not surface at all.

## Reproducing the measurements

Build Vibium from source first. A fresh worktree will not build until the
Makefile's four `cp` steps have run — `SKILL.md`, `CHECK_SKILL.md` and the two env
templates are `go:embed`ed but not tracked in git:

```sh
cp skills/browser/SKILL.md  clicker/cmd/clicker/SKILL.md
cp skills/check/SKILL.md    clicker/cmd/clicker/CHECK_SKILL.md
cp config/ai.env            clicker/cmd/clicker/AI_ENV_TEMPLATE
cp config/cloud-browser.env clicker/cmd/clicker/CLOUD_ENV_TEMPLATE
cd clicker && go build -o bin/vibium ./cmd/clicker
```

Build a second tree with `patch/fill-roundtrip-check.patch` applied, put both under
one directory, and point the scripts at it:

```sh
export VIBIUM_TREES=/path/to/builds        # each subdir has clicker/bin/vibium

cd repro
VIBIUM_TREE=<stock-dir>   python3 sweep.py chrome     # 31 cases, and firefox
VIBIUM_TREE=<patched-dir> python3 sweep.py chrome

bash normalization.sh <patched-dir> chrome   # values the browser normalizes, not rejects
bash grid.sh          <patched-dir> chrome   # the eight rejections, controls, and clear

npm i playwright-core selenium-webdriver              # no browser download needed
node playwright.mjs > ../data/playwright.ndjson
node selenium.mjs   > ../data/selenium.ndjson

cd surfaces                                           # CLI, MCP, JS, Python, Java
VIBIUM_STOCK=<stock-dir> VIBIUM_PATCHED=<patched-dir> bash run-all.sh
```

The language clients need `VIBIUM_BIN_PATH` pointing at the build under test or
they resolve the installed release and a patched tree tests as unpatched;
`run-all.sh` sets it. Its JS driver needs
`npm install && npm -w clients/javascript run build` and its Java driver
`./gradlew jar` in the stock tree — both layers are transport-only, so one build
of each serves both binaries.

## What is here

| path | |
|---|---|
| `ISSUE.md` | the report — repro, cause, and the patch inline |
| `patch/` | 2 files, +115. Applies clean at `dd48732` and at `e63bb73` |
| `index.html` | the measurement tables as one standalone page — rendered at the link above |
| `repro/` | every script needed to re-derive the tables |
| `data/` | the raw output those scripts produced, as checked in |

`data/normalization-before.txt` and `-after.txt` are the same battery run against
a literal round-trip check and against the one the patch ships.

## Environment

Measured at `dd48732` and reproduced identically at `e63bb73`. Chrome for Testing
152.0.7977.54 and .82 — identical results on both — Firefox 155.0, Playwright
1.63.0, Selenium 4.49.0 with `webSocketUrl: true`, Node 24.10.0, Go 1.27.0,
macOS arm64. The Playwright and Selenium columns are Chrome-only: Playwright
cannot drive a stock Firefox, it needs its own patched build.

## Two things worth reading before the tables

**The check cannot be a literal round trip, and that is the whole design.**
Comparing the value back byte-for-byte reports healthy writes as failures: a
`range` snaps to its `step` (`55` → `60`) and clamps to its bounds
(`150` → `100`); a `datetime-local` folds `2020-01-02 10:30` to the `T` form and
drops a trailing `:00`; a `color` expands `#abc` to `#aabbcc`. All five were
stored. So each family is asked what it can answer — an empty field for the types
that can be empty, and whether the value parsed as a number or a hex color for
`range` and `color`, which always hold something. The patch carries a regression
test for each of those five cases.

**Not validating is the majority behavior.** Playwright refuses both bad values;
Selenium raises nothing and leaves the field empty, exactly as Vibium does. The
argument for closing the gap is the spec and the silent empty field, not that
every other tool already does it.
