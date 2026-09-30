//! Carrying an OmniBridge v1.0.0 identity into Pliwee's directories.
//!
//! ADR-0020 D9, D11 and D12; implementation plan, Wave 4.
//!
//! In the Linux adapter rather than in `pliwee-core`, because OmniBridge
//! 1.0.0 only ever shipped on Linux: there is no legacy directory to look for
//! on any other platform, and the portable crates stay free of `std::os`.
//!
//! # The rule this module exists for
//!
//! *The absence of a Pliwee directory is never, by itself, a reason to create
//! a new identity.* An install that ran OmniBridge has its identity key and
//! its trust store in `$XDG_DATA_HOME/omnibridge`. If a Pliwee daemon looked
//! only at `$XDG_DATA_HOME/pliwee`, found nothing and generated a key, every
//! peer that had pinned this machine would meet a stranger, and every pairing,
//! grant and policy would be gone — silently, on an ordinary package upgrade.
//!
//! So before [`pliwee_core::store::Store`] is opened on the canonical directory,
//! [`migrate_data_dir`] decides one of four things:
//!
//! | Canonical `P` | Legacy `L` | Outcome |
//! | --- | --- | --- |
//! | holds an identity | anything | use `P`; `L` is **not looked at** |
//! | no identity | absent | genuine first run |
//! | no identity | present, readable, private, holds an identity | **copy** `L` into `P` |
//! | no identity | present but unreadable, not private, incomplete or corrupt | **refuse**, naming `L` |
//!
//! A legacy directory that exists but holds neither `identity.key` nor
//! `state.json` — both established absent, positively — is no identity at all,
//! and is treated as the first run it is.
//!
//! # Copy, never move
//!
//! `L` is opened for reading only. It is never renamed, rewritten, re-moded or
//! deleted, so OmniBridge 1.0.0 can still start on it after a downgrade. A
//! rename would also be unsafe on its own terms: a crash in the middle of
//! moving two files leaves neither directory whole.
//!
//! The copy is built in a private staging directory next to `P` — the same
//! filesystem, so the final step is one atomic `rename(2)` of a directory —
//! with both files and the `MIGRATED_FROM` record already in it and already
//! fsynced. A crash before the rename leaves no `P` at all, and the next start
//! simply does the copy again; a crash after it leaves a complete `P`. There
//! is no instant at which `P` holds half an identity.
//!
//! # What is not here
//!
//! No schema change, no key regeneration, no certificate rewrite. The bytes of
//! `identity.key` and `state.json` arrive in `P` exactly as they were in `L`,
//! and their SHA-256 is checked on the way.

use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use pliwee_core::identity::{IdentityState, SoftwareBacking};
use pliwee_core::platform::unix_fs::{xdg_base, FileSecretStore};
use pliwee_core::store::Store;

/// The directory name Pliwee owns under each XDG base.
pub const CANONICAL_DIR_NAME: &str = "pliwee";
/// The directory name OmniBridge used. A migration *source*, never canonical.
///
/// Durable (ADR-0020 D11): this detection stays until an ADR names the last
/// supported upgrade source.
pub const LEGACY_DIR_NAME: &str = "omnibridge";
/// The record written into `P` by a migration.
pub const MIGRATED_FROM_FILE: &str = "MIGRATED_FROM";

const IDENTITY_FILE: &str = "identity.key";
const STATE_FILE: &str = "state.json";
/// Staging directories live next to `P` and carry this prefix, so a crash
/// leftover is recognisable as ours and nothing else ever is.
const STAGING_PREFIX: &str = ".pliwee-migrating-";

const DIR_MODE: u32 = 0o700;
const FILE_MODE: u32 = 0o600;

/// The canonical and the legacy data directory, resolved together.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DataDirs {
    /// `P`: `$XDG_DATA_HOME/pliwee`.
    pub canonical: PathBuf,
    /// `L`: `$XDG_DATA_HOME/omnibridge`.
    pub legacy: PathBuf,
}

impl DataDirs {
    /// From this process's environment.
    pub fn from_env() -> Self {
        Self::resolve(std::env::var_os("XDG_DATA_HOME"), std::env::var_os("HOME"))
    }

    /// From explicit values: the seam the tests use, because mutating the
    /// environment would race every other test in the binary.
    pub fn resolve(xdg_data_home: Option<OsString>, home: Option<OsString>) -> Self {
        let base = xdg_base(xdg_data_home, home, ".local/share");
        Self {
            canonical: base.join(CANONICAL_DIR_NAME),
            legacy: base.join(LEGACY_DIR_NAME),
        }
    }
}

/// The canonical and the legacy GUI preference file, resolved together.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigFiles {
    /// `$XDG_CONFIG_HOME/pliwee/gui.json`.
    pub canonical: PathBuf,
    /// `$XDG_CONFIG_HOME/omnibridge/gui.json`.
    pub legacy: PathBuf,
}

impl ConfigFiles {
    pub fn from_env(file_name: &str) -> Self {
        Self::resolve(
            std::env::var_os("XDG_CONFIG_HOME"),
            std::env::var_os("HOME"),
            file_name,
        )
    }

    pub fn resolve(
        xdg_config_home: Option<OsString>,
        home: Option<OsString>,
        file_name: &str,
    ) -> Self {
        let base = xdg_base(xdg_config_home, home, ".config");
        Self {
            canonical: base.join(CANONICAL_DIR_NAME).join(file_name),
            legacy: base.join(LEGACY_DIR_NAME).join(file_name),
        }
    }
}

/// What `MIGRATED_FROM` says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MigrationRecord {
    /// The legacy directory the identity was copied from.
    pub source: PathBuf,
    pub migrated_at_unix: u64,
    pub identity_sha256: String,
    pub state_sha256: String,
}

impl MigrationRecord {
    fn render(&self) -> String {
        format!(
            "# Written by Pliwee when it copied an OmniBridge identity into this\n\
             # directory. The source directory was not modified (ADR-0020 D9).\n\
             source={}\n\
             migrated_at_unix={}\n\
             sha256.{IDENTITY_FILE}={}\n\
             sha256.{STATE_FILE}={}\n",
            self.source.display(),
            self.migrated_at_unix,
            self.identity_sha256,
            self.state_sha256,
        )
    }

    /// Reads the record back. `None` for anything that is not a complete
    /// record: it is an account of what happened, never an input to a
    /// decision, so a damaged one is simply not reported.
    pub fn parse(text: &str) -> Option<Self> {
        let mut source = None;
        let mut at = None;
        let mut identity = None;
        let mut state = None;
        for line in text.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            match key {
                "source" => source = Some(PathBuf::from(value)),
                "migrated_at_unix" => at = value.parse().ok(),
                k if k == format!("sha256.{IDENTITY_FILE}") => identity = Some(value.to_string()),
                k if k == format!("sha256.{STATE_FILE}") => state = Some(value.to_string()),
                _ => {}
            }
        }
        Some(Self {
            source: source?,
            migrated_at_unix: at?,
            identity_sha256: identity?,
            state_sha256: state?,
        })
    }

    /// The record in `dir`, if there is a readable, complete one.
    pub fn read_from(dir: &Path) -> Option<Self> {
        fs::read_to_string(dir.join(MIGRATED_FROM_FILE))
            .ok()
            .and_then(|t| Self::parse(&t))
    }
}

/// What [`migrate_data_dir`] found and did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DataDirOrigin {
    /// `P` already held an identity; `L` was not looked at. `migrated_from`
    /// is the record left by an earlier migration, if there was one.
    Existing {
        migrated_from: Option<MigrationRecord>,
    },
    /// This call copied `L` into `P`.
    Migrated(MigrationRecord),
    /// Neither directory holds an identity: a genuine first run.
    NoLegacyState,
}

impl DataDirOrigin {
    /// The migration record, whether it was written now or earlier.
    pub fn record(&self) -> Option<&MigrationRecord> {
        match self {
            Self::Existing { migrated_from } => migrated_from.as_ref(),
            Self::Migrated(r) => Some(r),
            Self::NoLegacyState => None,
        }
    }
}

/// Why startup must not continue.
///
/// Every value of this type means "an identity may exist and could not be
/// carried over", so the only safe response is to stop — never to fall
/// through to a first run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MigrationError {
    /// The path at fault. Always named to the operator.
    pub path: PathBuf,
    pub detail: String,
}

impl MigrationError {
    fn new(path: &Path, detail: impl Into<String>) -> Self {
        Self {
            path: path.to_path_buf(),
            detail: detail.into(),
        }
    }

    fn io(path: &Path, what: &str, e: &io::Error) -> Self {
        Self::new(path, format!("{what}: {e}"))
    }
}

impl std::fmt::Display for MigrationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}: {}. Pliwee will not create a new identity while existing \
             OmniBridge state may hold one; nothing has been written. Fix the \
             problem above and start again",
            self.path.display(),
            self.detail
        )
    }
}

impl std::error::Error for MigrationError {}

/// Prepares `dirs.canonical` so that [`Store::open`] can be called on it.
///
/// Returns before anything is written in every case except
/// [`DataDirOrigin::Migrated`]. Idempotent: once `P` holds an identity, a
/// second call reads only `P` and writes nothing.
pub fn migrate_data_dir(dirs: &DataDirs) -> Result<DataDirOrigin, MigrationError> {
    migrate_data_dir_with(dirs, &mut |_| {})
}

/// [`migrate_data_dir`], with a hook run after the staging directory is
/// complete and fsynced and before it is renamed into place. The tests use it
/// to kill the migration at the one point where a crash could matter.
fn migrate_data_dir_with(
    dirs: &DataDirs,
    before_rename: &mut dyn FnMut(&Path),
) -> Result<DataDirOrigin, MigrationError> {
    let p = dirs.canonical.as_path();
    let l = dirs.legacy.as_path();

    // Step 2: `P` holds an identity → use it and never look at `L`. "Holds"
    // is either file being present: a half identity in `P` is `Store`'s to
    // refuse, and is still not a reason to reach for `L`.
    if holds_identity(p)? {
        return Ok(DataDirOrigin::Existing {
            migrated_from: MigrationRecord::read_from(p),
        });
    }

    // Step 3: does `L` exist? `symlink_metadata`, not `try_exists`: a broken
    // symlink at `L` must be an error, and `try_exists` calls it absence.
    match fs::symlink_metadata(l) {
        Ok(_) => {}
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(DataDirOrigin::NoLegacyState),
        Err(e) => return Err(MigrationError::io(l, "could not be examined", &e)),
    }

    let meta =
        fs::metadata(l).map_err(|e| MigrationError::io(l, "exists but cannot be read", &e))?;
    if !meta.is_dir() {
        return Err(MigrationError::new(l, "exists but is not a directory"));
    }
    let mode = meta.permissions().mode() & 0o777;
    if mode & 0o077 != 0 {
        return Err(MigrationError::new(
            l,
            format!(
                "has mode {mode:o}; a directory holding an identity key must \
                 not be group- or world-accessible. Fix with: chmod 700 {}",
                l.display()
            ),
        ));
    }

    // The same classification `Store` uses, read-only. `probe_identity` never
    // writes; `Store::open` would call `harden()` on `L`, so it is not used.
    let legacy_store = FileSecretStore::new(l);
    match Store::probe_identity(&legacy_store, &SoftwareBacking) {
        IdentityState::Available => {}
        // Both files positively absent: an empty legacy directory holds no
        // identity, and there is nothing to lose by creating one.
        IdentityState::NotCreated => return Ok(DataDirOrigin::NoLegacyState),
        other => {
            return Err(MigrationError::new(
                l,
                format!("holds an OmniBridge identity that cannot be used: {other}"),
            ))
        }
    }

    let identity = fs::read(l.join(IDENTITY_FILE))
        .map_err(|e| MigrationError::io(&l.join(IDENTITY_FILE), "could not be read", &e))?;
    let state = fs::read(l.join(STATE_FILE))
        .map_err(|e| MigrationError::io(&l.join(STATE_FILE), "could not be read", &e))?;

    let record = MigrationRecord {
        source: l.to_path_buf(),
        migrated_at_unix: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or_default(),
        identity_sha256: sha256_hex(&identity),
        state_sha256: sha256_hex(&state),
    };

    let parent = p
        .parent()
        .ok_or_else(|| MigrationError::new(p, "has no parent directory"))?;
    fs::create_dir_all(parent)
        .map_err(|e| MigrationError::io(parent, "could not be created", &e))?;
    remove_stale_staging(parent)?;

    let staging = parent.join(format!(
        "{STAGING_PREFIX}{}-{}",
        std::process::id(),
        record.migrated_at_unix
    ));
    let result = stage(&staging, &identity, &state, &record).and_then(|()| {
        before_rename(&staging);
        // `P` may exist as an empty directory; `rename(2)` replaces an empty
        // directory and refuses a non-empty one, which is the right answer
        // for a `P` that holds something other than an identity.
        fs::rename(&staging, p).map_err(|e| {
            MigrationError::io(
                p,
                "could not receive the migrated identity (it exists without \
                 an identity but is not empty?)",
                &e,
            )
        })
    });
    if let Err(e) = result {
        // The staging directory holds a copy of the private key. It is ours,
        // and leaving it would be leaving key material lying around.
        let _ = fs::remove_dir_all(&staging);
        return Err(e);
    }
    sync_dir(parent).map_err(|e| MigrationError::io(parent, "could not be synced", &e))?;

    Ok(DataDirOrigin::Migrated(record))
}

/// Whether `dir` holds either identity file. An error that is not absence —
/// a directory that cannot be traversed — is reported, never read as "no".
fn holds_identity(dir: &Path) -> Result<bool, MigrationError> {
    for name in [IDENTITY_FILE, STATE_FILE] {
        let path = dir.join(name);
        match fs::symlink_metadata(&path) {
            Ok(_) => return Ok(true),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(MigrationError::io(&path, "could not be examined", &e)),
        }
    }
    Ok(false)
}

/// Removes staging directories a crashed migration left next to `P`.
///
/// Only entries that are real directories carrying our prefix: they are ours
/// by construction, `P` holds no identity (checked by the caller), and each
/// holds a copy of a private key that should not outlive the attempt.
fn remove_stale_staging(parent: &Path) -> Result<(), MigrationError> {
    let entries =
        fs::read_dir(parent).map_err(|e| MigrationError::io(parent, "could not be listed", &e))?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        if !name.to_string_lossy().starts_with(STAGING_PREFIX) {
            continue;
        }
        let path = entry.path();
        let is_dir = fs::symlink_metadata(&path)
            .map(|m| m.is_dir())
            .unwrap_or(false);
        if is_dir {
            fs::remove_dir_all(&path).map_err(|e| {
                MigrationError::io(
                    &path,
                    "a leftover migration directory could not be removed",
                    &e,
                )
            })?;
        }
    }
    Ok(())
}

/// Builds the complete, fsynced future `P` at `staging`.
fn stage(
    staging: &Path,
    identity: &[u8],
    state: &[u8],
    record: &MigrationRecord,
) -> Result<(), MigrationError> {
    fs::DirBuilder::new()
        .mode(DIR_MODE)
        .create(staging)
        .map_err(|e| MigrationError::io(staging, "could not be created", &e))?;
    // The umask can only narrow the mode, but say it explicitly anyway.
    fs::set_permissions(staging, fs::Permissions::from_mode(DIR_MODE))
        .map_err(|e| MigrationError::io(staging, "could not be made private", &e))?;

    write_new(&staging.join(IDENTITY_FILE), identity)?;
    write_new(&staging.join(STATE_FILE), state)?;
    write_new(
        &staging.join(MIGRATED_FROM_FILE),
        record.render().as_bytes(),
    )?;

    // Read back what landed and compare, so a short write or a filesystem
    // that lies cannot produce a `P` whose key differs from `L`'s.
    for (name, expected) in [
        (IDENTITY_FILE, &record.identity_sha256),
        (STATE_FILE, &record.state_sha256),
    ] {
        let path = staging.join(name);
        let bytes =
            fs::read(&path).map_err(|e| MigrationError::io(&path, "could not be read back", &e))?;
        if &sha256_hex(&bytes) != expected {
            return Err(MigrationError::new(
                &path,
                "the copy does not match its source (SHA-256 differs)",
            ));
        }
    }

    sync_dir(staging).map_err(|e| MigrationError::io(staging, "could not be synced", &e))
}

/// Creates `path` exclusively, already at 0600, and fsyncs it.
fn write_new(path: &Path, data: &[u8]) -> Result<(), MigrationError> {
    let mut f = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(FILE_MODE)
        .open(path)
        .map_err(|e| MigrationError::io(path, "could not be created", &e))?;
    f.write_all(data)
        .and_then(|()| f.sync_all())
        .map_err(|e| MigrationError::io(path, "could not be written", &e))
}

fn sync_dir(dir: &Path) -> io::Result<()> {
    File::open(dir)?.sync_all()
}

fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// What [`migrate_config_file`] found and did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigOrigin {
    /// The canonical file exists; the legacy one was not looked at.
    Existing,
    /// The legacy file was copied to the canonical path by this call.
    Migrated { source: PathBuf },
    /// Neither exists.
    NoLegacyState,
}

/// The same rule for one configuration file (`gui.json`): canonical wins; a
/// legacy file that exists is copied (0600, write-then-rename, fsync) and
/// left in place; one that exists and cannot be read is an error naming it,
/// and nothing is created.
///
/// Unlike the data directory, the file is not required to be private: it
/// holds one public fingerprint, and OmniBridge wrote it with the default
/// umask. Requiring more than OmniBridge did would turn a working install
/// into a refusal. The copy is written at 0600 regardless.
pub fn migrate_config_file(files: &ConfigFiles) -> Result<ConfigOrigin, MigrationError> {
    let p = files.canonical.as_path();
    let l = files.legacy.as_path();

    match fs::symlink_metadata(p) {
        Ok(_) => return Ok(ConfigOrigin::Existing),
        Err(e) if e.kind() == io::ErrorKind::NotFound => {}
        Err(e) => return Err(MigrationError::io(p, "could not be examined", &e)),
    }
    match fs::symlink_metadata(l) {
        Ok(_) => {}
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(ConfigOrigin::NoLegacyState),
        Err(e) => return Err(MigrationError::io(l, "could not be examined", &e)),
    }
    let meta =
        fs::metadata(l).map_err(|e| MigrationError::io(l, "exists but cannot be read", &e))?;
    if !meta.is_file() {
        return Err(MigrationError::new(l, "exists but is not a regular file"));
    }
    let bytes = fs::read(l).map_err(|e| MigrationError::io(l, "exists but cannot be read", &e))?;

    let parent = p
        .parent()
        .ok_or_else(|| MigrationError::new(p, "has no parent directory"))?;
    fs::create_dir_all(parent)
        .map_err(|e| MigrationError::io(parent, "could not be created", &e))?;
    fs::set_permissions(parent, fs::Permissions::from_mode(DIR_MODE))
        .map_err(|e| MigrationError::io(parent, "could not be made private", &e))?;

    let file_name = p
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let tmp = parent.join(format!(".{file_name}.migrating-{}", std::process::id()));
    let _ = fs::remove_file(&tmp);
    let result = write_new(&tmp, &bytes).and_then(|()| {
        fs::rename(&tmp, p).map_err(|e| MigrationError::io(p, "could not be written", &e))
    });
    if let Err(e) = result {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    sync_dir(parent).map_err(|e| MigrationError::io(parent, "could not be synced", &e))?;
    Ok(ConfigOrigin::Migrated {
        source: l.to_path_buf(),
    })
}

#[cfg(test)]
mod tests {
    //! Wave 4 cases (a)–(f) of the implementation plan, plus the config rule.
    //!
    //! Each legacy directory here is made by *OmniBridge's own code path*:
    //! `Store::open` on `L` is exactly what a v1.0.0 daemon did on its first
    //! start. The captured state of real v1.0.0 installs is a separate,
    //! integration-level fixture.

    use super::*;
    use std::os::unix::fs::MetadataExt;

    struct Fixture {
        _root: tempfile::TempDir,
        dirs: DataDirs,
    }

    fn fixture() -> Fixture {
        let root = tempfile::tempdir().expect("tempdir");
        let base = root.path().join("share");
        fs::create_dir(&base).expect("mkdir");
        let dirs = DataDirs {
            canonical: base.join(CANONICAL_DIR_NAME),
            legacy: base.join(LEGACY_DIR_NAME),
        };
        Fixture { _root: root, dirs }
    }

    /// Creates an identity in `dir` the way OmniBridge did, and returns its
    /// fingerprint and device id.
    fn make_identity(dir: &Path) -> (String, String) {
        let store = Store::open(dir).expect("create identity");
        (
            store.identity().fingerprint().to_hex(),
            store.identity().device_id().to_string(),
        )
    }

    /// Everything in a directory, as (name, sha256, mtime, mode).
    fn snapshot(dir: &Path) -> Vec<(String, String, i64, i64, u32)> {
        let mut out: Vec<_> = fs::read_dir(dir)
            .expect("list")
            .map(|e| {
                let e = e.expect("entry");
                let m = fs::symlink_metadata(e.path()).expect("stat");
                let hash = if m.is_file() {
                    sha256_hex(&fs::read(e.path()).expect("read"))
                } else {
                    String::new()
                };
                (
                    e.file_name().to_string_lossy().into_owned(),
                    hash,
                    m.mtime(),
                    m.mtime_nsec(),
                    m.mode(),
                )
            })
            .collect();
        out.sort();
        out
    }

    fn staging_leftovers(dirs: &DataDirs) -> usize {
        fs::read_dir(dirs.canonical.parent().expect("parent"))
            .expect("list")
            .filter(|e| {
                e.as_ref()
                    .map(|e| e.file_name().to_string_lossy().starts_with(STAGING_PREFIX))
                    .unwrap_or(false)
            })
            .count()
    }

    // (a) --------------------------------------------------------------------

    #[test]
    fn a_valid_legacy_identity_is_copied_and_keeps_its_fingerprint() {
        let f = fixture();
        let (fp_before, id_before) = make_identity(&f.dirs.legacy);
        let legacy_before = snapshot(&f.dirs.legacy);
        assert_eq!(
            Store::probe_identity_at(&f.dirs.canonical),
            IdentityState::NotCreated,
            "precondition: P holds no identity"
        );

        let origin = migrate_data_dir(&f.dirs).expect("migrate");

        let DataDirOrigin::Migrated(record) = origin else {
            panic!("expected a migration, got {origin:?}");
        };
        assert_eq!(record.source, f.dirs.legacy);
        let store = Store::open(&f.dirs.canonical).expect("open migrated");
        assert_eq!(store.identity().fingerprint().to_hex(), fp_before);
        assert_eq!(store.identity().device_id(), id_before);

        // Byte-identical, and the record says which bytes.
        for (name, recorded) in [
            (IDENTITY_FILE, &record.identity_sha256),
            (STATE_FILE, &record.state_sha256),
        ] {
            let l = fs::read(f.dirs.legacy.join(name)).expect("read L");
            let p = fs::read(f.dirs.canonical.join(name)).expect("read P");
            assert_eq!(l, p, "{name} differs");
            assert_eq!(&sha256_hex(&l), recorded, "{name} hash not recorded");
        }
        assert_eq!(
            MigrationRecord::read_from(&f.dirs.canonical).as_ref(),
            Some(&record)
        );

        // Private, and nothing left behind.
        let dir_mode = fs::metadata(&f.dirs.canonical).expect("stat").mode() & 0o777;
        assert_eq!(dir_mode, DIR_MODE);
        for name in [IDENTITY_FILE, STATE_FILE, MIGRATED_FROM_FILE] {
            let mode = fs::metadata(f.dirs.canonical.join(name))
                .expect("stat")
                .mode()
                & 0o777;
            assert_eq!(mode, FILE_MODE, "{name}");
        }
        assert_eq!(staging_leftovers(&f.dirs), 0);

        // `L` untouched: same names, bytes, mtimes and modes.
        assert_eq!(snapshot(&f.dirs.legacy), legacy_before);
    }

    // (b) --------------------------------------------------------------------

    #[test]
    fn a_populated_canonical_directory_wins_and_the_legacy_one_is_ignored() {
        let f = fixture();
        let (legacy_fp, _) = make_identity(&f.dirs.legacy);
        let (canonical_fp, _) = make_identity(&f.dirs.canonical);
        assert_ne!(legacy_fp, canonical_fp, "precondition: two identities");
        let p_before = snapshot(&f.dirs.canonical);

        // Make `L` unreadable: if it were looked at at all, this would fail.
        fs::set_permissions(&f.dirs.legacy, fs::Permissions::from_mode(0o000)).expect("chmod");
        let origin = migrate_data_dir(&f.dirs);
        fs::set_permissions(&f.dirs.legacy, fs::Permissions::from_mode(0o700)).expect("chmod");

        assert_eq!(
            origin.expect("L must not be read"),
            DataDirOrigin::Existing {
                migrated_from: None
            }
        );
        assert_eq!(snapshot(&f.dirs.canonical), p_before);
        let store = Store::open(&f.dirs.canonical).expect("open");
        assert_eq!(store.identity().fingerprint().to_hex(), canonical_fp);
    }

    // (c) --------------------------------------------------------------------

    /// Runs the migration on a broken `L` and asserts the G4 property: an
    /// error naming `L`, and no file created in `P` — so no identity either.
    fn assert_refused_naming_legacy(f: &Fixture) {
        let err = migrate_data_dir(&f.dirs).expect_err("must refuse");
        assert_eq!(err.path, f.dirs.legacy, "{err}");
        assert!(
            err.to_string()
                .contains(&f.dirs.legacy.display().to_string()),
            "{err}"
        );
        assert!(
            !f.dirs.canonical.exists(),
            "P was created on a refusal: {:?}",
            fs::read_dir(&f.dirs.canonical).map(|d| d.count())
        );
        assert_eq!(staging_leftovers(&f.dirs), 0);
        assert_eq!(
            Store::probe_identity_at(&f.dirs.canonical),
            IdentityState::NotCreated
        );
    }

    #[test]
    fn an_unreadable_legacy_directory_is_an_error_and_creates_nothing() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        fs::set_permissions(&f.dirs.legacy, fs::Permissions::from_mode(0o000)).expect("chmod");
        // EACCES only binds a non-root process; as root the case would be
        // measuring nothing, so it says so rather than passing.
        let probe = fs::read_dir(&f.dirs.legacy);
        if probe.is_ok() {
            fs::set_permissions(&f.dirs.legacy, fs::Permissions::from_mode(0o700)).expect("chmod");
            panic!("running with CAP_DAC_OVERRIDE: EACCES cannot be produced here");
        }
        let result = std::panic::catch_unwind(|| assert_refused_naming_legacy(&f));
        fs::set_permissions(&f.dirs.legacy, fs::Permissions::from_mode(0o700)).expect("chmod");
        if let Err(p) = result {
            std::panic::resume_unwind(p);
        }
    }

    #[test]
    fn an_unreadable_legacy_key_is_an_error_and_creates_nothing() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        fs::set_permissions(
            f.dirs.legacy.join(IDENTITY_FILE),
            fs::Permissions::from_mode(0o000),
        )
        .expect("chmod");
        assert_refused_naming_legacy(&f);
    }

    #[test]
    fn a_broken_legacy_symlink_is_an_error_and_creates_nothing() {
        let f = fixture();
        std::os::unix::fs::symlink(
            f.dirs.legacy.with_file_name("does-not-exist"),
            &f.dirs.legacy,
        )
        .expect("symlink");
        assert!(
            !f.dirs.legacy.exists(),
            "precondition: Path::exists calls this absent"
        );
        assert_refused_naming_legacy(&f);
    }

    #[test]
    fn a_legacy_directory_that_is_not_private_is_an_error_and_creates_nothing() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        fs::set_permissions(&f.dirs.legacy, fs::Permissions::from_mode(0o755)).expect("chmod");
        assert_refused_naming_legacy(&f);
        // And `L` was not "fixed" on the way: it is never modified.
        assert_eq!(
            fs::metadata(&f.dirs.legacy).expect("stat").mode() & 0o777,
            0o755
        );
    }

    #[test]
    fn a_legacy_key_that_is_not_private_is_an_error_and_creates_nothing() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        fs::set_permissions(
            f.dirs.legacy.join(IDENTITY_FILE),
            fs::Permissions::from_mode(0o644),
        )
        .expect("chmod");
        assert_refused_naming_legacy(&f);
    }

    #[test]
    fn an_incomplete_legacy_identity_is_an_error_and_creates_nothing() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        fs::remove_file(f.dirs.legacy.join(IDENTITY_FILE)).expect("rm");
        assert_refused_naming_legacy(&f);
    }

    #[test]
    fn a_corrupt_legacy_state_is_an_error_and_creates_nothing() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        fs::write(f.dirs.legacy.join(STATE_FILE), b"{ not json").expect("write");
        assert_refused_naming_legacy(&f);
    }

    #[test]
    fn a_legacy_file_where_a_directory_belongs_is_an_error() {
        let f = fixture();
        fs::write(&f.dirs.legacy, b"").expect("write");
        assert_refused_naming_legacy(&f);
    }

    #[test]
    fn a_non_traversable_canonical_directory_is_an_error_and_not_a_first_run() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        fs::DirBuilder::new()
            .mode(0o000)
            .create(&f.dirs.canonical)
            .expect("mkdir");
        let result = migrate_data_dir(&f.dirs);
        fs::set_permissions(&f.dirs.canonical, fs::Permissions::from_mode(0o700)).expect("chmod");
        let err = result.expect_err("an unexaminable P must refuse");
        assert!(err.path.starts_with(&f.dirs.canonical), "{err}");
        assert_eq!(fs::read_dir(&f.dirs.canonical).expect("list").count(), 0);
    }

    #[test]
    fn an_empty_legacy_directory_holds_no_identity_and_is_a_first_run() {
        let f = fixture();
        fs::DirBuilder::new()
            .mode(0o700)
            .create(&f.dirs.legacy)
            .expect("mkdir");
        assert_eq!(
            migrate_data_dir(&f.dirs).expect("no identity to carry"),
            DataDirOrigin::NoLegacyState
        );
        assert!(!f.dirs.canonical.exists(), "nothing is written by the step");
    }

    #[test]
    fn no_legacy_directory_is_a_first_run_and_writes_nothing() {
        let f = fixture();
        assert_eq!(
            migrate_data_dir(&f.dirs).expect("first run"),
            DataDirOrigin::NoLegacyState
        );
        assert!(!f.dirs.canonical.exists());
    }

    // (d) --------------------------------------------------------------------

    #[test]
    fn a_crash_between_copy_and_rename_leaves_no_half_state_and_the_next_start_completes() {
        let f = fixture();
        let (fp, id) = make_identity(&f.dirs.legacy);
        let legacy_before = snapshot(&f.dirs.legacy);

        // A panic unwinds straight out, skipping every cleanup, exactly as
        // process death would.
        let dirs = f.dirs.clone();
        let crashed = std::panic::catch_unwind(move || {
            let _ = migrate_data_dir_with(&dirs, &mut |staging| {
                assert!(staging.join(IDENTITY_FILE).exists(), "copy happened");
                panic!("injected crash before rename");
            });
        });
        assert!(crashed.is_err(), "the fault was not injected");

        // After the crash: no `P` at all (not a half one), one staging dir.
        assert!(
            !f.dirs.canonical.exists(),
            "P exists after a pre-rename crash"
        );
        assert_eq!(staging_leftovers(&f.dirs), 1);
        assert_eq!(
            Store::probe_identity_at(&f.dirs.canonical),
            IdentityState::NotCreated
        );

        // Next start completes, with the same identity, and cleans up.
        let origin = migrate_data_dir(&f.dirs).expect("next start");
        assert!(matches!(origin, DataDirOrigin::Migrated(_)), "{origin:?}");
        assert_eq!(staging_leftovers(&f.dirs), 0);
        let store = Store::open(&f.dirs.canonical).expect("open");
        assert_eq!(store.identity().fingerprint().to_hex(), fp);
        assert_eq!(store.identity().device_id(), id);
        assert_eq!(snapshot(&f.dirs.legacy), legacy_before);
    }

    #[test]
    fn a_failed_rename_into_a_non_empty_canonical_directory_refuses_and_leaves_no_key_copy() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        fs::create_dir(&f.dirs.canonical).expect("mkdir");
        fs::write(f.dirs.canonical.join("unrelated"), b"x").expect("write");

        let err = migrate_data_dir(&f.dirs).expect_err("must refuse");
        assert_eq!(err.path, f.dirs.canonical, "{err}");
        assert_eq!(staging_leftovers(&f.dirs), 0, "a key copy was left behind");
        assert!(!f.dirs.canonical.join(IDENTITY_FILE).exists());
    }

    // (e) --------------------------------------------------------------------

    #[test]
    fn a_second_start_is_a_no_op() {
        let f = fixture();
        make_identity(&f.dirs.legacy);
        let first = migrate_data_dir(&f.dirs).expect("first");
        let DataDirOrigin::Migrated(record) = first else {
            panic!("expected a migration, got {first:?}");
        };
        let p_before = snapshot(&f.dirs.canonical);
        let l_before = snapshot(&f.dirs.legacy);

        // Sub-second mtimes would hide a rewrite inside the same second.
        std::thread::sleep(std::time::Duration::from_millis(20));
        let second = migrate_data_dir(&f.dirs).expect("second");

        assert_eq!(
            second,
            DataDirOrigin::Existing {
                migrated_from: Some(record)
            }
        );
        assert_eq!(snapshot(&f.dirs.canonical), p_before, "P was rewritten");
        assert_eq!(snapshot(&f.dirs.legacy), l_before, "L was touched");
    }

    // (f) --------------------------------------------------------------------

    #[test]
    fn unset_or_relative_xdg_falls_back_to_home_for_both_directories() {
        let home = Some(OsString::from("/home/u"));
        let expected = DataDirs {
            canonical: PathBuf::from("/home/u/.local/share/pliwee"),
            legacy: PathBuf::from("/home/u/.local/share/omnibridge"),
        };
        assert_eq!(DataDirs::resolve(None, home.clone()), expected);
        assert_eq!(
            DataDirs::resolve(Some(OsString::from("relative/share")), home.clone()),
            expected
        );
        assert_eq!(
            DataDirs::resolve(Some(OsString::from("/xdg")), home.clone()),
            DataDirs {
                canonical: PathBuf::from("/xdg/pliwee"),
                legacy: PathBuf::from("/xdg/omnibridge"),
            }
        );

        let cfg = ConfigFiles {
            canonical: PathBuf::from("/home/u/.config/pliwee/gui.json"),
            legacy: PathBuf::from("/home/u/.config/omnibridge/gui.json"),
        };
        assert_eq!(ConfigFiles::resolve(None, home.clone(), "gui.json"), cfg);
        assert_eq!(
            ConfigFiles::resolve(Some(OsString::from("cfg")), home, "gui.json"),
            cfg
        );
    }

    #[test]
    fn the_migration_record_round_trips() {
        let r = MigrationRecord {
            source: PathBuf::from("/home/u/.local/share/omnibridge"),
            migrated_at_unix: 1_790_000_000,
            identity_sha256: "ab".repeat(32),
            state_sha256: "cd".repeat(32),
        };
        assert_eq!(MigrationRecord::parse(&r.render()), Some(r));
        assert_eq!(MigrationRecord::parse("source=/x\n"), None);
    }

    // gui.json ---------------------------------------------------------------

    fn config_fixture() -> (tempfile::TempDir, ConfigFiles) {
        let root = tempfile::tempdir().expect("tempdir");
        let files = ConfigFiles {
            canonical: root.path().join("pliwee/gui.json"),
            legacy: root.path().join("omnibridge/gui.json"),
        };
        (root, files)
    }

    #[test]
    fn a_legacy_gui_config_is_copied_once_and_left_in_place() {
        let (_root, files) = config_fixture();
        fs::create_dir_all(files.legacy.parent().expect("parent")).expect("mkdir");
        let body = b"{\n  \"schema\": 1,\n  \"selected_peer\": \"ab12\"\n}\n";
        fs::write(&files.legacy, body).expect("write");

        assert_eq!(
            migrate_config_file(&files).expect("migrate"),
            ConfigOrigin::Migrated {
                source: files.legacy.clone()
            }
        );
        assert_eq!(fs::read(&files.canonical).expect("read"), body);
        assert_eq!(fs::read(&files.legacy).expect("read"), body);
        assert_eq!(
            fs::metadata(&files.canonical).expect("stat").mode() & 0o777,
            FILE_MODE
        );

        // Second start: canonical wins, even over a changed legacy file.
        fs::write(&files.legacy, b"{}").expect("write");
        assert_eq!(
            migrate_config_file(&files).expect("again"),
            ConfigOrigin::Existing
        );
        assert_eq!(fs::read(&files.canonical).expect("read"), body);
    }

    #[test]
    fn an_unreadable_legacy_gui_config_is_an_error_and_creates_nothing() {
        let (_root, files) = config_fixture();
        let legacy_dir = files.legacy.parent().expect("parent").to_path_buf();
        fs::create_dir_all(&legacy_dir).expect("mkdir");
        fs::write(&files.legacy, b"{}").expect("write");
        fs::set_permissions(&files.legacy, fs::Permissions::from_mode(0o000)).expect("chmod");

        let result = migrate_config_file(&files);
        fs::set_permissions(&files.legacy, fs::Permissions::from_mode(0o600)).expect("chmod");

        let err = result.expect_err("must refuse");
        assert_eq!(err.path, files.legacy);
        assert!(!files.canonical.exists());
    }

    #[test]
    fn no_legacy_gui_config_writes_nothing() {
        let (_root, files) = config_fixture();
        assert_eq!(
            migrate_config_file(&files).expect("none"),
            ConfigOrigin::NoLegacyState
        );
        assert!(!files.canonical.parent().expect("parent").exists());
    }
}
