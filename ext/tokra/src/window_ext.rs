// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! The window state plan 040 deferred (plan 041): the enabled state
//! Tauri's `WindowExt` keeps with its own code for each platform, size
//! constraints, icons, background colors, shadows, and the Windows
//! undecorated resizing `set_resizable` and `set_decorations` attach.
//!
//! Each method is what tauri-runtime-wry's `handle_user_message` does for
//! the matching `WindowMessage` (`src/lib.rs:3330-3544`), on the main
//! thread. A closed window answers a getter with `nil` and ignores a
//! setter, as plan 040's do.

use magnus::{method, prelude::*, Error, RClass};
use tao::dpi::{LogicalUnit, PhysicalUnit, PixelUnit};
use tao::window::{Window, WindowSizeConstraints};

use crate::icon::RbIcon;
use crate::window::RbWindow;

/// A size limit as Ruby passes it: whether it is physical, then its
/// number.
type Unit = (bool, f64);

/// The four limits of a `WindowSizeConstraints`, in Tauri's order.
type Limits = (Option<Unit>, Option<Unit>, Option<Unit>, Option<Unit>);

/// A color as Ruby passes it: red, green, blue, and alpha, as tao's `RGBA`.
type Rgba = (u8, u8, u8, u8);

/// dpi's `PixelUnit` for a Ruby limit. A physical one becomes Tauri's
/// `PhysicalUnit<i32>`, which dpi's `From` casts, rounding
/// (dpi 0.1.2 `src/lib.rs:366-378`).
fn pixel_unit((physical, value): Unit) -> PixelUnit {
    if physical {
        PixelUnit::from(PhysicalUnit::new(value))
    } else {
        PixelUnit::from(LogicalUnit::new(value))
    }
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: WindowExt's enabled state adapted from tauri-runtime-wry/src/window/macos.rs

/// The `NSWindow` tao's window holds.
#[cfg(target_os = "macos")]
#[allow(unsafe_code)]
fn ns_window(window: &Window) -> &objc2_app_kit::NSWindow {
    use tao::platform::macos::WindowExtMacOS;

    let ns_window = window.ns_window().cast::<objc2_app_kit::NSWindow>();
    // SAFETY: as in `window_state::center`: `ns_window` points at the
    // `Retained<NSWindow>` tao's window holds while it lives (tao 0.34.5
    // `platform/macos.rs:88-92`), so it is non-null, aligned, and live
    // while `window` is borrowed, which the returned reference is.
    unsafe { &*ns_window }
}

/// Disables the window by attaching a half-transparent titled sheet the
/// size of its frame, or enables it by ending the attached sheet, as
/// Tauri's `WindowExt::set_enabled` does after Electron
/// (`src/window/macos.rs:10-33`). Unlike Tauri's, the sheet does not
/// release itself when closed, as objc2-app-kit requires. Tauri panics off the main thread; this
/// runs only on it (`RbWindow::open_window`), so the marker exists, and
/// without one it does nothing rather than panic.
#[cfg(target_os = "macos")]
#[allow(unsafe_code)]
fn set_enabled(window: &Window, enabled: bool) {
    use objc2::MainThreadMarker;
    use objc2_app_kit::{NSBackingStoreType, NSWindow, NSWindowStyleMask};

    let ns_window = ns_window(window);
    if !enabled {
        let frame = ns_window.frame();
        let Some(mtm) = MainThreadMarker::new() else {
            return;
        };
        // SAFETY: `initWithContentRect:styleMask:backing:defer:` is
        // `NSWindow`'s designated initializer, given a fresh allocation on
        // the main thread (`mtm`), a frame, a style mask, and a backing
        // store type AppKit defines, as Tauri calls it
        // (`src/window/macos.rs:17-25`). objc2-app-kit marks the creation
        // of a window outside a window controller unsafe because such a
        // window must not release itself when closed (objc2-app-kit 0.3.2
        // `src/lib.rs:15-20`); the call below sees to that before AppKit
        // can close it.
        let sheet = unsafe {
            NSWindow::initWithContentRect_styleMask_backing_defer(
                mtm.alloc(),
                frame,
                NSWindowStyleMask::Titled,
                NSBackingStoreType::Buffered,
                false,
            )
        };
        // SAFETY: `sheet` is the live window just created, on the main
        // thread. Without this, AppKit's release on close and the
        // `Retained`'s own release would release it twice; Tauri omits it
        // (plan 041, decision 6).
        unsafe { sheet.setReleasedWhenClosed(false) };
        sheet.setAlphaValue(0.5);
        ns_window.beginSheet_completionHandler(&sheet, None);
    } else if let Some(attached) = ns_window.attachedSheet() {
        ns_window.endSheet(&attached);
    }
}

/// Whether the window has no sheet attached, as Tauri's
/// `WindowExt::is_enabled` reads it (`src/window/macos.rs:35-38`).
#[cfg(target_os = "macos")]
fn is_enabled(window: &Window) -> bool {
    ns_window(window).attachedSheet().is_none()
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: WindowExt's enabled state adapted from tauri-runtime-wry/src/window/linux.rs

/// GTK's sensitivity, as Tauri's `WindowExt::set_enabled` sets it
/// (`src/window/linux.rs:16-18`).
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
fn set_enabled(window: &Window, enabled: bool) {
    use gtk::prelude::WidgetExt;
    use tao::platform::unix::WindowExtUnix;

    window.gtk_window().set_sensitive(enabled);
}

/// GTK's sensitivity, as Tauri's `WindowExt::is_enabled` reads it
/// (`src/window/linux.rs:20-22`).
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
fn is_enabled(window: &Window) -> bool {
    use gtk::prelude::WidgetExt;
    use tao::platform::unix::WindowExtUnix;

    window.gtk_window().is_sensitive()
}

// SPDX-SnippetEnd

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: WindowExt's enabled state adapted from tauri-runtime-wry/src/window/windows.rs

/// The window's `HWND`.
#[cfg(windows)]
fn hwnd(window: &Window) -> windows::Win32::Foundation::HWND {
    use tao::platform::windows::WindowExtWindows;

    windows::Win32::Foundation::HWND(std::ptr::with_exposed_provenance_mut(
        window.hwnd().cast_unsigned(),
    ))
}

/// Win32's `EnableWindow`, whose answer Tauri drops, as Tauri's
/// `WindowExt::set_enabled` calls it (`src/window/windows.rs:14-16`).
#[cfg(windows)]
#[allow(unsafe_code)]
fn set_enabled(window: &Window, enabled: bool) {
    use windows::Win32::UI::Input::KeyboardAndMouse::EnableWindow;

    // SAFETY: the `HWND` is the live window tao created (tao 0.34.5
    // `platform/windows.rs:201-203`), borrowed for the call; `EnableWindow`
    // takes any window handle and reports a bad one as its answer.
    let _ = unsafe { EnableWindow(hwnd(window), enabled) };
}

/// Win32's `IsWindowEnabled`, as Tauri's `WindowExt::is_enabled` asks it
/// (`src/window/windows.rs:18-20`).
#[cfg(windows)]
#[allow(unsafe_code)]
fn is_enabled(window: &Window) -> bool {
    use windows::Win32::UI::Input::KeyboardAndMouse::IsWindowEnabled;

    // SAFETY: as in `set_enabled`; `IsWindowEnabled` only reads the
    // window's state.
    unsafe { IsWindowEnabled(hwnd(window)) }.as_bool()
}

// SPDX-SnippetEnd

impl RbWindow {
    /// Whether the window takes input (see [`is_enabled`]), or `nil` once
    /// closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn is_enabled(&self) -> Result<Option<bool>, Error> {
        Ok(self.open_window()?.map(|window| is_enabled(&window)))
    }

    /// Enables or disables the window (see [`set_enabled`]); a closed
    /// window ignores it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_enabled(&self, enabled: bool) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            set_enabled(&window, enabled);
        }
        Ok(())
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The SetResizable, SetDecorations, SetShadow, SetSizeConstraints, SetIcon, and SetBackgroundColor arms adapted from tauri-runtime-wry/src/lib.rs handle_user_message

    /// tao's `Window::set_resizable`, then on Windows the undecorated
    /// resize handler: detached from a window that may not resize,
    /// attached to an undecorated one that may (`src/lib.rs:3337-3348`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_resizable(&self, resizable: bool) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_resizable(resizable);
            #[cfg(windows)]
            {
                use tao::platform::windows::WindowExtWindows;
                if !resizable {
                    crate::undecorated_resizing::detach_resize_handler(window.hwnd());
                } else if !window.is_decorated() {
                    crate::undecorated_resizing::attach_resize_handler(
                        window.hwnd(),
                        window.has_undecorated_shadow(),
                    );
                }
            }
        }
        Ok(())
    }

    /// tao's `Window::set_decorations`, then on Windows the undecorated
    /// resize handler: detached from a decorated window, attached to an
    /// undecorated one that may resize (`src/lib.rs:3366-3377`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_decorations(&self, decorations: bool) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_decorations(decorations);
            #[cfg(windows)]
            {
                use tao::platform::windows::WindowExtWindows;
                if decorations {
                    crate::undecorated_resizing::detach_resize_handler(window.hwnd());
                } else if window.is_resizable() {
                    crate::undecorated_resizing::attach_resize_handler(
                        window.hwnd(),
                        window.has_undecorated_shadow(),
                    );
                }
            }
        }
        Ok(())
    }

    /// macOS's `set_has_shadow`; on Windows `set_undecorated_shadow` and
    /// the resize handler's region; nothing on Linux
    /// (`src/lib.rs:3378-3385`). A closed window ignores it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_shadow(&self, enable: bool) -> Result<(), Error> {
        let window = self.open_window()?;
        #[cfg(windows)]
        if let Some(window) = window {
            use tao::platform::windows::WindowExtWindows;
            window.set_undecorated_shadow(enable);
            crate::undecorated_resizing::update_drag_hwnd_rgn_for_undecorated(
                window.hwnd(),
                enable,
            );
        }
        #[cfg(target_os = "macos")]
        if let Some(window) = window {
            use tao::platform::macos::WindowExtMacOS;
            window.set_has_shadow(enable);
        }
        #[cfg(not(any(windows, target_os = "macos")))]
        let _ = (window, enable);
        Ok(())
    }

    /// tao's `Window::set_inner_size_constraints`, from Tauri's four
    /// limits (`src/lib.rs:3404-3411`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_inner_size_constraints(&self, limits: Limits) -> Result<(), Error> {
        let (min_width, min_height, max_width, max_height) = limits;
        if let Some(window) = self.open_window()? {
            window.set_inner_size_constraints(WindowSizeConstraints::new(
                min_width.map(pixel_unit),
                min_height.map(pixel_unit),
                max_width.map(pixel_unit),
                max_height.map(pixel_unit),
            ));
        }
        Ok(())
    }

    /// tao's `Window::set_window_icon` with the icon `Native::Icon` built
    /// (`src/lib.rs:3434-3436`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_window_icon(&self, icon: &RbIcon) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_window_icon(Some(icon.icon()));
        }
        Ok(())
    }

    /// tao's `Window::set_background_color`; `nil` for the platform's
    /// default (`src/lib.rs:3542-3544`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_background_color(&self, color: Option<Rgba>) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_background_color(color);
        }
        Ok(())
    }

    // SPDX-SnippetEnd
}

/// Define this module's methods on `Tokra::Native::Window`.
///
/// # Errors
///
/// Returns an error if method definition fails.
pub fn define_methods(class: RClass) -> Result<(), Error> {
    class.define_method("is_enabled", method!(RbWindow::is_enabled, 0))?;
    class.define_method("set_enabled", method!(RbWindow::set_enabled, 1))?;
    class.define_method("set_resizable", method!(RbWindow::set_resizable, 1))?;
    class.define_method("set_decorations", method!(RbWindow::set_decorations, 1))?;
    class.define_method("set_shadow", method!(RbWindow::set_shadow, 1))?;
    class.define_method(
        "set_inner_size_constraints",
        method!(RbWindow::set_inner_size_constraints, 1),
    )?;
    class.define_method("set_window_icon", method!(RbWindow::set_window_icon, 1))?;
    class.define_method(
        "set_background_color",
        method!(RbWindow::set_background_color, 1),
    )?;
    Ok(())
}
