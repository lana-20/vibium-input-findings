// The JS client is resolved at runtime so this runs on any machine:
//   VIBIUM_TREES  directory holding the built worktrees
//   VIBIUM_STOCK  tree dir name whose clients/javascript/dist to import (default: stock)
// Build it first: npm install && npm -w clients/javascript run build
import path from "node:path";
const TREES = process.env.VIBIUM_TREES;
if (!TREES) throw new Error("set VIBIUM_TREES to the directory holding the built worktrees");
const DIST = path.join(TREES, process.env.VIBIUM_STOCK || "stock", "clients/javascript/dist/index.js");
const { browser } = await import(DIST);
const cases = [
  ["number-abc", '<input id=n type=number value="">', "#n", "abc"],
  ["date-bad",   '<input id=d type=date value="">',   "#d", "not-a-date"],
  ["number-42",  '<input id=n type=number value="">', "#n", "42"],
];
const b = await browser.start();
try {
  const p = await b.newPage();
  for (const [id, html, sel, val] of cases) {
    await p.go("data:text/html," + html);
    let err = "";
    try { await (await p.find(sel)).fill(val); }
    catch (e) { err = e.constructor.name + ": " + String(e.message).split("\n")[0]; }
    let v = "";
    try { v = await (await p.find(sel)).value(); } catch { v = "<value failed>"; }
    console.log(`js|${id}|${v}|${err}`);
  }
} finally { await b.stop(); }
