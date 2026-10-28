// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! tray-icon's tray icons: `Tokra::Native::TrayIcon` and its icon,
//! `Tokra::Native::TrayIcon::Icon` (plan 043).
//!
//! The class holds one tray-icon `TrayIcon` in a [`ThreadBound`]: it is an
//! `Rc` over platform objects, usable only on the main thread, where Tauri
//! also keeps it (`run_item_main_thread!`, `tray/mod.rs:497-607`). The
//! class exposes tray-icon's own methods; Tauri's logic around them (the
//! builder, the manager, the listeners, the plugin) is Ruby's, in
//! `lib/tokra/tray`.
//!
//! tray-icon reports the pointer through one event handler per process
//! (`src/lib.rs:254-285`). Tauri sets it once, to send the event through
//! its loop's proxy (`app.rs:2203-2210`); Tokra does the same, through the
//! proxy of the loop that runs now (`menu::attach_loop`).

use std::cell::RefCell;
use std::sync::Once;

use magnus::{function, method, prelude::*, Error, RClass, RHash, RModule, RString, Ruby, Value};

use crate::menu::{loop_proxy, on_main_thread, RbMenu, RbSubmenu};
use crate::runtime_error;
use crate::thread_bound::{wrong_thread, ThreadBound};
use crate::user_event::{Released, UserEvent};

/// Sets tray-icon's event handler, once per process: tray-icon keeps the
/// first handler it is given (`TRAY_EVENT_HANDLER`, a `OnceCell`).
static EVENT_HANDLER: Once = Once::new();

/// Sends tray-icon's events to the loop that runs now, as each
/// `Native::EventLoop` is built, after `menu::attach_loop` has made its
/// proxy the current one. The handler converts the event and sends
/// `UserEvent::TrayIconEvent`; it calls no Ruby.
pub fn attach_loop() {
    EVENT_HANDLER.call_once(|| {
        tray_icon::TrayIconEvent::set_event_handler(Some(|event: tray_icon::TrayIconEvent| {
            send(event);
        }));
    });
}

/// Converts `event` and sends it through the running loop's proxy, if
/// there is one.
fn send(event: tray_icon::TrayIconEvent) {
    if let (Some(event), Some(proxy)) = (TrayEvent::from_tray_icon(event), loop_proxy()) {
        let _ = proxy.send_event(UserEvent::TrayIconEvent(Box::new(event)));
    }
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The event's conversion adapted from tauri/crates/tauri/src/tray/mod.rs

/// A tray-icon event as Ruby receives it: Tauri's `TrayIconEvent`
/// (`tray/mod.rs:62-199`) in plain values.
#[derive(Debug, Clone, PartialEq)]
pub struct TrayEvent {
    /// The variant: `Click`, `DoubleClick`, `Enter`, `Move`, or `Leave`.
    pub kind: &'static str,
    /// The id of the tray icon.
    pub id: String,
    /// The pointer's physical position.
    pub position: (f64, f64),
    /// The icon's physical position, rounded to `i32` as dpi's
    /// `From<PhysicalPosition<f64>> for Position` rounds it, and its
    /// physical size.
    pub rect: (i32, i32, u32, u32),
    /// The mouse button of a click or double click.
    pub button: Option<&'static str>,
    /// The button's state in a click.
    pub button_state: Option<&'static str>,
}

impl TrayEvent {
    /// Tauri's `From<tray_icon::TrayIconEvent>` (`tray/mod.rs:139-199`).
    /// Tauri's last arm is `todo!()`, a panic, for a variant tray-icon
    /// adds later; Tokra drops such an event (plan 043, decision 8).
    fn from_tray_icon(event: tray_icon::TrayIconEvent) -> Option<Self> {
        use tray_icon::TrayIconEvent as E;
        let (kind, id, position, rect, button, button_state) = match event {
            E::Click {
                id,
                position,
                rect,
                button,
                button_state,
            } => (
                "Click",
                id,
                position,
                rect,
                Some(mouse_button(button)),
                Some(button_state_name(button_state)),
            ),
            E::DoubleClick {
                id,
                position,
                rect,
                button,
            } => (
                "DoubleClick",
                id,
                position,
                rect,
                Some(mouse_button(button)),
                None,
            ),
            E::Enter { id, position, rect } => ("Enter", id, position, rect, None, None),
            E::Move { id, position, rect } => ("Move", id, position, rect, None, None),
            E::Leave { id, position, rect } => ("Leave", id, position, rect, None, None),
            _ => return None,
        };
        Some(Self {
            kind,
            id: id.0,
            position: (position.x, position.y),
            rect: rect_values(rect),
            button,
            button_state,
        })
    }
}

/// A tray-icon `Rect` as Tauri's `Rect` holds it: the position through
/// dpi's `Position::from`, which casts to `PhysicalPosition<i32>`
/// (dpi 0.1.2 `src/lib.rs:769-774`, rounding as `:112-116`, `:130-133`),
/// and the size as it is (`tray/mod.rs:151-154`).
fn rect_values(rect: tray_icon::Rect) -> (i32, i32, u32, u32) {
    let position = rect.position.cast::<i32>();
    (position.x, position.y, rect.size.width, rect.size.height)
}

/// Tauri's `MouseButton` for tray-icon's (`tray/mod.rs:52-60`).
const fn mouse_button(button: tray_icon::MouseButton) -> &'static str {
    match button {
        tray_icon::MouseButton::Left => "Left",
        tray_icon::MouseButton::Right => "Right",
        tray_icon::MouseButton::Middle => "Middle",
    }
}

/// Tauri's `MouseButtonState` for tray-icon's (`tray/mod.rs:31-38`).
const fn button_state_name(state: tray_icon::MouseButtonState) -> &'static str {
    match state {
        tray_icon::MouseButtonState::Up => "Up",
        tray_icon::MouseButtonState::Down => "Down",
    }
}

// SPDX-SnippetEnd

/// A tray-icon error as a `RuntimeError` with tray-icon's text, which Ruby
/// raises as `Error::Tray` ("tray icon error: …", Tauri `error.rs:106-110`).
fn tray_error(error: &tray_icon::Error) -> Error {
    Error::new(runtime_error(), error.to_string())
}

/// tray-icon's `Icon`, made from RGBA bytes.
///
/// tray-icon's icon holds bytes on macOS and Linux and an `HICON` behind
/// an `Arc` on Windows, which tray-icon declares `Send`
/// (`platform_impl/windows/icon.rs:67`), so it is made on any thread,
/// as Tauri converts an image before it goes to the main thread
/// (`tray/mod.rs:499-504`). Ruby reaches `&self` only while its thread
/// holds the GVL; the one thing done through it is [`Self::icon`]'s
/// clone.
#[magnus::wrap(class = "Tokra::Native::TrayIcon::Icon", free_immediately, size)]
pub struct RbTrayIconIcon(tray_icon::Icon);

impl RbTrayIconIcon {
    /// The tray-icon icon, for the tray that takes it.
    fn icon(&self) -> tray_icon::Icon {
        self.0.clone()
    }

    /// tray-icon's `Icon::from_rgba`, after its own checks in 64 bits.
    ///
    /// tray-icon checks the pixel count as `width * height` in `u32` on
    /// macOS and Windows (`src/icon.rs:92-116`), which can wrap; on Windows
    /// the wrapped icon then reaches `CreateIcon` with fewer bytes than its
    /// size, which reads past them (`platform_impl/windows/icon.rs:21-49`).
    /// Linux's tray-icon checks nothing (`platform_impl/gtk/icon.rs:16-24`).
    /// So Tokra runs the checks first on every platform, with tray-icon's
    /// texts (plan 043, decision 8).
    ///
    /// # Errors
    ///
    /// Returns a `RuntimeError` with tray-icon's text, which Ruby raises as
    /// `Error::BadTrayIcon`.
    fn from_rgba(rgba: RString, width: u32, height: u32) -> Result<Self, Error> {
        let rgba = rgba.to_bytes().to_vec();
        if let Some(message) = crate::menu::bad_rgba(rgba.len(), width, height) {
            return Err(Error::new(runtime_error(), message));
        }
        tray_icon::Icon::from_rgba(rgba, width, height)
            .map(Self)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))
    }
}

/// `Tokra::Native::TrayIcon`: one tray-icon tray, or none once removed.
#[magnus::wrap(class = "Tokra::Native::TrayIcon", free_immediately, size)]
pub struct RbTrayIcon {
    id: String,
    inner: ThreadBound<RefCell<Option<tray_icon::TrayIcon>>>,
}

impl RbTrayIcon {
    const CLASS: &'static str = "Tokra::Native::TrayIcon";

    /// The id a new `TrayIconBuilder` takes from tray-icon's counter
    /// (`src/lib.rs:53-59`), as Tauri's `TrayIconBuilder::new` does
    /// (`tray/mod.rs:216-222`).
    fn next_id() -> String {
        tray_icon::TrayIconBuilder::new().id().0.clone()
    }

    /// Builds a tray with `id` and the attributes in `attributes`, as
    /// tray-icon's `TrayIconBuilder::build` does (`src/lib.rs:95-97`):
    /// `menu`, `icon`, `tooltip`, `title`, `temp_dir_path`,
    /// `icon_is_template`, and `menu_on_left_click` (default `true`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the main thread, a `RuntimeError` before
    /// any event loop exists (plan 043, decision 3) or with tray-icon's
    /// error, `TypeError` for a menu that is neither a native menu nor a
    /// submenu, and on Linux the refusals of decision 8.
    fn new(ruby: &Ruby, id: String, attributes: RHash) -> Result<Self, Error> {
        on_main_thread(ruby, Self::CLASS)?;
        if loop_proxy().is_none() {
            return Err(Error::new(
                runtime_error(),
                "no event loop exists yet; build tray icons once App#run has built it, such as in the setup hook",
            ));
        }
        #[cfg(target_os = "linux")]
        appindicator::refuse_missing()?;
        let menu = attributes
            .lookup::<_, Option<Value>>("menu")?
            .map(context_menu)
            .transpose()?;
        let icon = attributes
            .lookup::<_, Option<&RbTrayIconIcon>>("icon")?
            .map(RbTrayIconIcon::icon);
        let attrs = tray_icon::TrayIconAttributes {
            tooltip: attributes.lookup("tooltip")?,
            menu,
            icon,
            temp_dir_path: attributes
                .lookup::<_, Option<String>>("temp_dir_path")?
                .map(Into::into),
            icon_is_template: attributes
                .lookup::<_, Option<bool>>("icon_is_template")?
                .unwrap_or(false),
            menu_on_left_click: attributes
                .lookup::<_, Option<bool>>("menu_on_left_click")?
                .unwrap_or(true),
            title: attributes.lookup("title")?,
        };
        let tray = tray_icon::TrayIcon::with_id(id.clone(), attrs).map_err(|e| tray_error(&e))?;
        Ok(Self {
            id,
            inner: ThreadBound::new(RefCell::new(Some(tray))),
        })
    }

    fn id(&self) -> String {
        self.id.clone()
    }

    /// Runs `f` with the tray, or answers `None` once it is removed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` on another thread.
    fn with_tray<T>(&self, f: impl FnOnce(&tray_icon::TrayIcon) -> T) -> Result<Option<T>, Error> {
        let cell = self.inner.get().ok_or_else(|| wrong_thread(Self::CLASS))?;
        let tray = cell
            .try_borrow()
            .map_err(|_| Error::new(runtime_error(), "the tray icon is being removed"))?;
        Ok(tray.as_ref().map(f))
    }

    fn set_icon(&self, icon: Option<&RbTrayIconIcon>) -> Result<(), Error> {
        let icon = icon.map(RbTrayIconIcon::icon);
        self.with_tray(|tray| tray.set_icon(icon))?
            .transpose()
            .map_err(|e| tray_error(&e))
            .map(|_| ())
    }

    /// tray-icon's `set_menu`; on Linux a menu that is set stays, so `nil`
    /// changes nothing there (`platform_impl/gtk/mod.rs:76-81`).
    fn set_menu(&self, menu: Option<Value>) -> Result<(), Error> {
        let menu = menu.map(context_menu).transpose()?;
        self.with_tray(|tray| tray.set_menu(menu))?;
        Ok(())
    }

    fn set_tooltip(&self, tooltip: Option<String>) -> Result<(), Error> {
        self.with_tray(|tray| tray.set_tooltip(tooltip))?
            .transpose()
            .map_err(|e| tray_error(&e))
            .map(|_| ())
    }

    fn set_title(&self, title: Option<String>) -> Result<(), Error> {
        self.with_tray(|tray| tray.set_title(title))?;
        Ok(())
    }

    fn set_visible(&self, visible: bool) -> Result<(), Error> {
        self.with_tray(|tray| tray.set_visible(visible))?
            .transpose()
            .map_err(|e| tray_error(&e))
            .map(|_| ())
    }

    /// tray-icon's `set_temp_dir_path`, Linux only, where Tauri calls it
    /// (`tray/mod.rs:552-558`).
    #[cfg(target_os = "linux")]
    fn set_temp_dir_path(&self, path: Option<String>) -> Result<(), Error> {
        self.with_tray(|tray| tray.set_temp_dir_path(path))?;
        Ok(())
    }

    /// tray-icon's `set_icon_as_template`, macOS only, where Tauri calls it
    /// (`tray/mod.rs:561-567`).
    #[cfg(target_os = "macos")]
    fn set_icon_as_template(&self, is_template: bool) -> Result<(), Error> {
        self.with_tray(|tray| tray.set_icon_as_template(is_template))?;
        Ok(())
    }

    /// tray-icon's `set_show_menu_on_left_click`, macOS and Windows only,
    /// where Tauri calls it (`tray/mod.rs:575-581`).
    #[cfg(any(target_os = "macos", windows))]
    fn set_show_menu_on_left_click(&self, enable: bool) -> Result<(), Error> {
        self.with_tray(|tray| tray.set_show_menu_on_left_click(enable))?;
        Ok(())
    }

    /// The tray's rect as `[x, y, width, height]`, converted as Tauri's
    /// `rect` converts it (`tray/mod.rs:588-595`), or `nil` where
    /// tray-icon has none (always on Linux) or once removed.
    fn rect(&self) -> Result<Option<(i32, i32, u32, u32)>, Error> {
        Ok(self
            .with_tray(tray_icon::TrayIcon::rect)?
            .flatten()
            .map(rect_values))
    }

    /// Drops the tray on the main thread, which takes it off the system
    /// tray (plan 043, decision 6). Later calls do nothing.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` on another thread.
    fn remove(&self) -> Result<(), Error> {
        let cell = self.inner.get().ok_or_else(|| wrong_thread(Self::CLASS))?;
        let tray = cell
            .try_borrow_mut()
            .map_err(|_| Error::new(runtime_error(), "the tray icon is in use"))?
            .take();
        drop(tray);
        Ok(())
    }

    /// Whether the tray was removed.
    fn is_removed(&self) -> Result<bool, Error> {
        Ok(self.with_tray(|_| ())?.is_none())
    }
}

impl Drop for RbTrayIcon {
    /// Ruby frees this object on whichever thread sweeps it; off the main
    /// thread the tray goes home to be dropped, as the menus do. No Ruby
    /// API is called, as `free_immediately` requires.
    fn drop(&mut self) {
        if self.inner.owner().is_current() {
            return;
        }
        let value = self.inner.take();
        if let Some(proxy) = loop_proxy() {
            let _ = proxy.send_event(UserEvent::Release(Released::Tray(Box::new(value))));
        }
    }
}

/// The muda menu a tray takes, owned, as Tauri's `inner_context_owned`
/// gives it (`menu/mod.rs:744-750`).
///
/// # Errors
///
/// Returns `TypeError` for anything but a native menu or submenu, as
/// Tauri's `ContextMenu` bound would not compile, `ThreadError` on another
/// thread, and on Linux muda's error for a menu GTK cannot build.
fn context_menu(menu: Value) -> Result<Box<dyn muda::ContextMenu>, Error> {
    #[cfg(not(any(target_os = "macos", windows)))]
    let value = menu;
    let owned: Box<dyn muda::ContextMenu> = if let Ok(menu) = <&RbMenu>::try_convert(menu) {
        Box::new(menu.get()?.clone())
    } else if let Ok(submenu) = <&RbSubmenu>::try_convert(menu) {
        Box::new(submenu.get()?.clone())
    } else {
        let ruby = Ruby::get_with(menu);
        return Err(Error::new(
            ruby.exception_type_error(),
            format!(
                "wrong argument type {} (expected Tokra::Native::Menu or Tokra::Native::Submenu)",
                menu.class().inspect()
            ),
        ));
    };
    #[cfg(not(any(target_os = "macos", windows)))]
    crate::menu::refuse_unbuildable_gtk_menu(value)?;
    Ok(owned)
}

/// The `AppIndicator` library tray-icon loads on Linux.
///
/// libappindicator-sys loads it the first time tray-icon makes an
/// `AppIndicator`, and panics when it finds none (0.9.0 `src/lib.rs:13-49`,
/// with its default `backcompat` feature, which libappindicator 0.9.0
/// enables). The constructor loads the same libraries by the same names in
/// the same order first, and raises the crate's text instead (plan 043,
/// decision 8).
#[cfg(target_os = "linux")]
mod appindicator {
    use std::sync::atomic::{AtomicBool, Ordering};

    use magnus::Error;

    use crate::runtime_error;

    /// Set once a library has loaded: the crate's own load then succeeds
    /// too, so later trays need not look again.
    static FOUND: AtomicBool = AtomicBool::new(false);

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: MIT
    // SPDX-SnippetCopyrightText: 2018 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The library names and the panic text adapted from
    //                      libappindicator-sys 0.9.0 src/lib.rs

    /// The names libappindicator-sys tries, in its order.
    const NAMES: [&str; 4] = [
        "libayatana-appindicator3.so.1",
        "libappindicator3.so.1",
        "libayatana-appindicator3.so",
        "libappindicator3.so",
    ];

    /// Raises the crate's panic text, with each name's error, when no
    /// `AppIndicator` library loads.
    pub fn refuse_missing() -> Result<(), Error> {
        if FOUND.load(Ordering::Relaxed) {
            return Ok(());
        }
        let mut errors = Vec::with_capacity(NAMES.len());
        for name in NAMES {
            // SAFETY: `Library::new` is unsafe because loading a library
            // runs its initializers (libloading 0.7.4 `src/safe.rs:26-35`). This
            // loads the library libappindicator-sys's `LIB` loads when
            // tray-icon makes its first indicator, by the same name and in
            // the same order (0.9.0 `src/lib.rs:13-49`), so the same
            // initializers run that would run anyway. No symbol is read
            // through the handle.
            #[allow(unsafe_code)]
            let loaded = unsafe { libloading::Library::new(name) };
            match loaded {
                Ok(library) => {
                    // Kept loaded for the process, as the crate's own
                    // `LIB` keeps it: closing it here would unload it and
                    // run its finalizers only for the crate to load it
                    // again.
                    std::mem::forget(library);
                    FOUND.store(true, Ordering::Relaxed);
                    return Ok(());
                }
                Err(error) => errors.push(error.to_string()),
            }
        }
        Err(Error::new(
            runtime_error(),
            format!(
                "Failed to load ayatana-appindicator3 or appindicator3 dynamic library\n{}",
                errors.join("\n")
            ),
        ))
    }

    // SPDX-SnippetEnd
}

/// Defines `Tokra::Native::TrayIcon` and `Tokra::Native::TrayIcon::Icon`.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_classes(ruby: &Ruby, native: RModule) -> Result<(), Error> {
    let tray: RClass = native.define_class("TrayIcon", ruby.class_object())?;
    tray.define_singleton_method("new", function!(RbTrayIcon::new, 2))?;
    tray.define_singleton_method("next_id", function!(RbTrayIcon::next_id, 0))?;
    tray.define_method("id", method!(RbTrayIcon::id, 0))?;
    tray.define_method("set_icon", method!(RbTrayIcon::set_icon, 1))?;
    tray.define_method("set_menu", method!(RbTrayIcon::set_menu, 1))?;
    tray.define_method("set_tooltip", method!(RbTrayIcon::set_tooltip, 1))?;
    tray.define_method("set_title", method!(RbTrayIcon::set_title, 1))?;
    tray.define_method("set_visible", method!(RbTrayIcon::set_visible, 1))?;
    #[cfg(target_os = "linux")]
    tray.define_method(
        "set_temp_dir_path",
        method!(RbTrayIcon::set_temp_dir_path, 1),
    )?;
    #[cfg(target_os = "macos")]
    tray.define_method(
        "set_icon_as_template",
        method!(RbTrayIcon::set_icon_as_template, 1),
    )?;
    #[cfg(any(target_os = "macos", windows))]
    tray.define_method(
        "set_show_menu_on_left_click",
        method!(RbTrayIcon::set_show_menu_on_left_click, 1),
    )?;
    tray.define_method("rect", method!(RbTrayIcon::rect, 0))?;
    tray.define_method("remove", method!(RbTrayIcon::remove, 0))?;
    tray.define_method("removed?", method!(RbTrayIcon::is_removed, 0))?;

    // Where muda's GTK context menu can panic, the check Ruby runs before
    // it hands a tray its menu, to raise `Error::Menu` (plan 043,
    // decision 8).
    #[cfg(not(any(target_os = "macos", windows)))]
    native.define_module_function(
        "refuse_unbuildable_menu",
        function!(crate::menu::refuse_unbuildable_gtk_menu, 1),
    )?;

    let icon = tray.define_class("Icon", ruby.class_object())?;
    icon.define_singleton_method("from_rgba", function!(RbTrayIconIcon::from_rgba, 3))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{rect_values, TrayEvent};
    use tray_icon::dpi::{PhysicalPosition, PhysicalSize};
    use tray_icon::{MouseButton, MouseButtonState, Rect, TrayIconEvent, TrayIconId};

    fn rect() -> Rect {
        Rect {
            size: PhysicalSize::new(22, 24),
            position: PhysicalPosition::new(1.5, -2.5),
        }
    }

    #[test]
    fn a_click_keeps_its_button_and_state_and_rounds_the_rect_as_dpi_does() {
        let event = TrayIconEvent::Click {
            id: TrayIconId::new("tray"),
            position: PhysicalPosition::new(10.25, 20.75),
            rect: rect(),
            button: MouseButton::Right,
            button_state: MouseButtonState::Down,
        };

        assert_eq!(
            TrayEvent::from_tray_icon(event),
            Some(TrayEvent {
                kind: "Click",
                id: "tray".into(),
                position: (10.25, 20.75),
                rect: (2, -3, 22, 24),
                button: Some("Right"),
                button_state: Some("Down"),
            })
        );
    }

    #[test]
    fn a_double_click_has_a_button_and_no_state() {
        let event = TrayIconEvent::DoubleClick {
            id: TrayIconId::new("tray"),
            position: PhysicalPosition::new(0.0, 0.0),
            rect: rect(),
            button: MouseButton::Middle,
        };

        let converted = TrayEvent::from_tray_icon(event).expect("a known variant");
        assert_eq!(
            (converted.kind, converted.button, converted.button_state),
            ("DoubleClick", Some("Middle"), None)
        );
    }

    #[test]
    fn enter_move_and_leave_have_no_button() {
        let position = PhysicalPosition::new(3.0, 4.0);
        let id = TrayIconId::new("tray");
        let events = [
            TrayIconEvent::Enter {
                id: id.clone(),
                position,
                rect: rect(),
            },
            TrayIconEvent::Move {
                id: id.clone(),
                position,
                rect: rect(),
            },
            TrayIconEvent::Leave {
                id,
                position,
                rect: rect(),
            },
        ];

        let kinds: Vec<_> = events
            .into_iter()
            .filter_map(TrayEvent::from_tray_icon)
            .map(|event| (event.kind, event.button, event.button_state))
            .collect();
        assert_eq!(
            kinds,
            [
                ("Enter", None, None),
                ("Move", None, None),
                ("Leave", None, None)
            ]
        );
    }

    #[test]
    fn a_rect_rounds_half_away_from_zero() {
        let rect = Rect {
            size: PhysicalSize::new(0, 0),
            position: PhysicalPosition::new(0.5, -0.5),
        };

        assert_eq!(rect_values(rect), (1, -1, 0, 0));
    }

    #[test]
    fn a_wrapped_pixel_count_is_refused_in_tray_icons_words() {
        assert_eq!(
            crate::menu::bad_rgba(0, 65_536, 65_536).as_deref(),
            Some("The specified dimensions (65536x65536) don't match the number of pixels supplied by the `rgba` argument (0). For those dimensions, the expected pixel count is 4294967296.")
        );
        assert_eq!(crate::menu::bad_rgba(8, 2, 1), None);
    }
}
