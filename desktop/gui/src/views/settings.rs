//! This computer's own identity, and what Pliwee is.

use gtk::prelude::*;

use crate::widgets::{self, SPACING_SM};
use crate::DaemonState;

/// Everything this page shows, and nothing else from the status report.
///
/// The report also carries every device's session ages, which differ on each
/// poll. Keyed on the whole report, this page — whose full fingerprint is a
/// selectable, focusable label someone may be reading out — was rebuilt every
/// `REFRESH_SECS`. See [`super::live`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Key {
    device_name: String,
    fingerprint: String,
    device_id: String,
    listen_port: u16,
    listen_families: String,
    protocol_version_min: u32,
    protocol_version_max: u32,
    capabilities: Vec<String>,
    paired_devices: usize,
    connections: usize,
}

impl Key {
    pub(crate) fn of(state: &DaemonState) -> Option<Key> {
        state.status.as_ref().map(|s| Key {
            device_name: s.device_name.clone(),
            fingerprint: s.fingerprint.clone(),
            device_id: s.device_id.clone(),
            listen_port: s.listen_port,
            listen_families: s.listen_families.clone(),
            protocol_version_min: s.protocol_version_min,
            protocol_version_max: s.protocol_version_max,
            capabilities: s.capabilities.clone(),
            paired_devices: s.paired_devices,
            connections: s.connections.len(),
        })
    }
}

pub fn render(container: &gtk::Box, state: &DaemonState) {
    widgets::clear(container);
    container.append(&widgets::title("Settings"));

    let Some(status) = &state.status else {
        container.append(&widgets::body_muted(
            "The Pliwee daemon is not reachable. Start it to see this computer's identity.",
        ));
        return;
    };

    let identity = widgets::card();
    identity.append(&widgets::section_label("This computer"));
    identity.append(&widgets::subtitle(&status.device_name));
    identity.append(&widgets::caption("Device fingerprint"));
    // The full fingerprint, selectable, so it can be compared or read aloud
    // during pairing. Shortening it here would defeat its only purpose.
    identity.append(&widgets::fingerprint(&status.fingerprint));
    identity.append(&widgets::caption(&format!(
        "Device id {}",
        status.device_id
    )));
    container.append(&identity);

    let network = widgets::card();
    network.append(&widgets::section_label("Network"));
    network.append(&widgets::body(&format!(
        "Listening on port {} ({})",
        status.listen_port, status.listen_families
    )));
    network.append(&widgets::caption(&format!(
        "Protocol versions {}–{} · capabilities: {}",
        status.protocol_version_min,
        status.protocol_version_max,
        status.capabilities.join(", ")
    )));
    network.append(&widgets::caption(&format!(
        "{} paired device(s) · {} live session(s)",
        status.paired_devices,
        status.connections.len()
    )));
    container.append(&network);

    container.append(&widgets::security_notice(
        "Private by design",
        "Pliwee has no account, no cloud service and no analytics. Devices talk \
         directly over your local network on a mutually authenticated TLS 1.3 session \
         pinned to the key you approved when pairing.",
        false,
    ));

    // About: the mark, at the one size in the application where it is big
    // enough to be looked at rather than glanced past.
    let about = widgets::column(SPACING_SM);
    about.set_halign(gtk::Align::Center);
    about.set_margin_top(SPACING_SM);
    about.append(&widgets::brand_mark(48));
    let name = widgets::subtitle("Pliwee");
    name.set_halign(gtk::Align::Center);
    about.append(&name);
    let tag = widgets::caption("One flow. Any device.");
    tag.set_halign(gtk::Align::Center);
    about.append(&tag);
    container.append(&about);
}
