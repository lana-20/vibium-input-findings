import { spawn } from "node:child_process";
const BIN = process.env.VIBIUM_BIN_PATH;
const cases = [
  ["number-abc", '<input id=n type=number value="">', "#n", "abc"],
  ["date-bad",   '<input id=d type=date value="">',   "#d", "not-a-date"],
  ["number-42",  '<input id=n type=number value="">', "#n", "42"],
];
const args = ["mcp", "--headless"];
if (process.env.VIBIUM_ENGINE) args.push("--engine", process.env.VIBIUM_ENGINE);
const p = spawn(BIN, args, { stdio: ["pipe", "pipe", "pipe"] });
let buf = "", pending = new Map(), id = 0;
p.stdout.on("data", (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i); buf = buf.slice(i + 1);
    if (!line.trim()) continue;
    let m; try { m = JSON.parse(line); } catch { continue; }
    if (m.id !== undefined && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  }
});
const call = (method, params) => new Promise((res) => {
  const myId = ++id;
  pending.set(myId, res);
  p.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: myId, method, params }) + "\n");
});
await call("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "surf", version: "0" } });
const tools = await call("tools/list", {});
const names = (tools.result?.tools || []).map((t) => t.name);
const nav = names.find((n) => /navigate|goto|^browser_go$/.test(n)) || "browser_navigate";
const text = (r) => (r.result?.content || []).map((c) => c.text).join(" ").trim();
for (const [cid, html, sel, val] of cases) {
  await call("tools/call", { name: nav, arguments: { url: "data:text/html," + html } });
  const f = await call("tools/call", { name: "browser_fill", arguments: { selector: sel, value: val } });
  const isErr = f.result?.isError || f.error;
  const err = isErr ? (f.error?.message || text(f)).split("\n")[0] : "";
  const v = await call("tools/call", { name: "browser_get_value", arguments: { selector: sel } });
  console.log(`mcp|${cid}|${text(v)}|${err}`);
}
p.kill();
