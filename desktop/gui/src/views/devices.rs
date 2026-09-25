//! Every device this daemon knows: who is trusted, with what, and how to stop.
//!
//! This page used to be two. **Devices** listed every known device, revoked
//! included, read-only; **Trusted peers** held the trust store's controls.
//! Pliwee Wave 2 folded them into one (ADR-0020, P4). The card carries what
//! the old Devices page did; everything the old Trusted peers page did sits
//! behind a disclosure on the same card, so nothing was lost and nothing is
//! more than one keypress away.
//!
//! The daemon is still the authority. Every control here sends exactly the
//! request it sent from Trusted peers, and each one that did so behind a
//! confirmation dialog still does. [`card_controls`] and [`page_controls`] are
//! the list of those controls, and rendering walks that list. That way a
//! control cannot go missing from the screen without also going missing from
//! the list the parity test reads.

use adw::prelude::*;
use pliwee_control::{DeviceReport, Request, Response};

use super::Pages;
use crate::panel::model::{BATTERY, CLIPBOARD, FILES, NOTIFICATIONS};
use crate::widgets::{self, Status, SPACING_SM};
use crate::{client, DaemonState};

/// The capabilities a device can be granted here, and how to describe each.
///
/// `files.v1` writes files to this machine and `clipboard.v1` moves text
/// between machines, so neither is ever granted automatically. That is
/// ADR-0008's rule, and this page is where a person applies it.
const CAPABILITIES: [(&str, &str, &str, &str); 3] = [
    (
        CLIPBOARD,
        "Clipboard",
        "Send and receive clipboard text",
        "edit-paste-symbolic",
    ),
    (FILES, "Files", "Offer and receive files", "folder-symbolic"),
    (
        BATTERY,
        "Battery",
        "Share battery level",
        "battery-symbolic",
    ),
];

/// Something a person can do from this page.
///
/// One variant per kind of button or switch the Trusted peers page had. The
/// fields are what the resulting [`Request`] is keyed by, and nothing else.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum Control {
    /// A capability switch. `granted` is its current position.
    Grant {
        device_id: String,
        capability: &'static str,
        granted: bool,
    },
    /// "Revoke this device".
    Revoke { device_id: String, name: String },
    /// "Remove from list", for one revoked device. Keyed by the
    /// *fingerprint*, never the device id or the name. Two devices can both
    /// be called SM-X620, and only one of them holds this key.
    RemoveFromList { fingerprint: String, name: String },
    /// "Remove all revoked devices". The fingerprints are the ones whose
    /// GUI peer choice is cleared once the daemon agrees.
    RemoveAllRevoked { fingerprints: Vec<String> },
}

impl Control {
    /// Whether a confirmation dialog comes between the press and the request.
    ///
    /// A grant switch has never asked. Everything that takes something away
    /// asks first.
    pub(crate) fn confirmed(&self) -> bool {
        !matches!(self, Control::Grant { .. })
    }

    /// The one request the daemon receives. `wanted` is the position a grant
    /// switch was moved to; the other controls ignore it.
    pub(crate) fn request(&self, wanted: bool) -> Request {
        match self {
            Control::Grant {
                device_id,
                capability,
                ..
            } => Request::Grant {
                device: device_id.clone(),
                capability: (*capability).to_string(),
                granted: wanted,
            },
            Control::Revoke { device_id, .. } => Request::Unpair {
                device: device_id.clone(),
            },
            Control::RemoveFromList { fingerprint, .. } => Request::HideRevokedDevice {
                fingerprint: fingerprint.clone(),
            },
            Control::RemoveAllRevoked { .. } => Request::HideAllRevokedDevices,
        }
    }
}

/// The controls on one device's card, in the order they are drawn.
///
/// A trusted device gets the three grant switches and "Revoke". A revoked one
/// gets "Remove from list" and nothing that could re-grant it: revocation is
/// undone by pairing again, not from here.
pub(crate) fn card_controls(device: &DeviceReport) -> Vec<Control> {
    if device.revoked {
        return vec![Control::RemoveFromList {
            fingerprint: device.fingerprint.clone(),
            name: device.device_name.clone(),
        }];
    }
    let mut controls: Vec<Control> = CAPABILITIES
        .iter()
        .map(|(id, ..)| Control::Grant {
            device_id: device.device_id.clone(),
            capability: id,
            granted: device.granted_capabilities.iter().any(|c| c == id),
        })
        .collect();
    controls.push(Control::Revoke {
        device_id: device.device_id.clone(),
        name: device.device_name.clone(),
    });
    controls
}

/// The controls that act on the list rather than on one device.
///
/// "Remove all revoked devices" is offered only when there is more than one
/// visible revoked row, and its count is the count of those rows, which is
/// the exact set it touches. With one, that card's own button does the same
/// job. With none, the button is not drawn at all rather than drawn grey,
/// because there is nothing on the page it could be read as referring to.
pub(crate) fn page_controls(devices: &[DeviceReport]) -> Vec<Control> {
    let fingerprints: Vec<String> = devices
        .iter()
        .filter(|d| d.revoked)
        .map(|d| d.fingerprint.clone())
        .collect();
    if fingerprints.len() > 1 {
        vec![Control::RemoveAllRevoked { fingerprints }]
    } else {
        Vec::new()
    }
}

/// The trust state, in words: the card's always-visible answer to "can this
/// device connect?".
pub(crate) fn trust_label(device: &DeviceReport) -> &'static str {
    if device.revoked {
        "Revoked"
    } else {
        "Trusted"
    }
}

/// What this device has been granted, in the product's words.
///
/// Includes capabilities this page does not switch, such as notifications,
/// which is granted from the Notifications page. A summary that left them out
/// would under-report what the device can do.
pub(crate) fn capability_summary(device: &DeviceReport) -> String {
    if device.granted_capabilities.is_empty() {
        return "No capabilities granted".into();
    }
    let names: Vec<&str> = device
        .granted_capabilities
        .iter()
        .map(|id| match id.as_str() {
            CLIPBOARD => "Clipboard",
            FILES => "Files",
            BATTERY => "Battery",
            NOTIFICATIONS => "Notifications",
            other => other,
        })
        .collect();
    format!("Granted: {}", names.join(", "))
}

pub fn render(container: &gtk::Box, state: &DaemonState, pages: &Pages) {
    widgets::clear(container);
    container.append(&widgets::title("Devices"));

    let devices = state
        .devices
        .as_deref()
        .or(state.status.as_ref().map(|s| s.devices.as_slice()))
        .unwrap_or(&[]);

    if devices.is_empty() {
        container.append(&widgets::empty_state(
            "No devices yet",
            "Pair a device from the dashboard to see it here. It can do nothing \
             until you grant it something.",
        ));
        return;
    }

    for control in page_controls(devices) {
        if let Control::RemoveAllRevoked { fingerprints } = &control {
            let card = widgets::card();
            card.append(&widgets::section_label("Revoked devices"));
            card.append(&widgets::caption(&format!(
                "{} revoked device(s) are still listed here. Removing them from the \
                 list does not un-revoke them.",
                fingerprints.len()
            )));
            let bulk = widgets::destructive_button("Remove all revoked devices");
            bulk.set_halign(gtk::Align::Start);
            bulk.update_property(&[gtk::accessible::Property::Description(&format!(
                "Removes {} revoked device(s) from the list. They stay revoked. \
                 Devices you still trust are not affected.",
                fingerprints.len()
            ))]);
            let pages = pages.clone();
            bulk.connect_clicked(move |button| {
                confirm(button, control.clone(), pages.clone());
            });
            card.append(&bulk);
            container.append(&card);
        }
    }

    for device in devices {
        container.append(&device_card(device, pages));
    }
}

/// One device: the summary always, the controls on request.
fn device_card(device: &DeviceReport, pages: &Pages) -> gtk::Box {
    let card = widgets::card();
    let row = widgets::row(SPACING_SM);
    row.append(&widgets::icon_tile(
        if device.platform.to_ascii_lowercase().contains("android") {
            "phone-symbolic"
        } else {
            "computer-symbolic"
        },
        if device.revoked {
            "ob-tile-neutral"
        } else {
            "ob-tile-blue"
        },
    ));
    let text = widgets::column(2);
    text.append(&widgets::subtitle(&device.device_name));
    let fp = widgets::caption(&device.fingerprint_short);
    fp.add_css_class("ob-mono");
    text.append(&fp);
    text.set_hexpand(true);
    row.append(&text);
    row.append(&widgets::status_badge(Status::from_device_state(
        device.state,
    )));
    card.append(&row);

    if device.revoked {
        // The badge is a word already (see `widgets::status_badge`), so the
        // state is never shown by colour alone. This adds the device and its
        // state as one description, so they can be announced together rather
        // than as two separate objects a reader walks past in turn.
        //
        // The role has to be set for the description to be exposed at all: a
        // plain `gtk::Box` is `generic`, which AT-SPI does not surface. On
        // the old Trusted peers page the property was measured being dropped
        // before this line existed.
        card.set_accessible_role(gtk::AccessibleRole::Group);
        card.update_property(&[gtk::accessible::Property::Description(&format!(
            "{}, revoked. This device can no longer connect.",
            device.device_name
        ))]);
    }

    // Paired is durable; connected is momentary. Reporting them together is
    // what stops a dead session from reading as a live one.
    let mut facts = vec![
        trust_label(device).to_string(),
        format!("Platform: {}", device.platform),
    ];
    if let Some(silent) = device.silent_secs {
        facts.push(format!("Silent for {silent}s"));
    }
    if let Some(seen) = device.last_seen_secs_ago {
        facts.push(format!("Last session ended {seen}s ago"));
    }
    facts.push(capability_summary(device));
    card.append(&widgets::caption(&facts.join(" · ")));

    card.append(&details(device, pages));
    card
}

/// The disclosure: everything the Trusted peers page showed for this device.
///
/// A `gtk::Expander` rather than a custom toggle, because its title is
/// focusable and opens with Enter or Space, and it exposes its state to
/// AT-SPI. Whether it is open is remembered per *fingerprint* across
/// redraws. The page is rebuilt whenever the daemon's status changes, and
/// without that memory a disclosure would fold itself shut under the person
/// using it.
fn details(device: &DeviceReport, pages: &Pages) -> gtk::Expander {
    let body = widgets::column(SPACING_SM);
    body.set_margin_top(SPACING_SM);

    // Never abbreviated for balance: this is the string compared against the
    // other device's screen, and it is the whole reason pairing is safe.
    body.append(&widgets::section_label("Device fingerprint"));
    body.append(&widgets::fingerprint(&device.fingerprint));
    body.append(&widgets::caption(&format!(
        "Device id {}",
        device.device_id
    )));

    body.append(&widgets::section_label("Connection"));
    body.append(&widgets::caption(&format!(
        "{} · {}",
        if device.paired {
            "Paired"
        } else {
            "Not paired"
        },
        if device.connected {
            "Connected now"
        } else {
            "Not connected"
        },
    )));

    let controls = card_controls(device);
    if controls.iter().any(|c| matches!(c, Control::Grant { .. })) {
        body.append(&widgets::separator());
        body.append(&widgets::section_label("Capabilities"));
    }
    for control in controls {
        match &control {
            Control::Grant { .. } => body.append(&grant_row(control, &device.device_name, pages)),
            Control::Revoke { name, .. } => {
                body.append(&widgets::separator());
                let revoke = widgets::destructive_button("Revoke this device");
                revoke.set_halign(gtk::Align::Start);
                revoke.update_property(&[gtk::accessible::Property::Description(&format!(
                    "Revokes {name}. It will no longer be able to connect. Asks for \
                     confirmation first."
                ))]);
                let pages = pages.clone();
                revoke.connect_clicked(move |button| {
                    confirm(button, control.clone(), pages.clone());
                });
                body.append(&revoke);
            }
            Control::RemoveFromList { name, .. } => {
                body.append(&widgets::caption(
                    "Revoked. This device cannot connect until it pairs again.",
                ));
                body.append(&widgets::separator());
                // The destructive action carries a text label, not an icon:
                // the difference between taking a row off a list and taking
                // away a revocation is not something a glyph can carry.
                let remove = widgets::destructive_button("Remove from list");
                remove.set_halign(gtk::Align::Start);
                // Read aloud with the device it acts on and what it leaves
                // behind, because "Remove from list" on its own is the same
                // string on every card.
                //
                // `Description`, not `Label`: GTK derives a button's
                // accessible *name* from its own label, and an explicit
                // `Label` property on a `Button::with_label` is silently
                // ignored. That was measured through AT-SPI, where the longer
                // string never appeared. A description is additive and is
                // read after the name. The name has to keep matching the
                // visible text or voice control can no longer say it.
                remove.update_property(&[gtk::accessible::Property::Description(&format!(
                    "Removes {name} from the list. It stays revoked and cannot reconnect \
                     unless you pair it again."
                ))]);
                let pages = pages.clone();
                remove.connect_clicked(move |button| {
                    confirm(button, control.clone(), pages.clone());
                });
                body.append(&remove);
            }
            Control::RemoveAllRevoked { .. } => {}
        }
    }

    let expander = gtk::Expander::builder()
        .label(if device.revoked {
            "Details"
        } else {
            "Details and controls"
        })
        .child(&body)
        .expanded(pages.is_expanded(&device.fingerprint))
        .build();
    expander.update_property(&[gtk::accessible::Property::Description(&format!(
        "{}: full fingerprint, device id and {}",
        device.device_name,
        if device.revoked {
            "removal from the list"
        } else {
            "capability switches and revocation"
        }
    ))]);
    let fingerprint = device.fingerprint.clone();
    let pages = pages.clone();
    expander.connect_expanded_notify(move |e| {
        pages.set_expanded(&fingerprint, e.is_expanded());
    });
    expander
}

fn grant_row(control: Control, device_name: &str, pages: &Pages) -> gtk::Box {
    let Control::Grant {
        capability,
        granted,
        ..
    } = control
    else {
        unreachable!("grant_row is only called for a grant switch");
    };
    let (_, title, description, icon) = CAPABILITIES
        .iter()
        .find(|(id, ..)| *id == capability)
        .copied()
        .expect("every grant control names a capability in CAPABILITIES");

    let row = widgets::row(SPACING_SM);
    let tile = widgets::icon_tile(
        icon,
        if granted {
            "ob-tile-cyan"
        } else {
            "ob-tile-neutral"
        },
    );
    tile.set_size_request(28, 28);
    row.append(&tile);

    let text = widgets::column(0);
    text.append(&widgets::body(title));
    text.append(&widgets::caption(description));
    text.set_hexpand(true);
    row.append(&text);

    let sw = gtk::Switch::new();
    sw.set_active(granted);
    sw.set_valign(gtk::Align::Center);
    // Named after the device as well as the capability: with several cards on
    // one page, "Clipboard for this device" was the same string on each.
    sw.update_property(&[gtk::accessible::Property::Label(&format!(
        "{title} for {device_name}"
    ))]);
    let pages = pages.clone();
    sw.connect_state_set(move |_, wanted| {
        let pages = pages.clone();
        client::send(control.request(wanted), move |reply| {
            if let Ok(Response::Error { message }) = reply {
                eprintln!("pliwee-gui: the daemon refused the grant change: {message}");
            }
            pages.refresh_now();
        });
        gtk::glib::Propagation::Proceed
    });
    row.append(&sw);
    row
}

/// Asks before a destructive control sends anything. Every button on this
/// page that takes something away goes through here.
fn confirm(button: &gtk::Button, control: Control, pages: Pages) {
    debug_assert!(
        control.confirmed(),
        "{control:?} is not a confirmed control"
    );
    let dialog = match &control {
        Control::Revoke { .. } => revoke_dialog(control, pages),
        Control::RemoveFromList { .. } => remove_dialog(control, pages),
        Control::RemoveAllRevoked { .. } => remove_all_dialog(control, pages),
        Control::Grant { .. } => unreachable!("a grant switch is not confirmed"),
    };
    if let Some(window) = button.root().and_downcast::<gtk::Window>() {
        dialog.present(Some(&window));
    }
}

/// Cancel is both the default and what Escape does, so a mistimed keypress
/// gives the safe answer.
fn confirmation(title: &str, body: &str, response: &str, response_label: &str) -> adw::AlertDialog {
    let dialog = adw::AlertDialog::new(Some(title), Some(body));
    dialog.add_responses(&[("cancel", "Cancel"), (response, response_label)]);
    dialog.set_response_appearance(response, adw::ResponseAppearance::Destructive);
    dialog.set_default_response(Some("cancel"));
    dialog.set_close_response("cancel");
    dialog
}

/// Revoking is not a toggle. It is confirmed, and the full fingerprint is on
/// screen next to the button that asks.
fn revoke_dialog(control: Control, pages: Pages) -> adw::AlertDialog {
    let Control::Revoke { name, .. } = &control else {
        unreachable!("revoke_dialog is only built for Revoke");
    };
    let dialog = confirmation(
        &format!("Revoke {name}?"),
        "This device will no longer be able to connect. Pairing it again means \
         scanning a new code and checking the fingerprint on both screens.",
        "revoke",
        "Revoke",
    );
    dialog.connect_response(None, move |_, response| {
        if response != "revoke" {
            return;
        }
        let pages = pages.clone();
        client::send(control.request(false), move |reply| {
            if let Ok(Response::Error { message }) = reply {
                eprintln!("pliwee-gui: could not revoke: {message}");
            }
            pages.refresh_now();
        });
    });
    dialog
}

/// "Remove from list" for one revoked device.
///
/// The confirmation says what actually happens, which is that the device
/// stays revoked. It does not describe the mechanism. Nothing here mentions
/// deleting a key or erasing trust, because the button does neither.
fn remove_dialog(control: Control, pages: Pages) -> adw::AlertDialog {
    let Control::RemoveFromList { fingerprint, name } = &control else {
        unreachable!("remove_dialog is only built for RemoveFromList");
    };
    let fingerprint = fingerprint.clone();
    let dialog = confirmation(
        &format!("Remove {name} from the list?"),
        "The device will stay revoked and cannot reconnect unless you pair it again.",
        "remove",
        "Remove",
    );
    dialog.connect_response(None, move |_, response| {
        if response != "remove" {
            return;
        }
        let pages = pages.clone();
        let fingerprint = fingerprint.clone();
        client::send(control.request(false), move |reply| {
            if let Ok(Response::Error { message }) = reply {
                eprintln!("pliwee-gui: could not remove the device from the list: {message}");
                pages.refresh_now();
                return;
            }
            // Only after the daemon agreed, and only for this fingerprint.
            // Nothing is chosen in its place.
            pages.forget_peer_choice(&fingerprint);
            pages.refresh_now();
        });
    });
    dialog
}

/// "Remove all revoked devices".
///
/// The count is in the title and on the confirming button, because "all" is
/// the word a person is most likely to read as meaning more than it does.
fn remove_all_dialog(control: Control, pages: Pages) -> adw::AlertDialog {
    let Control::RemoveAllRevoked { fingerprints } = &control else {
        unreachable!("remove_all_dialog is only built for RemoveAllRevoked");
    };
    let fingerprints = fingerprints.clone();
    let count = fingerprints.len();
    let dialog = confirmation(
        &format!("Remove {count} revoked devices from the list?"),
        "They will remain revoked and cannot reconnect unless paired again. \
         Devices you still trust are not affected.",
        "remove",
        &format!("Remove {count}"),
    );
    dialog.connect_response(None, move |_, response| {
        if response != "remove" {
            return;
        }
        let pages = pages.clone();
        let fingerprints = fingerprints.clone();
        client::send(control.request(false), move |reply| {
            if let Ok(Response::Error { message }) = reply {
                eprintln!("pliwee-gui: could not remove the revoked devices: {message}");
                pages.refresh_now();
                return;
            }
            // The choice is cleared only if it named one of the removed
            // fingerprints. A choice pointing at a device that was never
            // revoked is untouched.
            for fingerprint in &fingerprints {
                pages.forget_peer_choice(fingerprint);
            }
            pages.refresh_now();
        });
    });
    dialog
}

#[cfg(test)]
pub(in crate::views) mod tests {
    use super::*;
    use crate::DaemonState;
    use pliwee_control::DeviceState;
    use std::cell::RefCell;
    use std::rc::Rc;

    fn trusted(name: &str, fingerprint: &str, granted: &[&str]) -> DeviceReport {
        DeviceReport {
            device_id: format!("id-{fingerprint}"),
            device_name: name.into(),
            platform: "android".into(),
            fingerprint: fingerprint.into(),
            fingerprint_short: format!("SHORT {fingerprint}"),
            paired_at_unix: 0,
            granted_capabilities: granted.iter().map(|c| c.to_string()).collect(),
            revoked: false,
            paired: true,
            connected: true,
            state: DeviceState::Connected,
            silent_secs: Some(1),
            last_seen_secs_ago: None,
            battery: None,
        }
    }

    fn revoked(name: &str, fingerprint: &str) -> DeviceReport {
        DeviceReport {
            revoked: true,
            paired: false,
            connected: false,
            state: DeviceState::Revoked,
            silent_secs: None,
            granted_capabilities: Vec::new(),
            ..trusted(name, fingerprint, &[])
        }
    }

    // ---- G2: the model -----------------------------------------------------

    /// Every control the Trusted peers page had exists on Devices: a grant
    /// switch for each of clipboard, files and battery, and "Revoke" for a
    /// trusted device; "Remove from list" for a revoked one; and "Remove all
    /// revoked devices" for the list.
    #[test]
    fn every_trusted_peers_control_exists_on_devices() {
        let phone = trusted("Phone", "aa11", &[CLIPBOARD]);
        let old_a = revoked("Old A", "bb22");
        let old_b = revoked("Old B", "cc33");

        assert_eq!(
            card_controls(&phone),
            vec![
                Control::Grant {
                    device_id: "id-aa11".into(),
                    capability: CLIPBOARD,
                    granted: true,
                },
                Control::Grant {
                    device_id: "id-aa11".into(),
                    capability: FILES,
                    granted: false,
                },
                Control::Grant {
                    device_id: "id-aa11".into(),
                    capability: BATTERY,
                    granted: false,
                },
                Control::Revoke {
                    device_id: "id-aa11".into(),
                    name: "Phone".into(),
                },
            ]
        );
        assert_eq!(
            card_controls(&old_a),
            vec![Control::RemoveFromList {
                fingerprint: "bb22".into(),
                name: "Old A".into(),
            }]
        );
        assert_eq!(
            page_controls(&[phone, old_a, old_b]),
            vec![Control::RemoveAllRevoked {
                fingerprints: vec!["bb22".into(), "cc33".into()],
            }]
        );
    }

    /// Nothing is granted by drawing the page: a switch reflects the trust
    /// store and nothing more, and a new device starts with every switch off.
    #[test]
    fn no_capability_is_granted_by_default() {
        let fresh = trusted("New", "dd44", &[]);
        for control in card_controls(&fresh) {
            if let Control::Grant { granted, .. } = control {
                assert!(!granted, "{control:?} must start off");
            }
        }
    }

    /// A revoked device is not offered a switch or a revoke: its only control
    /// is taking it off the list, which leaves it revoked.
    #[test]
    fn a_revoked_device_cannot_be_granted_from_here() {
        let old = revoked("Old", "ee55");
        assert!(card_controls(&old)
            .iter()
            .all(|c| matches!(c, Control::RemoveFromList { .. })));
    }

    /// Everything that takes something away is confirmed, as it was on
    /// Trusted peers. A grant switch never asked and still does not.
    #[test]
    fn every_destructive_control_is_confirmed() {
        let phone = trusted("Phone", "aa11", &[]);
        let all: Vec<Control> = card_controls(&phone)
            .into_iter()
            .chain(card_controls(&revoked("A", "bb22")))
            .chain(page_controls(&[revoked("A", "bb22"), revoked("B", "cc33")]))
            .collect();
        for control in &all {
            let destructive = !matches!(control, Control::Grant { .. });
            assert_eq!(control.confirmed(), destructive, "{control:?}");
        }
        assert_eq!(all.iter().filter(|c| c.confirmed()).count(), 3);
    }

    /// The same requests Trusted peers sent, keyed the same way. `Request`
    /// has no `PartialEq`, so each is matched by shape.
    #[test]
    fn each_control_sends_the_request_trusted_peers_sent() {
        let grant = Control::Grant {
            device_id: "id-aa11".into(),
            capability: FILES,
            granted: false,
        };
        assert!(matches!(
            grant.request(true),
            Request::Grant { device, capability, granted: true }
                if device == "id-aa11" && capability == FILES
        ));
        assert!(matches!(
            grant.request(false),
            Request::Grant { granted: false, .. }
        ));

        let revoke = Control::Revoke {
            device_id: "id-aa11".into(),
            name: "Phone".into(),
        };
        assert!(matches!(
            revoke.request(false),
            Request::Unpair { device } if device == "id-aa11"
        ));

        // By fingerprint, never by device id or name.
        let remove = Control::RemoveFromList {
            fingerprint: "bb22".into(),
            name: "Old".into(),
        };
        assert!(matches!(
            remove.request(false),
            Request::HideRevokedDevice { fingerprint } if fingerprint == "bb22"
        ));

        let all = Control::RemoveAllRevoked {
            fingerprints: vec!["bb22".into(), "cc33".into()],
        };
        assert!(matches!(all.request(false), Request::HideAllRevokedDevices));
    }

    /// The bulk action counts only visible revoked rows, and is not offered
    /// for one or none.
    #[test]
    fn remove_all_is_offered_only_for_more_than_one_revoked_device() {
        assert!(page_controls(&[]).is_empty());
        assert!(page_controls(&[trusted("P", "aa11", &[])]).is_empty());
        assert!(page_controls(&[trusted("P", "aa11", &[]), revoked("A", "bb22")]).is_empty());
    }

    #[test]
    fn the_card_states_trust_and_what_is_granted() {
        let phone = trusted("Phone", "aa11", &[CLIPBOARD, NOTIFICATIONS]);
        assert_eq!(trust_label(&phone), "Trusted");
        assert_eq!(
            capability_summary(&phone),
            "Granted: Clipboard, Notifications"
        );
        let old = revoked("Old", "bb22");
        assert_eq!(trust_label(&old), "Revoked");
        assert_eq!(capability_summary(&old), "No capabilities granted");
    }

    // ---- G2: the widget tree (needs a display) ----------------------------

    fn descendants(root: &gtk::Widget) -> Vec<gtk::Widget> {
        let mut out = Vec::new();
        let mut child = root.first_child();
        while let Some(w) = child {
            out.push(w.clone());
            out.extend(descendants(&w));
            child = w.next_sibling();
        }
        out
    }

    fn labels(root: &gtk::Widget) -> Vec<String> {
        descendants(root)
            .into_iter()
            .filter_map(|w| w.downcast::<gtk::Label>().ok())
            .map(|l| l.label().to_string())
            .collect()
    }

    fn buttons(root: &gtk::Widget, label: &str) -> Vec<gtk::Button> {
        descendants(root)
            .into_iter()
            .filter_map(|w| w.downcast::<gtk::Button>().ok())
            .filter(|b| b.label().as_deref() == Some(label))
            .collect()
    }

    const FULL: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn page(devices: Vec<DeviceReport>) -> (gtk::Box, Pages) {
        if !gtk::is_initialized() {
            gtk::init().expect("a display is needed: run with --ignored on a desktop session");
        }
        let state = Rc::new(RefCell::new(DaemonState {
            devices: Some(devices),
            ..DaemonState::default()
        }));
        let stack = gtk::Stack::new();
        let pages = Pages::new(&stack, state.clone(), crate::views::test_selection());
        let container = gtk::Box::new(gtk::Orientation::Vertical, 0);
        render(&container, &state.borrow(), &pages);
        (container, pages)
    }

    /// Every widget-tree assertion for this page, in one section. Called from
    /// `views::display_gate`; see there for why it is not a `#[test]`.
    pub(in crate::views) fn the_devices_page_widget_tree() {
        every_control_is_on_the_page_inside_its_expander();
        revoked_devices_stay_visible_and_marked();
        each_confirmation_defaults_to_cancel();
        an_open_disclosure_survives_a_redraw();
    }

    fn every_control_is_on_the_page_inside_its_expander() {
        let (page, _) = page(vec![
            trusted("Phone", FULL, &[CLIPBOARD]),
            revoked("Old A", "bb22"),
            revoked("Old B", "cc33"),
        ]);
        let root: &gtk::Widget = page.upcast_ref();
        let expanders: Vec<gtk::Expander> = descendants(root)
            .into_iter()
            .filter_map(|w| w.downcast::<gtk::Expander>().ok())
            .collect();
        assert_eq!(expanders.len(), 3, "one disclosure per device");
        assert!(
            expanders.iter().all(|e| !e.is_expanded()),
            "details are on demand, so every card starts folded"
        );
        // Folded really means out of the tree: GTK unparents a collapsed
        // expander's child, so keyboard focus cannot land on a hidden control.
        assert!(descendants(root)
            .into_iter()
            .all(|w| !w.is::<gtk::Switch>()));
        assert!(buttons(root, "Revoke this device").is_empty());
        assert!(buttons(root, "Remove from list").is_empty());

        // One keypress each (Enter or Space on the title) is what a person
        // does. Here the property is set directly.
        for e in &expanders {
            e.set_expanded(true);
        }

        let phone = expanders[0].upcast_ref::<gtk::Widget>();
        let switches: Vec<gtk::Switch> = descendants(phone)
            .into_iter()
            .filter_map(|w| w.downcast::<gtk::Switch>().ok())
            .collect();
        assert_eq!(switches.len(), 3, "grant ×3 inside the disclosure");
        assert_eq!(
            switches.iter().map(|s| s.is_active()).collect::<Vec<_>>(),
            vec![true, false, false],
            "the switches show the trust store: clipboard on, files and battery off"
        );
        assert!(
            labels(phone).contains(&widgets::group_fingerprint(FULL)),
            "the full fingerprint, never shortened, is inside the disclosure: {:?}",
            labels(phone)
        );
        assert!(labels(phone)
            .iter()
            .any(|l| l == &format!("Device id id-{FULL}")));
        assert_eq!(buttons(phone, "Revoke this device").len(), 1);

        assert_eq!(buttons(root, "Revoke this device").len(), 1);
        assert_eq!(buttons(root, "Remove from list").len(), 2);
        for b in buttons(root, "Remove from list") {
            assert!(
                b.ancestor(gtk::Expander::static_type()).is_some(),
                "Remove from list lives in its card's disclosure"
            );
        }
        let bulk = buttons(root, "Remove all revoked devices");
        assert_eq!(bulk.len(), 1, "page-level bulk removal");
        assert!(bulk[0].ancestor(gtk::Expander::static_type()).is_none());
    }

    fn revoked_devices_stay_visible_and_marked() {
        let (page, _) = page(vec![revoked("Old A", "bb22")]);
        let text = labels(page.upcast_ref()).join("\n");
        assert!(text.contains("Old A"), "{text}");
        assert!(text.contains("Revoked"), "{text}");
        assert!(
            !text.contains("No devices yet"),
            "a revoked device is still a device: {text}"
        );
    }

    fn each_confirmation_defaults_to_cancel() {
        let (_, pages) = page(Vec::new());
        let dialogs = [
            (
                revoke_dialog(
                    Control::Revoke {
                        device_id: "id".into(),
                        name: "Phone".into(),
                    },
                    pages.clone(),
                ),
                "revoke",
            ),
            (
                remove_dialog(
                    Control::RemoveFromList {
                        fingerprint: "bb22".into(),
                        name: "Old".into(),
                    },
                    pages.clone(),
                ),
                "remove",
            ),
            (
                remove_all_dialog(
                    Control::RemoveAllRevoked {
                        fingerprints: vec!["bb22".into(), "cc33".into()],
                    },
                    pages.clone(),
                ),
                "remove",
            ),
        ];
        for (dialog, act) in dialogs {
            assert!(dialog.has_response("cancel"));
            assert!(dialog.has_response(act));
            assert_eq!(dialog.default_response().as_deref(), Some("cancel"));
            assert_eq!(dialog.close_response().as_str(), "cancel");
            assert_eq!(
                dialog.response_appearance(act),
                adw::ResponseAppearance::Destructive
            );
        }
    }

    fn an_open_disclosure_survives_a_redraw() {
        let (page, pages) = page(vec![trusted("Phone", "aa11", &[])]);
        let expander = descendants(page.upcast_ref())
            .into_iter()
            .find_map(|w| w.downcast::<gtk::Expander>().ok())
            .expect("a disclosure");
        expander.set_expanded(true);
        assert!(pages.is_expanded("aa11"));

        render(&page, &pages.state.borrow(), &pages);
        let again = descendants(page.upcast_ref())
            .into_iter()
            .find_map(|w| w.downcast::<gtk::Expander>().ok())
            .expect("a disclosure after the redraw");
        assert!(again.is_expanded(), "a redraw must not fold it shut");
    }
}
