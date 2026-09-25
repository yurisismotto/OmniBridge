#!/usr/bin/env python3
"""G3 — per-suite test counts from a `cargo test --workspace --no-fail-fast` log.

Prints one line per test binary (and doc-test crate), in the order cargo ran
them: `<ordinal> <crate> <target> passed=<n> failed=<n> ignored=<n>`.

The crate is the one named by the most recent `unittests` line, and the
namespace root (`omnibridge_` before Wave 3, `pliwee_` after) is written as
`<root>_`, so a before/after diff shows only real count changes. Binary names
are not renamed by Wave 3 and appear as they are.

Refuses (exit 2) on an input that is not a complete cargo test log: no
`Running` line, a `Running` line with no `test result`, or no `exit=` trailer.
"""
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
lines = text.splitlines()

running = re.compile(r"^\s+Running (unittests )?(\S+) \(target/[^/]+/deps/([A-Za-z0-9_]+)-[0-9a-f]+\)")
doctests = re.compile(r"^\s+Doc-tests (\S+)")
result = re.compile(r"^test result: \w+\. (\d+) passed; (\d+) failed; (\d+) ignored")
root = re.compile(r"^(omnibridge|pliwee)_")

suites = []
current = None
crate = "?"
for line in lines:
    m = running.match(line)
    if m:
        unit, target, deps = m.groups()
        if unit:
            crate = root.sub("<root>_", deps)
        if current is not None:
            sys.exit(f"refused: {current} has no test result")
        current = (crate, target)
        continue
    m = doctests.match(line)
    if m:
        if current is not None:
            sys.exit(f"refused: {current} has no test result")
        current = (root.sub("<root>_", m.group(1)), "doc-tests")
        continue
    m = result.match(line)
    if m and current is not None:
        suites.append((*current, *map(int, m.groups())))
        current = None

if not suites:
    print("refused: no test binary found in the log", file=sys.stderr)
    sys.exit(2)
if current is not None:
    print(f"refused: {current} started and never reported", file=sys.stderr)
    sys.exit(2)
if not re.search(r"^exit=\d+$", text, re.M):
    print("refused: the log has no exit= trailer; it may be truncated", file=sys.stderr)
    sys.exit(2)

tp = tf = ti = 0
for i, (c, t, p, f, ig) in enumerate(suites, 1):
    print(f"{i:03d} {c} {t} passed={p} failed={f} ignored={ig}")
    tp, tf, ti = tp + p, tf + f, ti + ig
print(f"TOTAL binaries={len(suites)} passed={tp} failed={tf} ignored={ti}")
