# `fill` reports success for a value the field cannot hold, and leaves the field empty

> Filed upstream as **[#530](https://github.com/VibiumDev/vibium/issues/530)**.

`vibium fill "#d" "not-a-date"` prints `Filled "not-a-date" into #d`, exits 0, and leaves the field empty. The same holds for `fill "#n" "abc"` on a number input, and for the whole date family, `color` and `range`. An agent filling a form has no way to notice: the command succeeded, and the next step submits an empty field.

The cause is that `buildSetValueScript` writes through the native `value` setter and then returns `'ok'` without ever reading the value back. Assigning through that setter runs the type's [value sanitization algorithm](https://html.spec.whatwg.org/multipage/input.html#value-sanitization-algorithm), which for these types discards a string it cannot parse — silently, throwing nothing.

Every table in this report is also rendered as a standalone page — **[Fill Acceptance Measurements](https://lana-20.github.io/vibium-input-findings/fill-acceptance/)** — next to the scripts that produced it and their raw output.

## Repro (~5s, no network)

Build `main` first — `make build-go`. A `main` build still reports `vibium v26.8.21`, so the version string will not tell it apart from the release.

```
$ vibium go 'data:text/html,<input id="d" type="date"><input id="n" type="number">'
Navigated to data:text/html,<input id="d" type="date"><input id="n" type="number">
$ vibium fill "#d" "not-a-date"
Filled "not-a-date" into #d
$ echo $?
0
$ vibium value "#d"

$ vibium fill "#n" "abc"
Filled "abc" into #n
$ vibium value "#n"

```

Both fields are empty. Same on Firefox — add `--engine firefox` to `go` (with a browser already running the flag is refused: `chrome is already running; requested firefox`).

## Scope

The fourteen input types that hold an editable value — `text`, `search`, `url`, `tel`, `password`, `email`, `number`, `date`, `time`, `month`, `week`, `datetime-local`, `color`, `range` — plus `textarea` were swept, both engines, page reloaded before every action: 31 value cases per engine, 62 in total. **Every one exits 0.** Fifteen do not round-trip on Chrome, thirteen on Firefox, and they fall into three groups that need to be told apart:

| group | types | example | field afterwards |
|---|---|---|---|
| **rejected → empty** | `number`, `date`, `time`, `month`, `week`, `datetime-local` | `fill "#d" "not-a-date"` | `""` |
| **rejected → substitute** | `color`, `range` | `fill "#c" "notacolor"` | `"#000000"`, `"50"` |
| normalized | `text`, `email`, `textarea` | `fill "#t" $'a\nb'` | `"ab"` |

Only the first two groups are the bug. The third is the same sanitization algorithm doing what it is specified to do — stripping line breaks from a single-line input, trimming an `email`, folding CRLF in a `textarea` — and must not be reported as a failure. `color` lowercasing `#00FF00` to `#00ff00` and `range` clamping `150` to `100` belong with it as normalizations of an accepted value.

Firefox differs on two rows: it does not implement `month` or `week`, renders them as ordinary text inputs, and so keeps whatever it is given. Both are Chrome-only.

One command per group, four `fill`s reporting success and not one of them storing its value (note the `%23` — a bare `#` in a `data:` URL starts the fragment and truncates the markup):

```
$ vibium go 'data:text/html,<input id="a" type="number"><input id="b" type="date"><input id="c" type="color" value="%23aabbcc"><input id="r" type="range" max="100">'
Navigated to data:text/html,<input id="a" type="number"><input id="b" type="date"><input id="c" type="color" value="%23aabbcc"><input id="r" type="range" max="100">
$ vibium fill "#a" "abc";       vibium fill "#b" "not-a-date"
$ vibium fill "#c" "notacolor"; vibium fill "#r" "abc"
Filled "abc" into #a
Filled "not-a-date" into #b
Filled "notacolor" into #c
Filled "abc" into #r
$ vibium eval '["a="+a.value, "b="+b.value, "c="+c.value, "r="+r.value].join(" | ")'
a= | b= | c=#000000 | r=50
```

## Root cause

[`buildSetValueScript`](https://github.com/VibiumDev/vibium/blob/dd48732/clicker/internal/api/handlers_interaction.go#L1165) sets the value and returns `'ok'` unconditionally:

```js
			if (nativeSetter) {
				nativeSetter.call(el, value);
			} else {
				el.value = value;
			}
			el.dispatchEvent(new Event('input', { bubbles: true }));
			el.dispatchEvent(new Event('change', { bubbles: true }));
			return 'ok';
```

— [`handlers_interaction.go:1182-1189`](https://github.com/VibiumDev/vibium/blob/dd48732/clicker/internal/api/handlers_interaction.go#L1182-L1189)

The assignment cannot throw, so there is nothing for the callers to catch, and both of them treat `'ok'` as proof the field took the value: [`Fill`](https://github.com/VibiumDev/vibium/blob/dd48732/clicker/internal/api/handlers_interaction.go#L823) (reached by the CLI and MCP through [`browserFill`](https://github.com/VibiumDev/vibium/blob/dd48732/clicker/internal/agent/handlers.go#L2528)) and [`handleVibiumFill`](https://github.com/VibiumDev/vibium/blob/dd48732/clicker/internal/api/handlers_interaction.go#L64) (the three language clients). One builder, so one fix covers all five surfaces — and all five were measured rather than inferred from that.

The same builder also serves [`handleVibiumClear`](https://github.com/VibiumDev/vibium/blob/dd48732/clicker/internal/api/handlers_interaction.go#L179), which calls it with `""` — which is why the fix below exempts empty writes rather than checking every call.

`skills/browser/SKILL.md:135` tells agents `fill` is "clear field and type new text (replaces value)", with no note that the replacement may not stick.

This is probably not only here: the same coarse type model is why `type` cannot tell these types apart either. [`FillableInputTypesJS`](https://github.com/VibiumDev/vibium/blob/dd48732/clicker/internal/api/actionability.go#L179) is the one place input types are modeled, and it answers one question — may `fill` set this value — so `number` and `email` sit in it beside `text`, though unlike `text` they cannot carry a caret, which is what #507 is about.

## Every surface, both engines

`number` ← `"abc"` and `date` ← `"not-a-date"`, plus `number` ← `"42"` as a control that proves each surface is wired up, on Chrome and Firefox, against stock and patched builds of `dd48732`: 60 runs. **Every surface agrees with every other in all twelve combinations.**

| surface | stock | patched |
|---|---|---|
| CLI | `Filled …`, exit 0 | exit 1, `Error: failed to fill: fill: input[type=number] did not accept "abc"; the field holds ""` |
| MCP (`browser_fill` over stdio JSON-RPC) | success content, no `isError` | `isError`, same message |
| JavaScript | resolves | throws `Error` |
| Python | returns | raises `BiDiError` |
| Java | returns | throws `VibiumException` |

Stock leaves the field empty on all five, on both engines, with nothing raised and nothing to inspect. Patched refuses on all five with the message intact, and the control still fills to `42` everywhere. The Java type is the generic `VibiumException` rather than one of the specific ones, which is the right outcome here: #483's substring classifier has no pattern matching this message, so it does not misfile it.

## Patch

Check that the write took, and let the existing `val != "ok"` path turn a failure into an error. 2 files, +115. Each family is asked the question it can answer: `number` and the five date types can hold the empty string, so a wholesale rejection shows up directly as an empty field after a non-empty write; `range` and `color` always hold *something*, so they are asked instead whether the value was a number, or a hex color, at all.

The type list and the read-back check are the whole mechanism; the rest of the diff is the doc comment explaining why the other types are left alone.

```diff
@@ -1184,6 +1184,50 @@ func buildSetValueScript(ep ElementParams, value string) (string, []map[string]i
 			} else {
 				el.value = value;
 			}
+			// Check the write took before reporting success. Assigning through
+			// the value IDL attribute runs the type's value sanitization
+			// algorithm, which can discard a string outright while the
+			// assignment itself throws nothing: the field is left empty
+			// (number, and the date family) or moved to a substitute (color,
+			// range). Without this check fill answers "ok" for a value the field
+			// never took, and the caller goes on to submit an empty form.
+			//
+			// What is NOT checked is equally deliberate. Comparing the value
+			// back byte-for-byte would fail on ordinary, spec-mandated
+			// normalization and report a healthy write as an error: a range
+			// snaps to its step (55 -> 60) and clamps to its bounds, a
+			// datetime-local folds "2020-01-02 10:30" to the T form and drops a
+			// trailing ":00", a color expands "#abc" to "#aabbcc", and the
+			// text-like types strip line breaks or trim. Every one of those was
+			// stored. So each family is asked the question it can actually
+			// answer.
+			//
+			// An empty value is exempt throughout: it is what clear writes
+			// through this same builder, and #187 established that fill "" means
+			// "clear the field".
+			if (value !== '' && el instanceof window.HTMLInputElement) {
+				const t = el.type;
+				let rejected = false;
+				if (['number', 'date', 'time', 'month', 'week', 'datetime-local'].indexOf(t) !== -1) {
+					// These can hold the empty string, so a wholesale rejection
+					// is visible directly: the field is empty after a non-empty
+					// write.
+					rejected = el.value === '';
+				} else if (t === 'range') {
+					// A range always holds some number, so emptiness cannot be
+					// the signal. Snapping and clamping are sanitization; a value
+					// that is not a number at all is a rejection.
+					rejected = isNaN(Number(String(value).trim()));
+				} else if (t === 'color') {
+					// Likewise a color always holds some color. Accepts
+					// #rgb and #rrggbb; anything else lands on #000000.
+					rejected = !/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(String(value).trim());
+				}
+				if (rejected) {
+					return 'input[type=' + t + '] did not accept "' + value +
+						'"; the field holds "' + el.value + '"';
+				}
+			}
 			el.dispatchEvent(new Event('input', { bubbles: true }));
 			el.dispatchEvent(new Event('change', { bubbles: true }));
 			return 'ok';
```

With it, `fill "#d" "not-a-date"` exits 1 with `Error: failed to fill: fill: input[type=date] did not accept "not-a-date"; the field holds ""`, and the Python client raises `BiDiError` carrying the same text. The check runs before the `input`/`change` events, so a rejected write no longer announces itself to the page.

The second file adds three tests to the existing `CLI: fill edge cases` suite in `tests/cli/engine/input-tools.test.js` — one for the rejection, and two asserting that a value the control merely normalized still succeeds: the line-break and color-case pair, and the five accepted-but-transformed cases above. Against stock the rejection test fails and the normalization tests pass.

Cherry-pick it or ignore it; the measurements are the part worth having.

### What it deliberately leaves alone

- **Normalization is not an error.** Stripping a line break, trimming an email, folding CRLF and lowercasing a color all still exit 0.
- **`fill ""` still clears.** #187 established that, and `clear` goes through this same builder — a color input cannot hold `""`, so checking empty writes would break both. `fill "#c" ""` therefore still exits 0 with the field on `#000000`.
- **Normalization of an accepted value is never an error, and that is where a literal round-trip check goes wrong.** A `range` snaps to its step (`55` -> `60`) and clamps to its bounds (`150` -> `100`); a `datetime-local` folds `2020-01-02 10:30` to the `T` form and drops a trailing `:00`; a `color` expands `#abc` to `#aabbcc`. Every one of those was stored, and comparing the value back byte-for-byte reports all five as failures. The per-family tests above exist precisely to avoid that, and the patch carries a regression test for each case.

## Prior art

Playwright treats this as two separate failures and errors on both: `fill` refuses a non-numeric value for `number` up front (`Cannot type text into input[type=number]`), and for `color`, `date`, `time`, `datetime-local`, `month`, `range` and `week` it sets and then verifies — `if (input.value !== value) throw 'Malformed value'` (`packages/injected/src/injectedScript.ts`, `fill`). Its text-like types are typed rather than set, so normalization never trips the check. The patch above lands in the same place by a shorter route, with one deliberate difference: reading its `fill`, Playwright would also throw on `fill('')` into a color input, which #187 rules out here.

Both of those were run, not just read, against the same Chrome build (see Environment) — and so was Selenium, which does **not** validate:

| | `number` ← `"abc"` | `date` ← `"not-a-date"` |
|---|---|---|
| **Vibium** `fill` | `Filled "abc" into #n`, exit 0, field empty | `Filled "not-a-date" into #d`, exit 0, field empty |
| **Playwright** `locator.fill` | throws `Cannot type text into input[type=number]` | throws `Malformed value` |
| **Selenium** `element.sendKeys` | no exception, field empty | no exception, field empty |

Selenium has no `fill`, so the comparison is `sendKeys`, and the two columns are not the same test. For `date` it is: the UA renders it as something other than a text input, so Element Send Keys takes the non-typeable branch quoted below, and the implementation neither sets the value nor reports bad input. For `number` it is not — a desktop `number` is a text input, so the keys are simply typed and Chrome drops the non-numeric ones; the empty field there is the browser's doing, not a skipped check. Either way the caller is told nothing.

So this is the majority behavior rather than a Vibium peculiarity, with Playwright the outlier that gets it right. That is the honest framing of the gap: worth closing because a silent empty field is worth closing, not because everyone else already does.

The W3C WebDriver [Element Send Keys](https://w3c.github.io/webdriver/#element-send-keys) algorithm makes the same call for a non-typeable form control: *"Set a property value to text on element. If element is suffering from bad input return an error with error code invalid argument."* Write through the property, then check the control and error — Vibium has had the write half and not the check half. The spec requires it; the measurement above is that the reference implementation does not deliver it either, so the spec is the argument here, not existing practice.

Related, all closed: #187 (`fill ""` must clear), #181 and #188 (`range` rejected by the editable check), #264 (three copies of the editable predicate disagreeing), #117 (the `<textarea>` native-setter fix that put the current code in place). #507 and #488 are the `type`/`press` side of the same surface, where `fill` is the suggested way to set the types `type` cannot append to — which is how this turned up.

## Environment

Upstream `dd48732`, built from source; the patch also applies clean to `e63bb73`, `main` as of 2026-09-11, where the defect reproduces identically. Chrome for Testing 152.0.7977.82, Firefox 155.0, macOS arm64, Go 1.27.0. The cross-tool table was taken separately on the installed Chrome for Testing 152.0.7977.54, shared by all three tools — Playwright 1.63.0 through `executablePath`, Selenium 4.49.0 through a matching ChromeDriver 152.0.7977.54 — with the Vibium rows re-run on that build and identical to the ones above. `git apply --check` clean at `dd48732`; `go build ./...`, `go vet ./...` and `go test ./...` pass, as do `tests/cli/engine/{input-tools,elements,actionability,type-append,storage}.test.js` (45 tests before the three added here, 14 in `input-tools` after). The five-surface table was taken with the JS client built from `clients/javascript` and the Java client from its jar, both pointed at the build under test with `VIBIUM_BIN_PATH`.

---

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

## What else is here

| path | |
|---|---|
| `patch/` | 2 files, +115. Applies clean at `dd48732` and at `e63bb73` |
| `index.html` | the measurement tables as one standalone page — rendered at the link above |
| `repro/` | every script needed to re-derive the tables |
| `data/` | the raw output those scripts produced, as checked in |

`data/normalization-before.txt` and `-after.txt` are the same battery run against
a literal round-trip check and against the one the patch ships.
