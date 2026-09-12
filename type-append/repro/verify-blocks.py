#!/usr/bin/env python3
"""Re-run the `$`-prompted command blocks in an issue draft and compare stdout.

Extracts every fenced block whose first line starts with "$ ", runs each command
with the vibium binary under test, and diffs the recorded output against what the
command actually prints. Exits non-zero if any line differs.

Usage:
    VIBIUM_TREES=/path/to/trees python3 verify-blocks.py ../ISSUE-....md [tree]

Environment:
    VIBIUM_TREES      directory holding the built worktrees          (required)
    VIBIUM_WORK       scratch dir for the sandboxed HOME             (default: $TMPDIR/vibium-evidence)
    VIBIUM_CACHE_DIR  browser cache                                  (default: ~/Library/Caches/vibium)
"""
import json, os, re, shlex, subprocess, sys

if len(sys.argv) < 2:
    sys.exit(__doc__)
MD = os.path.abspath(sys.argv[1])
TREE = sys.argv[2] if len(sys.argv) > 2 else "stock"

TREES = os.environ.get("VIBIUM_TREES")
if not TREES:
    sys.exit("set VIBIUM_TREES to the directory holding the built worktrees")
V = os.path.join(TREES, TREE, "clicker/bin/vibium")
if not os.path.exists(V):
    sys.exit("no vibium binary at %s" % V)

WORK = os.environ.get("VIBIUM_WORK") or os.path.join(os.environ.get("TMPDIR", "/tmp"), "vibium-evidence")
HOME = os.path.join(WORK, "blocks")
env = dict(os.environ,
           HOME=HOME,
           VIBIUM_CONFIG_DIR=os.path.join(HOME, ".config/vibium"),
           VIBIUM_CACHE_DIR=os.environ.get("VIBIUM_CACHE_DIR",
                                           os.path.join(os.path.expanduser("~"), "Library/Caches/vibium")),
           VIBIUM_SESSION="blk")
os.makedirs(env["VIBIUM_CONFIG_DIR"], exist_ok=True)

# --- extract the prompted blocks straight from the markdown ---
blocks = []
for m in re.finditer(r"```(\w*)\n(.*?)```", open(MD).read(), re.S):
    body = m.group(2)
    if not body.lstrip().startswith("$ "):
        continue
    steps, cur = [], None
    for line in body.split("\n"):
        if line.startswith("$ "):
            if cur:
                steps.append(cur)
            cur = {"cmd": line[2:], "expect": []}
        elif cur is not None:
            cur["expect"].append(line)
    if cur:
        steps.append(cur)
    for s in steps:
        while s["expect"] and s["expect"][-1] == "":
            s["expect"].pop()
    blocks.append(steps)

# `vibium` must be on PATH so a line like `vibium fill ...; vibium fill ...`
# runs as written. Blocks are compared in aggregate: some show one output run
# after several commands rather than interleaving them.
BIN = os.path.join(WORK, "bin")
os.makedirs(BIN, exist_ok=True)
shim = os.path.join(BIN, "vibium")
if os.path.islink(shim) or os.path.exists(shim):
    os.remove(shim)
os.symlink(V, shim)
env["PATH"] = BIN + os.pathsep + env.get("PATH", "")

def sh(cmd):
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env).stdout

subprocess.run([V, "stop"], capture_output=True, env=env)
bad = 0
for n, steps in enumerate(blocks, 1):
    got, want = [], []
    for s_ in steps:
        got += [l for l in sh(s_["cmd"]).rstrip("\n").split("\n") if l != ""]
        want += [l for l in s_["expect"] if l != ""]
    ok = got == want
    bad += 0 if ok else 1
    print("=== block %d: %s ===" % (n, "OK" if ok else "MISMATCH"))
    for s_ in steps:
        print("    $ " + s_["cmd"])
    if not ok:
        print("    expected: %r" % want)
        print("    actual  : %r" % got)
subprocess.run([V, "stop"], capture_output=True, env=env)
print("\nblocks: %d   mismatching blocks: %d" % (len(blocks), bad))
sys.exit(1 if bad else 0)
