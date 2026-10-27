// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! A window's raw handles, as plain Ruby values.
//!
//! Tauri's `Window` answers raw-window-handle's `HasWindowHandle` and
//! `HasDisplayHandle` (tauri `src/window/mod.rs:943-957`), so a crate such as
//! rfd can parent a dialog to it. tao implements both traits for its
//! `Window` (tao 0.34.5 `src/window.rs:1422-1437`). This module turns what
//! tao answers into a tagged Array of a Symbol and Integers, which
//! `Tokra::RawWindowHandle.from_native` turns into Ruby values (ADR 013).
//!
//! Handing Ruby an address as an Integer reads nothing through it, so it is
//! sound. Whoever turns the Integer back into a pointer takes on the
//! window's lifetime and thread, as raw-window-handle's own `borrow_raw`
//! does (raw-window-handle 0.6.2 `src/borrowed.rs:225-247`).

use std::ffi::c_int;
use std::sync::OnceLock;

use magnus::{IntoValue, RArray, Ruby, Value};
use tao::rwh_06::{HandleError, RawDisplayHandle, RawWindowHandle};

/// The Xlib display tao opened for the first display handle Ruby asked
/// for: its address and screen.
///
/// tao answers every X11 display handle with a fresh `XOpenDisplay` that it
/// never closes (tao 0.34.5 `src/platform_impl/linux/window.rs:984-992`),
/// so each call leaks an X connection. Once the X server refuses one,
/// `XOpenDisplay` returns null, and tao 0.34.5 hands it to
/// `XDefaultScreen`, which faults inside libX11, before it reaches
/// `NonNull::new_unchecked`: undefined behavior either way (tao 0.37.2
/// checks the pointer first, `linux/window.rs:984-992`). A page can
/// open dialogs as often as it likes, and each reads the display handle, so
/// Tokra asks tao once and keeps the answer for the life of the process
/// (ADR 013, decision 4). The connection stays open, so the address stays
/// valid.
static XLIB_DISPLAY: OnceLock<(Option<usize>, c_int)> = OnceLock::new();

/// The tagged Array for tao's window handle, or for its error.
pub fn window_handle(ruby: &Ruby, handle: Result<RawWindowHandle, HandleError>) -> RArray {
    let values: Vec<Value> = match handle {
        Ok(RawWindowHandle::Win32(win32)) => vec![
            tag(ruby, "Win32"),
            win32.hwnd.get().into_value_with(ruby),
            win32
                .hinstance
                .map(std::num::NonZero::get)
                .into_value_with(ruby),
        ],
        Ok(RawWindowHandle::AppKit(appkit)) => vec![
            tag(ruby, "AppKit"),
            appkit.ns_view.as_ptr().addr().into_value_with(ruby),
        ],
        Ok(RawWindowHandle::Xlib(xlib)) => vec![
            tag(ruby, "Xlib"),
            xlib.window.into_value_with(ruby),
            xlib.visual_id.into_value_with(ruby),
        ],
        Ok(RawWindowHandle::Wayland(wayland)) => vec![
            tag(ruby, "Wayland"),
            wayland.surface.as_ptr().addr().into_value_with(ruby),
        ],
        // tao gives a desktop window no other kind; raw-window-handle's
        // answer for a kind it cannot represent is NotSupported
        // (src/lib.rs:350-364).
        Ok(_) => vec![tag(ruby, "NotSupported")],
        Err(error) => vec![error_tag(ruby, &error)],
    };
    ruby.ary_from_iter(values)
}

/// The tagged Array for tao's display handle, or for its error. An Xlib
/// display is the first one tao answered (see [`XLIB_DISPLAY`]).
pub fn display_handle(
    ruby: &Ruby,
    read: impl FnOnce() -> Result<RawDisplayHandle, HandleError>,
) -> RArray {
    if let Some(&(display, screen)) = XLIB_DISPLAY.get() {
        return xlib_display(ruby, display, screen);
    }
    let values: Vec<Value> = match read() {
        Ok(RawDisplayHandle::Windows(_)) => vec![tag(ruby, "Windows")],
        Ok(RawDisplayHandle::AppKit(_)) => vec![tag(ruby, "AppKit")],
        Ok(RawDisplayHandle::Xlib(xlib)) => {
            let &(display, screen) = XLIB_DISPLAY.get_or_init(|| {
                (
                    xlib.display.map(|display| display.as_ptr().addr()),
                    xlib.screen,
                )
            });
            return xlib_display(ruby, display, screen);
        }
        Ok(RawDisplayHandle::Wayland(wayland)) => vec![
            tag(ruby, "Wayland"),
            wayland.display.as_ptr().addr().into_value_with(ruby),
        ],
        Ok(_) => vec![tag(ruby, "NotSupported")],
        Err(error) => vec![error_tag(ruby, &error)],
    };
    ruby.ary_from_iter(values)
}

/// The tagged Array for an Xlib display.
fn xlib_display(ruby: &Ruby, display: Option<usize>, screen: c_int) -> RArray {
    ruby.ary_from_iter([
        tag(ruby, "Xlib"),
        display.into_value_with(ruby),
        screen.into_value_with(ruby),
    ])
}

/// The tag for a `HandleError` variant. The enum is non-exhaustive; a
/// variant this version does not know reads as `NotSupported`.
fn error_tag(ruby: &Ruby, error: &HandleError) -> Value {
    match error {
        HandleError::Unavailable => tag(ruby, "Unavailable"),
        _ => tag(ruby, "NotSupported"),
    }
}

/// A Symbol, as a Value.
fn tag(ruby: &Ruby, name: &str) -> Value {
    ruby.to_symbol(name).into_value_with(ruby)
}
