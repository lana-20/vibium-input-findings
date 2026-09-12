import json, os, subprocess, sys

# Paths come from the environment so this runs on any machine:
#   VIBIUM_TREES      directory holding the built worktrees        (required)
#   VIBIUM_TREE       tree dir name to drive                       (default: fill-patched)
#   VIBIUM_WORK       scratch dir for the sandboxed HOME           (default: $TMPDIR/vibium-evidence)
#   VIBIUM_CACHE_DIR  browser cache; keep it SHORT, the daemon socket has a 103-byte limit
HERE = os.path.dirname(os.path.abspath(__file__))
TREES = os.environ.get("VIBIUM_TREES")
if not TREES:
    sys.exit("set VIBIUM_TREES to the directory holding the built worktrees")
V = os.path.join(TREES, os.environ.get("VIBIUM_TREE", "fill-patched"), "clicker/bin/vibium")
URL = "file://" + os.path.join(HERE, "fixture.html")
ENGINE = sys.argv[1] if len(sys.argv) > 1 else "chrome"

WORK = os.environ.get("VIBIUM_WORK") or os.path.join(os.environ.get("TMPDIR", "/tmp"), "vibium-evidence")
env = dict(os.environ)
env.update(HOME=os.path.join(WORK, "sweep"), VIBIUM_CONFIG_DIR=os.path.join(WORK, "sweep/cfg"),
           VIBIUM_CACHE_DIR=os.environ.get("VIBIUM_CACHE_DIR", "/tmp/vibium-cache"),
           VIBIUM_SESSION="fs-%s-%s" % (ENGINE, os.environ.get("VIBIUM_TREE", "fill-patched")))

# A per-engine, per-build session AND an explicit stop: with one shared session
# name a second run silently reuses the first run's daemon, so a "firefox" or
# "patched" sweep quietly reports the previous run's engine and binary.
subprocess.run([V, "stop"], capture_output=True, env=env)
os.makedirs(env["VIBIUM_CONFIG_DIR"], exist_ok=True)

def run(*args):
    p = subprocess.run([V] + list(args) + (["--engine",ENGINE] if args[0]=="go" else []), capture_output=True, text=True, env=env)
    return p.returncode, p.stdout.strip(), p.stderr.strip()

CASES = [
    ("text",     "hello",              "plain"),
    ("text",     "a\nb",               "newline stripped by sanitizer"),
    ("search",   "hello",              "plain"),
    ("url",      "not a url",          "no sanitization, invalid kept"),
    ("tel",      "555",                "plain"),
    ("password", "hunter2",            "plain"),
    ("email",    "not-an-email",       "no sanitization, invalid kept"),
    ("email",    "  a@b.com  ",        "whitespace stripped by sanitizer"),
    ("number",   "abc",                "INVALID"),
    ("number",   "1.50",               "valid"),
    ("number",   "1e3",                "valid float syntax"),
    ("number",   " 12",                "leading space"),
    ("date",     "not-a-date",         "INVALID"),
    ("date",     "2020-01-02",         "valid"),
    ("date",     "2020-13-45",         "out of range"),
    ("time",     "99",                 "INVALID"),
    ("time",     "10:30",              "valid"),
    ("month",    "2020-13",            "out of range"),
    ("month",    "2020-01",            "valid"),
    ("week",     "2020-W99",           "out of range"),
    ("week",     "2020-W02",           "valid"),
    ("dtl",      "junk",               "INVALID"),
    ("dtl",      "2020-01-02T10:30",   "valid"),
    ("color",    "notacolor",          "INVALID"),
    ("color",    "#00ff00",            "valid"),
    ("color",    "",                   "empty = what clear writes"),
    ("range",    "abc",                "INVALID"),
    ("range",    "75",                 "valid"),
    ("range",    "",                   "empty = what clear writes"),
    ("ta",       "a\nb",               "textarea newline"),
    ("ta",       "a\r\nb",             "textarea CRLF normalized"),
]

out = []
for sel, val, note in CASES:
    run("go", URL)
    rc, so, se = run("fill", "#" + sel, val)
    vrc, vso, vse = run("value", "#" + sel)
    out.append(dict(engine=ENGINE, sel=sel, sent=val, note=note,
                    fill_rc=rc, fill_out=so, fill_err=se,
                    readback=vso, readback_rc=vrc,
                    round_trips=(vso == val)))
    print(json.dumps(out[-1]))

# Name the output after the build that produced it — a stock run must not
# land in a file called "-patched".
LABEL = os.environ.get("VIBIUM_TREE", "fill-patched")
with open(os.path.join(HERE, "sweep-%s-%s.ndjson" % (ENGINE, LABEL)), "w") as f:
    for r in out:
        f.write(json.dumps(r) + "\n")
