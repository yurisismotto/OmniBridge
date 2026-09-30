//! Pairing: show a code, check a fingerprint, decide.
//!
//! The QR is rendered here rather than shown as the daemon's ASCII art. That
//! is not only cosmetic: the terminal rendering inverts on a dark background
//! and ZXing will not decode an inverted code, so the ASCII form is
//! unscannable on a dark terminal. A drawn code is always the right way up.
//!
//! What the code contains is unchanged — the same payload string the daemon
//! emits — and the fingerprint check is unchanged too. Nothing here shortens
//! or hides the fingerprint, because comparing it on both screens is the
//! entire reason pairing has no man-in-the-middle window.

use adw::prelude::*;
use pliwee_control::Event;
use std::cell::RefCell;
use std::rc::Rc;

use super::Pages;
use crate::client;
use crate::widgets::{self, SPACING_MD, SPACING_SM, SPACING_XS};

pub fn present_pairing_dialog(parent: Option<&gtk::Window>, pages: &Pages) {
    let dialog = adw::Dialog::builder()
        .title("Pair a new device")
        .content_width(760)
        .content_height(560)
        .build();

    let root = widgets::column(SPACING_MD);
    root.set_margin_top(SPACING_MD);
    root.set_margin_bottom(SPACING_MD);
    root.set_margin_start(SPACING_MD);
    root.set_margin_end(SPACING_MD);

    root.append(&widgets::heading("Pair a new device"));
    root.append(&widgets::body_muted(
        "Scan this code with Pliwee on your other device.",
    ));

    let columns = widgets::row(SPACING_MD);

    // --- the code ---------------------------------------------------------
    let qr_card = widgets::card();
    qr_card.set_hexpand(true);
    let qr_area = gtk::DrawingArea::builder()
        .content_width(300)
        .content_height(300)
        .hexpand(true)
        .vexpand(true)
        .build();
    qr_area.set_accessible_role(gtk::AccessibleRole::Img);
    qr_area.update_property(&[gtk::accessible::Property::Label(
        "Pairing QR code. Scan it with Pliwee on the other device.",
    )]);
    // The centre mark is the Wave 0 master itself, compiled into the binary
    // and rendered by GTK's SVG loader: the same resource `brand_mark` shows
    // everywhere else. It is laid over the code, not drawn into it, so no
    // geometry is re-created here (ADR-0020 D8). It stays hidden until there
    // is a code to sit in.
    let centre_mark = widgets::brand_mark(centre_mark_px(300, 300));
    centre_mark.set_can_target(false);
    centre_mark.set_visible(false);
    {
        let centre_mark = centre_mark.clone();
        qr_area.connect_resize(move |_, width, height| {
            centre_mark.set_pixel_size(centre_mark_px(width, height));
        });
    }
    let qr_overlay = gtk::Overlay::new();
    qr_overlay.set_child(Some(&qr_area));
    qr_overlay.add_overlay(&centre_mark);
    qr_card.append(&qr_overlay);
    let expiry = widgets::caption("Opening a pairing window…");
    qr_card.append(&expiry);
    columns.append(&qr_card);

    // --- the identity, once a device answers ------------------------------
    let identity_card = widgets::card();
    identity_card.set_size_request(300, -1);
    let identity_body = widgets::column(SPACING_XS);
    identity_card.append(&widgets::section_label("Trusted device identity"));
    identity_card.append(&identity_body);
    identity_body.append(&widgets::body_muted(
        "Waiting for a device to scan the code…",
    ));
    columns.append(&identity_card);
    root.append(&columns);

    // --- what the person is actually deciding ------------------------------
    let notes = widgets::card();
    notes.append(&widgets::section_label("Before you confirm"));
    for (icon, text) in [
        (
            "security-high-symbolic",
            "Direct local connection. The code and the session never leave your network.",
        ),
        (
            "network-transmit-receive-symbolic",
            "Pinned identity. The scanning device pins this computer's key before it \
             opens a socket, so there is no window in which it could be impersonated.",
        ),
        (
            "camera-photo-symbolic",
            "Check the fingerprint matches on both screens before confirming. That \
             comparison is what makes the pairing safe.",
        ),
    ] {
        let r = widgets::row(SPACING_XS);
        let i = gtk::Image::from_icon_name(icon);
        i.set_pixel_size(16);
        i.set_valign(gtk::Align::Start);
        i.add_css_class("ob-status-connected");
        r.append(&i);
        r.append(&widgets::caption(text));
        notes.append(&r);
    }
    root.append(&notes);

    let actions = widgets::row(SPACING_SM);
    let cancel = widgets::secondary_button("Cancel", None);
    let confirm = widgets::cta_button("Confirm & pair", Some("object-select-symbolic"));
    // Nothing to confirm until a device has proved it holds the code.
    confirm.set_sensitive(false);
    let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    spacer.set_hexpand(true);
    actions.append(&spacer);
    actions.append(&cancel);
    actions.append(&confirm);
    root.append(&actions);

    dialog.set_child(Some(&root));

    // --- the stream --------------------------------------------------------
    let handle: Rc<RefCell<Option<client::PairHandle>>> = Rc::new(RefCell::new(None));
    let payload: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));

    {
        let payload = payload.clone();
        qr_area.set_draw_func(move |_, cr, width, height| {
            if let Some(text) = payload.borrow().as_deref() {
                draw_qr(cr, width, height, text);
            }
        });
    }

    let stream = {
        let qr_area = qr_area.clone();
        let expiry = expiry.clone();
        let identity_body = identity_body.clone();
        let confirm = confirm.clone();
        let payload = payload.clone();
        let centre_mark = centre_mark.clone();
        let dialog = dialog.clone();
        let pages = pages.clone();
        client::pair(None, move |event| match event {
            Ok(Event::PairingReady {
                payload: text,
                expires_in_secs,
                ..
            }) => {
                *payload.borrow_mut() = Some(text);
                qr_area.queue_draw();
                centre_mark.set_visible(true);
                expiry.set_label(&format!("This code expires in {expires_in_secs} seconds."));
                true
            }
            Ok(Event::ConfirmRequest {
                device_name,
                device_id,
                fingerprint,
                ..
            }) => {
                widgets::clear(&identity_body);
                identity_body.append(&widgets::subtitle(&device_name));
                identity_body.append(&widgets::caption(&format!("Device id {device_id}")));
                identity_body.append(&widgets::section_label("Device fingerprint"));
                identity_body.append(&widgets::fingerprint(&fingerprint));
                identity_body.append(&widgets::security_notice(
                    "Check this against the other screen",
                    "Confirm only if the fingerprint shown on the other device is \
                     exactly the same.",
                    true,
                ));
                confirm.set_sensitive(true);
                true
            }
            Ok(Event::Finished { status, detail }) => {
                widgets::clear(&identity_body);
                identity_body.append(&widgets::body(&detail));
                confirm.set_sensitive(false);
                expiry.set_label(&status);
                pages.refresh_now();
                if status == "paired" {
                    dialog.close();
                }
                false
            }
            Ok(_) => true,
            Err(e) => {
                widgets::clear(&identity_body);
                identity_body.append(&widgets::security_notice(
                    "Pairing could not start",
                    &e.to_string(),
                    true,
                ));
                false
            }
        })
    };
    *handle.borrow_mut() = Some(stream);

    {
        let handle = handle.clone();
        confirm.connect_clicked(move |b| {
            b.set_sensitive(false);
            if let Some(h) = handle.borrow().as_ref() {
                h.confirm(true);
            }
        });
    }
    {
        let dialog = dialog.clone();
        cancel.connect_clicked(move |_| {
            dialog.close();
        });
    }
    {
        // Dropping the handle closes the stream, which ends the daemon's
        // pairing window rather than leaving it open until it times out.
        let handle = handle.clone();
        dialog.connect_closed(move |_| {
            handle.borrow_mut().take();
        });
    }

    dialog.present(parent);
}

/// The share of the code's side the centre mark may cover.
///
/// Error correction is level H, which recovers up to 30% of the codewords; a
/// square of a fifth of the side, plus a one-module margin, stays well inside
/// that.
const CENTRE_MARK_FRACTION: f64 = 0.20;

/// The side, in logical pixels, of the square the centre mark is fitted into
/// for a drawing area of `width` x `height`. The keep-out square in
/// [`draw_qr`] and the mark's pixel size both come from here, so the two
/// cannot disagree about where the mark is.
fn centre_mark_px(width: i32, height: i32) -> i32 {
    (f64::from(width.min(height).max(0)) * CENTRE_MARK_FRACTION).floor() as i32
}

/// Draws the pairing payload as a QR code, with a white keep-out square in the
/// middle for the centre mark.
///
/// Error correction is set to the highest level precisely so the centre can
/// carry the mark without making the code harder to read. The mark itself is
/// not drawn here: it is the compiled-in `pliwee-mark.svg`, laid over this
/// area by [`present_pairing_dialog`].
fn draw_qr(cr: &gtk::cairo::Context, width: i32, height: i32, payload: &str) {
    use qrcode::{EcLevel, QrCode};

    let Ok(code) = QrCode::with_error_correction_level(payload.as_bytes(), EcLevel::H) else {
        return;
    };
    let colors = code.to_colors();
    let modules = code.width();
    let quiet = 2;
    let total = modules + quiet * 2;
    let size = width.min(height) as f64;
    let scale = size / total as f64;
    let ox = (width as f64 - size) / 2.0;
    let oy = (height as f64 - size) / 2.0;

    // Always light-on-dark in the conventional direction, whatever the app
    // theme is. A themed QR is an unscannable QR.
    cr.set_source_rgb(1.0, 1.0, 1.0);
    cr.rectangle(ox, oy, size, size);
    let _ = cr.fill();

    cr.set_source_rgb(0.059, 0.090, 0.165); // Ink
    for (i, color) in colors.iter().enumerate() {
        if *color == qrcode::Color::Dark {
            let x = (i % modules + quiet) as f64;
            let y = (i / modules + quiet) as f64;
            cr.rectangle(ox + x * scale, oy + y * scale, scale, scale);
        }
    }
    let _ = cr.fill();

    // The keep-out square the code can spare at level H, one module wider
    // than the mark on every side. Centred, as the overlaid mark is.
    let logo = f64::from(centre_mark_px(width, height));
    let lx = (width as f64 - logo) / 2.0;
    let ly = (height as f64 - logo) / 2.0;
    cr.set_source_rgb(1.0, 1.0, 1.0);
    cr.rectangle(
        lx - scale,
        ly - scale,
        logo + scale * 2.0,
        logo + scale * 2.0,
    );
    let _ = cr.fill();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_centre_mark_is_a_fifth_of_the_code() {
        assert_eq!(centre_mark_px(300, 300), 60);
        assert_eq!(centre_mark_px(500, 300), 60);
        assert_eq!(centre_mark_px(299, 400), 59);
        assert_eq!(centre_mark_px(0, 0), 0);
        assert_eq!(centre_mark_px(-5, 10), 0);
    }
}
