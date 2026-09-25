#!/usr/bin/env python3
"""G1 — copy census for Pliwee rebrand Wave 1.

Counts every occurrence of `omnibridge` (any case: OmniBridge, omnibridge,
OMNIBRIDGE, …) and of the old tagline in the three areas the plan names
(android/app/src/main/res, the desktop `src/` trees, docs/design), and
classifies each one. Exits 1 if any occurrence is unexplained, if the capture
is empty, if two independent counts disagree, or if a positive anchor (the
new copy actually being there) is missing. Exits 2 if git is absent.

Run from the repository root:  python3 docs/reports/branding/pliwee-wave-1/g1_copy_census.py
"""
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict

AREAS = [
    "android/app/src/main/res",
    "desktop/*/src/*",
    "desktop/capabilities/*/src/*",
    "docs/design",
]
TOKEN = re.compile(r"[A-Za-z0-9_./:@$-]*omnibridge[A-Za-z0-9_./:@$-]*", re.I)

C1, C2, C3 = "1 identifier owned by a later wave", "2 historical context (ADR-0020 D7)", "3 test fixture"
C5 = "5 artwork still shipped until W6/W7"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=False)


# Explicit, line-level decisions: (path, substring of the line) -> (cat, owner, why).
EXPLICIT = [
    # Historical statements about what OmniBridge shipped.
    ("desktop/core/src/identity.rs", "OmniBridge has always shipped", (C2, "—", "what OmniBridge (v1.0.0) shipped")),
    ("desktop/core/src/identity.rs", "Everything OmniBridge has", (C2, "—", "what OmniBridge ever shipped")),
    ("desktop/core/src/identity.rs", "every OmniBridge install in the", (C2, "—", "the OmniBridge v1.0.0 installed base")),
    ("desktop/core/src/platform/unix_fs.rs", "Everything OmniBridge has always done", (C2, "—", "refactor history of the OmniBridge store")),
    # Prose whose subject is an identifier.
    ("desktop/capabilities/notifications/src/backend/dbus.rs", "naming OmniBridge's own application id", (C1, "W7", "describes the desktop app id")),
    ("desktop/capabilities/notifications/src/backend/dbus.rs", "The application id OmniBridge posts under", (C1, "W7", "doc of the APP_ID constant")),
    ("desktop/platform-linux/src/activation.rs", "None of them is OmniBridge", (C1, "W7", "app-id near-miss test")),
    ("desktop/platform-linux/src/tray/model.rs", "the OmniBridge mark from", (C5, "W7", "tray icon is the shipped omnibridge-app-icon.svg")),
    ("desktop/gui/src/widgets.rs", "OmniBridge mark", (C5, "W7", "the GTK brand mark still draws omnibridge-mark.svg")),
    ("docs/design/UI-GUIDELINES.md", "prefix until the code-naming wave", (C1, "W3", "note on the Kotlin type-name prefix")),
    ("docs/design/BRAND.md", "`omnibridge`, and each moves", (C1, "W3–W10", "names the identifier set later waves own")),
    ("docs/design/BRAND.md", "Run `omnibridge pair`", (C1, "W7", "quotes the CLI binary")),
    # BRAND.md: previous names and the OmniBridge artwork that still ships.
    ("docs/design/BRAND.md", "| **Previous names** |", (C2, "—", "Previous names row")),
    ("docs/design/BRAND.md", "The OmniBridge era reserved a naming family", (C2, "—", "lapsed OmniBridge naming family")),
    ("docs/design/BRAND.md", "*OmniBridge Desktop* (the desktop application", (C2, "—", "lapsed OmniBridge naming family")),
    ("docs/design/BRAND.md", "*OmniBridge for Android*", (C2, "—", "lapsed OmniBridge naming family")),
    ("docs/design/BRAND.md", "*OmniBridge Mirror* and *OmniBridge Find*", (C2, "—", "lapsed OmniBridge naming family")),
    ("docs/design/BRAND.md", "Flow Cyan was called *Bridge Cyan* under OmniBridge", (C2, "—", "former colour name")),
    ("docs/design/BRAND.md", "carried over unchanged from the OmniBridge era", (C2, "—", "icon-family provenance")),
    ("docs/design/BRAND.md", "## Shipped artwork: OmniBridge", (C5, "W6/W7", "section on the shipped artwork")),
    ("docs/design/BRAND.md", "is still the OmniBridge set below", (C5, "W6/W7", "shipped artwork")),
    ("docs/design/BRAND.md", "The official OmniBridge artwork was supplied", (C5, "W6/W7", "shipped artwork")),
    ("docs/design/BRAND.md", "| **Name drawn by the wordmark and lockup** | OmniBridge |", (C5, "W6/W7", "what the shipped wordmark draws")),
    ("docs/design/BRAND.md", "keeps shipping the OmniBridge artwork above", (C5, "W6/W7", "shipped artwork (Wave 0 text)")),
    ("docs/design/BRAND.md", "OmniBridge derivatives are today", (C5, "W6/W7", "shipped derivatives (Wave 0 text)")),
    ("docs/design/BRAND.md", "still draw the OmniBridge span", (C5, "W6/W7", "shipped artwork")),
    ("docs/design/BRAND.md", "describes the **OmniBridge** mark the builds", (C5, "W6/W7", "shipped artwork")),
    ("docs/design/BRAND.md", "![OmniBridge](assets/omnibridge-mark.svg)", (C5, "W6/W7", "image of the shipped mark")),
    ("docs/design/BRAND.md", "The OmniBridge mark is **filled**", (C5, "W6/W7", "shipped artwork")),
    ("docs/design/BRAND.md", "The OmniBridge wordmark and lockup", (C5, "W6/W7", "shipped artwork")),
    ("docs/design/BRAND.md", "still *draw* \"OmniBridge\"", (C5, "W6/W7", "shipped artwork")),
    ("docs/design/BRAND.md", "OmniBridge artwork (W6, W7)", (C5, "W6/W7", "shipped artwork")),
]

CLI_USE = re.compile(
    r"`omnibridge[ `]|`omnibridge$|omnibridge (pair|grant|send|status|clipboard|notifications|devices|transfers|cancel)\b"
    r"|name = \"omnibridge\"|the `omnibridge` CLI|older `omnibridge` binary|a `omnibridge\b|between `omnibridge`"
)

RULES = [
    # W10 / W9: Play listing and public URLs.
    (lambda p, l, t: p == "docs/design/PLAY-STORE-LISTING.md", (C1, "W10", "Play listing copy, lengths and URLs (plan §2)")),
    (lambda p, l, t: p == "docs/design/assets/play/render.sh", (C1, "W10", "Play-graphics source paths")),
    (lambda p, l, t: "github.com/yurisismotto/OmniBridge" in t, (C1, "W9/W10", "repository / privacy-policy URL")),
    # Links to historical documents.
    (lambda p, l, t: re.search(r"ADR-0018-rename-to-omnibridge\.md|MIGRATION-ANYFLOW-TO-OMNIBRIDGE\.md", t), (C2, "—", "link to a historical document")),
    # Artwork file names and the Android drawable name.
    (lambda p, l, t: re.search(r"omnibridge-(mark|mark-mono|app-icon|android-monochrome|wordmark|logo-lockup)\.svg", t), (C5, "W6/W7", "shipped artwork file name")),
    (lambda p, l, t: t == "logo_omnibridge_mark", (C1, "W6", "Android drawable resource name")),
    # W3: code names.
    (lambda p, l, t: re.fullmatch(r"(Theme\.OmniBridge(\.Dialog)?|@color/omnibridge_\w+|omnibridge_(background|background_dark|accent))", t), (C1, "W3", "Android resource name")),
    (lambda p, l, t: re.fullmatch(r"OmniBridge[A-Z]\w*|Modifier\.omniBridge\w+|omniBridge\w+", t), (C1, "W3", "Kotlin/Rust type or function name")),
    (lambda p, l, t: re.match(r"omnibridge_(core|proto|control|runtime|linux|gui|daemon|capability_(battery|clipboard|files|notifications))(::|$)", t), (C1, "W3", "Rust crate path")),
    (lambda p, l, t: re.fullmatch(r"omnibridge-(core|proto|control|runtime|linux|daemon|cli|capability-(battery|clipboard|files|notifications))", t), (C1, "W3", "Rust crate name")),
    (lambda p, l, t: t == "omnibridge-gui:", (C1, "W3", "stderr log prefix")),
    (lambda p, l, t: t == "omnibridge-gui", (C1, "W3/W7", "GUI crate and binary name")),
    (lambda p, l, t: re.fullmatch(r"_OMNIBRIDGE_CLIPBOARD_WATCH_STOP|omnibridge-clipboard-x11|\.omnibridge-", t), (C1, "W3", "X11 atom / thread name / temp prefix")),
    (lambda p, l, t: re.search(r"omnibridge\.v1", t), (C1, "W3", "protobuf package")),
    (lambda p, l, t: re.fullmatch(r"omnibridge-(selection|panel-test|gui-test)-|the_omnibridge_subdirectory_is_used", t), (C3, "W3", "test temp-dir prefix / test name")),
    (lambda p, l, t: 'b"omnibridge files.v1"' in l, (C3, "W3", "arbitrary test payload bytes")),
    # W4: desktop paths.
    (lambda p, l, t: re.search(r"\$XDG_(DATA_HOME|CONFIG_HOME|RUNTIME_DIR)/omnibridge|\.local/share/omnibridge|\.config/omnibridge|/tmp/omnibridge-|omnibridge/control\.sock|/run/user/\d+/omnibridge", t), (C1, "W4", "data / config / runtime path")),
    (lambda p, l, t: p.startswith("desktop/") and (re.search(r"Downloads/OmniBridge", t) or t in ("OmniBridge/", "/OmniBridge")), (C1, "W4", "desktop download dir")),
    (lambda p, l, t: re.search(r'join\("(omnibridge|OmniBridge)"\)|Some\("OmniBridge"\)', l), (C1, "W4", "path component")),
    (lambda p, l, t: p.startswith("android/") and re.search(r"Downloads?/OmniBridge", t), (C1, "W6", "Android download dir")),
    # W5: wire and crypto identifiers.
    (lambda p, l, t: re.fullmatch(r"omnibridge(-data)?/1|_omnibridge\._tcp\.local\.|omnibridge1:?|omnibridge/(pairing-proof|pairing-confirm|files\.v1|notifications\.v1)\S*", t), (C1, "W5", "ALPN / mDNS / QR / domain separator")),
    (lambda p, l, t: t == "omnibridge:" and "CommonName" in l, (C1, "W5", "certificate CN")),
    # W7: installed and OS-persisted names.
    (lambda p, l, t: re.search(r"io\.github\.yurisismotto\.(omnibridge|OmniBridge)|/io/github/yurisismotto/omnibridge", t, re.I), (C1, "W7", "desktop app id / D-Bus name / object path (incl. near-miss fixtures)")),
    (lambda p, l, t: re.fullmatch(r"omnibridged(\.service)?|omnibridge\.service|omnibridge\.gresource|omnibridge-definitely-not-a-real-binary|omnibridge-quickpanel", t), (C1, "W7", "binary / unit / D-Bus service / gresource / activation name")),
    (lambda p, l, t: t.startswith("gnome-shell-") and "omnibridge" in t, (C3, "W7", "activation-token fixture carrying the app name")),
    (lambda p, l, t: t == "omnibridge" and (CLI_USE.search(l) or "dnf install omnibridge" in l), (C1, "W7", "CLI binary / package name")),
]


def classify(path, line, tok):
    for p, sub, verdict in EXPLICIT:
        if path == p and sub in line:
            return verdict
    for pred, verdict in RULES:
        if pred(path, line, tok):
            return verdict
    return None


def main():
    if shutil.which("git") is None:
        print("REFUSED: git is not installed; nothing was measured")
        return 2
    out = git("grep", "-a", "-I", "-n", "-i", "-e", "omnibridge", "--", *AREAS)
    if out.returncode not in (0, 1):
        print(out.stderr)
        return 1
    lines = [l for l in out.stdout.splitlines() if l]
    if not lines:
        print("FAIL: empty capture — the areas matched nothing, so the census would be vacuous")
        return 1

    # Second, independent count: git's own -o over the same pathspec.
    independent = len(git("grep", "-a", "-I", "-o", "-i", "-e", "omnibridge", "--", *AREAS).stdout.splitlines())

    cats, owners, per_file = Counter(), Counter(), defaultdict(Counter)
    unexplained, total = [], 0
    for raw in lines:
        path, lineno, text = raw.split(":", 2)
        for m in TOKEN.finditer(text):
            n = len(re.findall("omnibridge", m.group(0), re.I))
            total += n
            verdict = classify(path, text, m.group(0))
            if verdict is None:
                unexplained.append(f"{path}:{lineno}: {m.group(0)!r}  | {text.strip()[:120]}")
                continue
            cat, owner, why = verdict
            cats[cat] += n
            owners[(cat, owner, why)] += n
            per_file[path][cat] += n

    # Case variants, for the report.
    variants = Counter(git("grep", "-a", "-I", "-o", "-h", "-i", "-e", "omnibridge", "--", *AREAS).stdout.split())

    # Tagline census: the old tagline in the same areas.
    tag = [l for l in git("grep", "-a", "-I", "-n", "-i", "-e", "one bridge", "--", *AREAS).stdout.splitlines() if l]
    TAG_OK = {
        ("docs/design/BRAND.md", "| **Previous names** |"): "historical: previous tagline",
        ("docs/design/BRAND.md", "| **Tagline drawn by the lockup** |"): "shipped OmniBridge lockup (W6/W7)",
        ("docs/design/PLAY-STORE-LISTING.md", "One bridge. Any device."): "Play listing (W10)",
        ("desktop/gui/src/widgets.rs", "one bridge, any device"): "meaning of the OmniBridge mark still drawn (W7)",
    }
    tag_unexplained = [t for t in tag if not any(t.startswith(p + ":") and s in t for (p, s) in TAG_OK)]

    # Positive anchors: the new copy is really there.
    def has(path, s):
        return s in open(path, encoding="utf-8").read()
    anchors = {
        "Android app_name is Pliwee": has("android/app/src/main/res/values/strings.xml", '<string name="app_name">Pliwee</string>'),
        "tray ITEM_TITLE is Pliwee": has("desktop/platform-linux/src/tray/model.rs", 'pub const ITEM_TITLE: &str = "Pliwee";'),
        "tray tooltip carries the tagline": has("desktop/platform-linux/src/tray/model.rs", 'TOOLTIP_BODY: &str = "One flow. Any device.";'),
        "Quick Panel title + tagline": has("desktop/gui/src/panel/mod.rs", 'adw::WindowTitle::new("Pliwee", "One flow. Any device.")'),
        "Android About tagline": has("android/app/src/main/java/io/github/yurisismotto/omnibridge/ui/SettingsScreen.kt", '"One flow. Any device.",'),
        "default desktop name": has("desktop/core/src/platform/unix_fs.rs", '"Pliwee Desktop".to_string()'),
        "default settings name": has("desktop/core/src/store.rs", 'device_name: "Pliwee Device"'),
        "ClipData label": has("android/app/src/main/java/io/github/yurisismotto/omnibridge/clipboard/SystemClipboard.kt", 'DEFAULT_LABEL = "Pliwee"'),
    }

    print(f"G1 copy census over: {' '.join(AREAS)}")
    print(f"lines matched: {len(lines)}   occurrences: {total}   independent count (git grep -o): {independent}")
    print("case variants:", dict(sorted(variants.items())))
    print("\nby category:")
    for c in sorted(cats):
        print(f"  {cats[c]:4d}  {c}")
    print("\nby category / owner / reason:")
    for (c, o, w), n in sorted(owners.items()):
        print(f"  {n:4d}  [{c[0]}] {o:7s} {w}")
    print("\nby area:")
    for area in ("android/app/src/main/res", "desktop/", "docs/design"):
        print(f"  {sum(sum(v.values()) for k, v in per_file.items() if k.startswith(area.rstrip('*'))):4d}  {area}")
    print(f"\nold tagline 'one bridge': {len(tag)} line(s), unexplained {len(tag_unexplained)}")
    for t in tag:
        print("   ", t[:140])
    print("\nanchors:")
    for k, v in anchors.items():
        print(f"  {'ok  ' if v else 'MISS'} {k}")
    print(f"\nUNEXPLAINED: {len(unexplained)}")
    for u in unexplained:
        print("  ", u)

    ok = (not unexplained and not tag_unexplained and total == independent and total > 0 and all(anchors.values()))
    print("\nG1:", "PASS — ZERO UNEXPLAINED OCCURRENCES" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
