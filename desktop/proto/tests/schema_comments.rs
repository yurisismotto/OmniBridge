//! The schema's comments state the canonical constructions (G8 defect D4).
//!
//! The `.proto` files are the normative description of the wire, and their
//! comments spell out the domain separators the code computes. Wave 5 moved
//! the code to the `pliwee/…` domains and left the comments on `omnibridge/…`,
//! so the schema described a construction only a legacy peer uses, and for
//! notifications one that nothing computes at all. These tests read the text,
//! because the comments are what they check.
//!
//! The legacy OmniBridge 1.0.0 values may still be named, since the legacy
//! profile is real (ADR-0020 D4), but only where the comment says so.

use std::path::PathBuf;

fn schema(file: &str) -> String {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../protocol/proto/pliwee/v1")
        .join(file);
    std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

/// Each canonical construction appears in the schema that defines it.
#[test]
fn the_schema_states_the_canonical_domains() {
    for (file, domain) in [
        ("core.proto", "\"pliwee/pairing-proof/v1\""),
        ("core.proto", "\"pliwee/pairing-confirm/v1\""),
        ("capabilities/files_v1.proto", "\"pliwee-data/1\""),
        (
            "capabilities/files_v1.proto",
            "\"pliwee/files.v1/data-stream/v1\"",
        ),
        (
            "capabilities/notifications_v1.proto",
            "\"pliwee/notifications.v1/id/v1\"",
        ),
        (
            "capabilities/notifications_v1.proto",
            "\"pliwee/notifications.v1/group/v1\"",
        ),
    ] {
        assert!(
            schema(file).contains(domain),
            "{file} does not state the canonical {domain}"
        );
    }
}

/// A legacy value is only ever named as legacy: the line that names it, or
/// the one before it, says "legacy".
#[test]
fn a_legacy_value_is_named_only_as_legacy() {
    let mut named = 0;
    for file in [
        "envelope.proto",
        "core.proto",
        "capabilities/battery_v1.proto",
        "capabilities/files_v1.proto",
        "capabilities/clipboard_v1.proto",
        "capabilities/notifications_v1.proto",
    ] {
        let text = schema(file);
        let lines: Vec<&str> = text.lines().collect();
        for (n, line) in lines.iter().enumerate() {
            let lower = line.to_ascii_lowercase();
            let values = ["\"omnibridge", "`omnibridge"];
            if !values.iter().any(|v| lower.contains(v)) {
                continue;
            }
            named += 1;
            let context = format!("{} {}", n.checked_sub(1).map_or("", |p| lines[p]), line);
            assert!(
                context.to_ascii_lowercase().contains("legacy"),
                "{file}:{}: names an OmniBridge value without calling it legacy: {line}",
                n + 1
            );
        }
    }
    // The legacy profile exists, and the schema says what it is. If this
    // count ever drops to zero, the comments stopped mentioning it and this
    // test stopped measuring anything.
    assert!(
        named > 0,
        "no legacy value is named; the check above ran on nothing"
    );
}
