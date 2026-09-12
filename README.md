# Vibium input findings

Measured evidence for two defects in [Vibium](https://github.com/VibiumDev/vibium)
on the same surface — writing text into form fields. Every value here was read
back from a live field, not inferred from source.

**Rendered tables: https://lana-20.github.io/vibium-input-findings/**

| | |
|---|---|
| **[type-append](https://lana-20.github.io/vibium-input-findings/type-append/)** | `type` breaks its documented append contract on seven input types — spliced mid-value on `number` and `email`, a segment overwritten on the five date types |
| **[fill-acceptance](https://lana-20.github.io/vibium-input-findings/fill-acceptance/)** | `fill` reports success for a value the field cannot hold — exits 0 and leaves the field empty, or on a substitute the browser picked |

Each directory's `README.md` is the report itself, followed by the commands to
re-derive every table in it. Alongside sit the patch, the scripts, and the raw
output those scripts produced.

Measured at `dd48732` and reproduced identically at `e63bb73`. Chrome for Testing
152.0.7977.54 and .82, Firefox 155.0, Playwright 1.63.0, Selenium 4.49.0,
Node 24.10.0, Go 1.27.0, macOS arm64. Playwright and Selenium are pointed at the
Chrome for Testing build Vibium already installs, so no result turns on a browser
difference.
