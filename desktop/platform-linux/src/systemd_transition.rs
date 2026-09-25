//! The OmniBridge → Pliwee `systemd --user` transition, as the daemon sees it.
//!
//! ADR-0020 ("Legacy systemd, firewalld and desktop integration") and the
//! rebrand plan's Wave 7 decision B5, made by measurement:
//!
//! * **(a) the package** ships `omnibridged.service` as a *symlink* to
//!   `pliweed.service` in the same unit directory. systemd treats that as an
//!   alias, so an account whose `~/.config/systemd/user/default.target.wants/`
//!   still holds the `omnibridged.service` link from OmniBridge 1.0.0 starts
//!   `pliweed.service` at its next login — **one** unit, one process, because
//!   an alias is the same unit under a second name. No package scriptlet ever
//!   writes into a home directory.
//! * **(b) this module** notices that such an account is enabled *only*
//!   through the legacy name. It still works, but `systemctl --user
//!   is-enabled pliweed.service` answers `disabled` for it, which is a lie a
//!   person will eventually act on. The daemon therefore says so once per
//!   start, with the exact command that records the enablement under the new
//!   name: `systemctl --user reenable pliweed.service`. Measured on systemd
//!   259 (Fedora 44): that command removes the legacy link, creates the
//!   canonical one, and running it a second time changes nothing.
//!
//! This module only *reads* the user's unit configuration. It cannot write
//! it: the unit runs with `ProtectHome=read-only`, and writing a user's
//! enablement would be doing on their behalf what the ADR says only they may
//! do.

use std::path::{Path, PathBuf};

/// The unit name OmniBridge 1.0.0 shipped. An alias of [`UNIT`] since Wave 7.
pub const LEGACY_UNIT: &str = "omnibridged.service";

/// The daemon's unit.
pub const UNIT: &str = "pliweed.service";

/// The one command that moves an account's enablement to the new name.
pub const REENABLE_COMMAND: &str = "systemctl --user reenable pliweed.service";

/// How an account's `default.target` pulls the daemon in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Enablement {
    /// Only the canonical link, or no link at all. Nothing to say.
    Canonical,
    /// Only the OmniBridge-era link. Starts at login through the alias, but
    /// `is-enabled pliweed.service` reports `disabled`.
    LegacyOnly { link: PathBuf },
    /// Both links. Harmless — one unit either way — but the legacy one is
    /// redundant.
    Both { link: PathBuf },
}

/// `$XDG_CONFIG_HOME/systemd/user/default.target.wants`, with the same HOME
/// fallback (and the same refusal of a relative `XDG_CONFIG_HOME`) the rest
/// of the adapter uses.
pub fn wants_dir_from_env() -> PathBuf {
    pliwee_core::platform::unix_fs::xdg_base(
        std::env::var_os("XDG_CONFIG_HOME"),
        std::env::var_os("HOME"),
        ".config",
    )
    .join("systemd/user/default.target.wants")
}

/// Classifies the links in `wants_dir`.
///
/// `symlink_metadata`, not `exists`: the legacy link points at
/// `/usr/lib/systemd/user/omnibridged.service`, and it counts whether or not
/// that target is still there. A dangling legacy link is still the user's
/// enablement, and still worth the one-line fix.
pub fn classify(wants_dir: &Path) -> Enablement {
    let legacy = wants_dir.join(LEGACY_UNIT);
    let has_legacy = legacy.symlink_metadata().is_ok();
    let has_canonical = wants_dir.join(UNIT).symlink_metadata().is_ok();
    match (has_legacy, has_canonical) {
        (true, false) => Enablement::LegacyOnly { link: legacy },
        (true, true) => Enablement::Both { link: legacy },
        (false, _) => Enablement::Canonical,
    }
}

/// Writes the finding to the journal. Nothing at all in the common case.
pub fn log(enablement: &Enablement) {
    match enablement {
        Enablement::Canonical => {}
        Enablement::LegacyOnly { link } => tracing::warn!(
            link = %link.display(),
            "this account enables Pliwee through the OmniBridge unit name {LEGACY_UNIT}, \
             which is now an alias of {UNIT}: it still starts at login, but \
             `systemctl --user is-enabled {UNIT}` reports it disabled. \
             To record it under the new name, run once: {REENABLE_COMMAND}"
        ),
        Enablement::Both { link } => tracing::info!(
            link = %link.display(),
            "{UNIT} is enabled, and the OmniBridge link {LEGACY_UNIT} is still present; \
             it is redundant (the same unit). To remove it, run once: {REENABLE_COMMAND}"
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    fn wants() -> (tempfile::TempDir, PathBuf) {
        let dir = tempfile::tempdir().expect("tempdir");
        let wants = dir.path().join("systemd/user/default.target.wants");
        std::fs::create_dir_all(&wants).expect("mkdir");
        (dir, wants)
    }

    #[test]
    fn no_links_is_canonical_and_says_nothing() {
        let (_d, w) = wants();
        assert_eq!(classify(&w), Enablement::Canonical);
    }

    #[test]
    fn a_missing_config_directory_is_canonical() {
        let dir = tempfile::tempdir().expect("tempdir");
        assert_eq!(classify(&dir.path().join("absent")), Enablement::Canonical);
    }

    #[test]
    fn the_canonical_link_alone_is_canonical() {
        let (_d, w) = wants();
        symlink("/usr/lib/systemd/user/pliweed.service", w.join(UNIT)).expect("link");
        assert_eq!(classify(&w), Enablement::Canonical);
    }

    /// The OmniBridge 1.0.0 upgrade case: `systemctl --user enable
    /// omnibridged.service` was run, and nothing has touched it since.
    #[test]
    fn the_legacy_link_alone_is_reported_with_its_path() {
        let (_d, w) = wants();
        symlink(
            "/usr/lib/systemd/user/omnibridged.service",
            w.join(LEGACY_UNIT),
        )
        .expect("link");
        assert_eq!(
            classify(&w),
            Enablement::LegacyOnly {
                link: w.join(LEGACY_UNIT)
            }
        );
    }

    /// A dangling link is still the user's enablement: the target not
    /// existing must not make the finding disappear.
    #[test]
    fn a_dangling_legacy_link_still_counts() {
        let (d, w) = wants();
        symlink(d.path().join("nowhere.service"), w.join(LEGACY_UNIT)).expect("link");
        assert!(matches!(classify(&w), Enablement::LegacyOnly { .. }));
    }

    #[test]
    fn both_links_are_reported_as_redundant() {
        let (_d, w) = wants();
        symlink(
            "/usr/lib/systemd/user/omnibridged.service",
            w.join(LEGACY_UNIT),
        )
        .expect("link");
        symlink("/usr/lib/systemd/user/pliweed.service", w.join(UNIT)).expect("link");
        assert!(matches!(classify(&w), Enablement::Both { .. }));
    }

    /// The instruction is the measured one, verbatim. A different command
    /// (`enable` alone leaves the legacy link; `disable omnibridged` leaves the
    /// account disabled) would be advice that does not do what it says.
    #[test]
    fn the_instruction_is_exactly_reenable() {
        assert_eq!(
            REENABLE_COMMAND,
            "systemctl --user reenable pliweed.service"
        );
        assert_eq!(UNIT, "pliweed.service");
        assert_eq!(LEGACY_UNIT, "omnibridged.service");
    }
}
