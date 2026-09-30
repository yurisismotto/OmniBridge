# Erratum: the Fedora firewall commands in OmniBridge 1.0.0

**2026-09-26 — branch `feat/pre-g8-autopilot`.** This supersedes the firewall
commands in OmniBridge 1.0.0's `packaging/fedora/README.md`. The v1.0.0 tag,
its README and the published release are left exactly as they were.

## What 1.0.0 said

```bash
sudo firewall-cmd --permanent --add-service=omnibridge   # TCP 55432
sudo firewall-cmd --permanent --add-service=mdns         # discovery
sudo firewall-cmd --reload
```

## Why that fails

The `omnibridge` package installs `/usr/lib/firewalld/services/omnibridge.xml`.
A firewalld that is already running knows only the service definitions it read
when it last started or reloaded. Right after installing the package, before
any reboot or reload, the first command is refused:

```
Error: INVALID_SERVICE: Zone 'work': 'omnibridge' not among existing services
```

It exits 101, and nothing is added to the zone. Installing the package, and
upgrading to Pliwee (which installs `pliwee.xml`), both leave firewalld in this
state. By design, the packages never run `firewall-cmd` themselves: installing
something must not change the firewall the user runs.

This was found by the pre-G8 upgrade gate `G7UP-fedora44-INSTALL` on
2026-09-26. The harness followed the 1.0.0 order and failed with exactly that
error. It was then measured on a write-protected copy of the same Fedora 44
guest (firewalld 2.4.4): the 1.0.0 order failed the same way, and the order
below put the service in both the permanent and the running zone.

## The corrected order

Reload first, so firewalld reads the new definition. That reload opens
nothing. Then add the service permanently, and reload again to apply it:

```bash
sudo firewall-cmd --reload
sudo firewall-cmd --permanent --add-service=omnibridge   # or pliwee, after the upgrade
sudo firewall-cmd --permanent --add-service=mdns
sudo firewall-cmd --reload
```

The current instructions are in
[`packaging/fedora/README.md`](../../packaging/fedora/README.md), § Firewall,
including the move from `omnibridge` to `pliwee` after an upgrade. On Fedora
Workstation nothing needs doing, because its default zone already allows both
flows. Users who never tightened their zone were not affected.
