import { chromium } from "playwright-core";
import { TYPE_CASES, FILL_CASES, CHROME, fillHtml, url } from "./cases2.mjs";
const b = await chromium.launch({ executablePath: CHROME });
const page = await b.newPage();
for (const [t, , html] of TYPE_CASES) {
  await page.goto(url(html));
  let err = "";
  try { await page.locator("#x").pressSequentially("99"); }
  catch (e) { err = String(e.message).split("\n")[0].replace("locator.pressSequentially: Error: ", ""); }
  console.log(JSON.stringify({ tool: "playwright", op: "type", type: t, value: await page.locator("#x").inputValue(), err }));
}
for (const [t, v] of FILL_CASES) {
  await page.goto(url(fillHtml(t)));
  let err = "";
  try { await page.locator("#x").fill(v); }
  catch (e) { err = String(e.message).split("\n")[0].replace("locator.fill: Error: ", ""); }
  console.log(JSON.stringify({ tool: "playwright", op: "fill", type: t, sent: v, value: await page.locator("#x").inputValue(), err }));
}
await b.close();
