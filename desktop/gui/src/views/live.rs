//! Keeping a page's widgets alive across polls that only move its numbers.
//!
//! [`super::Pages::render`] already refuses to rebuild a page whose slice of
//! [`DaemonState`] is unchanged. That was not enough, and the W2-GNOME Orca
//! gate measured why: the daemon reports ages — `silent_secs`,
//! `last_seen_secs_ago`, a battery reading's `age_secs`, a pending clip's
//! `age_secs` — computed at the moment it answers. A connected device makes
//! `StatusReport` unequal on *every* poll, so the Devices page was torn down
//! and rebuilt every `REFRESH_SECS` while a screen-reader user was walking
//! through it. The switch Orca had located was destroyed under it, focus was
//! dropped, and the reader restarted at the first focusable control on the
//! page — which, with two revoked devices listed, is "Remove all revoked
//! devices".
//!
//! A page drawn through a [`Surface`] is therefore split in two:
//!
//! * a **key** — the part of the state that decides which widgets exist and
//!   what they are called. Only a change here rebuilds;
//! * **live bindings** — closures registered while building that write the
//!   volatile values (an age, a connection state, a switch position) into the
//!   widgets that already exist. They run after every draw, so the numbers
//!   stay as current as they ever were.
//!
//! When the key does change — a device paired, revoked or removed — the page
//! is rebuilt, and focus is put back on the control with the same *logical*
//! name ([`Binder::focusable`]) or, if that control no longer exists, on the
//! nearest enclosing one that does.

use std::cell::RefCell;

use gtk::prelude::*;

use crate::DaemonState;

/// What a draw did. Returned so a test can assert on it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Plan {
    /// The key changed (or nothing was drawn yet): the widgets were rebuilt.
    Rebuild,
    /// The key is the same: the existing widgets were updated in place.
    Update,
}

/// The whole decision, and deliberately nothing else: the key alone says
/// whether widgets are replaced. Volatile values never reach it.
pub(crate) fn plan<K: PartialEq>(drawn: Option<&K>, next: &K) -> Plan {
    if drawn == Some(next) {
        Plan::Update
    } else {
        Plan::Rebuild
    }
}

/// The logical names to try, most specific first, when focus is restored.
///
/// A name is a `/`-separated path — `"<fingerprint>/grant/files.v1"` — and
/// each shorter prefix names something that encloses it, so a control that
/// went away hands focus to its card's disclosure rather than to nothing.
pub(crate) fn fallbacks(key: &str) -> Vec<&str> {
    let mut out = vec![key];
    let mut rest = key;
    while let Some(cut) = rest.rfind('/') {
        rest = &rest[..cut];
        out.push(rest);
    }
    out
}

type Binding = Box<dyn Fn(&DaemonState)>;

/// Collects a page's live bindings and focusable controls while it is built.
#[derive(Default)]
pub(crate) struct Binder {
    bindings: Vec<Binding>,
    focus: Vec<(String, gtk::Widget)>,
}

impl Binder {
    /// Registers an in-place update. It runs once straight after the build
    /// and again after every later draw whose key is unchanged, so it must be
    /// idempotent and must look its data up in the state it is given rather
    /// than capture it.
    pub(crate) fn live(&mut self, update: impl Fn(&DaemonState) + 'static) {
        self.bindings.push(Box::new(update));
    }

    /// Gives a control a logical name that survives a rebuild.
    pub(crate) fn focusable(&mut self, key: impl Into<String>, widget: &impl IsA<gtk::Widget>) {
        self.focus.push((key.into(), widget.clone().upcast()));
    }
}

/// One page's drawn key, live bindings and focusable controls.
pub(crate) struct Surface<K> {
    drawn: RefCell<Option<K>>,
    bindings: RefCell<Vec<Binding>>,
    focus: RefCell<Vec<(String, gtk::Widget)>>,
}

impl<K> Default for Surface<K> {
    fn default() -> Self {
        Surface {
            drawn: RefCell::new(None),
            bindings: RefCell::new(Vec::new()),
            focus: RefCell::new(Vec::new()),
        }
    }
}

impl<K: PartialEq> Surface<K> {
    /// Rebuilds through `build` only if `key` differs from the last one, then
    /// brings every live value up to date.
    pub(crate) fn draw(
        &self,
        container: &impl IsA<gtk::Widget>,
        key: K,
        state: &DaemonState,
        build: impl FnOnce(&mut Binder),
    ) -> Plan {
        let plan = plan(self.drawn.borrow().as_ref(), &key);
        let mut restore = None;
        if plan == Plan::Rebuild {
            restore = self.focused_key(container.as_ref());
            // Recorded before building, for the reason `Pages::render` gives:
            // a handler connected during the build must compare against what
            // is going on screen.
            *self.drawn.borrow_mut() = Some(key);
            let mut binder = Binder::default();
            build(&mut binder);
            *self.bindings.borrow_mut() = binder.bindings;
            *self.focus.borrow_mut() = binder.focus;
        }
        for update in self.bindings.borrow().iter() {
            update(state);
        }
        if let Some(key) = restore {
            self.restore_focus(&key);
        }
        plan
    }

    /// The logical name of the registered control that holds focus, or that
    /// contains the widget that does. The deepest one wins.
    fn focused_key(&self, container: &gtk::Widget) -> Option<String> {
        let root = container.root()?;
        let mut widget = gtk::prelude::RootExt::focus(&root)?;
        if !widget.is_ancestor(container) {
            return None;
        }
        let registry = self.focus.borrow();
        loop {
            if let Some((key, _)) = registry.iter().find(|(_, w)| *w == widget) {
                return Some(key.clone());
            }
            widget = widget.parent()?;
        }
    }

    fn restore_focus(&self, key: &str) {
        let registry = self.focus.borrow();
        for candidate in fallbacks(key) {
            if let Some((_, widget)) = registry.iter().find(|(k, _)| k == candidate) {
                if widget.grab_focus() {
                    return;
                }
            }
        }
    }

    /// Forgets the drawn key, so the next draw rebuilds. For tests that need
    /// a page built from a particular starting point.
    #[cfg(test)]
    pub(crate) fn forget(&self) {
        self.drawn.borrow_mut().take();
    }

    /// The widget registered under `key`, for tests.
    #[cfg(test)]
    pub(crate) fn widget(&self, key: &str) -> Option<gtk::Widget> {
        self.focus
            .borrow()
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, w)| w.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_equal_key_updates_in_place() {
        assert_eq!(plan(Some(&1), &1), Plan::Update);
    }

    #[test]
    fn a_different_key_rebuilds() {
        assert_eq!(plan(Some(&1), &2), Plan::Rebuild);
    }

    #[test]
    fn the_first_draw_always_builds() {
        assert_eq!(plan(None, &1), Plan::Rebuild);
    }

    #[test]
    fn focus_falls_back_to_the_enclosing_control() {
        assert_eq!(
            fallbacks("aa11/grant/files.v1"),
            vec!["aa11/grant/files.v1", "aa11/grant", "aa11"]
        );
        assert_eq!(fallbacks("bulk"), vec!["bulk"]);
    }
}
