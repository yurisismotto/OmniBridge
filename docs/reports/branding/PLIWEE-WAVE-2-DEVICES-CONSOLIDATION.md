# Pliwee rebrand — Wave 2: Desktop UX, Devices consolidation

| | |
| --- | --- |
| **Status** | **WAVE 2 BLOCKED_MANUAL.** Implementation is complete and every automated check is green. G2's automated half (static gate plus unit and display tests) **PASSES**. The plan's real-session checks on a **GNOME and a KDE session** (keyboard reaches every control, including inside the disclosure, and screen-reader labels for revoke and grant) were **NOT EXECUTED** (§7), so the exit criterion "both real sessions checked" is open. |
| **Date** | 2026-09-24 |
| **Branch** | `feature/pliwee-rebrand-wave2`, based on `1566279` (merge of Wave 1, PR #6). Changes are uncommitted; the orchestrator owns commit and merge. |
| **Plan** | [PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md § Wave 2](../../research/pliwee-rebrand/PLIWEE-REBRAND-IMPLEMENTATION-PLAN.md#wave-2--desktop-ux-devices-consolidation) (normative) |
| **Decision** | [ADR-0020](../../adr/ADR-0020-rename-to-pliwee.md), planning decision **P4** |
| **Previous wave** | [Wave 1 — Brand copy](PLIWEE-WAVE-1-BRAND-COPY.md) |
| **Gate tool** | [`pliwee-wave-2/g2_no_widened_authority.sh`](pliwee-wave-2/g2_no_widened_authority.sh) |
| **Host** | Fedora 44, kernel 7.2.5, GNOME on Wayland (`WAYLAND_DISPLAY=wayland-0`), rustc/cargo 1.98.1. Every cargo job ran in the foreground, one at a time, with `-j 2` and `RUST_TEST_THREADS=2`. |

---

## 1. Scope

The desktop **Devices** and **Trusted peers** pages are now one main area,
**Devices** (P4). The distinctions between device, peer, trusted peer,
pairing, trust relationship and capability are kept in the code and in the
wording. Only the navigation moved. The daemon is untouched and still enforces
every authorization decision.

**Not in scope, and not touched:** any identifier in plan §2 other than the
GUI route (W3 and later); `desktop/{daemon,runtime,control,core}` and their
tests; the Quick Panel; historical documents; the frozen brand masters.

## 2. What changed

| File | Change |
| --- | --- |
| `desktop/gui/src/views/devices.rs` | Rewritten as the merged page. It adds a small model, `Control` (`Grant`, `Revoke`, `RemoveFromList`, `RemoveAllRevoked`), plus `card_controls`, `page_controls`, `trust_label` and `capability_summary`. **Rendering walks that model**, so the parity test reads the same list the screen is drawn from. There is one `confirm()` path for every destructive control, and the dialog builders `revoke_dialog`, `remove_dialog` and `remove_all_dialog` are separate so the tests can inspect them. There are 7 model unit tests and one display section, `the_devices_page_widget_tree`. |
| `desktop/gui/src/views/peers.rs` | **Deleted.** All of its code, comments and behaviour moved into `devices.rs`. |
| `desktop/gui/src/views/mod.rs` | The `peers` module, its box and its stack child are gone. `devices::render` now takes `&Pages`. `Pages` gains `expanded`, a set of fingerprints, with `is_expanded` and `set_expanded`. The display gate now calls the Devices section. The module doc says "Devices" where it said "Trusted peers". |
| `desktop/gui/src/lib.rs` | `Page::TrustedPeers` is removed, and `Page::ALL` goes from 7 entries to 6. `const LEGACY_PEERS_PAGE = "peers"`, and `Page::from_name("peers")` returns `Page::Devices`. The `a_page_can_still_be_named` test is **kept**; its expected page for `--page=peers` changes from `TrustedPeers` to `Devices`, which is the fact that changed. Two new tests are added (§5). |
| `README.md` (quick start, step 5) | "**Trusted peers** page" becomes "**Devices** page (open the phone's **Details and controls**)". |
| `docs/design/UI-GUIDELINES.md` | The Navigation list is now the real sidebar: Dashboard · Files · Clipboard · Notifications · Devices · Settings. The old list also omitted Notifications. A new **Devices** paragraph describes the card, the disclosure and the alias. |
| `docs/reports/branding/pliwee-wave-2/g2_no_widened_authority.sh` | New. The static half of G2 (§6). |

## 3. Design as built

**Card (always visible):** platform icon · name · short fingerprint · live
status badge (`Status::from_device_state`: Connected / Not responding /
Available / Revoked, from the same `DaemonState` facts as before) · a facts
line with the **trust state** (*Trusted* / *Revoked*), platform, silence and
last-session facts, and a **summary of granted capabilities** in product
words. The summary includes `notifications.v1`, which is granted on the
Notifications page, so it never under-reports.

**Disclosure (`gtk::Expander`, "Details and controls"; "Details" on a revoked
card):** "Device fingerprint" in full through `widgets::fingerprint`, which is
never shortened · "Device id …" · Connection (Paired/Not paired · Connected
now/Not connected) · for a trusted device, the three grant switches
(Clipboard, Files, Battery) and **Revoke this device** · for a revoked device,
the revoked sentence and **Remove from list**.

**Page level:** **Remove all revoked devices** is shown only when more than
one revoked device is listed, exactly as on Trusted peers. It sits on its own
card and is not inside a disclosure. The plan lists it under "Expanded" with
the qualifier "page-level". It is kept visible because there is no single
device to hang it on, and hiding a count-bearing bulk action behind a second
disclosure would add no safety: it is already confirmed.

**Behaviour kept exactly:**

- Revoked devices are shown and marked. Nothing is hidden by default.
- Removal is keyed by **fingerprint**.
- `forget_peer_choice` runs only after the daemon agrees, and only for the
  removed fingerprints.
- All three destructive dialogs keep their text, have Cancel as the default
  and close response, and give the destructive response the Destructive
  appearance.
- Grant switches send `Request::Grant` with the position the switch was moved
  to, and nothing is granted automatically.
- The accessible descriptions on the revoked card and on "Remove from list"
  are unchanged.

**Small accessibility additions (wording is allowed by the plan):**

- A grant switch's accessible label is now "{Capability} for {device name}"
  instead of "… for this device", which was the same string on every card.
- "Revoke this device" gains an accessible description naming the device and
  saying that it asks first.
- The expander carries a description naming the device and what it holds.

**Disclosure state survives redraws.** The page is rebuilt wholesale whenever
the status report changes (see `views/mod.rs`), and a connected device's
`silent_secs` changes it on almost every poll. Without memory, an open card
would fold itself shut under the user every 2 s. `Pages::expanded` records the
open cards by fingerprint, and the display test
`an_open_disclosure_survives_a_redraw` proves it works.

**Measured property of the disclosure.** GTK unparents a collapsed expander's
child. While a card is folded, its switches and buttons are **not in the
widget tree at all**, so keyboard focus cannot land on a hidden control. The
display test asserts both states. The first run of the display gate failed
here (`grant ×3 inside the disclosure: left 0, right 3`), because the test
had counted switches inside a folded expander. That failure is what
established the property, and the test was corrected to assert *absent while
folded, present when opened*. Nothing in the product changed as a result.

## 4. Routes and compatibility

| Input | Before | After |
| --- | --- | --- |
| sidebar | Devices, Trusted peers (2 entries) | Devices (1 entry) |
| `--page devices` / `--page=devices` | Devices | Devices |
| `--page peers` / `--page=peers` | Trusted peers | **Devices** (alias) |
| stack child `peers` | existed | removed; no path can select it, because `from_name` maps the alias before the stack is touched |
| `gui.json` | peer *selection* keyed by fingerprint | unchanged; nothing to migrate |
| daemon control protocol | — | unchanged (G2 A1/B) |

`app.settings`, the tray and the Quick Panel pass no page. No `.desktop`
action or packaging file names the `peers` route. `git grep -n
'page=peers\|page peers\|"peers"' -- desktop packaging` finds only the alias
constant and its tests in `gui/src/lib.rs`, plus an unrelated `Debug` field
name in `core/src/store.rs` and state-file fixtures in packaging tests.

## 5. Tests executed

All commands were run from `desktop/`, sequentially.

| Command | Result |
| --- | --- |
| `cargo fmt --all -- --check` | **clean** |
| `cargo clippy -j 2 -p omnibridge-gui --all-targets -- -D warnings` | **clean.** The first build had one `dead_code` warning (`Control::confirmed` was used only by tests); the fix was to route every destructive click through `confirm()`, which asserts it. |
| `cargo test -j 2 -p omnibridge-gui` | **165 passed** (140 unit + 25 `brand_assets`), 0 failed, 1 ignored (the display gate, run below). Wave 1 had 131 unit tests; the +9 are the tests below. |
| `cargo test -j 2 -p omnibridge-gui --lib -- --ignored every_page_widget_tree --test-threads=1` (GNOME, Wayland) | **1 passed.** Runs the notifications, clipboard, **devices**, Quick Panel and application-window sections. |
| `cargo test -j 2 -p omnibridge-daemon --test security_certification --test control --test revoked_cleanup --test file_approval` | **34 passed** (7 + 4 + 12 + 11), 0 failed |
| `cargo test -j 2 -p omnibridge-core --test revoked_tombstone` | **16 passed**, 0 failed |
| `bash docs/reports/branding/pliwee-wave-2/g2_no_widened_authority.sh` | **G2: PASS** (26 `ok`, 0 `FAIL`, exit 0) |
| `git diff --check` | **clean** |

**New or changed tests (plan § Wave 2 "Unit tests" / "Integration"):**

| Test | What it proves |
| --- | --- |
| `lib::tests::a_page_can_still_be_named` (kept; expectation changed) | `--page=peers` → `Page::Devices` |
| `lib::tests::the_old_trusted_peers_route_opens_devices` | the alias in both spellings, plus `from_name("peers")` |
| `lib::tests::the_sidebar_has_one_devices_entry_and_no_trusted_peers` | `Page::ALL` has exactly 6 entries and exactly one `Devices`; no page is named `peers` or titled "Trusted peers"; every page round-trips through `from_name` |
| `devices::tests::every_trusted_peers_control_exists_on_devices` | **the control-parity test**: grant ×3 (clipboard/files/battery, with current positions) and revoke for a trusted device; remove-one for a revoked device; remove-all for >1 revoked, carrying exactly the revoked fingerprints |
| `devices::tests::each_control_sends_the_request_trusted_peers_sent` | `Grant{device, capability, granted: wanted}`, `Unpair{device}`, `HideRevokedDevice{fingerprint}` (by fingerprint), `HideAllRevokedDevices` |
| `devices::tests::every_destructive_control_is_confirmed` | revoke, remove and remove-all are confirmed (exactly 3); grant is not, as before |
| `devices::tests::no_capability_is_granted_by_default` | a fresh device's switches are all off |
| `devices::tests::a_revoked_device_cannot_be_granted_from_here` | a revoked card offers only "Remove from list" |
| `devices::tests::remove_all_is_offered_only_for_more_than_one_revoked_device` | 0 or 1 revoked device → no bulk action |
| `devices::tests::the_card_states_trust_and_what_is_granted` | trust label and capability summary |
| display: `the_devices_page_widget_tree` | one expander per device, all folded; while folded, no switch or trust button is in the tree; when opened: exactly 3 switches in the trusted card's expander, with the store's positions; the **full grouped fingerprint** and device id inside it; 1 "Revoke this device"; 2 "Remove from list", each inside an expander; 1 page-level "Remove all revoked devices", outside any expander; a revoked-only list still shows the device and "Revoked"; each of the 3 confirmation dialogs has Cancel as default and close response and a Destructive action; an opened disclosure stays open across a redraw |

## 6. Gate G2 — no lost control, no widened authority

**Automated half: PASS.** Two layers cover it:

- The tests in §5 check behaviour: parity, requests, confirmation and the
  widget tree.
- `g2_no_widened_authority.sh` checks what the tests cannot see. It uses
  `packaging/tests/lib/assert.sh` (`need_tool`, `need_window_covers`,
  `need_exact_count`, `need_nonempty`, `contains`/`absent` on here-strings,
  and never `| grep -q`). Baseline `1566279`.

| Check | Measured |
| --- | --- |
| A0 window anchor | the changed-file list (`git diff --name-only 1566279` plus untracked) contains `desktop/gui/src/views/devices.rs` |
| A1 forbidden paths | **exactly 0** files changed under `desktop/{daemon,runtime,control,core}` |
| B security suites byte-identical | **exactly 5 of 5** blobs are equal to `1566279`: `security_certification.rs` `e4e13a3b`, `control.rs` `4e275bb9`, `revoked_cleanup.rs` `4cd131d5`, `file_approval.rs` `d4faf502`, `core/tests/revoked_tombstone.rs` `bd35dc51` |
| C parity in source | Devices sends `Request::Grant`, `Unpair`, `HideRevokedDevice` and `HideAllRevokedDevices`, and draws both destructive buttons, the bulk button and the switches; `peers.rs` is gone; `TrustedPeers` is absent from `lib.rs`; the alias constant is present |
| D Quick Panel | none of the four trust requests appears in `gui/src/panel/**` |
| E confirmation | **exactly 3** `confirmation(` dialogs; default and close response `cancel`; Destructive appearance |

**Manual half (real GNOME and KDE sessions): NOT EXECUTED** (§7). G2 as the
plan defines it is therefore **not closed**.

## 7. NOT EXECUTED

| Item | Reason |
| --- | --- |
| **Real GNOME session, keyboard:** Tab and arrow keys reach every control, including inside the expander; Enter/Space opens it; the dialogs take focus and Escape cancels | Needs a person driving a real session. This run was an unattended agent with no input device or screen reader. The display gate ran on this host's GNOME Wayland session, but it proves only the widget tree, not keyboard traversal. Not inferred. |
| **Real GNOME session, screen reader (Orca):** revoke and grant are announced with their labels and descriptions | Same reason. The labels and descriptions exist in code (§3) and the tree test builds them; nothing was heard. |
| **Real KDE Plasma session**, both checks above | No KDE session on this host. |
| Full `cargo test --workspace` | Not required by the plan's Wave 2 regression list. The five named suites were run (§5), and G2 A1 proves that no non-GUI desktop crate changed, so the other crates' results at `1566279` (Wave 1 report §8.1) are not invalidated. It was not rerun, to keep the workstation stable. |
| Android suites | Wave 2 touches no Android file. |

**Procedure for the operator** (about 10 minutes per session): on GNOME and
then KDE, run `omnibridge-gui --page=peers` with one trusted and at least two
revoked devices. Confirm that it opens on **Devices**. Using only the keyboard:

1. open a trusted card's *Details and controls*;
2. toggle Files on, then off;
3. press *Revoke this device*, check that the dialog's focused default is
   **Cancel**, and press Escape;
4. open a revoked card and repeat with *Remove from list*;
5. repeat with *Remove all revoked devices*.

Then repeat steps 1–3 with Orca (GNOME) or the KDE screen reader, and record
what is announced for the switch ("Files for {name}") and for the revoke
button. Record the results in a dated addendum to this report.

## 8. Identifiers intentionally preserved

- `omnibridge_control`, `omnibridge-gui:` in `eprintln!` prefixes,
  `omnibridge-gui` in test argv, `APP_ID` `io.github.yurisismotto.omnibridge`
  (W3/W7), the ALPN string in the status bar tooltip (W5) and `omnibridge
  grant` in `README.md` (W7). All belong to later waves (plan §2).
- The route string `"peers"` survives only as `LEGACY_PEERS_PAGE`, the input
  alias. It is not a page name.
- "Trusted peers" remains in code comments and test names that describe the
  former page and the parity it guarantees, in
  `desktop/daemon/tests/notifications.rs:987` (a comment in a forbidden-path
  test file, left untouched), and in historical documents (ADR-0020 D7).
  "Trusted" remains as the trust **state** label, as the plan requires.
- The five frozen brand masters are unchanged: `git status` is clean on
  `docs/design/assets/`.

## 9. Exit criteria

| Criterion | State |
| --- | --- |
| one sidebar entry | **met** (`Page::ALL` = 6, one `Devices`; test) |
| control-parity test green | **met** |
| security suites byte-identical (and green) | **met** (G2 B: 5/5; 34 + 16 passed) |
| both real sessions checked | **NOT MET: NOT EXECUTED** (§7) |
| G2 | automated half **PASS**; manual half **NOT EXECUTED** |

## 10. Risks

- **Focus after a redraw.** A status change rebuilds the page, as it rebuilt
  both old pages. The open disclosure is now preserved, but keyboard focus is
  not. This is not new behaviour, but the disclosure makes a live device's card
  denser, so the operator check in §7 should watch for it on a connected
  device.
- **Two nested controls per card.** Opening the disclosure is one extra step
  before a grant or revoke. That is the intended progressive disclosure, and
  it is the reason for the operator check.
- **Rollback** is GUI-only: revert this wave; the daemon was not touched.
