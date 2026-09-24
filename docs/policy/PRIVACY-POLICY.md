# OmniBridge Privacy Policy

**Effective:** 2026-09-24 · **Applies to:** the OmniBridge Android app
(`io.github.yurisismotto.omnibridge`) and the OmniBridge desktop software it
connects to.

OmniBridge connects your Android device to computers you own, directly over
your local network, so you can move files and clipboard text between them and
see your phone's notifications on your computer. This policy says exactly what
the app touches, where it goes, and how to stop it.

## The short version

* **There is no OmniBridge server.** No account, no sign-in, no cloud sync.
  The developers of OmniBridge never receive any of your data. There is no
  server for it to reach.
* **No advertising, analytics, telemetry or crash reporting.** The app includes
  no advertising or analytics SDK and makes no internet request of its own.
* **Data goes only to computers you pair.** You pair a computer by scanning a
  QR code it shows you. From then on the two talk directly on your local
  network over an encrypted connection that only that computer can answer.
* **Every kind of data has its own switch**, per computer, and can be turned
  off at any time. Clipboard and notifications are off until you turn them on.

## Who is responsible

OmniBridge is open-source software published at
<https://github.com/yurisismotto/OmniBridge>. Questions about this policy:
open an issue at <https://github.com/yurisismotto/OmniBridge/issues>.

## What OmniBridge uses, and why

### Pairing and device identity

When you pair, the app creates a cryptographic key in your device's Android
Keystore (hardware-backed where the device supports it). The private key can't
be exported and never leaves the device. When your phone connects to a paired
computer it tells that computer:

* a random device identifier created by the app. It is not your Android ID,
  your IMEI or any other hardware identifier;
* your device's name, which is its model name (for example "SM-X620");
* the public fingerprint of its key;
* which OmniBridge features it supports.

On your phone the app keeps a list of the computers you have paired: each one's
name, identifier, key fingerprint, when you paired it, which features you have
allowed it, your settings for it, and up to four local network addresses it was
last reached at.

### Camera — only to scan the pairing code

The camera is used only to scan the QR code a computer shows when you pair.
Android asks for camera permission only when you tap **Pair**. The image is
decoded on your device and discarded. No photo or video is saved or sent. Only
the decoded pairing code is used, and only to reach that computer.

### Clipboard

* **Phone → computer: only when you choose to send.** You can send from the
  Send screen, the Quick Settings tile, or by sharing text to OmniBridge. The
  app never watches your clipboard and never sends it on its own. If the
  clipboard is marked sensitive (for example a copied password), the app asks
  you again before sending.
* **Computer → phone:** text a paired computer sends is held in memory for at
  most five minutes until you tap to copy it. If you turn on automatic receive
  for that computer, it is copied straight away.
* What is sent: the text (up to 32 KiB), a checksum of it, whether it is marked
  sensitive, and a timestamp.
* Clipboard text is never written to your device's storage.

Clipboard sharing is **off** for each computer until you turn it on.

### Files

* **Phone → computer:** only files you pick in Android's file picker or share
  to OmniBridge. Android gives the app access to that one file for that one
  transfer. OmniBridge asks for no storage permission.
* **Computer → phone:** you are asked to accept every incoming file. Accepted
  files are saved to `Download/OmniBridge` on your device. They are yours and
  stay there, even if you uninstall the app.
* What is sent with a file: its name, size, type and a checksum.
* The app keeps no history of transfers. The list on screen lasts only while
  the app is running.

Files are allowed when you pair a computer, because every incoming file still
needs your approval. You can turn files off for any computer.

### Notifications (optional, off by default)

If you turn it on, OmniBridge can show your phone's notifications on your
computer. Three separate things must all be true before anything is sent:

1. **You allow that computer.** Turning this on shows a screen explaining what
   will be sent, and nothing is allowed until you tap **Allow**.
2. **You allow Android notification access** for OmniBridge in Android's own
   settings.
3. **You choose which apps.** No app is chosen for you.

For each notification from an app you chose, the computer receives:

* the app's name and package name;
* the notification's title and text;
* when it was posted, its category, importance and progress;
* whether it is ongoing or can be dismissed.

It never receives pictures, icons, action buttons, reply fields or the people
attached to a notification. OmniBridge never shares its own notifications, or
notifications an app has marked as secret on the lock screen.

**While your phone is locked**, only the app's name is sent by default. You can
change this to send everything or nothing.

**When it runs:** OmniBridge sends notifications only while your phone is
connected to a computer you allowed for this. That can happen while the app is
in the background. OmniBridge asks Android to attach its notification reader
only while such a computer is connected, and to detach it afterwards. One
exception has been observed: if OmniBridge is force-stopped while attached,
Android may re-attach the reader and keep it attached until notification access
is turned off and on again. While no allowed computer is connected, nothing is
sent anywhere. While connected, OmniBridge appears in Android's list of
active apps, and shows an ongoing notification if you allow notifications.
Notifications are not stored on your phone. The OmniBridge desktop software
shows them and does not save them.

If you turn on **dismiss sync** for a computer, dismissing a notification on
that computer dismisses it on your phone. This is off by default, and it never
applies to ongoing notifications.

The apps you chose, and the list of apps you were last shown to pick from, are
stored on your phone with that computer's settings.

### Battery

Your phone's battery percentage and charging state are sent to a paired
computer when it connects, so the computer can show them. This is allowed when
you pair, and you can turn it off per computer with the **Battery** switch. A
computer's own battery reading is shown on your phone and kept only in memory.

### Background connection

While connected, OmniBridge runs a foreground service of type "connected
device" so the link to your computer stays up with the screen off. It starts
only when you pair or connect, or when you share something to a computer. It
never starts when the phone boots. It stops when you tap **Disconnect**, remove
the computer, or the connection gives up.

### Notification permission

OmniBridge asks to post notifications when you first connect. It uses them for
the connection status and for "clipboard received" prompts, which show the
computer's name and the size, never the text. Everything else works without
this permission.

## How your data is protected in transit

Everything between your phone and a computer goes over **TLS 1.3**, and each
side proves its identity with its own key. Your phone accepts only the exact
computer whose fingerprint it learned when you paired. There is no certificate
authority to trick, and no unencrypted connection is ever allowed. Pairing
itself is protected by a one-time code in the QR code, which both sides must
prove they know.

## What stays on your phone

* Your device key (in the Android Keystore, not exportable).
* The paired-computer list and your settings for each computer, described
  above.
* Files you accepted, in `Download/OmniBridge`.

App data is excluded from Android cloud backup and from device-to-device
transfer. The Android system log may contain technical events such as
connection attempts, transfer identifiers, sizes, network addresses and key
fingerprints. It never contains clipboard text, notification content or file
names. That log stays on your device and OmniBridge sends it nowhere.

## Sharing with third parties

OmniBridge does not sell, rent or share your data with anyone. The only place
anything goes is a computer you paired yourself, and you choose, per computer,
what it may receive.

## Your choices, and how to stop

| To stop… | Do this |
| --- | --- |
| one kind of data to one computer | open the computer in **Devices** and turn off Clipboard, Files or Battery; for notifications, turn off **Share notifications with this computer** |
| all notification reading | turn off OmniBridge in Android's **Notification access** settings |
| everything to one computer | **Revoke this device** on its card, then **Remove from list** if you like |
| the current connection | **Disconnect** |
| everything, everywhere | uninstall OmniBridge, or clear its storage in Android settings. This deletes the device key and the paired-computer list. Files you accepted stay in `Download/OmniBridge` until you delete them |

Camera and notification permissions can also be withdrawn at any time in
Android's app settings.

## Children

OmniBridge is a tool for connecting your own devices. It is not directed at
children.

## Changes

Changes to this policy are published at this address, with a new effective
date. Because the policy lives beside the source code, every change is recorded
in the project's public history.
