# `type` breaks its documented append contract on seven input types, not just `number`
Split out of #488, #507 covers `input[type=number]`. Sweeping all 22 HTML input types shows `type` breaks its documented append contract on seven of them on Chrome — five on Firefox, which renders `month` and `week` as ordinary text inputs where the append works — and that they split into two groups with different causes, only one of which is the #488 mechanism. For `number` and `email` the focusing click is provably the cause: remove it and the corruption disappears entirely. For the five segmented date types there is no caret to misplace in the first place, and they misbehave with or without a click.

Nothing in #507 is wrong — its `number` report reproduces as written on Chrome at the default width, and at any width narrow enough for the value to reach the click point. It stops reproducing once the field is wide enough that the center of the box falls past the end of the text: at `width:400px` the same commands append correctly (`123456789099`) on both engines. That is this issue's own mechanism, not a contradiction of it, and it is why every repro below pins a width. This is the same defect measured across the whole type surface, and the patch at the end fixes both, so #507 can close with it.

## Repro (~1s, no network)

Build `main` first — `make build-go`. The released v26.8.21 (2026-08-21) predates `7f88254` and contains no `caretToEnd` at all, so on that build every text field is affected and these seven do not stand out. Note that a `main` build still reports `vibium v26.8.21`, so the version string will not tell the two apart. Everything below is Chrome. For the other engine run `vibium stop` first and then add `--engine firefox` to each command — with a browser already running the flag is refused (`chrome is already running; requested firefox`).

Every measurement here is at `dd48732`. The 22-type sweep in the next section was first taken at `5964275`; re-running it at `dd48732` gives all 144 recorded lines identical on both engines, which is what `handlers_interaction.go` and `clients/` being byte-identical between the two commits predicts.

**A — `type` splices into the middle of a number input.**

```
$ vibium go 'data:text/html,<input id="n" type="number" value="1234567890" style="width:100px">'
Navigated to data:text/html,<input id="n" type="number" value="1234567890" style="width:100px">
$ vibium type "#n" "99"
Typed into element: #n
$ vibium value "#n"
123456997890
```

Spliced after character 6, not appended. The `style` attribute only makes the splice large and layout-independent; it is not what causes it. Drop it and Chrome still corrupts — the same three commands give `123456789990`, spliced before the last character, and `press Backspace` gives `123456780`, deleting the ninth. Firefox at default width is the one case that appends cleanly (`123456789099`), and only by a hair: its number input is 189px wide against Chrome's 147px, so the center of the box lands 5.0px past the end of the value instead of 4.6px short of it. Both engines sit within one character (~7–9px) of that boundary, so a repro that does not pin a width is decided by font, zoom and engine defaults. Pin the width and it is not — which is why a regression test should fix the width and assert *appended* rather than a literal value.

**B — `press` deletes the wrong character, and the click is provably the cause.**

```
$ vibium go 'data:text/html,<input id="n" type="number" value="1234567890" style="width:100px">'
Navigated to data:text/html,<input id="n" type="number" value="1234567890" style="width:100px">
$ vibium press Backspace "#n"
Pressed Backspace
$ vibium value "#n"
123457890
```

Character 6 is gone, not the last one. Now the same field with the click removed — `press` with no selector acts on whatever is already focused, so focusing from JS skips `ClickAtCenter`:

```
$ vibium go 'data:text/html,<input id="n" type="number" value="1234567890" style="width:100px">'
Navigated to data:text/html,<input id="n" type="number" value="1234567890" style="width:100px">
$ vibium eval "(function(){document.getElementById('n').focus();return 'ok'})()"
ok
$ vibium press Backspace
Pressed Backspace
$ vibium value "#n"
1234567890
```

Nothing is deleted, on both engines, because a freshly focused input puts the caret at offset 0 and `Backspace` at the start is a no-op. The corruption is entirely a product of the focusing click, and `caretToEnd` is the step that is supposed to undo it but cannot on these types.

Both engines print `123456997890` for A, so the splice index tracks layout rather than engine — worth knowing for a regression test, which should assert "appended" rather than a literal value.

**On the date family, `press Backspace` is a different thing and does not belong to this bug.** `vibium press Backspace "#d"` on `<input type="date" value="2020-01-02">` leaves the value empty on both engines at any width — but so does the `focus()`-only form above, with no click involved. Clearing a segment makes the date incomplete and the HTML value sanitization algorithm then reports `""`. That is native behavior and any tool would produce it; it is silent and exits 0, which is worth knowing, but it is not caused by the caret and no fix here would change it. What *is* caused by the click is which segment a key lands in: on Chrome `press 5` edits the **year** at default width (`0005-01-02`) and the **month** at `width:100px` (`2020-05-02`), while `focus()` without a click gives `2020-05-02` at every width. Firefox ignores the key on `date` entirely.

## The affected set

All 22 input types plus `textarea` and `contenteditable`, two widths, both engines:

| verdict | types |
|---|---|
| **Click-derived corruption** — the #488 mechanism, both engines | `number`, `email` — spliced mid-value whenever the value reaches the click point |
| **Segmented, no caret to place** — overwrites a segment instead of appending, Chrome | `date`, `time`, `month`, `week`, `datetime-local` |
| Same five on Firefox | `month`, `week` render as text inputs and append correctly; `date`, `time`, `datetime-local` ignore the keys and still exit 0 |
| Correct — `caretToEnd` reaches them | `text`, `search`, `tel`, `url`, `password`, `textarea`, `contenteditable` |
| Unaffected — no editable text value | `color`, `range`, `checkbox`, `radio`, `button`, `submit`, `reset`, `image` |
| Refused correctly (`rc=1`, visible check) | `hidden` |
| Silent no-op — reports success, value stays empty | `file` |

**"Overwrites a segment" is the worse of the two failures, not the milder one.** A segmented input has no string to append to: Chrome renders `date` as three independent spin-button segments, so each keystroke *replaces* whichever segment holds focus. Seeded `2020-01-02`, `type "99"` gives `2020-09-09` — the month became `09`, focus advanced, the day became `09`. `time` `10:30` gives `09:09`, and on `week` the click lands on the year, so `2020-W02` gives `0009-W09`. Unlike the `number` splice, which is visibly mangled, every one of those is a **well-formed value that will pass validation downstream** — silently not the one that was there, at exit 0.

Seventeen types have no selection API, but only these seven have an editable text-like value to get wrong.

The table is one paste, about six seconds, no fixture file. It prints the exit status as well as the value, because for one type the exit status *is* the result:

```sh
for t in text search tel url password email number date time month week datetime-local \
         color range checkbox radio file hidden button submit reset image; do
  case $t in
    date) v=2020-01-02;; time) v=10:30;; month) v=2020-01;; week) v=2020-W02;;
    datetime-local) v=2020-01-02T10:30;; color) v=%23aabbcc;; range) v=50;;
    email|url) v=abcdefghij;; *) v=1234567890;;
  esac
  vibium go "data:text/html,<input id=x type=$t value=\"$v\" style=\"width:100px\">" >/dev/null
  vibium type "#x" "99" --timeout 2000 >/dev/null 2>&1
  printf '%-16s rc=%s %s\n' "$t" "$?" "$(vibium value '#x' 2>&1 | head -1)"
done
```

It prints:

```
text             rc=0 123456789099
search           rc=0 123456789099
tel              rc=0 123456789099
url              rc=0 abcdefghij99
password         rc=0 123456789099
email            rc=0 abcdefg99hij
number           rc=0 123456997890
date             rc=0 2020-09-09
time             rc=0 09:09
month            rc=0 2020-09
week             rc=0 0009-W09
datetime-local   rc=0 2020-09-09T10:30
color            rc=0 #aabbcc
range            rc=0 50
checkbox         rc=0 1234567890
radio            rc=0 1234567890
file             rc=0 
hidden           rc=1 1234567890
button           rc=0 1234567890
submit           rc=0 1234567890
reset            rc=0 1234567890
image            rc=0 1234567890
```

`text`, `search`, `tel`, `url` and `password` come back appended; `number` and `email` spliced; the five date types with a segment overwritten instead — which segment depends on the field's width, so the exact value differs from the table above while the verdict does not; `file` reports success and stays empty; `hidden` is the only one that fails, and only the exit status says so — its value is unchanged, which is indistinguishable from the inert types unless you print `rc`. Two details are load-bearing. The `%23` in the `color` seed: a bare `#` in a `data:` URL starts the fragment and truncates the markup. And `--timeout 2000`: `hidden` fails an actionability check that waits the full default 30s, which is the whole runtime of the sweep if you leave it out.

`multiple` does not change the picture and is worth one line because it is where the damage looks worst: `input[type=email][multiple]` still throws on `setSelectionRange`, so a list gets spliced. In a field styled `font:16px monospace;width:100px`, appending `,ee@f.co` to `aa@b.co,cc@d.co` produces **`aa@b.,ee@f.coco,cc@d.co`** on both engines — two addresses destroyed rather than one appended:

```
vibium go 'data:text/html,<style>input{font:16px monospace;width:100px}</style><input id="m" type="email" multiple value="aa@b.co,cc@d.co">'
vibium type "#m" ",ee@f.co"
vibium value "#m"
```

The styling is load-bearing for the exact string, not for the defect: the splice index is the character nearest the center of the box, so it moves with font and width. At the browser default font and the same 100px the same command gives `aa@b.c,ee@f.coo,cc@d.co` on both engines; at default width the engines part company — `aa@b.co,cc,ee@f.co@d.co` on Chrome, `aa@b.co,cc@d,ee@f.co.co` on Firefox. Two addresses are wrecked in every one of those.

And the corruption is not confined to the DOM. On a React controlled `number` input the spliced value goes through `onChange` into component state: in the same `font:16px monospace;width:100px` fixture, after `type "99"` the state holds `123459967890`, so anything downstream of that state is working from the corrupted value too. React is not what sets that index — a plain, uncontrolled `number` input in the same fixture splices to the identical `123459967890`. What React adds is that the wrecked value is now in application state, not only in the DOM.

The two groups were separated by measurement, not by reading the code. Comparing a clicked `press 5` against a `focus()`-only one across all 24 elements: `number` and `email` differ (clicked splices mid-value, `focus()` prepends), so the click is the cause. The segmented types give the identical result either way at most widths — `time` and `week` on Chrome, and every one of them at `width:400px` — so for them the click is not what is wrong. The exception is narrow: on Chrome at **default** width the click does pick a different segment than focus for `date`, `month` and `datetime-local` (`0005-01-02` vs `2020-05-02`). Either way, a key overwrites a segment rather than appending, which is the contract violation.

## Every client surface, both engines

The same `caretToEnd` serves both implementations — `TypeInto`/`PressOn` for CLI and MCP, `handleVibiumType`/`handleVibiumPress` for the router the language clients reach — so all five surfaces were measured rather than assumed. They are five entry points onto those two paths rather than five independent ones: `vibium type` issues `browser_type` to the daemon and MCP's `tools/call` lands in the same `browserType` handler, and the three language clients all send `vibium:element.type`. So what the matrix demonstrates is that both paths are affected and both are fixed, on both engines — not that five separate implementations happen to agree. Same fixture throughout: `date` `2020-01-02` + one `press Backspace`; `number` `1234567890` at `width:100px` + `type "99"`; the same at `type=text` as a control; `email` `abcdefghij` at `width:100px` + `type "99"`.

| surface | `date` + Backspace | `number` + `"99"` | `text` + `"99"` (control) | `email` + `"99"` |
|---|---|---|---|---|
| CLI | **empty** | `123456997890` | `123456789099` ✓ | `abcdefg99hij` / `abcdef99ghij` |
| MCP | **empty** | `123456997890` | `123456789099` ✓ | `abcdefg99hij` / `abcdef99ghij` |
| JavaScript | **empty** | `123456997890` | `123456789099` ✓ | `abcdefg99hij` / `abcdef99ghij` |
| Python | **empty** | `123456997890` | `123456789099` ✓ | `abcdefg99hij` / `abcdef99ghij` |
| Java | **empty** | `123456997890` | `123456789099` ✓ | `abcdefg99hij` / `abcdef99ghij` |

All five surfaces agree on both engines — ten runs of four cases, with no cell differing between surfaces. The fix was re-checked the same way: with the patch applied, all five surfaces append correctly on `number` (`123456789099`) and `email` (`abcdefghij99`) on both engines, so it reaches the language clients as well as the CLI. Where two values are shown they are Chrome / Firefox. The control column appends everywhere, which is what proves each surface is wired correctly and that `caretToEnd` does reach it. MCP was driven as a real client — `vibium mcp --headless` over stdio JSON-RPC, `tools/call` for `browser_navigate`, `browser_type`, `browser_press`, `browser_get_value` — not as a CLI wrapper.

`email` splices after character 7 on Chrome and 6 on Firefox, identically on all five surfaces, while `number` splices after 6 on both. The index tracks font metrics, so it is engine-dependent for some fixtures and not others.

## Cause

`caretToEnd` ([`handlers_interaction.go:853`](https://github.com/VibiumDev/vibium/blob/dd487326445739776792ed4bdff54913bcb5b9f6/clicker/internal/api/handlers_interaction.go#L853)) restores the append contract by collapsing the caret after the focusing click. Its guard is `n !== null && typeof el.setSelectionRange === 'function'` ([`:856`](https://github.com/VibiumDev/vibium/blob/dd487326445739776792ed4bdff54913bcb5b9f6/clicker/internal/api/handlers_interaction.go#L856)) — and both halves are **true for all 22 input types**: `el.value` is a string on every one of them, so `n` is never null, and `setSelectionRange` exists on every `HTMLInputElement`. The call is made, throws `InvalidStateError`, and the empty `catch` on [`:860`](https://github.com/VibiumDev/vibium/blob/dd487326445739776792ed4bdff54913bcb5b9f6/clicker/internal/api/handlers_interaction.go#L860) swallows it.

So the guard cannot distinguish these types. Detecting them needs an explicit type list or a deliberate probe. Nothing else in the codebase makes that distinction either: [`FillableInputTypesJS`](https://github.com/VibiumDev/vibium/blob/dd48732/clicker/internal/api/actionability.go#L179) is the one place input types are modeled, and it is a single flat list of what `fill` may set — correct for `fill`, and no help here, since `number` and `email` are in it. That is why the patch below carries its own list rather than reusing one. (The comment on [`:857`](https://github.com/VibiumDev/vibium/blob/dd487326445739776792ed4bdff54913bcb5b9f6/clicker/internal/api/handlers_interaction.go#L857) already names number, email and date correctly — it is the guard above it that cannot act on that knowledge.)

The contract these seven miss is documented in three places, none with a carve-out: [`element.ts:109`](https://github.com/VibiumDev/vibium/blob/dd487326445739776792ed4bdff54913bcb5b9f6/clients/javascript/src/element.ts#L109), [`Element.java:58`](https://github.com/VibiumDev/vibium/blob/dd487326445739776792ed4bdff54913bcb5b9f6/clients/java/src/main/java/com/vibium/Element.java#L58), [`SKILL.md:134`](https://github.com/VibiumDev/vibium/blob/dd487326445739776792ed4bdff54913bcb5b9f6/skills/browser/SKILL.md#L134).

Worth ruling out the obvious alternative: focusing without clicking, the way Playwright does, removes the corruption but does not satisfy that contract. A freshly focused input puts the caret at offset 0, so the text lands at the **front** — `focus()` then `press 9` on `1234567890` gives `91234567890` on both engines. So dropping the click is not sufficient on its own; the caret has to be placed deliberately, which is what the fix below does.

## How Playwright and WebDriver handle this

The W3C WebDriver spec specifies the behavior #488 restored, and it splits the types the same way this patch does. [Element Send Keys](https://w3c.github.io/webdriver/#element-send-keys) runs the first matching branch of four, and which branch an element takes turns on whether the user agent renders it as a text input. `number` and `email` on a desktop do, so they fall through to the last branch: if the element was not already focused, set the caret *"using set selection range using current text length for both the start and end parameters"*, then dispatch the keys — `caretToEnd` followed by `TypeText`, exactly. Content-editable has its own branch, *"set the text insertion caret after any child content"*, which is `caretToEnd`'s other arm. A *non-typeable form control* — defined as one *"rendered by the user agent as something other than as a text input control"*, which is what the five segmented date types are — never receives keys at all: *"Set a property value to text on element. If element is suffering from bad input return an error with error code invalid argument."* That sets rather than appends, so it is not option 1 exactly; what it endorses is the shape — write through the property, then check the control's state and **error** rather than leave a wrecked value behind. Vibium has the write half of that as `fill` — `buildSetValueScript` goes through the native `value` setter and fires `input`/`change` — and that is where the patch sends the caller. It does not have the check half, which is worth saying since the patch now points at it: `vibium fill "#d" "not-a-date"` prints `Filled "not-a-date" into #d`, exits 0, and leaves the field empty, as does `fill "#n" "abc"` on a number. The spec requires `invalid argument` in exactly that case and Playwright's `fill` throws `Malformed value`. Adjacent to this bug rather than part of it, and not something this patch changes. The one place the spec calls `number` non-typeable is *"on non-desktop devices"*, where it is a number keypad rather than a text field.

Playwright's typing path cannot reach this bug, because it never clicks to focus: `_type` and `_press` both call `_focus(progress, true /* resetSelectionIfNotFocused */)` (`packages/playwright-core/src/server/dom.ts`), and `focusNode` then puts the caret at offset 0 with `input.setSelectionRange(0, 0)` inside a `try`/`catch` commented *"Some inputs do not allow selection"* (`packages/injected/src/injectedScript.ts`). It swallows the identical `InvalidStateError` in the identical shape, and harmlessly — no click ever put a caret mid-value, and the caret it aims for is the front of the field rather than the end, because `type` there is not documented as appending. That is the same position the `focus()` control above lands in, which is why copying it would not satisfy this contract. Its `fill` then partitions the types explicitly: `color`, `date`, `time`, `datetime-local`, `month`, `range` and `week` are set rather than typed, the write is verified with `if (input.value !== value) throw 'Malformed value'`, and a non-numeric value for `number` is refused up front instead of being written and silently sanitized to empty.

And the reason this one is ours rather than everyone's: it follows from driving the browser over BiDi alone. The spec allows a BiDi session to be either an HTTP session that has opted into a WebSocket by requesting the `webSocketUrl` capability, or a *BiDi-only session* — one "which is not a HTTP Session". Selenium is the first shape, where enabling BiDi is purely additive: every classic endpoint stays, and `sendKeys` still issues `POST /session/{id}/element/{id}/value` (`defineCommand(SEND_KEYS_TO_ELEMENT, post(elementId + "/value"))`, `AbstractHttpCommandCodec`), so Element Send Keys and the caret rule above come with it — with one caveat, measured in the next section: chromedriver delivers that rule only on types whose selection API works. On `number` and `email` it lands at offset 0, the same place Playwright does. Vibium speaks BiDi for everything: a local launch connects straight to a BiDi WebSocket, and against a classic grid endpoint it creates a session only to read back the `webSocketUrl` and to `DELETE` it afterwards (`clicker/internal/bidi/classic.go`) — no classic element command is ever issued. So none of that is inherited here, and [BiDi](https://w3c.github.io/webdriver-bidi/) does not supply it: its input module is three commands — `input.performActions`, `input.releaseActions`, `input.setFiles` — and the word "caret" does not appear anywhere in that spec. `input.performActions` does defer to classic WebDriver, but to its *actions* section, where `dispatch a keyDown action` takes a browsing context rather than an element: it presses keys at whatever holds focus and says nothing about where the caret should be. The caret rule lives in Element Send Keys, which BiDi has no equivalent of, so a tool in this position has to supply that rule itself. That is what `caretToEnd` is.

## Measured against Playwright and Selenium

The paragraphs above are read out of those projects' source. This table is the same claims run, against **the same Chrome build Vibium uses** — the installed Chrome for Testing 152.0.7977.54, pointed at by `executablePath` for Playwright and by a matching ChromeDriver 152.0.7977.54 for Selenium — so nothing here turns on a browser difference. Playwright 1.63.0 (`playwright-core`), Selenium 4.49.0 with `webSocketUrl: true`, i.e. a classic HTTP session that has opted into a BiDi WebSocket, which the session capabilities confirm.

The three tools spell the same three operations differently: append is `vibium type` / `locator.pressSequentially` / `element.sendKeys`; the keypress is `vibium press` / `locator.press` / `sendKeys(Key.BACK_SPACE)`; setting a value outright is `vibium fill` / `locator.fill` / `sendKeys` again, since Selenium has no `fill` and Element Send Keys *is* the spec's set-a-property path for a control the UA does not render as a text input. Fixtures are the ones used throughout this issue, `width:100px` where a width is shown.

| # | case | Vibium stock | Vibium + patch | Playwright 1.63.0 | Selenium 4.49.0, BiDi on |
|---|---|---|---|---|---|
| F1 | append `99` to `number` `1234567890` | `123456997890` spliced | `123456789099` ✓ | `991234567890` prepended | `991234567890` prepended |
| F2 | append `99` to `email` `abcdefghij` | `abcdefg99hij` spliced | `abcdefghij99` ✓ | `99abcdefghij` prepended | `99abcdefghij` prepended |
| F3 | append `99` to `text` `1234567890` — **control** | `123456789099` ✓ | `123456789099` ✓ | `991234567890` prepended | `123456789099` ✓ |
| F4 | `Backspace` on `number` `1234567890` | `123457890` — 6th char | `123456789` ✓ | `1234567890` no-op | `1234567890` no-op |
| F5 | append `99` to `date` `2020-01-02` | `0099-01-02` segment | error, value unchanged ✓ | `2020-09-09` segments | `2020-09-09` segments |
| F6 | set `number` to `abc` | `""`, exit 0 | `""`, exit 0 | **throws** `Cannot type text into input[type=number]` | `""`, no exception |
| F7 | set `date` to `not-a-date` | `""`, exit 0 | `""`, exit 0 | **throws** `Malformed value` | `""`, no exception |

Three things fall out of it.

**F3 is why the control column matters.** Selenium appends on `text` and Playwright does not, which is the caret rule in Element Send Keys showing up in exactly one of the two — and confirms that enabling BiDi on a Selenium session leaves the classic path intact, because that is where the rule lives. Driving it with ChromeDriver's verbose log on, the command that arrives for `sendKeys` is the classic `TypeElement`, while the session simultaneously carries a `webSocketUrl`.

**But that rule stops at the selection API, which is this bug's whole subject.** On F1 and F2 Selenium lands at offset 0 exactly like Playwright, at every width I tried (60px, 100px, 400px — a prepend does not move with width; a click-point splice does). The reason is the same `InvalidStateError` this issue is about: measured through Selenium, `setSelectionRange(3,3)` on a `number` input throws it and `selectionStart` reads `null`. So no tool in this table appends on `number` or `email` today. **The patch makes Vibium the one that does** — that is the column to look at, rather than any claim that the others get it right.

**F6 and F7 are the adjacent gap, and only Playwright closes it.** Playwright refuses both, with the two errors quoted earlier reproduced verbatim. Selenium silently leaves the field empty and raises nothing, and Vibium — patched or not — prints `Filled …` and exits 0. So `fill`'s missing validation is not a Vibium peculiarity; it is the majority behavior, with Playwright the outlier that gets it right. This patch does not change it, and it is filed separately rather than folded in here.

The drivers are about twenty lines each and are reproducible from this issue: launch Chromium with `executablePath` set to a Chrome for Testing binary, or build a Selenium `ServiceBuilder` on the matching ChromeDriver, then walk the seven fixtures above.

## On #507's options — `number` and `email` need none of them

The three options all assume the caret cannot be placed on these types. It can. The same element exposes `setSelectionRange` while its `type` is `text`, and the value survives the round trip, so the caret can be set by borrowing it:

```js
const t = el.type, n = String(el.value).length;
el.type = 'text';
el.setSelectionRange(n, n);
el.type = t;
```

Measured on both engines, `width:100px`, `1234567890` then `press 5`: clicked gives `12345657890`, and with the swap `12345678905` — a correct append. `email` likewise: `abcdefg5hij` clicked on Chrome and `abcdef5ghij` on Firefox, against `abcdefghij5` on both with the swap.

That is better than either option on every axis I measured, because the keys stay real: key events still fire (`keydown, keypress, input, keyup`), `maxlength` still truncates, a `readonly` field is still left alone, and `type` stays "character by character" as `Element.java:58` documents. Writing the value through the setter — option 1 — loses all four, and I have the measurements from trying it: it silently exceeded `maxlength` by a character, wrote into a `readonly` field, and reduced the events to `input, change`. It also fixes `press`, which option 1 could not touch: `press Backspace` on a narrow number now deletes the last character instead of the sixth.

The one cost is that the swap is observable — a `MutationObserver` watching attributes sees `type` change twice. Measured: on stock such an observer records nothing, on the patch it records `type, type`. That seems a fair price, and it is the only difference I could find from ordinary typing. Probed alongside it and unchanged either way: the events fired (`keydown, keypress, input, keyup`), `min`/`max`/`step` and the validity they imply, `valueAsNumber`, a decimal value, an empty field, and the element's `name`/`form` association.

**The five segmented types still need option 2**, and for a reason no fix can route around: they have no caret to place. The swap does not help — it succeeds and the value survives it, but the caret does not survive back into the segmented control, so a following `press 5` leaves `2020-01-02` untouched where a clicked one gives `2020-05-02` — and appending to a set of segments is undefined anyway. The patch refuses them and names `fill`.

**Worth stating plainly, because it is the one place this patch reduces parity:** refusing makes Vibium the only one of the three tools measured above that does not write to a segmented input. Playwright and Selenium both overwrite a segment and report success, as stock Vibium does. The argument for refusing anyway is that they do not promise to append and Vibium does, and that a valid-looking wrong date is worse than a failure — but a maintainer who weighs parity more heavily than the contract could reasonably keep the current behavior for these five and take only the `number`/`email` half of the patch. The two halves are independent.

**Option 3 is the only one that leaves the agent-facing `SKILL.md:134` line — `type` "appends to existing value" — untrue for seven types.**

## Patch

Applies clean to `dd48732`, where it was measured, and to `e63bb73`, `main` as of 2026-09-11 — the five commits between them fix #510 and #511 and touch nothing on this surface, and both defects reproduce identically at each. `caretToEnd` gains one fallback: when `setSelectionRange` throws and the type is `number` or `email`, place the caret by swapping to `text` and back. The five segmented types are reported and `type` refuses them. `press` needs no change of its own — it already calls `caretToEnd`, so it inherits the fix for `number` and `email`.

| case, in the fixture below | stock | patched |
|---|---|---|
| `number` `1234567890` + `type "99"` | `123456997890` | `123456789099` ✓ |
| `email` `abcdefghij` + `type "99"` | `abcdefg99hij` / `abcdef99ghij` | `abcdefghij99` ✓ |
| `number` + `press Backspace` | `123457890` | `123456789` ✓ |
| `email` + `press Backspace` | `abcdefhij` / `abcdeghij` | `abcdefghi` ✓ |
| `date` `2020-01-02` + `type "99"` | `0099-01-02` / unchanged | error, value unchanged ✓ |
| key events on `type` | `keydown, keypress, input, keyup` | unchanged ✓ |
| `email maxlength=12` + `type "XYZ"` | `abcdeXYfghij` | `abcdefghijXY` ✓ |
| `readonly` + `type "9"` | unchanged | unchanged ✓ |
| `email[multiple]` `aa@b.co,cc@d.co` + `",ee@f.co"` | `aa@b.,ee@f.coco,cc@d.co` | `aa@b.co,cc@d.co,ee@f.co` ✓ |
| React controlled `number`, state after `type "99"` | `123459967890` | `123456789099` ✓ |
| `text` + `type "99"` (control) | `123456789099` | `123456789099` — unchanged |

Two values are Chrome / Firefox. The first six rows and the control use a field styled only `width:100px`, at the browser default font — the fixtures in the repro above. The `maxlength`, `multiple` and React rows come from an adversarial page styled `font:16px monospace;width:100px`, and their exact strings are specific to it: the splice index is the character nearest the center of the box, so it tracks font metrics as well as width. The verdict in each row is the same under either styling; only the digits move. This is the same reason the regression tests assert *appended* rather than a literal.

**Blast radius, measured rather than reasoned about.** Re-running the whole 24-element x 2-width x 2-action sweep against stock and patched and diffing every cell: **16 of 96 change on Chrome, 10 on Firefox, and nothing else moves.** They are exactly the cells above — `number` and `email` appending, `number` and `email` `press` taking the last character, and the five segmented types going from a silent exit 0 to `rc=1` at both widths: a corrupted value on Chrome, a keystroke Firefox had ignored. Firefox changes in six fewer cells for two reasons: `month` and `week` are text inputs there and were already appending correctly (four cells), and its default-width `number` box is wide enough that the value never reaches the click point, so it appended correctly already (the remaining two). An earlier cut of this patch also flipped `color`, `range`, `checkbox`, `radio`, `file`, `button`, `submit`, `reset` and `image` from `rc=0` to `rc=1`, which is 18 more cells and well outside this bug; those types have no text to put a caret in front of and are now left exactly as they were.

Verified on both engines against `dd48732`: `git apply` clean on a pristine checkout, then `make build-go`, `go vet ./...` and `go test ./internal/api/` all green; the new CLI suite 9/9 and the new JS suite 4/4; #488's own suites still pass (2/2 CLI, 4/4 JS). Against a stock build five of the nine new CLI cases fail — the four that pass are the controls and the `maxlength`/`readonly` guards, which stock satisfies for free.

<details>
<summary>3 files, +214/−19</summary>

```diff
diff --git a/clicker/internal/api/handlers_interaction.go b/clicker/internal/api/handlers_interaction.go
index bb7419f..7001104 100644
--- a/clicker/internal/api/handlers_interaction.go
+++ b/clicker/internal/api/handlers_interaction.go
@@ -127,11 +127,7 @@ func (r *Router) handleVibiumType(session *BrowserSession, cmd bidiCommand) {
 		r.sendError(session, cmd.ID, err)
 		return
 	}
-	if err := caretToEnd(s, context, ep); err != nil {
-		r.sendError(session, cmd.ID, err)
-		return
-	}
-	if err := TypeText(s, context, text); err != nil {
+	if err := typeIntoFocused(s, context, ep, text); err != nil {
 		r.sendError(session, cmd.ID, err)
 		return
 	}
@@ -162,7 +158,7 @@ func (r *Router) handleVibiumPress(session *BrowserSession, cmd bidiCommand) {
 		r.sendError(session, cmd.ID, err)
 		return
 	}
-	if err := caretToEnd(s, context, ep); err != nil {
+	if _, err := caretToEnd(s, context, ep); err != nil {
 		r.sendError(session, cmd.ID, err)
 		return
 	}
@@ -839,6 +835,15 @@ func Fill(s Session, context string, ep ElementParams, value string) error {
 	return nil
 }
 
+// Caret modes reported by caretToEnd. Anything else means the caret is placed.
+const (
+	// caretModeSegmented prefixes a date/time control: the value is a set of
+	// segments rather than text, so there is nothing to append to.
+	caretModeSegmented = "segmented"
+	// caretModeNoCaret means the caret could not be placed at all.
+	caretModeNoCaret = "nocaret"
+)
+
 // caretToEnd moves the caret past the element's existing content, ignoring
 // elements that cannot carry one.
 //
@@ -850,14 +855,43 @@ func Fill(s Session, context string, ep ElementParams, value string) error {
 // depended on CSS width, font metrics and engine (#488). Collapsing the
 // caret to the end afterwards restores the documented "appends to existing
 // content" contract.
-func caretToEnd(s Session, context string, ep ElementParams) error {
+func caretToEnd(s Session, context string, ep ElementParams) (string, error) {
 	script, args := buildElActionScript(ep, nil, nil, `
+			// setSelectionRange exists on every HTMLInputElement but throws on
+			// types that do not support selection, so its presence is not a
+			// test for one. These two lists name the types that reach that
+			// throw and still hold something a caller can edit.
+			const appendable = ['number', 'email'];
+			const segmented = ['date', 'time', 'month', 'week', 'datetime-local'];
+			const tag = el.tagName ? el.tagName.toLowerCase() : '';
+			const inputType = tag === 'input' ? String(el.type || '').toLowerCase() : '';
+			if (segmented.indexOf(inputType) !== -1) {
+				return 'segmented:' + inputType;
+			}
 			const n = el.value !== undefined && el.value !== null ? String(el.value).length : null;
 			if (n !== null && typeof el.setSelectionRange === 'function') {
-				// setSelectionRange throws on input types that do not support
-				// selection (number, email, date). Those cannot hold a caret
-				// mid-value anyway, so leaving them alone is correct.
-				try { el.setSelectionRange(n, n); } catch (e) {}
+				try {
+					el.setSelectionRange(n, n);
+				} catch (e) {
+					// No selection API on this type. The same element does have
+					// one while its type is text, and the value survives the
+					// round trip, so borrow it: the caret placed as text is
+					// still there when the type is restored. Keeping real key
+					// events is what this buys over writing the value directly,
+					// and maxlength and readonly keep working by themselves.
+					// Everything else that throws here — checkbox, color, file,
+					// the buttons — has no text to put a caret in front of, so
+					// it is left exactly as it was.
+					if (appendable.indexOf(inputType) !== -1) {
+						try {
+							el.type = 'text';
+							el.setSelectionRange(n, n);
+							el.type = inputType;
+						} catch (e2) {
+							return 'nocaret';
+						}
+					}
+				}
 			} else if (el.isContentEditable) {
 				const r = document.createRange();
 				r.selectNodeContents(el);
@@ -866,10 +900,30 @@ func caretToEnd(s Session, context string, ep ElementParams) error {
 				sel.removeAllRanges();
 				sel.addRange(r);
 			}
-			return 'ok';
+			return 'caret';
 		`)
-	_, err := CallScript(s, context, script, args)
-	return err
+	resp, err := CallScript(s, context, script, args)
+	if err != nil {
+		return "", err
+	}
+	return parseScriptResult(resp)
+}
+
+// typeIntoFocused types into an element that has already been focused, refusing
+// the cases where appending is not defined rather than typing into them blind.
+func typeIntoFocused(s Session, context string, ep ElementParams, text string) error {
+	mode, err := caretToEnd(s, context, ep)
+	if err != nil {
+		return err
+	}
+	if strings.HasPrefix(mode, caretModeSegmented+":") {
+		return fmt.Errorf("type: input[type=%s] holds segments rather than text, so there is nothing to append to; use fill to set it",
+			strings.TrimPrefix(mode, caretModeSegmented+":"))
+	}
+	if mode == caretModeNoCaret {
+		return fmt.Errorf("type: this element cannot hold a caret, so typing would land at an arbitrary position; use fill to set it")
+	}
+	return TypeText(s, context, text)
 }
 
 // TypeInto resolves an element with actionability checks, clicks to focus, and types text.
@@ -881,10 +935,7 @@ func TypeInto(s Session, context string, ep ElementParams, text string) error {
 	if err := ClickAtCenter(s, context, info); err != nil {
 		return err
 	}
-	if err := caretToEnd(s, context, ep); err != nil {
-		return err
-	}
-	return TypeText(s, context, text)
+	return typeIntoFocused(s, context, ep, text)
 }
 
 // PressOn resolves an element with actionability checks, clicks to focus, and presses a key.
@@ -896,7 +947,7 @@ func PressOn(s Session, context string, ep ElementParams, key string) error {
 	if err := ClickAtCenter(s, context, info); err != nil {
 		return err
 	}
-	if err := caretToEnd(s, context, ep); err != nil {
+	if _, err := caretToEnd(s, context, ep); err != nil {
 		return err
 	}
 	return PressKey(s, context, key)
diff --git a/tests/cli/engine/type-no-caret-inputs.test.js b/tests/cli/engine/type-no-caret-inputs.test.js
new file mode 100644
index 0000000..d442fad
--- /dev/null
+++ b/tests/cli/engine/type-no-caret-inputs.test.js
@@ -0,0 +1,90 @@
+/**
+ * CLI Tests: type and press on inputs that cannot carry a caret
+ *
+ * Follow-on to #488. caretToEnd restores the append contract by collapsing the
+ * caret, which needs a selection API. input[type=number] and [type=email] have
+ * none, so typed keys landed wherever the focusing click did. The caret is
+ * placed by borrowing the selection API the same element has while its type is
+ * text; the date family has no caret to place at all and is refused.
+ *
+ * The fixture is a 100px field so the focusing click lands deep inside the
+ * value and the splice is unmistakable. A default-width field is decided by
+ * font metrics to within one character, so it is not safe to assert on.
+ */
+
+const { test, describe, after } = require("../../helpers/capabilities").suite("core");
+const assert = require('node:assert');
+const { execSync } = require('node:child_process');
+const { VIBIUM } = require("../../helpers");
+
+function cli(args) {
+  return execSync(`${VIBIUM} --headless ${args}`, { encoding: 'utf-8', timeout: 30000 });
+}
+
+function cliFails(args) {
+  try { cli(args); return null; } catch (e) { return `${e.stdout || ''}${e.stderr || ''}`; }
+}
+
+function page(html) { cli(`go 'data:text/html,${html}'`); }
+
+after(() => {
+  try { cli('stop'); } catch { /* no session left behind either way */ }
+});
+
+describe('CLI: type/press on inputs with no selection API (#507)', () => {
+  test('type appends into number instead of splicing', () => {
+    page('<input id="n" type="number" value="1234567890" style="width:100px">');
+    cli(`type "#n" "99"`);
+    assert.strictEqual(cli(`value "#n"`).trim(), '123456789099');
+  });
+
+  test('type appends into email instead of splicing', () => {
+    page('<input id="e" type="email" value="abcdefghij" style="width:100px">');
+    cli(`type "#e" "99"`);
+    assert.strictEqual(cli(`value "#e"`).trim(), 'abcdefghij99');
+  });
+
+  test('press acts on the last character of a number, not the click point', () => {
+    page('<input id="n" type="number" value="1234567890" style="width:100px">');
+    cli(`press "Backspace" "#n"`);
+    assert.strictEqual(cli(`value "#n"`).trim(), '123456789');
+  });
+
+  test('press acts on the last character of an email', () => {
+    page('<input id="e" type="email" value="abcdefghij" style="width:100px">');
+    cli(`press "Backspace" "#e"`);
+    assert.strictEqual(cli(`value "#e"`).trim(), 'abcdefghi');
+  });
+
+  test('a segmented date input is refused, not corrupted', () => {
+    page('<input id="d" type="date" value="2020-01-02">');
+    const err = cliFails(`type "#d" "99"`);
+    assert.ok(err, 'expected type to fail');
+    assert.match(err, /segments/);
+    assert.strictEqual(cli(`value "#d"`).trim(), '2020-01-02');
+  });
+
+  test('maxlength still applies, because the keys are still real', () => {
+    page('<input id="m" type="email" maxlength="12" value="abcdefghij">');
+    cli(`type "#m" "XYZ"`);
+    assert.strictEqual(cli(`value "#m"`).trim(), 'abcdefghijXY');
+  });
+
+  test('a readonly field is left alone', () => {
+    page('<input id="r" type="number" value="1234567890" readonly>');
+    cli(`type "#r" "9"`);
+    assert.strictEqual(cli(`value "#r"`).trim(), '1234567890');
+  });
+
+  test('an empty number input still takes the text', () => {
+    page('<input id="n" type="number" value="">');
+    cli(`type "#n" "99"`);
+    assert.strictEqual(cli(`value "#n"`).trim(), '99');
+  });
+
+  test('text is unaffected at the same width', () => {
+    page('<input id="t" type="text" value="1234567890" style="width:100px">');
+    cli(`type "#t" "99"`);
+    assert.strictEqual(cli(`value "#t"`).trim(), '123456789099');
+  });
+});
diff --git a/tests/js/async/engine/type-no-caret-inputs.test.js b/tests/js/async/engine/type-no-caret-inputs.test.js
new file mode 100644
index 0000000..b2102eb
--- /dev/null
+++ b/tests/js/async/engine/type-no-caret-inputs.test.js
@@ -0,0 +1,54 @@
+/**
+ * JS Library Tests: type and press on inputs that cannot carry a caret
+ *
+ * Same regression as the CLI suite of the same name (#507), through the client
+ * router — handleVibiumType — rather than TypeInto. Both reach the shared
+ * caretToEnd, and this pins that the language clients get the fix too.
+ */
+
+const { test, describe, before, after } = require("../../../helpers/capabilities").suite("core");
+const assert = require('node:assert');
+
+const { browser } = require('../../../../clients/javascript/dist');
+
+let bro;
+
+before(async () => { bro = await browser.start({ headless: true }); });
+after(async () => { await bro.stop(); });
+
+async function page(html) {
+  const vibe = await bro.page();
+  await vibe.go('about:blank');
+  await vibe.setContent(html);
+  return vibe;
+}
+
+describe('Type/press on inputs with no selection API (#507)', () => {
+  test('type appends into number instead of splicing', async () => {
+    const vibe = await page('<input id="n" type="number" value="1234567890" style="width:100px">');
+    const input = await vibe.find('#n');
+    await input.type('99');
+    assert.strictEqual(await input.value(), '123456789099');
+  });
+
+  test('type appends into email instead of splicing', async () => {
+    const vibe = await page('<input id="e" type="email" value="abcdefghij" style="width:100px">');
+    const input = await vibe.find('#e');
+    await input.type('99');
+    assert.strictEqual(await input.value(), 'abcdefghij99');
+  });
+
+  test('press acts on the last character, not the click point', async () => {
+    const vibe = await page('<input id="n" type="number" value="1234567890" style="width:100px">');
+    const input = await vibe.find('#n');
+    await input.press('Backspace');
+    assert.strictEqual(await input.value(), '123456789');
+  });
+
+  test('a segmented date input is refused, not corrupted', async () => {
+    const vibe = await page('<input id="d" type="date" value="2020-01-02">');
+    const input = await vibe.find('#d');
+    await assert.rejects(() => input.type('99'));
+    assert.strictEqual(await input.value(), '2020-01-02');
+  });
+});
```

</details>

## Environment

Everything is measured at `dd48732`, macOS arm64, Go 1.27.0.

The Vibium sweeps and repros were taken on **Chrome for Testing 152.0.7977.82** and **Firefox 155.0**; the cross-tool table was taken on **Chrome for Testing 152.0.7977.54**, the build installed here, so that Playwright and Selenium could be pointed at the same binary through `executablePath` and a matching **ChromeDriver 152.0.7977.54**. Every Vibium value in this issue was re-run on both Chrome builds and is identical on each, which is the useful thing to know about the version: these numbers did not move across a patch release. Other tools: **Playwright 1.63.0** (`playwright-core`), **Selenium 4.49.0**, Node 24.10.0.

The splice indices are the character nearest the center of the field, so they depend on the engine's font metrics and default widget widths; the verdicts — appended, prepended, spliced, segment overwritten, refused — do not. A browser release can move the digits without changing anything this issue claims, which is why the regression tests assert the shape rather than the string.
