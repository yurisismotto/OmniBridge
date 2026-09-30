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

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use super::live::{Binder, Plan};
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

/// The devices this page lists: the `devices` reply when there is one, the
/// list inside `status` until then.
fn devices_of(state: &DaemonState) -> &[DeviceReport] {
    state
        .devices
        .as_deref()
        .or(state.status.as_ref().map(|s| s.devices.as_slice()))
        .unwrap_or(&[])
}

/// What decides which widgets this page has and what each is called.
///
/// Everything a card's *controls* are built from, and nothing that moves on
/// its own. `silent_secs`, `last_seen_secs_ago`, the connection state and the
/// grants are deliberately absent: the daemon computes the ages when it
/// answers, so they differ on every poll, and a page keyed on them was
/// rebuilt every `REFRESH_SECS` under the W2-GNOME Orca gate. They are
/// [`CardValues`] instead, written into the existing widgets in place.
///
/// Grants are values rather than structure so that the switch a person has
/// just moved is still the same object when the daemon's answer arrives.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CardLayout {
    pub fingerprint: String,
    pub fingerprint_short: String,
    pub device_id: String,
    pub name: String,
    pub platform: String,
    /// Decides the whole control set — see [`card_controls`] — and, across
    /// the page, whether "Remove all revoked devices" exists and its count.
    pub revoked: bool,
}

/// The page's key: one entry per card, in order. Empty draws the empty state.
pub(crate) fn layout(devices: &[DeviceReport]) -> Vec<CardLayout> {
    devices
        .iter()
        .map(|d| CardLayout {
            fingerprint: d.fingerprint.clone(),
            fingerprint_short: d.fingerprint_short.clone(),
            device_id: d.device_id.clone(),
            name: d.device_name.clone(),
            platform: d.platform.clone(),
            revoked: d.revoked,
        })
        .collect()
}

/// What on a card changes without its controls changing, as it is drawn.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CardValues {
    pub status: Status,
    /// The always-visible line: trust, platform, ages, what is granted.
    pub facts: String,
    /// "Paired · Connected now", inside the disclosure.
    pub connection: String,
    /// Each switchable capability and whether the trust store grants it.
    pub grants: Vec<(&'static str, bool)>,
}

pub(crate) fn card_values(device: &DeviceReport) -> CardValues {
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
    CardValues {
        status: Status::from_device_state(device.state),
        facts: facts.join(" · "),
        connection: format!(
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
        ),
        grants: CAPABILITIES
            .iter()
            .map(|(id, ..)| (*id, device.granted_capabilities.iter().any(|c| c == id)))
            .collect(),
    }
}

/// The accessible name of a grant switch. Named after the device as well as
/// the capability: with several cards on one page, "Clipboard for this
/// device" was the same string on each.
pub(crate) fn grant_accessible_label(title: &str, device_name: &str) -> String {
    format!("{title} for {device_name}")
}

/// Draws the page, rebuilding it only when [`layout`] changed. See
/// [`super::live`].
pub fn render(container: &gtk::Box, state: &DaemonState, pages: &Pages) -> Plan {
    let devices = devices_of(state);
    pages
        .devices_surface
        .draw(container, layout(devices), state, |binder| {
            build(container, devices, pages, binder)
        })
}

fn build(container: &gtk::Box, devices: &[DeviceReport], pages: &Pages, binder: &mut Binder) {
    widgets::clear(container);
    container.append(&widgets::title("Devices"));

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
            binder.focusable(BULK_KEY, &bulk);
            let pages = pages.clone();
            bulk.connect_clicked(move |button| {
                confirm(button, control.clone(), pages.clone());
            });
            card.append(&bulk);
            container.append(&card);
        }
    }

    for device in devices {
        container.append(&device_card(device, pages, binder));
    }
}

/// The focus name of "Remove all revoked devices".
const BULK_KEY: &str = "bulk";

/// Looks a card's device up again in a later state, by fingerprint.
fn find<'a>(state: &'a DaemonState, fingerprint: &str) -> Option<&'a DeviceReport> {
    devices_of(state)
        .iter()
        .find(|d| d.fingerprint == fingerprint)
}

/// One device: the summary always, the controls on request.
fn device_card(device: &DeviceReport, pages: &Pages, binder: &mut Binder) -> gtk::Box {
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
    let values = card_values(device);
    let badge = Rc::new(RefCell::new((
        values.status,
        widgets::status_badge(values.status),
    )));
    row.append(&badge.borrow().1);
    card.append(&row);

    // The badge is not focusable, so swapping it — only when the state it
    // names actually changed — cannot take focus from anything.
    {
        let fingerprint = device.fingerprint.clone();
        binder.live(move |state| {
            let Some(device) = find(state, &fingerprint) else {
                return;
            };
            let status = card_values(device).status;
            let mut badge = badge.borrow_mut();
            if badge.0 != status {
                let fresh = widgets::status_badge(status);
                row.remove(&badge.1);
                row.append(&fresh);
                *badge = (status, fresh);
            }
        });
    }

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

    let facts = widgets::caption(&values.facts);
    live_label(binder, &facts, &device.fingerprint, |v| v.facts);
    card.append(&facts);

    card.append(&details(device, pages, binder));
    card
}

/// Keeps a label's text equal to one [`CardValues`] field, in place.
fn live_label(
    binder: &mut Binder,
    label: &gtk::Label,
    fingerprint: &str,
    field: fn(CardValues) -> String,
) {
    let (label, fingerprint) = (label.clone(), fingerprint.to_string());
    binder.live(move |state| {
        if let Some(device) = find(state, &fingerprint) {
            let text = field(card_values(device));
            if label.label() != text {
                label.set_label(&text);
            }
        }
    });
}

/// The disclosure: everything the Trusted peers page showed for this device.
///
/// A `gtk::Expander` rather than a custom toggle, because its title is
/// focusable and opens with Enter or Space, and it exposes its state to
/// AT-SPI. Whether it is open is remembered per *fingerprint*, so a rebuild
/// forced by a real change to the list — a device paired, revoked or removed
/// — does not fold it shut under the person using it. A poll that changes
/// only ages or grants does not rebuild it at all.
fn details(device: &DeviceReport, pages: &Pages, binder: &mut Binder) -> gtk::Expander {
    let body = widgets::column(SPACING_SM);
    body.set_margin_top(SPACING_SM);

    // Never abbreviated for balance: this is the string compared against the
    // other device's screen, and it is the whole reason pairing is safe.
    body.append(&widgets::section_label("Device fingerprint"));
    let fingerprint = widgets::fingerprint(&device.fingerprint);
    binder.focusable(format!("{}/fingerprint", device.fingerprint), &fingerprint);
    body.append(&fingerprint);
    body.append(&widgets::caption(&format!(
        "Device id {}",
        device.device_id
    )));

    body.append(&widgets::section_label("Connection"));
    let connection = widgets::caption(&card_values(device).connection);
    live_label(binder, &connection, &device.fingerprint, |v| v.connection);
    body.append(&connection);

    let controls = card_controls(device);
    if controls.iter().any(|c| matches!(c, Control::Grant { .. })) {
        body.append(&widgets::separator());
        body.append(&widgets::section_label("Capabilities"));
    }
    for control in controls {
        match &control {
            Control::Grant { .. } => body.append(&grant_row(control, device, pages, binder)),
            Control::Revoke { name, .. } => {
                body.append(&widgets::separator());
                let revoke = widgets::destructive_button("Revoke this device");
                revoke.set_halign(gtk::Align::Start);
                revoke.update_property(&[gtk::accessible::Property::Description(&format!(
                    "Revokes {name}. It will no longer be able to connect. Asks for \
                     confirmation first."
                ))]);
                binder.focusable(format!("{}/revoke", device.fingerprint), &revoke);
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
                binder.focusable(format!("{}/remove", device.fingerprint), &remove);
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
    binder.focusable(device.fingerprint.clone(), &expander);
    let fingerprint = device.fingerprint.clone();
    let pages = pages.clone();
    expander.connect_expanded_notify(move |e| {
        pages.set_expanded(&fingerprint, e.is_expanded());
    });
    expander
}

/// The tint a grant's icon wears.
fn grant_tile_class(granted: bool) -> &'static str {
    if granted {
        "ob-tile-cyan"
    } else {
        "ob-tile-neutral"
    }
}

fn grant_row(
    control: Control,
    device: &DeviceReport,
    pages: &Pages,
    binder: &mut Binder,
) -> gtk::Box {
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
    let tile = widgets::icon_tile(icon, grant_tile_class(granted));
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
    sw.update_property(&[gtk::accessible::Property::Label(&grant_accessible_label(
        title,
        &device.device_name,
    ))]);
    binder.focusable(format!("{}/grant/{capability}", device.fingerprint), &sw);

    // Set while this switch's own request is with the daemon, so a poll that
    // lands in between does not flick it back to the answer to the previous
    // question.
    let pending = Rc::new(Cell::new(false));
    let handler = {
        let (pages, pending) = (pages.clone(), pending.clone());
        sw.connect_state_set(move |_, wanted| {
            pending.set(true);
            let (pages, pending) = (pages.clone(), pending.clone());
            client::send(control.request(wanted), move |reply| {
                if let Ok(Response::Error { message }) = reply {
                    eprintln!("pliwee-gui: the daemon refused the grant change: {message}");
                }
                pending.set(false);
                // The daemon is the authority. Whatever it answered, the next
                // poll re-reads the grant and the binding below moves this
                // switch to it — including back, after a refusal, when that
                // poll may be identical to the last one.
                pages.resync_devices();
                pages.refresh_now();
            });
            gtk::glib::Propagation::Proceed
        })
    };

    row.append(&sw);
    let fingerprint = device.fingerprint.clone();
    binder.live(move |state| {
        if pending.get() {
            return;
        }
        let Some(device) = find(state, &fingerprint) else {
            return;
        };
        let granted = device.granted_capabilities.iter().any(|c| c == capability);
        if sw.is_active() != granted {
            // Blocked, or moving the switch to the daemon's answer would
            // send that answer straight back to the daemon as a request.
            sw.block_signal(&handler);
            sw.set_active(granted);
            sw.unblock_signal(&handler);
        }
        tile.remove_css_class(grant_tile_class(!granted));
        tile.add_css_class(grant_tile_class(granted));
    });
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

    pub(in crate::views) fn trusted(
        name: &str,
        fingerprint: &str,
        granted: &[&str],
    ) -> DeviceReport {
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

    pub(in crate::views) fn revoked(name: &str, fingerprint: &str) -> DeviceReport {
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

    // ---- W2-GNOME remediation: what a poll may and may not rebuild --------
    //
    // The Orca gate failed because every poll rebuilt this page. These pin the
    // decision that replaced that — which differences are structure and which
    // are values — as pure functions. They do not stand in for the real Orca
    // gate: they prove the page is *not asked* to rebuild, not what a screen
    // reader then does.

    use crate::views::live::{plan, Plan};

    pub(in crate::views) fn status_with(devices: Vec<DeviceReport>) -> DaemonState {
        DaemonState {
            status: Some(pliwee_control::StatusReport {
                device_name: "Desk".into(),
                device_id: "desk".into(),
                fingerprint: "ff".into(),
                fingerprint_short: "FF".into(),
                key_backing: "software".into(),
                listen_port: 1716,
                listen_families: "IPv4+IPv6".into(),
                protocol_version_min: 1,
                protocol_version_max: 1,
                capabilities: Vec::new(),
                paired_devices: devices.len(),
                connections: Vec::new(),
                devices: devices.clone(),
                pairing_active: false,
                migrated_from: None,
                legacy_partial_files: Vec::new(),
            }),
            devices: Some(devices),
            ..DaemonState::default()
        }
    }

    /// The measured state: one real connected tablet, one trusted fake phone,
    /// two revoked fake phones.
    fn gate_devices() -> Vec<DeviceReport> {
        vec![
            trusted("SM-X620", "aa11", &[CLIPBOARD]),
            trusted("Fake Phone", "dd44", &[]),
            revoked("Fake Phone", "bb22"),
            revoked("Fake Phone", "cc33"),
        ]
    }

    fn step(before: &[DeviceReport], after: &[DeviceReport]) -> Plan {
        plan(Some(&layout(before)), &layout(after))
    }

    /// The defect, reproduced as data: two polls a second apart differ only in
    /// the ages the daemon computes when it answers, and that was enough to
    /// make the status slice — which used to key this page — unequal.
    #[test]
    fn an_age_only_poll_changes_the_status_slice_but_not_the_layout() {
        let before = gate_devices();
        let mut after = gate_devices();
        after[0].silent_secs = Some(2);
        after[1].silent_secs = Some(3);
        after[0].battery = Some(pliwee_control::BatteryReport {
            percentage: 80,
            charging_state: "charging".into(),
            age_secs: 5,
            stale: false,
        });
        let mut earlier = before.clone();
        earlier[0].battery = after[0].battery.clone().map(|mut b| {
            b.age_secs = 3;
            b
        });
        after[2].last_seen_secs_ago = Some(40);

        assert_ne!(
            status_with(earlier.clone()).status,
            status_with(after.clone()).status,
            "the old key: this inequality is what rebuilt the page every poll"
        );
        assert_eq!(step(&earlier, &after), Plan::Update);
        // The live information is still there, written in place.
        assert!(card_values(&after[0]).facts.contains("Silent for 2s"));
        assert!(card_values(&after[2])
            .facts
            .contains("Last session ended 40s ago"));
        assert_ne!(card_values(&before[0]), card_values(&after[0]));
    }

    #[test]
    fn a_connection_change_updates_values_without_a_rebuild() {
        let before = gate_devices();
        let mut after = gate_devices();
        after[1].connected = false;
        after[1].state = DeviceState::Disconnected;
        after[1].silent_secs = None;
        after[1].last_seen_secs_ago = Some(0);
        assert_eq!(step(&before, &after), Plan::Update);
        assert_eq!(card_values(&after[1]).status, Status::Available);
        assert_eq!(card_values(&after[1]).connection, "Paired · Not connected");
        assert_eq!(card_values(&before[1]).connection, "Paired · Connected now");

        let mut stale = gate_devices();
        stale[0].state = DeviceState::Stale;
        assert_eq!(step(&before, &stale), Plan::Update);
        assert_eq!(card_values(&stale[0]).status, Status::Stale);
    }

    /// A grant is a value: the switch that asked for it must still exist when
    /// the answer arrives, and must show the answer.
    #[test]
    fn a_grant_change_updates_the_switch_value_without_a_rebuild() {
        let before = gate_devices();
        let mut after = gate_devices();
        after[0].granted_capabilities.push(FILES.into());
        assert_eq!(step(&before, &after), Plan::Update);
        let grants = |d: &DeviceReport| card_values(d).grants;
        assert_eq!(
            grants(&before[0]),
            vec![(CLIPBOARD, true), (FILES, false), (BATTERY, false)]
        );
        assert_eq!(
            grants(&after[0]),
            vec![(CLIPBOARD, true), (FILES, true), (BATTERY, false)]
        );
        assert!(card_values(&after[0])
            .facts
            .contains("Granted: Clipboard, Files"));
    }

    #[test]
    fn trusted_to_revoked_rebuilds_with_the_revoked_controls() {
        let before = gate_devices();
        let mut after = gate_devices();
        after[1] = revoked("Fake Phone", "dd44");
        assert_eq!(step(&before, &after), Plan::Rebuild);
        assert!(card_controls(&after[1])
            .iter()
            .all(|c| matches!(c, Control::RemoveFromList { .. })));
        assert_eq!(
            page_controls(&after),
            vec![Control::RemoveAllRevoked {
                fingerprints: vec!["dd44".into(), "bb22".into(), "cc33".into()],
            }]
        );
    }

    #[test]
    fn pairing_removing_or_renaming_a_device_rebuilds() {
        let before = gate_devices();

        let mut paired = gate_devices();
        paired.push(trusted("New", "ee55", &[]));
        assert_eq!(step(&before, &paired), Plan::Rebuild);

        let mut renamed = gate_devices();
        renamed[0].device_name = "Tablet".into();
        assert_eq!(step(&before, &renamed), Plan::Rebuild);

        // One revoked device removed from the list: the bulk action goes, as
        // there is only one row left for it to refer to.
        let one_removed: Vec<_> = gate_devices()
            .into_iter()
            .filter(|d| d.fingerprint != "bb22")
            .collect();
        assert_eq!(step(&before, &one_removed), Plan::Rebuild);
        assert!(page_controls(&one_removed).is_empty());

        // Bulk removal: every revoked row gone.
        let bulk_removed: Vec<_> = gate_devices().into_iter().filter(|d| !d.revoked).collect();
        assert_eq!(step(&before, &bulk_removed), Plan::Rebuild);
        assert!(page_controls(&bulk_removed).is_empty());

        assert_eq!(step(&before, &[]), Plan::Rebuild, "to the empty state");
    }

    #[test]
    fn the_files_switch_is_named_after_its_device() {
        assert_eq!(
            grant_accessible_label("Files", "SM-X620"),
            "Files for SM-X620"
        );
        let phone = trusted("SM-X620", "aa11", &[]);
        let (_, title, ..) = CAPABILITIES
            .iter()
            .find(|(id, ..)| *id == FILES)
            .copied()
            .expect("files is switchable here");
        assert!(grant_accessible_label(title, &phone.device_name).contains("Files for SM-X620"));
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
        an_age_only_poll_keeps_every_control_and_the_focus();
        a_grant_answer_moves_the_same_switch();
        a_structural_change_puts_focus_back_on_the_same_control();
        revoking_hands_focus_to_the_cards_disclosure();
        the_controls_keep_their_accessible_metadata();
    }

    /// A page inside a window, with the gate's four devices and the
    /// tablet's disclosure open.
    fn windowed(devices: Vec<DeviceReport>) -> (gtk::Window, gtk::Box, Pages) {
        let (page, pages) = page(devices);
        pages.set_expanded("aa11", true);
        pages.devices_surface.forget();
        render(&page, &pages.state.borrow(), &pages);
        let window = gtk::Window::new();
        window.set_child(Some(&page));
        (window, page, pages)
    }

    fn redraw(page: &gtk::Box, pages: &Pages, devices: Vec<DeviceReport>) -> Plan {
        *pages.state.borrow_mut() = DaemonState {
            devices: Some(devices),
            ..DaemonState::default()
        };
        let plan = render(page, &pages.state.borrow(), pages);
        plan
    }

    fn widget(pages: &Pages, key: &str) -> gtk::Widget {
        pages
            .devices_surface
            .widget(key)
            .unwrap_or_else(|| panic!("no control named {key}"))
    }

    fn focus(window: &gtk::Window) -> Option<gtk::Widget> {
        gtk::prelude::RootExt::focus(window)
    }

    fn an_age_only_poll_keeps_every_control_and_the_focus() {
        let (window, page, pages) = windowed(gate_devices());
        let files = widget(&pages, "aa11/grant/files.v1");
        let bulk = widget(&pages, "bulk");
        assert!(files.grab_focus(), "the Files switch takes focus");
        assert_eq!(focus(&window).as_ref(), Some(&files));
        let before = descendants(page.upcast_ref());

        let mut aged = gate_devices();
        aged[0].silent_secs = Some(9);
        aged[3].last_seen_secs_ago = Some(77);
        assert_eq!(redraw(&page, &pages, aged), Plan::Update);

        assert_eq!(
            descendants(page.upcast_ref())
                .iter()
                .filter(|w| !before.contains(w))
                .count(),
            0,
            "an age-only poll created no widget"
        );
        assert_eq!(widget(&pages, "aa11/grant/files.v1"), files);
        assert_eq!(widget(&pages, "bulk"), bulk);
        assert_eq!(focus(&window).as_ref(), Some(&files), "focus stayed put");
        let text = labels(page.upcast_ref()).join("\n");
        assert!(text.contains("Silent for 9s"), "{text}");
        assert!(text.contains("Last session ended 77s ago"), "{text}");
        window.destroy();
    }

    fn a_grant_answer_moves_the_same_switch() {
        let (window, page, pages) = windowed(gate_devices());
        let files = widget(&pages, "aa11/grant/files.v1")
            .downcast::<gtk::Switch>()
            .expect("a switch");
        assert!(!files.is_active());

        let mut granted = gate_devices();
        granted[0].granted_capabilities.push(FILES.into());
        assert_eq!(redraw(&page, &pages, granted), Plan::Update);
        assert_eq!(
            widget(&pages, "aa11/grant/files.v1"),
            files.clone().upcast::<gtk::Widget>()
        );
        assert!(files.is_active(), "the daemon's grant is shown");
        assert!(files.state(), "and the switch's state follows it");

        // Taken away again — a refusal looks the same from here.
        assert_eq!(redraw(&page, &pages, gate_devices()), Plan::Update);
        assert!(
            !files.is_active(),
            "no stale switch after the daemon says no"
        );
        window.destroy();
    }

    fn a_structural_change_puts_focus_back_on_the_same_control() {
        let (window, page, pages) = windowed(gate_devices());
        let files = widget(&pages, "aa11/grant/files.v1");
        assert!(files.grab_focus());

        let mut paired = gate_devices();
        paired.push(trusted("New", "ee55", &[]));
        assert_eq!(redraw(&page, &pages, paired), Plan::Rebuild);

        let again = widget(&pages, "aa11/grant/files.v1");
        assert_ne!(again, files, "a real change does build new widgets");
        assert_eq!(
            focus(&window).as_ref(),
            Some(&again),
            "and focus is on the same logical control, not the first button"
        );
        assert_ne!(focus(&window).as_ref(), Some(&widget(&pages, "bulk")));
        assert!(
            widget(&pages, "aa11")
                .downcast::<gtk::Expander>()
                .expect("an expander")
                .is_expanded(),
            "the open card stayed open through the rebuild"
        );
        window.destroy();
    }

    fn revoking_hands_focus_to_the_cards_disclosure() {
        let (window, page, pages) = windowed(gate_devices());
        assert!(widget(&pages, "aa11/revoke").grab_focus());

        let mut revoked_now = gate_devices();
        revoked_now[0] = revoked("SM-X620", "aa11");
        assert_eq!(redraw(&page, &pages, revoked_now), Plan::Rebuild);
        assert!(pages.devices_surface.widget("aa11/revoke").is_none());
        assert!(pages
            .devices_surface
            .widget("aa11/grant/files.v1")
            .is_none());
        assert!(pages.devices_surface.widget("aa11/remove").is_some());
        assert_eq!(focus(&window).as_ref(), Some(&widget(&pages, "aa11")));
        window.destroy();
    }

    fn the_controls_keep_their_accessible_metadata() {
        use gtk::AccessibleProperty as P;
        let (window, _page, pages) = windowed(gate_devices());
        let files = widget(&pages, "aa11/grant/files.v1");
        // The value itself is `grant_accessible_label`, pinned by
        // `the_files_switch_is_named_after_its_device`; GTK has no public
        // getter for it, so here the property is asserted to be set.
        assert!(gtk::test_accessible_has_property(&files, P::Label));
        assert!(gtk::test_accessible_has_role(
            &files,
            gtk::AccessibleRole::Switch
        ));

        let revoke = widget(&pages, "aa11/revoke")
            .downcast::<gtk::Button>()
            .expect("a button");
        assert_eq!(revoke.label().as_deref(), Some("Revoke this device"));
        assert!(revoke.has_css_class("ob-destructive"));
        assert!(gtk::test_accessible_has_role(
            &revoke,
            gtk::AccessibleRole::Button
        ));
        assert!(gtk::test_accessible_has_property(&revoke, P::Description));

        let bulk = widget(&pages, "bulk")
            .downcast::<gtk::Button>()
            .expect("a button");
        assert_eq!(bulk.label().as_deref(), Some("Remove all revoked devices"));
        assert!(bulk.has_css_class("ob-destructive"));
        assert!(gtk::test_accessible_has_property(&bulk, P::Description));

        for key in ["bb22/remove", "cc33/remove"] {
            let remove = pages.devices_surface.widget(key);
            // Folded disclosures still hold their controls, out of the tree.
            let remove = remove
                .and_then(|w| w.downcast::<gtk::Button>().ok())
                .expect("a Remove from list button");
            assert!(remove.has_css_class("ob-destructive"));
            assert!(gtk::test_accessible_has_property(&remove, P::Description));
        }
        window.destroy();
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

        // And through a real rebuild, which a rename is.
        *pages.state.borrow_mut() = DaemonState {
            devices: Some(vec![trusted("Renamed", "aa11", &[])]),
            ..DaemonState::default()
        };
        assert_eq!(render(&page, &pages.state.borrow(), &pages), Plan::Rebuild);
        let rebuilt = descendants(page.upcast_ref())
            .into_iter()
            .find_map(|w| w.downcast::<gtk::Expander>().ok())
            .expect("a disclosure after the rebuild");
        assert_ne!(rebuilt, again, "a rename builds a new card");
        assert!(rebuilt.is_expanded(), "a rebuild must not fold it shut");
    }
}
