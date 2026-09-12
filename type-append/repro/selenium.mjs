import { Builder, By } from "selenium-webdriver";
import chrome from "selenium-webdriver/chrome.js";
import { TYPE_CASES, FILL_CASES, CHROME, CHROMEDRIVER, fillHtml, url } from "./cases2.mjs";
const o = new chrome.Options(); o.setChromeBinaryPath(CHROME); o.set("webSocketUrl", true);
const d = await new Builder().forBrowser("chrome").setChromeService(new chrome.ServiceBuilder(CHROMEDRIVER)).setChromeOptions(o).build();
for (const [t, , html] of TYPE_CASES) {
  await d.get(url(html));
  const el = await d.findElement(By.id("x"));
  let err = "";
  try { await el.sendKeys("99"); } catch (e) { err = String(e.message).split("\n")[0]; }
  console.log(JSON.stringify({ tool: "selenium", op: "type", type: t, value: await el.getAttribute("value"), err }));
}
for (const [t, v] of FILL_CASES) {
  await d.get(url(fillHtml(t)));
  const el = await d.findElement(By.id("x"));
  let err = "";
  try { await el.sendKeys(v); } catch (e) { err = String(e.message).split("\n")[0]; }
  console.log(JSON.stringify({ tool: "selenium", op: "fill", type: t, sent: v, value: await el.getAttribute("value"), err }));
}
await d.quit();
