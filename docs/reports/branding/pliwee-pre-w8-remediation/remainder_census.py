#!/usr/bin/env python3
"""G8 remainder census for the Pliwee rebrand (plan Wave 8), pre-W8 remediation copy.

Copied from the failed Wave 8 run (docs/audits/rebrand/pliwee-remainder-audit/,
recoverable from the stash that holds that evidence) and changed only in its
rule table: every DEFECT and OPEN rule is removed because the line it named
was fixed (a stale rule is a refusal), the P lines renamed by the remediation
lost their explicit rules for the same reason, and the new guard tests and the
remaining legacy prose got explicit rules. The method, the refusals and the
independent counts are unchanged.

Classifies every case-insensitive occurrence of `omnibridge` in every file git
knows about (tracked plus untracked-not-ignored), line by line, and fails when
any occurrence is unexplained or is a blocking defect.

Why it reads bytes: the committed DER vectors carry NUL bytes, and a UTF-8
`grep` silently reports no match in them (the lesson recorded in
OMNIBRIDGE-REBRAND-REMAINDER-AUDIT.md). This tool reads every file as bytes
and matches with an ASCII case-insensitive regex, which is `LC_ALL=C grep -ai`.

Refusals, per AGENTS.md:
  * exit 2 if git is absent or the file list is empty;
  * exit 1 if the independent `LC_ALL=C git grep -aio` occurrence count
    disagrees with this tool's own count (the census lost or invented a match);
  * exit 1 if any occurrence is UNEXPLAINED, or any is a DEFECT;
  * exit 1 if an explicit rule matched nothing (a stale rule is a rule that
    could be hiding a new occurrence behind an old reason).

Run from the repository root:
  python3 docs/reports/branding/pliwee-pre-w8-remediation/remainder_census.py [--list CATEGORY]
"""
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict

TOKEN = re.compile(rb"omnibridge", re.I)

# ---------------------------------------------------------------- categories
HIST = "H  historical / rebrand record (ADR-0020 D7)"
W10 = "W10 pre-migration public value (P1; owned by W9/W10)"
WIRE = "L1 legacy wire profile (D4, W5)"
STATE = "L2 legacy state paths and their migration (D9, W4)"
UNIT = "L3 legacy systemd unit name, alias (W7)"
FWD = "L4 legacy firewalld service, kept (W7)"
PKG = "L5 legacy package names, transition and bounds (W7)"
APPID = "L6 retired app ids, removed or refused by name (W6/W7)"
SIGN = "L7 retired Android signing identity (D3, W6)"
ART = "L8 retired OmniBridge artwork, unused (W7)"
UPG = "L9 G7-UP / transition harness driving the real OmniBridge 1.0.0 (W7)"
NEG = "T1 negative / dead-list / near-miss test value"
FIX = "T2 test fixture, sentinel or certification-guest name"
QUOTE = "Q  measured transcript or historical fact quoted in a comment"
NOTE = "N  transition notice or rename documentation (intentional)"
PROSE = "P  product noun in developer-only prose (comment / living tech doc)"
OPEN = "O  open cleanup: developer-only name a wave deferred to W8 (non-blocking)"
DEFECT = "D  DEFECT: stale user-visible or normative text (blocking)"
UNEXPLAINED = "?  UNEXPLAINED"

BLOCKING = {DEFECT, UNEXPLAINED}

# ------------------------------------------------ whole-file (path) decisions
PATH_RULES = [
    (re.compile(r"^docs/(audits|certification|reports|research|migrations)/"), HIST),
    (re.compile(r"^docs/adr/ADR-00(0[1-9]|1[0-9])-"), HIST),
    (re.compile(r"^docs/adr/ADR-0020-rename-to-pliwee\.md$"), HIST),
    # README: product entry point; its install/verify/badge/logo sections describe
    # the published OmniBridge v1.0.0 until W10 publishes Pliwee (plan W10 "URLs").
    (re.compile(r"^README\.md$"), W10),
    (re.compile(r"^docs/policy/PRIVACY-POLICY\.md$"), W10),
    (re.compile(r"^docs/design/PLAY-STORE-LISTING\.md$"), W10),
    (re.compile(r"^docs/design/assets/play/render\.sh$"), W10),
]

# ------------------------------------------- explicit (path, substring) lines
# Checked before the pattern rules. Each must match at least once.
EXPLICIT = [
    # ---- DEFECTS: returned to the owning wave (see the audit, section 4) ----

    # ---- OPEN (non-blocking): developer-only names a wave explicitly deferred to W8 ----

    # ---- pre-W8 remediation: the guards that keep D2 and D4 fixed name the
    # retired values they refuse (negative tests) ----
    ("android/app/src/test/java/io/github/yurisismotto/pliwee/HostCommandCopyTest.kt", '!copy.contains("omnibridge"', NEG, "D2 guard: the copy must not name the retired command"),
    ("android/app/src/test/java/io/github/yurisismotto/pliwee/HostCommandCopyTest.kt", "omnibridged?", NEG, "D2 guard: the retired command pattern it refuses"),
    ("android/app/src/test/java/io/github/yurisismotto/pliwee/HostCommandCopyTest.kt", "says `omnibridge pair`", NEG, "D2 guard: KDoc naming the defect it refuses"),
    ("android/app/src/test/java/io/github/yurisismotto/pliwee/HostCommandCopyTest.kt", "`omnibridge1:`, `omnibridge/1`", WIRE, "D2 guard: legacy wire values it must not match"),
    ("desktop/proto/tests/schema_comments.rs", 'let values = ["\\"omnibridge", "`omnibridge"];', NEG, "D4 guard: the legacy values it looks for"),
    ("desktop/proto/tests/schema_comments.rs", "names an OmniBridge value without calling it legacy", NEG, "D4 guard: its failure message"),
    ("desktop/proto/tests/schema_comments.rs", "the code to the `pliwee/…` domains and left the comments on `omnibridge/…`", NOTE, "D4 guard: module doc on the defect"),
    ("desktop/proto/tests/schema_comments.rs", "The legacy OmniBridge 1.0.0 values may still be named", WIRE, "D4 guard: module doc"),
    ("desktop/cli/src/main.rs", '.contains("omnibridge")', NEG, "D1 guard: the CLI must not name the retired binary"),
    # ---- pre-W8 remediation: prose that refers to OmniBridge 1.0.0, the legacy
    # state or the transition on purpose (the rest of P was renamed) ----
    ('android/app/src/test/java/io/github/yurisismotto/pliwee/BatteryGrantTest.kt', 'which is every OmniBridge desktop', NOTE, 'account of a defect fixed in the OmniBridge era'),
    ('desktop/capabilities/files/src/destination.rs', 'The `OmniBridge/`', NOTE, 'the legacy download folder (D9)'),
    ('desktop/capabilities/files/src/destination.rs', 'Where OmniBridge put received files', NOTE, 'the legacy download folder (D9)'),
    ('desktop/core/src/platform/unix_fs.rs', 'decides whether an OmniBridge', NOTE, 'legacy state migration (D9)'),
    ('desktop/core/tests/wire_identity.rs', 'the reviewable event the OmniBridge', NOTE, 'history of the OmniBridge rename'),
    ('desktop/core/tests/wire_identity.rs', 'the shape of an OmniBridge', NOTE, 'legacy profile server (D4)'),
    ('desktop/daemon/tests/legacy_state_migration.rs', 'OmniBridge state exists', NOTE, 'legacy state migration test (D9/D12)'),
    ('desktop/daemon/tests/legacy_state_migration.rs', 'the code path OmniBridge', NOTE, 'legacy state migration test'),
    ('desktop/daemon/tests/legacy_state_migration.rs', 'a **real** OmniBridge', NOTE, 'legacy state migration test'),
    ('desktop/gui/data/io.github.yurisismotto.pliwee.metainfo.xml', 'a software centre that listed OmniBridge', NOTE, 'AppStream transition comment'),
    ('desktop/gui/data/io.github.yurisismotto.pliwee.metainfo.xml', 'URLs still point at the OmniBridge repository', NOTE, 'W10-owned URLs, explained'),
    ('desktop/gui/data/io.github.yurisismotto.pliwee.service.in', 'pkill -x omnibridge-gui', NOTE, 'measured transcript on the OmniBridge build'),
    ('desktop/gui/data/io.github.yurisismotto.pliwee.service.in', '--object-path /io/github/yurisismotto/omnibridge', NOTE, 'measured transcript on the OmniBridge build'),
    ('desktop/gui/data/io.github.yurisismotto.pliwee.service.in', 'Measured on the OmniBridge', NOTE, 'measured transcript on the OmniBridge build'),
    ('desktop/gui/data/io.github.yurisismotto.pliwee.service.in', '(then named omnibridge-gui)', NOTE, 'measured transcript on the OmniBridge build'),
    ('desktop/gui/src/selection.rs', 'carrying an OmniBridge', NOTE, 'legacy gui.json migration (D9)'),
    ('desktop/gui/tools/install-desktop-metadata.sh', 'development install from OmniBridge', NOTE, 'legacy dev-install removal'),
    ('desktop/gui/tools/install-desktop-metadata.sh', '(ADR-0020): an OmniBridge', NOTE, 'legacy dev-install removal'),
    ('desktop/platform-linux/src/legacy_migration.rs', 'because OmniBridge', NOTE, 'legacy state migration (D9)'),
    ('desktop/platform-linux/src/legacy_migration.rs', 'An install that ran OmniBridge', NOTE, 'legacy state migration (D9)'),
    ('desktop/platform-linux/src/legacy_migration.rs', 'and OmniBridge wrote it', NOTE, 'legacy state migration (D9)'),
    ('desktop/platform-linux/src/legacy_migration.rs', 'Requiring more than OmniBridge did', NOTE, 'legacy state migration (D9)'),
    ('desktop/platform-linux/src/legacy_migration.rs', "*OmniBridge's own code path*", NOTE, 'legacy state migration (D9)'),
    ('desktop/platform-linux/src/legacy_migration.rs', 'the way OmniBridge did', NOTE, 'legacy state migration (D9)'),
    ('docs/README.md', 'still say `yurisismotto/omnibridge`', NOTE, 'history repository note'),
    ('docs/architecture/NOTIFICATIONS.md', 'on the grounds that OmniBridge implemented', NOTE, 'historical account of a past decision'),
    ('docs/design/BRAND.md', '*artwork* the builds draw is still the OmniBridge set', NOTE, 'dated W1 note'),
    ('docs/design/BRAND.md', 'hand-drawn in Cairo from the OmniBridge', NOTE, 'dated pre-W8 note on D8'),
    ('docs/design/BRAND.md', 'What follows records the OmniBridge rule', NOTE, 'retired-artwork history'),
    ('docs/design/UI-GUIDELINES.md', 'from their earlier `OmniBridge` prefix', NOTE, 'rename note'),
    ('docs/security/THREAT_MODEL.md', 'Pliwee was called OmniBridge', NOTE, 'former-name note (ADR-0020 D7)'),
    ('packaging/common/README.md', 'a running OmniBridge daemon is merged', NOTE, 'Upgrading from OmniBridge'),
    ('packaging/debian/control', 'upgrade path from OmniBridge', NOTE, 'transitional package comment'),
    ('packaging/debian/control', 'upgrade that omnibridge rather', NOTE, 'transitional package comment'),
    ('packaging/debian/control', '"install omnibridge"', NOTE, 'transitional package comment'),
    ('packaging/debian/rules', '# OmniBridge"). No maintainer script', NOTE, 'section title "Upgrading from OmniBridge"'),
    ('packaging/fedora/pliwee.spec', '# from OmniBridge and must not move', NOTE, 'transitional bound comment'),
    ('packaging/fedora/pliwee.spec', 'the upgrade of omnibridge.', NOTE, 'transitional package comment'),
    ('packaging/tests/install-smoke.sh', 'The OmniBridge unit name is an alias', NOTE, 'legacy unit alias'),
    ('packaging/tests/install-smoke.sh', 'The older build is OmniBridge', NOTE, 'the upgrade starts from OmniBridge 1.0.0'),
    # ---- explicit explained lines that no pattern rule states well ----
    ("desktop/core/tests/identity_and_store.rs", '"OmniBridge Desktop"', FIX, "an existing OmniBridge-era device name is kept (W1)"),
    ("desktop/core/tests/identity_and_store.rs", "including an OmniBridge-era default", FIX, "same test"),
    ("desktop/gui/data/io.github.yurisismotto.pliwee.metainfo.xml", "OmniBridge is now Pliwee.", NOTE, "AppStream release note"),
    ("packaging/debian/control", "Description: transitional package", PKG, "transitional package"),
    ("packaging/debian/control", "OmniBridge was renamed Pliwee.", PKG, "transitional package description"),
    ("packaging/debian/control", "Pliwee was called OmniBridge until 1.0.0", NOTE, "package description"),
    ("packaging/fedora/pliwee.spec", "Pliwee was called OmniBridge until 1.0.0", NOTE, "package description"),
    ("packaging/fedora/pliwee.spec", "Transitional package: OmniBridge is now Pliwee", PKG, "transitional summary"),
    ("packaging/fedora/pliwee.spec", "OmniBridge was renamed Pliwee.", PKG, "transitional description"),
    ("packaging/fedora/pliwee.spec", "Upgrading from OmniBridge 1.0.0: your device identity", NOTE, "%post notice"),
    ("packaging/fedora/pliwee.spec", "and if you had enabled omnibridged.service", UNIT, "%post notice"),
    ("packaging/fedora/omnibridge-firewalld.xml", "<short>OmniBridge</short>", FWD, "the kept 1.0.0 file, byte-identical"),
    ("desktop/gui/src/views/mod.rs", "for an OmniBridge 1.0.0 device", WIRE, "legacy ALPN in the connection tooltip"),
    ("desktop/cli/src/main.rs", "interrupted OmniBridge transfer(s)", STATE, "OmniBridge's own .part leftovers (W4)"),
    ("desktop/daemon/src/main.rs", "could not look for interrupted OmniBridge transfers", STATE, "W4"),
    ("desktop/daemon/src/main.rs", "interrupted OmniBridge transfers (.omnibridge-*.part)", STATE, "W4"),
    ("desktop/gui/src/panel/model/tests.rs", "/run/user/1000/omnibridge/control.sock", QUOTE, "a verbatim error string used as a parser fixture"),
    ("desktop/gui/src/panel/model/tests.rs", "/home/yuri/Downloads/OmniBridge/photo.jpg", FIX, "a stored path from an OmniBridge-era transfer"),
    ("desktop/daemon/tests/files.rs", '("/etc/cron.d/omnibridge", "omnibridge")', NEG, "path-traversal target in a hostile filename"),
    ("android/app/src/test/java/io/github/yurisismotto/pliwee/UiMappingTest.kt", "ProcessRecord{omnibridge}", QUOTE, "a platform exception message, quoted"),
    ("android/fixture/src/main/res/values/strings.xml", "OmniBridge Fixture", FIX, "test-only APK label (W3 §8)"),
    ("android/fixture/src/main/java/io/github/yurisismotto/pliwee/fixture/FixtureActivity.kt", '"OmniBridge fixture"', FIX, "test-only APK"),
    ("android/fixture/src/main/java/io/github/yurisismotto/pliwee/fixture/FixtureActivity.kt", "Test notifications for OmniBridge certification", FIX, "test-only APK"),
    ("android/fixture/src/main/java/io/github/yurisismotto/pliwee/fixture/FixtureActivity.kt", '"omnibridge-fixture', FIX, "test-only channel ids (W6 §8)"),
    ("desktop/capabilities/notifications/tests/real_dbus.rs", '"OmniBridge N2 fixture"', FIX, "fixture app name"),
    ("desktop/capabilities/notifications/tests/real_dbus.rs", '"example.omnibridge.n4fixture"', FIX, "fixture app id"),
    ("desktop/capabilities/clipboard/tests/real_backend.rs", '"omnibridge real-backend round trip"', FIX, "neutral test payload"),
    ("desktop/capabilities/clipboard/tests/real_backend.rs", '"omnibridge ordinary sentinel"', FIX, "neutral test payload"),
    ("desktop/capabilities/files/src/stream.rs", 'b"omnibridge files.v1"', FIX, "neutral test payload"),
    ("packaging/tests/harness-selftests.sh", "omnibridge-definitely-not-a-real-tool", NEG, "a tool that must not exist"),
    ("packaging/tests/release-signing-tests.sh", "omnibridge-release.gpg", FIX, "scratch keyring name in $WORK"),
    ("desktop/core/src/profile.rs", "    OmniBridge,", WIRE, "the legacy Profile variant"),
    ("android/fixture/src/main/java/io/github/yurisismotto/pliwee/fixture/FixtureActivity.kt", "OmniBridge notification fixture", FIX, "test-only APK screen text"),
    ("android/fixture/src/main/java/io/github/yurisismotto/pliwee/fixture/FixtureActivity.kt", "so that OmniBridge's", FIX, "test-only APK screen text"),
    ("desktop/gui/tests/brand_assets.rs", '"omnibridge",', NEG, "dead-name list the Pliwee artwork must not contain"),
    ("desktop/platform-linux/src/legacy_migration.rs", 'LEGACY_DIR_NAME: &str = "omnibridge"', STATE, "the legacy directory name (D9)"),
    ("desktop/platform-linux/src/legacy_migration.rs", "OmniBridge state may hold one", STATE, "refusal message naming the legacy state (D12)"),
    ("desktop/platform-linux/src/legacy_migration.rs", 'join("omnibridge/gui.json")', STATE, "legacy gui.json path in a test"),
    ("desktop/platform-linux/src/systemd_transition.rs", "through the OmniBridge unit name", UNIT, "user-facing hint about the legacy link"),
    ("desktop/platform-linux/src/systemd_transition.rs", "the OmniBridge link {LEGACY_UNIT}", UNIT, "user-facing hint about the legacy link"),
    ("packaging/fedora/pliwee.spec", "Obsoletes/Provides for omnibridge-gui", PKG, "%changelog"),
    ("packaging/tests/install-smoke.sh", "for fw in pliwee omnibridge", FWD, "both firewalld files"),
    ("packaging/tests/packaging-checks.sh", "for fw in pliwee omnibridge", FWD, "both firewalld files"),
    ("packaging/tests/packaging-checks.sh", "omnibridge.user.service", UNIT, "refuses the 1.0.0 debian unit file name"),
    ("packaging/tests/lifecycle-gates.sh", "_pliwee|_omnibridge", WIRE, "both advertisements in the journal"),
    ("packaging/tests/release-signing-tests.sh", "OmniBridge TEST KEY", FIX, "throw-away test key UID"),
    ("packaging/tests/release-signing-tests.sh", "OmniBridge WRONG TEST KEY", FIX, "throw-away test key UID"),
    ("desktop/daemon/examples/fake_phone.rs", "pliwee|omnibridge", WIRE, "--profile choice"),
    ("desktop/daemon/examples/fake_phone.rs", "pliwee or omnibridge", WIRE, "--profile choice"),
    ("desktop/daemon/tests/common/mod.rs", "pliwee or omnibridge", WIRE, "PLIWEE_TEST_PROFILE choice"),
]

# ------------------------------------------------ pattern rules, in order
# (category, path regex or None, line regex). First match wins.
R = lambda s: re.compile(s)
PATTERN_RULES = [
    # the G7-UP harness installs, drives and upgrades the published OmniBridge 1.0.0
    (UPG, R(r"^packaging/tests/upgrade-gates\.sh$"), R(r"(?i)omnibridge")),
    (APPID, R(r"^packaging/tests/packaging-checks\.sh$"), R(r"<replaces> the OmniBridge component id")),
    (PKG, R(r"^packaging/tests/(install-smoke|packaging-checks)\.sh$"), R(r"\bomnibridge(-gui)?\b")),
    (FIX, R(r"^packaging/tests/release-signing"), R(r"TEST -- DO NOT TRUST|not OmniBridge")),
    # pre-migration public values (W9/W10)
    (W10, None, R(r"github\.com/yurisismotto/(omnibridge|OmniBridge)")),
    (W10, None, R(r"yurisismotto/omnibridge-history")),
    (W10, None, R(r"omnibridge-release-pubkey")),
    (W10, R(r"^android/app/src/(main|test)/.*PrivacyPolicy"), R(r"OmniBridge")),
    # legacy wire profile (W5)
    (WIRE, None, R(r"omnibridge(-data)?/1\b|_omnibridge\._tcp|omnibridge1\b|omnibridge/(pairing-(proof|confirm)|files\.v1|notifications\.v1|…)|Profile::OmniBridge|WireProfile\.OMNIBRIDGE|\bOMNIBRIDGE\(|id = \"omnibridge\"|=> \"omnibridge\"|\"omnibridge\"\)|KNOWN(_SCHEME)?_BRANDS|omnibridge\.invalid|legacy `omnibridge/…`|pre-Wave-5 `omnibridge/…`|legacy \(`omnibridge/…`\)|omnibridge:\b|`omnibridge:`|omnibridge\.v1\b|omnibridge0|omnibridge-discovery")),
    (NEG, None, R(r"omnibridge[29]\b|omnibridge/2\b|omnibridge:v1:")),
    (WIRE, None, R(r"(fun `legacy .*omnibridge|fn legacy_\w*omnibridge)")),
    (STATE, None, R(r"fn \w*omnibridge_(identity|transfers)\w*")),
    # legacy state (W4)
    (STATE, None, R(r"(\.local/share|XDG_DATA_HOME|XDG_CONFIG_HOME|/xdg)/omnibridge|\.config/omnibridge|Downloads?/OmniBridge|\.omnibridge-|LEGACY_DOWNLOAD_SUBDIR|\"OmniBridge\";|join\(\"omnibridge\"\)|a/b/omnibridge|omnibridge-fake-phone|/run/user/\d+/omnibridge|`…/omnibridge`|OmniBridge data directory|OmniBridge identity|OmniBridge `gui\.json`|an OmniBridge install \(ADR-0020 D9\)|OmniBridge transfers|OmniBridge used|an OmniBridge downgrade|upgrade from OmniBridge|Renamed from `omnibridge` without any migration")),
    # systemd alias (W7)
    (UNIT, None, R(r"omnibridged(\.service)?\b|OmniBridge name\b|OmniBridge-era `omnibridged")),
    # firewalld (W7)
    (FWD, None, R(r"omnibridge(-firewalld)?\.xml|service=omnibridge|the `omnibridge` service|\"omnibridge\" to add|named \"omnibridge\"|firewalld service definition for OmniBridge|The OmniBridge file stays|A zone that an OmniBridge 1\.0\.0 user added")),
    # retired app ids (W6/W7)
    (APPID, None, R(r"io\.github\.yurisismotto\.omnibridge|LEGACY_APP_ID|bin/omnibridge-gui")),
    # packages (W7)
    (PKG, None, R(r"(Obsoletes|Provides|Replaces|Breaks|Package|%package -n|%files -n|%description -n):?\s+omnibridge|omnibridge(-gui)?[ _-](<<|<|=|\(|\*|\$V|\[0-9\]|1\.0\.0|0\.1\.0|dbgsym|_\*|\{,-gui\})|omnibridge\{,-gui\}|transitional|\bomnibridge (and|is|package|to|upgraded|1\.0\.0)\b|`omnibridge`|omnibridge-13 \(trixie\)|omnibridge (\(1\.0\.0-1\)|\(0\.1\.0-1\))|omnibridge-gui has no|`omnibridge-gui`|an OmniBridge 1\.0\.0 install|An OmniBridge install upgrades|Two binary packages: omnibridge|and omnibridge-gui \(desktop|omnibridge-gui subpackage|omnibridge-gui with no GTK|omnibridge-\[0-9\]|ubuntu2[46]04-omnibridge|\./omnibridge")),
    # retired Android signing (W6, D3)
    (SIGN, None, R(r"legacy-omnibridge|omnibridge-android-signing|RETIRED_SLUG|retired OmniBridge|OmniBridge (record|RESTORE|Android signing|identity is planted|upload keystore)|planted OmniBridge identity|an OmniBridge record|the Pliwee record mentions omnibridge|the retired OmniBridge|OmniBridge path|\*omnibridge-android-signing\*|Retired OmniBridge fingerprints|\*\*OmniBridge\*\* \(ADR-0019\)|OmniBridge entries")),
    # retired artwork (W7): structural checks and history
    (ART, None, R(r"omnibridge-(mark|mark-mono|app-icon|android-monochrome|wordmark|logo-lockup)(\.svg)?\b|logo_omnibridge_mark|\"omnibridge\"\)\)|OmniBridge (mark|wordmark|artwork|derivatives|span)|Shipped artwork: OmniBridge|!\[OmniBridge\]|Name drawn by the wordmark and lockup|draw\* \"OmniBridge\"")),
    # negative / dead lists
    (NEG, None, R(r"(dead|retired|near-miss|NotOmniBridge|for dead in|startsWith\(\"omnibridge-\"\)|\"omnibridge\", \"anyflow\"|\"anyflow\", \"fedroid\", \"omnibridge\"|\"flowing\", \"omnibridge\"|omnibridge-identity-v1|`omnibridge-\*`|aliases: under this|A near-miss|is not OmniBridge|None of them is OmniBridge)")),
    # fixtures, sentinels, certification-guest hostnames
    (FIX, None, R(r"OMNIBRIDGE-N\d|omnibridge-n\d|omnibridge-(d13|u2404|u2604)|omnibridge-(test|pending|discard|dup|large)\b")),
    # rename documentation (living docs that document the transition on purpose)
    (NOTE, None, R(r"Upgrading from OmniBridge|upgrading-from-omnibridge|OmniBridge is now Pliwee|OmniBridge -> Pliwee|OmniBridge → Pliwee|renamed from `omnibridge`|`omnibridge` is a dead namespace|Previous names|OmniBridge era|OmniBridge-era|\*OmniBridge (Desktop|for Android|Connect|Mirror|Find)\*|called \*Bridge Cyan\* under OmniBridge|ADR-0018|rename-to-omnibridge|ANYFLOW-TO-OMNIBRIDGE|AnyFlow → OmniBridge|OmniBridge 1\.0\.0|OmniBridge v1\.0\.0|OmniBridge build|OmniBridge checkout|OmniBridge files|OmniBridge was|was OmniBridge|OmniBridge had|OmniBridge values|OmniBridge ones|OmniBridge identifiers|legacy OmniBridge|OmniBridge peer|OmniBridge \(ADR-0018\)|OmniBridge, until|`omnibridge`, and each moves|Run `omnibridge pair`\", Android's `Download/OmniBridge`|what OmniBridge \(v1\.0\.0\) shipped|OmniBridge has always|Everything OmniBridge has|every OmniBridge install|un-upgraded OmniBridge|OmniBridge desktop that is later|the OmniBridge item|never-distributed OmniBridge|An OmniBridge app left|An OmniBridge app cannot scan|OmniBridge 1\.0\.0 app|the\s+OmniBridge record|OmniBridge `~/\.local|the OmniBridge 1\.0\.0|OmniBridge name")),
]

MD_OR_PROSE_FILE = re.compile(r"\.md$|^android/fixture/README|README\.source$")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, check=False)


def files():
    out = git("ls-files", "-co", "--exclude-standard", "-z").stdout
    import os
    return sorted(p for p in out.decode().split("\0") if p and os.path.isfile(p))


C_STYLE = re.compile(r"\.(rs|kt|kts|java|proto|css|gradle)$")
XML_STYLE = re.compile(r"\.xml$")


def comment_lines(path, lines):
    """Per line: is it (inside) a comment? Block comments are tracked only in
    languages that have them: /* */ in C-style sources, <!-- --> in XML.
    Everything else (shell, TOML, YAML, spec, units, debian files) has `#`
    line comments only, so a glob such as `'omnibridge*'` cannot open a block."""
    c_style, xml = bool(C_STYLE.search(path)), bool(XML_STYLE.search(path))
    prefixes = (b"//", b"/*", b"*") if c_style else (b"<!--",) if xml else (b"#",)
    flags, in_block = [], False
    opener, closer = (b"/*", b"*/") if c_style else (b"<!--", b"-->")
    for raw in lines:
        s = raw.strip()
        is_c = in_block or s.startswith(prefixes) or (c_style and s.startswith(b"#"))
        if c_style or xml:
            if opener in raw:
                is_c = True
                if closer not in raw.split(opener, 1)[1]:
                    in_block = True
            elif in_block and closer in raw:
                in_block = False
        flags.append(is_c)
    return flags


def main():
    if not shutil.which("git"):
        print("REFUSE: git is absent")
        return 2
    paths = files()
    if not paths:
        print("REFUSE: git listed no files; the census would be vacuous")
        return 2

    per_cat_occ, per_cat_lines = Counter(), Counter()
    per_cat_files = defaultdict(set)
    listing = defaultdict(list)
    explicit_hits = Counter()
    total_occ = 0

    for path in paths:
        data = open(path, "rb").read()
        if not TOKEN.search(data):
            continue
        cat_for_file = next((c for rx, c in PATH_RULES if rx.search(path)), None)
        lines = data.split(b"\n")
        cflags = comment_lines(path, lines)
        prose_file = bool(MD_OR_PROSE_FILE.search(path))
        for n, raw in enumerate(lines, 1):
            occ = len(TOKEN.findall(raw))
            if not occ:
                continue
            total_occ += occ
            text = raw.decode("utf-8", "replace")
            cat, why = cat_for_file, "path rule"
            if cat is None:
                for i, (p, sub, c, w) in enumerate(EXPLICIT):
                    if p == path and sub in text:
                        cat, why = c, w
                        explicit_hits[i] += 1
                        break
            if cat is None:
                for c, prx, lrx in PATTERN_RULES:
                    if (prx is None or prx.search(path)) and lrx.search(text):
                        cat, why = c, lrx.pattern[:40]
                        break
            if cat is None and (cflags[n - 1] or prose_file):
                cat, why = PROSE, "comment / prose"
            if cat is None:
                cat, why = UNEXPLAINED, ""
            per_cat_occ[cat] += occ
            per_cat_lines[cat] += 1
            per_cat_files[cat].add(path)
            listing[cat].append(f"{path}:{n}: {text.strip()[:160]}   [{why}]")

    # ---- file NAMES carrying the old name (the content census cannot see them)
    NAME_RULES = [
        (re.compile(r"^docs/(audits|certification|reports|research|migrations)/|^docs/adr/ADR-0018-"), HIST),
        (re.compile(r"^android/signing/certs/legacy-omnibridge/[a-z-]+\.pem$"), SIGN),
        (re.compile(r"^docs/design/assets/omnibridge-[a-z-]+\.svg$"), ART),
        (re.compile(r"^packaging/fedora/omnibridge-firewalld\.xml$"), FWD),
    ]
    named = [p for p in paths if TOKEN.search(p.encode())]
    name_cats = Counter()
    name_unexplained = []
    for p in named:
        c = next((c for rx, c in NAME_RULES if rx.search(p)), None)
        if c is None:
            name_unexplained.append(p)
        else:
            name_cats[c] += 1

    # independent count
    gg = subprocess.run(
        "git ls-files -co --exclude-standard -z | xargs -0 -r env LC_ALL=C grep -aoi omnibridge -- 2>/dev/null | wc -l",
        shell=True, capture_output=True, text=True, check=False,
    )
    independent = int((gg.stdout or "0").strip() or 0)

    order = [HIST, W10, WIRE, STATE, UNIT, FWD, PKG, APPID, SIGN, ART, UPG, NEG, FIX, QUOTE, NOTE, PROSE, OPEN, DEFECT, UNEXPLAINED]
    print(f"{'category':<74} {'files':>5} {'lines':>6} {'occ':>6}")
    all_files = set()
    for c in order:
        all_files |= per_cat_files[c]
        print(f"{c:<74} {len(per_cat_files[c]):>5} {per_cat_lines[c]:>6} {per_cat_occ[c]:>6}")
    print(f"{'TOTAL (unique files)':<74} {len(all_files):>5} {sum(per_cat_lines.values()):>6} {total_occ:>6}")
    print(f"independent count (LC_ALL=C grep -aoi): {independent} occurrences")

    print(f"\nfile names containing omnibridge: {len(named)}")
    for c in order:
        if name_cats[c]:
            print(f"  {c:<72} {name_cats[c]:>5}")
    print(f"  {UNEXPLAINED:<72} {len(name_unexplained):>5}")
    gl = subprocess.run("git ls-files -co --exclude-standard | LC_ALL=C grep -ci omnibridge",
                        shell=True, capture_output=True, text=True, check=False)
    independent_names = int((gl.stdout or "0").strip() or 0)
    print(f"independent name count (git ls-files | grep -ci): {independent_names}")

    fail = 0
    if independent != total_occ:
        print(f"FAIL: independent count {independent} != census count {total_occ}")
        fail = 1
    if independent_names != len(named):
        print(f"FAIL: independent name count {independent_names} != census {len(named)}")
        fail = 1
    for p in name_unexplained:
        print(f"FAIL: unexplained file name: {p}")
        fail = 1
    stale = [EXPLICIT[i] for i in range(len(EXPLICIT)) if explicit_hits[i] == 0]
    for p, sub, c, w in stale:
        print(f"FAIL: explicit rule matched nothing (stale): {p} :: {sub}")
        fail = 1
    for c in (DEFECT, UNEXPLAINED):
        if per_cat_lines[c]:
            print(f"\n== {c}: {per_cat_lines[c]} line(s)")
            for l in listing[c]:
                print("   " + l)
            fail = 1
    if "--list" in sys.argv:
        want = sys.argv[sys.argv.index("--list") + 1]
        for c in order:
            if c.startswith(want):
                print(f"\n== listing {c}")
                for l in listing[c]:
                    print("   " + l)
    print("\nG8 remainder census:", "FAIL" if fail else "PASS (zero unexplained, zero defects)")
    return fail


if __name__ == "__main__":
    sys.exit(main())
