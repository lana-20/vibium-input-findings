// Chrome and chromedriver are discovered from the vibium cache, newest first, so
// this keeps working when the browser updates. Override with CHROME_BIN /
// CHROMEDRIVER_BIN, or VIBIUM_CACHE_DIR to point at a different cache.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
const CACHE = process.env.VIBIUM_CACHE_DIR || path.join(os.homedir(), "Library/Caches/vibium");
function newestChromeDir() {
  const root = path.join(CACHE, "chrome-for-testing");
  const versions = fs.existsSync(root)
    ? fs.readdirSync(root).filter((v) => /^[0-9]+\./.test(v))
        .sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).reverse()
    : [];
  if (!versions.length) throw new Error("no Chrome for Testing under " + root + " - run: vibium install");
  return path.join(root, versions[0]);
}
const DIR = (process.env.CHROME_BIN && process.env.CHROMEDRIVER_BIN) ? null : newestChromeDir();
export const CHROME = process.env.CHROME_BIN
  || path.join(DIR, "Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing");
export const CHROMEDRIVER = process.env.CHROMEDRIVER_BIN || path.join(DIR, "chromedriver");
const W = 'style="width:100px"';
// TYPE: append "99" to a seeded field of each affected type, plus controls.
export const TYPE_CASES = [
  ["text",           "1234567890",        `<input id=x type=text value=1234567890 ${W}>`],
  ["password",       "1234567890",        `<input id=x type=password value=1234567890 ${W}>`],
  ["number",         "1234567890",        `<input id=x type=number value=1234567890 ${W}>`],
  ["email",          "abcdefghij",        `<input id=x type=email value=abcdefghij ${W}>`],
  ["date",           "2020-01-02",        `<input id=x type=date value=2020-01-02 ${W}>`],
  ["time",           "10:30",             `<input id=x type=time value=10:30 ${W}>`],
  ["month",          "2020-01",           `<input id=x type=month value=2020-01 ${W}>`],
  ["week",           "2020-W02",          `<input id=x type=week value=2020-W02 ${W}>`],
  ["datetime-local", "2020-01-02T10:30",  `<input id=x type=datetime-local value=2020-01-02T10:30 ${W}>`],
];
// FILL: write a value the type's sanitization rejects.
export const FILL_CASES = [
  ["number",         "abc"],
  ["date",           "not-a-date"],
  ["time",           "99"],
  ["month",          "2020-13"],
  ["week",           "2020-W99"],
  ["datetime-local", "junk"],
  ["color",          "notacolor"],
  ["range",          "abc"],
];
export const fillHtml = (t) => `<input id=x type=${t} value="">`;
export const url = (h) => "data:text/html," + h;
