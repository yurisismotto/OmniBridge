# Android / Google Play v1 — release build and physical API 36 smoke (PLAY16 · PLAY17)

| | |
| --- | --- |
| Date | 2026-09-24 |
| Branch / commit built | `feature/android-google-play-v1` @ `e2cb6f4` |
| Device | Samsung SM-X620 (`gts10fepwifi`), Android 16 / API 36, One UI 8.0, tablet (sw ≥ 600dp) |
| Desktop peer | `fedora`, packaged **omnibridge 1.0.0-1.fc44** (`/usr/bin/omnibridged`, systemd user service), fingerprint `149F 6B66 AB5D 8526` |
| Scope | narrow regression for the targetSdk 35 → 36 change, not a re-certification |

This is a report, not a certification. Every row names what was observed and
how. Rows that needed a person say so.

---

## 1. The release bundle (PLAY16)

Built by the operator with `android/signing/build-release-bundle.sh --install
--uninstall-existing`. The password was entered by the operator, so it never
reached this session. Re-verified independently afterwards:

```
verify-release-bundle.sh app/build/outputs/bundle/release/app-release.aab
  PASS  exactly one signer
  PASS  signed by the expected certificate (75:FC:88:B5:20:72:47:EF:21:50:6B:D5:F6:EB:87:A8:15:AE:C0:13:87:41:83:30:3E:42:6A:92:7E:2F:BA:47)
  PASS  not a debug certificate
  PASS  jarsigner verifies every entry
  PASS  package io.github.yurisismotto.omnibridge
  INFO  versionCode 1
  INFO  versionName 1.0.0
  PASS  minSdk 29
  PASS  targetSdk 36
  PASS  debuggable is None (expected absent/false)
  PASS  allowBackup=false
  PASS  permissions are exactly the expected 9
  PASS  no keystore / key / properties files inside the bundle
  PASS  no PEM private key block inside the bundle
  PASS  dex present
  PASS  R8 mapping carried in bundle metadata (minification ran)
  SHA-256  19bf170338afdca93edc793fcc759934c755016b795eabf2a1bb695206ceaa6a  app-release.aab
  VERDICT  PASS
```

The bundle and its R8 mapping are kept outside the repository at
`~/.local/share/omnibridge-android-release/1.0.0-vc1/`, with `SHA256SUMS` and
`COMMIT` (`e2cb6f487a74e8c84b31f957fe7fdb296d3e1c5c`). The AAB is not
committed.

Installed on the device: a universal APK derived from that bundle by
bundletool 1.18.3 (SHA-256 of the jar verified against the GitHub release
digest). `dumpsys package` shows `versionCode=1 minSdk=29 targetSdk=36
versionName=1.0.0`, and the flags carry no `DEBUGGABLE`. `apksigner` reports
the signer as `75fc88b5…2fba47`, which is the upload certificate. The previous
debug install was removed first, as `--uninstall-existing` asked.

## 2. Smoke results (PLAY17)

| # | Surface | How | Result |
| --- | --- | --- | --- |
| 1 | Launch | `am start -W`, cold | ✅ `TotalTime 412 ms`; no crash |
| 2 | No permission asked at launch (F2) | focus after launch | ✅ focus is `MainActivity`, not a permission dialog |
| 3 | Edge-to-edge (Android 16 removes the opt-out) | screenshots | ✅ nothing under the status bar or taskbar |
| 4 | Large-screen rules (orientation/resizability ignored at sw ≥ 600dp) | rotate to landscape and back | ✅ same pid, same screen kept, layout adapts |
| 5 | Settings: new privacy text and **Privacy policy** link (F4, F5) | tap | ✅ `ACTION_VIEW https://github.com/…` resolved by the browser. The page itself 404s until the branch reaches `main` |
| 6 | Camera permission, in context | operator tapped **Pair device** | ✅ asked on Pair; `CAMERA granted=true USER_SET` |
| 7 | Pairing by QR | operator scanned; desktop confirmation by the operator | ✅ paired as `B92C F572 2D47 0331` (see §3 for the first two attempts) |
| 8 | `POST_NOTIFICATIONS` requested in context (F2) | after pairing | ✅ `granted=true USER_SET` |
| 9 | `connectedDevice` foreground service | `dumpsys activity services` | ✅ `isForeground=true types=0x00000010`; notification "Connected to fedora", channel `connection`, ongoing |
| 10 | Battery honours the grant (F1) | desktop `devices` | ✅ 72% received; the grant is on at pairing |
| 11 | Predictive back (on by default at target 36) | `KEYCODE_BACK` through Choose apps → Notifications → Device → Devices | ✅ each back goes to the declared parent inside the app. Back from a top-level tab leaves the app, which is the designed behaviour, not a change |
| 12 | Notification disclosure (F3) | switch on | ✅ dialog shown; switch still off behind it |
| 13 | …**Not now** | tap | ✅ switch off, grant "Not granted" |
| 14 | …**Allow** | tap | ✅ grant written; *Open Android settings* appears only now |
| 15 | Android notification access | One UI access screen, OmniBridge toggle, system dialog **Permitir** | ✅ `OmniBridgeNotificationListener` enabled |
| 16 | Listener bound only with an eligible peer | `dumpsys notification` "Live notification listeners" | ✅ bound only after the desktop grant arrived. Clean-state control: access granted with no peer → **0 live** |
| 17 | Deny by default for apps | picker | ✅ nothing pre-selected; log `not mirrored: NOT_ALLOWED_APP`; secondary profile `not mirrored: SECONDARY_PROFILE` |
| 18 | Mirroring a chosen app | `cmd notification post` (as `com.android.shell`), picked in the app | ✅ desktop "showing 1 of 1 mirrored"; app log `peer outcome NOTIFICATION_OUTCOME_DISPLAYED` |
| 19 | Mirroring with the app in the background and the screen off | Home + `KEYCODE_SLEEP` (`mWakefulness=Dozing`), then an update posted | ✅ session held (`last frame 4s ago`); update `DISPLAYED` on the desktop at 02:52:13 |
| 20 | Desktop → Android clipboard | `wl-copy` + `omnibridge clipboard send` | ✅ held `PENDING_USER`. The notification says "29 bytes of text. Open OmniBridge to copy it." with no content. The in-app **Copy** applied it: the Send screen then previewed the exact text `OmniBridge API36 smoke 025223` |
| 21 | Android → desktop clipboard, manual | Send clipboard → **Send to fedora** | ✅ `sent … bytes=29`; desktop `outcome="pending"` (its auto-receive is off) |
| 22 | Sharesheet, text | `SEND text/plain` to `SendActivity` | ✅ preview withholds the text; desktop received event `b05edd4b` |
| 23 | Quick Settings tile (the PendingIntent path on API 34+) | `cmd statusbar add-tile` / `click-tile`; removed afterwards | ✅ tap → focused activity → `sent … bytes=29`; desktop received `80695152` |
| 24 | Desktop → Android file | `omnibridge send`, 1 MiB random; **Accept** tapped | ✅ saved to `Download/OmniBridge`; SHA-256 `a74108b1…0e45a` identical on both sides |
| 25 | Filename kept out of the log (F5) | whole app-pid logcat (1 743 lines), anchored by `incoming bf7ab581 (1048576B)` / `received and verified bf7ab581` | ✅ 0 hits for the filename, 0 for the clipboard text |
| 26 | Android → desktop file via sharesheet | `SEND` with a `content://media/…` URI | ✅ offer `c2a476c0`, 1 048 576 B reached the desktop. It then waited for the **desktop's** approval and was cancelled from the CLI, because desktop approval is not an Android surface |
| 27 | Disconnect → Connect | app buttons | ✅ FGS 1 → 0, desktop "disconnected"; FGS 0 → 1, "connected" |
| 28 | Close and reopen | `am force-stop`, then `am start` | ✅ reopened in 177 ms; the FGS does **not** restart on its own |
| 29 | Crashes | `logcat -b crash` over the whole session | ✅ empty |

Human actions in this run: the operator ran the signed build (password),
tapped **Pair device** / allowed the camera / scanned the QR code, and
confirmed pairing on the desktop. Everything else was driven over adb on the
operator's device, with the operator's authorisation for this smoke. That
included the system notification-access toggle, the in-app **Allow**, **Copy**
and **Accept**, and granting `notifications.v1`, `files.v1` and
`clipboard.v1` to this tablet on the desktop. Test files, test notifications
and the temporary QS tile were removed afterwards.

## 3. Findings

### F11 — after a force-stop while bound, the listener can stay bound with no eligible peer

Reproduced on this device at targetSdk 36:

1. listener bound (a granted, mirroring peer connected);
2. `am force-stop` → Android restarts the process **for the listener service**
   (`Start proc … for service {…OmniBridgeNotificationListener}`);
3. the app sees no eligible peer and logs `requesting listener unbind: no
   eligible peer`;
4. the binding **remains** (`Live notification listeners` still lists it,
   system_server holds a `ConnectionRecord`), and a later connect/disconnect
   does not clear it;
5. `cmd notification disallow_listener` + `allow_listener` clears it.

Control, same session, from a clean state: connect → **1 live**; disconnect →
**0 live** at +3 s, +10 s and +20 s, with `onListenerDisconnected` received. So
the normal unbind works at target 36. This is the `requestRebind` stickiness
that N6 recorded as "never independently provoked" (§33 D); these are the
steps that provoke it. Whether it also happens at target 35 was not measured.

**Impact.** Nothing is sent: there is no session, and the source drops every
notification. But while stuck, the process is still delivered notifications
without a connected, granted computer. That contradicts ADR-0015 §3's
"structurally true" wording. **Classification: NON-BLOCKING for Play.** No data
leaves the device, and the privacy policy now describes the exception exactly.
It is open product debt: the fix belongs to the listener lifecycle, needs its
own hardware test, and would ship with the next versionCode.

### F12 — the share sheet's transfer row reads "To 1,0 MB"

`TransferViews.TransferRow` builds `"$direction ${humanBytes(size)}"` and never
includes the computer's name. It has been there since the v1.0.0 baseline.
Cosmetic. **NON-BLOCKING.**

### Procedure, not product: the first two pairing attempts

1. At about 02:36 the GA RPMs were installed while a source-built daemon
   (running since 2026-09-22) still held port 55432. The packaged service
   restart-looped with `Address already in use`. The stale daemon was stopped
   and the packaged one took over, with the same identity and store.
2. `omnibridge pair` was started in the background by this session. Its
   `[y/N]` confirmation read end-of-input and **declined**, as it should: the
   desktop log showed `pairing failed: declined by user` after the tablet's
   proof had verified. Pairing then succeeded from the desktop app with the
   operator confirming the fingerprint.

## 4. Store screenshots

Six tablet screenshots were captured from this release build and saved under
[`docs/design/assets/play/screenshots/tablet/`](../../design/assets/play/screenshots/tablet/).
Each is 1800 × 2724, 24-bit PNG. The only change is cropping off the status
bar (60 px) and the taskbar (96 px), because One UI does not honour SystemUI
demo mode and both showed the operator's own apps. No app UI was edited.

## 5. Verdict

The targetSdk 36 release behaves correctly on Android 16 hardware for every
surface in scope. F11 and F12 are recorded as non-blocking. This is the
evidence PLAY18 relies on.
