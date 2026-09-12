import { Builder, By } from "selenium-webdriver";
import chrome from "selenium-webdriver/chrome.js";
import { CHROME, CHROMEDRIVER, url } from "./cases.mjs";
const o = new chrome.Options(); o.setChromeBinaryPath(CHROME); o.set("webSocketUrl", true);
const d = await new Builder().forBrowser("chrome").setChromeService(new chrome.ServiceBuilder(CHROMEDRIVER)).setChromeOptions(o).build();

// Is it a prepend (caret 0) or a splice (click point)? Vary the width: a splice
// index moves with width, a caret-at-0 prepend does not.
for (const w of ["60px", "100px", "400px"]) {
  for (const t of ["number", "email", "text"]) {
    const seed = t === "email" ? "abcdefghij" : "1234567890";
    await d.get(url(`<input id=x type=${t} value=${seed} style="width:${w}">`));
    const el = await d.findElement(By.id("x"));
    await el.sendKeys("99");
    console.log(`${t.padEnd(7)} width=${w.padEnd(6)} -> ${await el.getAttribute("value")}`);
  }
}
// Does selectionStart even exist on these types?
await d.get(url(`<input id=x type=number value=1234567890>`));
console.log("number selectionStart:", await d.executeScript(
  "try { return String(document.getElementById('x').selectionStart) } catch (e) { return 'THROWS:' + e.name }"));
console.log("number setSelectionRange:", await d.executeScript(
  "try { document.getElementById('x').setSelectionRange(3,3); return 'OK' } catch (e) { return 'THROWS:' + e.name }"));
await d.quit();
