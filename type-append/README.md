# `type` breaks its documented append contract on seven input types

`vibium type` and `press` are documented as appending to a field's existing value
— `clients/javascript/src/element.ts:109`, `clients/java/.../Element.java:58`,
`skills/browser/SKILL.md:134`. On `number` and `email` the focusing click leaves
the caret mid-value and the text is spliced into the middle. On `date`, `time`,
`month`, `week` and `datetime-local` there is no caret to place at all and a
keystroke overwrites a segment instead. Seven types on Chrome; five on Firefox,
which renders `month` and `week` as ordinary text inputs.

`ISSUE.md` is the report. The same results are rendered as **[a single page](./)**,
which needs no server and fetches nothing but a webfont.

## See it in ten seconds

```sh
vibium go 'data:text/html,<input id="n" type="number" value="1234567890" style="width:100px">'
vibium type "#n" "99"
vibium value "#n"          # 123456997890 — spliced after character 6, not appended
```

Exit status is 0 throughout. The width is pinned because the caret lands at the
character nearest the center of the field: at `width:400px` the center falls past
the end of the text and the same commands append correctly. That is the mechanism,
not a caveat — it is why every repro here pins a width and why the regression
tests assert *appended* rather than a literal string.

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

Build a second tree with `patch/507-type-no-caret-inputs.patch` applied, put both
under one directory, and point the scripts at it:

```sh
export VIBIUM_TREES=/path/to/builds        # each subdir has clicker/bin/vibium

cd repro
bash vibium-type.sh stock   <stock-dir>   chrome    # and firefox
bash vibium-type.sh patched <patched-dir> chrome

npm i playwright-core selenium-webdriver                 # no browser download needed
node playwright.mjs        > ../data/playwright.ndjson
node selenium.mjs          > ../data/selenium.ndjson
node selenium-probe.mjs                                  # widths 60/100/400 + the selection API

bash blast.sh  <patched-dir> chrome    # 96 cells per build per engine
bash probes.sh <patched-dir> chrome    # events, min/max/step, valueAsNumber, form state
python3 verify-blocks.py ../ISSUE.md <stock-dir>   # re-runs the report's own blocks
```

Playwright and Selenium are pointed at the Chrome for Testing build Vibium already
installs, so nothing turns on a browser difference. `VIBIUM_WORK` overrides the
scratch directory, `VIBIUM_CACHE_DIR` the browser cache, and `CHROME_BIN` /
`CHROMEDRIVER_BIN` pin a specific browser build.

`repro/react-controlled.html` is the fixture behind the React row; it loads React
from a CDN so it runs as-is.

## What is here

| path | |
|---|---|
| `ISSUE.md` | the report — repros, cause, and the patch inline |
| `patch/` | 3 files, +214/−19. Applies clean at `dd48732` and at `e63bb73` |
| `index.html` | the measurement tables as one standalone page — rendered at the link above |
| `repro/` | every script needed to re-derive the tables |
| `data/` | the raw output those scripts produced, as checked in |

`data/blast.txt` and `data/blast-rerun.txt` are two independent runs of the same
96-cell sweep; they agree cell for cell.

## Environment

Measured at `dd48732` and reproduced identically at `e63bb73`. Chrome for Testing
152.0.7977.54 and .82 — identical results on both — Firefox 155.0, Playwright
1.63.0, Selenium 4.49.0 with `webSocketUrl: true`, Node 24.10.0, Go 1.27.0,
macOS arm64. The Playwright and Selenium columns are Chrome-only: Playwright
cannot drive a stock Firefox, it needs its own patched build.

## Two things that argue against the patch

**It changes 16 of 96 cells on Chrome and 10 on Firefox**, and nothing else moves
— no `color`, `range`, `checkbox`, `file` or `button` cell shifts. The changed
cells are `number` and `email` appending, their `press` taking the last character,
and the five segmented types going from a silent exit 0 to `rc=1`.

**On the segmented types it makes Vibium the only one of the three tools measured
that refuses to write at all.** Playwright and Selenium both overwrite a segment
and report success, exactly as stock Vibium does. The case for refusing is that
neither of them documents `type` as appending and Vibium does, and that a
valid-looking wrong date is worse than a failure — but that is a judgment, and
the two halves of the patch are independent if you weigh parity differently.
