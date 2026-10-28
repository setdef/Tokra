// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! The window's getters and setters (plan 040).
//!
//! Each method is the tao call tauri-runtime-wry's `handle_user_message`
//! makes for the matching `WindowMessage` (`src/lib.rs:3244-3546`), run on
//! the window's own thread, the main thread. A closed window answers a
//! getter with `nil` and ignores a setter, as `RbWindow::title` and
//! `RbWindow::set_title` do (plan 038, decision 3). A getter whose answer
//! may itself be nothing (a monitor, a position tao does not support) wraps
//! it in a one-element Array, so `nil` always means a closed window.
//!
//! Sizes and positions arrive from Ruby as `[physical, a, b]`: `true` for
//! physical pixels, `false` for logical ones (plan 040, decision 2).

use magnus::{method, prelude::*, Error, RClass, RString};
use tao::dpi::{LogicalPosition, LogicalSize, PhysicalPosition, PhysicalSize, Position, Size};
use tao::monitor::MonitorHandle;
use tao::window::{CursorIcon, Fullscreen, ResizeDirection, Theme, UserAttentionType, Window};

use crate::webview::RbWebView;
use crate::window::RbWindow;

/// A size or position as Ruby passes it: whether it is physical, then its
/// two numbers.
type Dimensions = (bool, f64, f64);

/// An answer that may itself be nothing, wrapped so that `nil` alone means
/// a closed window: `[value]` or `[nil]`.
pub type Maybe<T> = (Option<T>,);

/// A position and a size, as Ruby reads a rectangle.
pub type Rect = ((i32, i32), (u32, u32));

/// A monitor as Ruby reads it: name, position, size, work area, and scale
/// factor, the fields tauri-runtime-wry copies (`src/lib.rs:596-608`).
pub type MonitorValue = (Option<String>, (i32, i32), (u32, u32), Rect, f64);

/// tao's `Size` for a Ruby size: `Size::Physical` holds `u32`s, as
/// Tauri's `PhysicalSize<u32>` does, and dpi rounds into them.
fn size((physical, width, height): Dimensions) -> Size {
    if physical {
        Size::Physical(PhysicalSize::new(width, height).cast())
    } else {
        Size::Logical(LogicalSize::new(width, height))
    }
}

/// tao's `Position` for a Ruby position: `Position::Physical` holds
/// `i32`s, as Tauri's `PhysicalPosition<i32>` does.
fn position((physical, x, y): Dimensions) -> Position {
    if physical {
        Position::Physical(PhysicalPosition::new(x, y).cast())
    } else {
        Position::Logical(LogicalPosition::new(x, y))
    }
}

/// An `ArgumentError` for a name the Ruby class does not have.
///
/// # Panics
///
/// Panics outside the Ruby VM, as `runtime_error` does.
fn argument_error(message: String) -> Error {
    let ruby = magnus::Ruby::get().expect("Ruby VM not initialized");
    Error::new(ruby.exception_arg_error(), message)
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Enum and monitor conversions adapted from tauri-runtime-wry/src/lib.rs and src/monitor/

/// The name Ruby's `Tokra::Theme` gives tao's theme. A theme Tauri does
/// not know reads as `Light`, as `map_theme` maps it (`src/lib.rs:578-584`).
const fn theme_name(theme: Theme) -> &'static str {
    match theme {
        Theme::Dark => "Dark",
        _ => "Light",
    }
}

/// tao's theme for a `Tokra::Theme` name, or `None` to follow the system,
/// as `to_tao_theme` maps it (`src/lib.rs:5224-5230`).
fn theme(name: Option<&str>) -> Result<Option<Theme>, Error> {
    match name {
        None => Ok(None),
        Some("Light") => Ok(Some(Theme::Light)),
        Some("Dark") => Ok(Some(Theme::Dark)),
        Some(other) => Err(argument_error(format!("unknown theme: {other}"))),
    }
}

/// tao's cursor icon for a `Tokra::CursorIcon` name, as
/// `CursorIconWrapper` maps Tauri's (`src/lib.rs:708-753`): a name it does
/// not know is the default cursor.
fn cursor_icon(name: &str) -> CursorIcon {
    match name {
        "Crosshair" => CursorIcon::Crosshair,
        "Hand" => CursorIcon::Hand,
        "Arrow" => CursorIcon::Arrow,
        "Move" => CursorIcon::Move,
        "Text" => CursorIcon::Text,
        "Wait" => CursorIcon::Wait,
        "Help" => CursorIcon::Help,
        "Progress" => CursorIcon::Progress,
        "NotAllowed" => CursorIcon::NotAllowed,
        "ContextMenu" => CursorIcon::ContextMenu,
        "Cell" => CursorIcon::Cell,
        "VerticalText" => CursorIcon::VerticalText,
        "Alias" => CursorIcon::Alias,
        "Copy" => CursorIcon::Copy,
        "NoDrop" => CursorIcon::NoDrop,
        "Grab" => CursorIcon::Grab,
        "Grabbing" => CursorIcon::Grabbing,
        "AllScroll" => CursorIcon::AllScroll,
        "ZoomIn" => CursorIcon::ZoomIn,
        "ZoomOut" => CursorIcon::ZoomOut,
        "EResize" => CursorIcon::EResize,
        "NResize" => CursorIcon::NResize,
        "NeResize" => CursorIcon::NeResize,
        "NwResize" => CursorIcon::NwResize,
        "SResize" => CursorIcon::SResize,
        "SeResize" => CursorIcon::SeResize,
        "SwResize" => CursorIcon::SwResize,
        "WResize" => CursorIcon::WResize,
        "EwResize" => CursorIcon::EwResize,
        "NsResize" => CursorIcon::NsResize,
        "NeswResize" => CursorIcon::NeswResize,
        "NwseResize" => CursorIcon::NwseResize,
        "ColResize" => CursorIcon::ColResize,
        "RowResize" => CursorIcon::RowResize,
        _ => CursorIcon::Default,
    }
}

/// tao's attention request for a `Tokra::UserAttentionType` name, as
/// `UserAttentionTypeWrapper` maps Tauri's (`src/lib.rs:695-705`).
fn user_attention_type(name: &str) -> Result<UserAttentionType, Error> {
    match name {
        "Critical" => Ok(UserAttentionType::Critical),
        "Informational" => Ok(UserAttentionType::Informational),
        other => Err(argument_error(format!(
            "unknown user attention type: {other}"
        ))),
    }
}

/// tao's resize direction for a `Tokra::ResizeDirection` name, as the
/// `ResizeDragWindow` arm maps Tauri's (`src/lib.rs:3467-3478`).
fn resize_direction(name: &str) -> Result<ResizeDirection, Error> {
    match name {
        "East" => Ok(ResizeDirection::East),
        "North" => Ok(ResizeDirection::North),
        "NorthEast" => Ok(ResizeDirection::NorthEast),
        "NorthWest" => Ok(ResizeDirection::NorthWest),
        "South" => Ok(ResizeDirection::South),
        "SouthEast" => Ok(ResizeDirection::SouthEast),
        "SouthWest" => Ok(ResizeDirection::SouthWest),
        "West" => Ok(ResizeDirection::West),
        other => Err(argument_error(format!("unknown resize direction: {other}"))),
    }
}

/// The monitor as Ruby reads it, as `MonitorHandleWrapper` copies it.
pub fn monitor(handle: &MonitorHandle) -> MonitorValue {
    let position = handle.position();
    let size = handle.size();
    let (work_position, work_size) = work_area(handle);
    (
        handle.name(),
        (position.x, position.y),
        (size.width, size.height),
        (
            (work_position.x, work_position.y),
            (work_size.width, work_size.height),
        ),
        handle.scale_factor(),
    )
}

/// The part of the monitor windows may use, without the menu bar and the
/// Dock, as Tauri's `MonitorExt::work_area` reads it from `NSScreen`
/// (`src/monitor/macos.rs:8-34`). Like Tauri's, it moves the position
/// right by the visible frame's left edge and leaves its top alone.
#[cfg(target_os = "macos")]
#[allow(unsafe_code)]
fn work_area(handle: &MonitorHandle) -> (PhysicalPosition<i32>, PhysicalSize<u32>) {
    use objc2::rc::Retained;
    use objc2_app_kit::NSScreen;
    use tao::platform::macos::MonitorHandleExtMacOS;

    let Some(ns_screen) = handle.ns_screen() else {
        return (handle.position(), handle.size());
    };
    // SAFETY: tao 0.34.5 answers `Retained::into_raw` of the
    // `Retained<NSScreen>` it found for this display
    // (`platform/macos.rs:376-381`, `platform_impl/macos/monitor.rs:314`),
    // so the pointer is a non-null `NSScreen` carrying one retain that the
    // caller owns. `from_raw` takes that retain back, so dropping the
    // `Retained` releases it, where Tauri's reference leaks it.
    let Some(ns_screen) = (unsafe { Retained::from_raw(ns_screen.cast::<NSScreen>()) }) else {
        return (handle.position(), handle.size());
    };
    let screen_frame = ns_screen.frame();
    let visible_frame = ns_screen.visibleFrame();
    let scale_factor = handle.scale_factor();
    let mut position = handle.position().to_logical::<f64>(scale_factor);
    position.x += visible_frame.origin.x - screen_frame.origin.x;
    (
        position.to_physical(scale_factor),
        LogicalSize::new(visible_frame.size.width, visible_frame.size.height)
            .to_physical(scale_factor),
    )
}

/// The monitor's work area, as Tauri's `MonitorExt::work_area` reads it
/// from GDK (`src/monitor/linux.rs:10-19`).
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
fn work_area(handle: &MonitorHandle) -> (PhysicalPosition<i32>, PhysicalSize<u32>) {
    use gtk::prelude::MonitorExt;
    use tao::platform::unix::MonitorHandleExtUnix;

    let rect = handle.gdk_monitor().workarea();
    let scale_factor = handle.scale_factor();
    (
        LogicalPosition::new(rect.x(), rect.y()).to_physical(scale_factor),
        LogicalSize::new(rect.width().cast_unsigned(), rect.height().cast_unsigned())
            .to_physical(scale_factor),
    )
}

/// The monitor's work area, as Tauri's `MonitorExt::work_area` reads it
/// from `GetMonitorInfoW` (`src/monitor/windows.rs:9-33`).
#[cfg(windows)]
#[allow(unsafe_code)]
fn work_area(handle: &MonitorHandle) -> (PhysicalPosition<i32>, PhysicalSize<u32>) {
    use tao::platform::windows::MonitorHandleExtWindows;
    use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, HMONITOR, MONITORINFO};

    let mut info = MONITORINFO {
        cbSize: u32::try_from(std::mem::size_of::<MONITORINFO>()).unwrap_or(u32::MAX),
        ..Default::default()
    };
    let hmonitor = HMONITOR(std::ptr::with_exposed_provenance_mut(
        handle.hmonitor().cast_unsigned(),
    ));
    // SAFETY: `hmonitor` is the monitor handle tao enumerated for this
    // monitor (tao 0.34.5 `platform/windows.rs:388-395`), and `info` is a
    // live `MONITORINFO` whose `cbSize` names its size, as
    // `GetMonitorInfoW` requires; the call writes only within it.
    let status = unsafe { GetMonitorInfoW(hmonitor, &raw mut info) };
    if !status.as_bool() {
        return (handle.position(), handle.size());
    }
    let work = info.rcWork;
    (
        PhysicalPosition::new(work.left, work.top),
        PhysicalSize::new(
            (work.right - work.left).cast_unsigned(),
            (work.bottom - work.top).cast_unsigned(),
        ),
    )
}

/// The outer position that centers a window of `window_size` in the
/// monitor's work area (`src/window/mod.rs:58-67`).
#[cfg(not(target_os = "macos"))]
fn center_position(
    window_size: PhysicalSize<u32>,
    target_monitor: &MonitorHandle,
) -> PhysicalPosition<i32> {
    let (position, size) = work_area(target_monitor);
    PhysicalPosition::new(
        (size.width.cast_signed() - window_size.width.cast_signed()) / 2 + position.x,
        (size.height.cast_signed() - window_size.height.cast_signed()) / 2 + position.y,
    )
}

/// Centers the window as `-[NSWindow center]` does, as Tauri's
/// `WindowExt::center` asks it to (`src/window/macos.rs:41-44`).
#[cfg(target_os = "macos")]
#[allow(unsafe_code)]
fn center(window: &Window) {
    use objc2_app_kit::NSWindow;
    use tao::platform::macos::WindowExtMacOS;

    let ns_window = window.ns_window().cast::<NSWindow>();
    // SAFETY: as in `raw_handle::window_number`: `ns_window` points at the
    // `Retained<NSWindow>` tao's window holds while it lives (tao 0.34.5
    // `platform/macos.rs:88-92`), so it is non-null, aligned, and live
    // while `window` is borrowed; the caller is on the main thread, which
    // owns the window (`thread_bound.rs`).
    let ns_window = unsafe { &*ns_window };
    ns_window.center();
}

/// Centers the window in its monitor's work area, as Tauri's
/// `WindowExt::center` does on Linux (`src/window/linux.rs:24-30`).
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
fn center(window: &Window) {
    if let Some(monitor) = window.current_monitor() {
        window.set_outer_position(center_position(window.outer_size(), &monitor));
    }
}

/// Centers the window in its monitor's work area, as Tauri's
/// `WindowExt::center` does on Windows, measuring a decorated window's
/// height without its invisible resize border (`src/window/windows.rs:22-46`).
#[cfg(windows)]
#[allow(unsafe_code)]
fn center(window: &Window) {
    use tao::platform::windows::WindowExtWindows;
    use windows::Win32::Foundation::{HWND, RECT};
    use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_EXTENDED_FRAME_BOUNDS};

    let Some(monitor) = window.current_monitor() else {
        return;
    };
    let mut window_size = window.outer_size();
    if window.is_decorated() {
        let mut rect = RECT::default();
        let hwnd = HWND(std::ptr::with_exposed_provenance_mut(
            window.hwnd().cast_unsigned(),
        ));
        // SAFETY: `hwnd` is the live window tao created (tao 0.34.5
        // `platform/windows.rs:201-203`), and the attribute's buffer is
        // `rect`, a live `RECT` whose size the call is given, as
        // `DWMWA_EXTENDED_FRAME_BOUNDS` requires.
        let result = unsafe {
            DwmGetWindowAttribute(
                hwnd,
                DWMWA_EXTENDED_FRAME_BOUNDS,
                (&raw mut rect).cast(),
                u32::try_from(std::mem::size_of::<RECT>()).unwrap_or(u32::MAX),
            )
        };
        if result.is_ok() {
            window_size.height = (rect.bottom - rect.top).cast_unsigned();
        }
    }
    window.set_outer_position(center_position(window_size, &monitor));
}

/// The size of the window's webview, in physical pixels, or `None` without
/// an open one. On macOS wry makes its own view the window's content view
/// (wry 0.54.1 `src/wkwebview/mod.rs:616-636`), so the view tao measures
/// for `inner_size` no longer follows the window; Tauri measures the
/// webview instead when the window has one and no child webviews
/// (`src/lib.rs:5195-5212`), and so does this.
#[cfg(target_os = "macos")]
fn webview_size(
    window: &Window,
    webview: Option<&RbWebView>,
) -> Result<Option<PhysicalSize<u32>>, Error> {
    use wry::WebViewExtMacOS;

    let Some(webview) = webview else {
        return Ok(None);
    };
    Ok(webview.open_webview()?.map(|webview| {
        let frame = webview.webview().frame();
        let logical: LogicalSize<f64> = (frame.size.width, frame.size.height).into();
        logical.to_physical(window.scale_factor())
    }))
}
// SPDX-SnippetEnd

/// A getter answering `Option<bool>` from the `tao::window::Window` method
/// of the same name.
macro_rules! flag_getters {
    ($($name:ident),* $(,)?) => {
        $(
            #[doc = concat!("tao's `Window::", stringify!($name), "`, or `nil` once closed.")]
            ///
            /// # Errors
            ///
            /// Returns `ThreadError` off the window's thread.
            pub fn $name(&self) -> Result<Option<bool>, Error> {
                Ok(self.open_window()?.map(|window| window.$name()))
            }
        )*
    };
}

/// A setter passing one `bool` to the `tao::window::Window` method of the
/// same name.
macro_rules! flag_setters {
    ($($name:ident),* $(,)?) => {
        $(
            #[doc = concat!("tao's `Window::", stringify!($name), "`; a closed window ignores it.")]
            ///
            /// # Errors
            ///
            /// Returns `ThreadError` off the window's thread.
            pub fn $name(&self, value: bool) -> Result<(), Error> {
                if let Some(window) = self.open_window()? {
                    window.$name(value);
                }
                Ok(())
            }
        )*
    };
}

impl RbWindow {
    flag_getters!(
        is_minimized,
        is_maximized,
        is_focused,
        is_decorated,
        is_resizable,
        is_maximizable,
        is_minimizable,
        is_closable,
        is_visible,
        is_always_on_top,
    );

    flag_setters!(
        set_maximizable,
        set_minimizable,
        set_closable,
        set_maximized,
        set_minimized,
        set_visible,
        set_always_on_bottom,
        set_visible_on_all_workspaces,
        set_content_protection,
        set_focusable,
        set_cursor_visible,
    );

    /// tao's `Window::scale_factor`, or `nil` once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn scale_factor(&self) -> Result<Option<f64>, Error> {
        Ok(self.open_window()?.map(|window| window.scale_factor()))
    }

    /// `[[x, y]]` from tao's `Window::inner_position`, `[nil]` where tao
    /// does not support it, or `nil` once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn inner_position(&self) -> Result<Option<Maybe<(i32, i32)>>, Error> {
        Ok(self
            .open_window()?
            .map(|window| (window.inner_position().ok().map(|p| (p.x, p.y)),)))
    }

    /// `[[x, y]]` from tao's `Window::outer_position`, `[nil]` where tao
    /// does not support it, or `nil` once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn outer_position(&self) -> Result<Option<Maybe<(i32, i32)>>, Error> {
        Ok(self
            .open_window()?
            .map(|window| (window.outer_position().ok().map(|p| (p.x, p.y)),)))
    }

    /// `[width, height]` of the window's inner size in physical pixels, or
    /// `nil` once closed. On macOS `webview`, the window's webview, gives
    /// the size (see [`webview_size`]).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's or the webview's thread.
    pub fn inner_size(&self, webview: Option<&RbWebView>) -> Result<Option<(u32, u32)>, Error> {
        let Some(window) = self.open_window()? else {
            return Ok(None);
        };
        #[cfg(target_os = "macos")]
        let size = webview_size(&window, webview)?.unwrap_or_else(|| window.inner_size());
        // Elsewhere tao measures the window (`src/lib.rs:5214-5222`).
        #[cfg(not(target_os = "macos"))]
        let size = {
            let _ = webview;
            window.inner_size()
        };
        Ok(Some((size.width, size.height)))
    }

    /// `[width, height]` from tao's `Window::outer_size`, or `nil` once
    /// closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn outer_size(&self) -> Result<Option<(u32, u32)>, Error> {
        Ok(self.open_window()?.map(|window| {
            let size = window.outer_size();
            (size.width, size.height)
        }))
    }

    /// Whether tao reports the window fullscreen, as the `IsFullscreen` arm
    /// asks (`src/lib.rs:3283`), or `nil` once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn is_fullscreen(&self) -> Result<Option<bool>, Error> {
        Ok(self
            .open_window()?
            .map(|window| window.fullscreen().is_some()))
    }

    /// The name of tao's `Window::theme`, or `nil` once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn theme(&self) -> Result<Option<&'static str>, Error> {
        Ok(self.open_window()?.map(|window| theme_name(window.theme())))
    }

    /// `[monitor]` for tao's `Window::current_monitor` (`[nil]` when it has
    /// none), or `nil` once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn current_monitor(&self) -> Result<Option<Maybe<MonitorValue>>, Error> {
        Ok(self
            .open_window()?
            .map(|window| (window.current_monitor().as_ref().map(monitor),)))
    }

    /// `[monitor]` for tao's `Window::primary_monitor` (`[nil]` when it has
    /// none), or `nil` once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn primary_monitor(&self) -> Result<Option<Maybe<MonitorValue>>, Error> {
        Ok(self
            .open_window()?
            .map(|window| (window.primary_monitor().as_ref().map(monitor),)))
    }

    /// `[monitor]` for tao's `Window::monitor_from_point` (`[nil]` when no
    /// monitor holds the point), or `nil` once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn monitor_from_point(&self, x: f64, y: f64) -> Result<Option<Maybe<MonitorValue>>, Error> {
        Ok(self
            .open_window()?
            .map(|window| (window.monitor_from_point(x, y).as_ref().map(monitor),)))
    }

    /// Every monitor tao's `Window::available_monitors` lists, or `nil`
    /// once closed.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn available_monitors(&self) -> Result<Option<Vec<MonitorValue>>, Error> {
        Ok(self
            .open_window()?
            .map(|window| window.available_monitors().map(|m| monitor(&m)).collect()))
    }

    /// Centers the window (see [`center`]); a closed window ignores it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn center(&self) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            center(&window);
        }
        Ok(())
    }

    /// tao's `Window::request_user_attention`, `nil` to cancel a request.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread, or `ArgumentError`
    /// for a name `Tokra::UserAttentionType` does not have.
    pub fn request_user_attention(&self, request_type: Option<RString>) -> Result<(), Error> {
        let request_type = request_type
            .map(|name| user_attention_type(&name.to_string()?))
            .transpose()?;
        if let Some(window) = self.open_window()? {
            window.request_user_attention(request_type);
        }
        Ok(())
    }

    /// tao's `Window::set_inner_size`.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_inner_size(&self, dimensions: Dimensions) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_inner_size(size(dimensions));
        }
        Ok(())
    }

    /// tao's `Window::set_min_inner_size`; `nil` removes the minimum.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_min_inner_size(&self, dimensions: Option<Dimensions>) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_min_inner_size(dimensions.map(size));
        }
        Ok(())
    }

    /// tao's `Window::set_max_inner_size`; `nil` removes the maximum.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_max_inner_size(&self, dimensions: Option<Dimensions>) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_max_inner_size(dimensions.map(size));
        }
        Ok(())
    }

    /// tao's `Window::set_outer_position`.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_outer_position(&self, dimensions: Dimensions) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_outer_position(position(dimensions));
        }
        Ok(())
    }

    /// Borderless fullscreen on the current monitor, or none, as the
    /// `SetFullscreen` arm asks tao (`src/lib.rs:3415-3421`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_fullscreen(&self, fullscreen: bool) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_fullscreen(fullscreen.then_some(Fullscreen::Borderless(None)));
        }
        Ok(())
    }

    /// macOS's fullscreen without a new Space, through tao's
    /// `WindowExtMacOS::set_simple_fullscreen`, whose answer Tauri drops
    /// (`src/lib.rs:3424-3427`); elsewhere `set_fullscreen`, as Tauri's
    /// `Window::set_simple_fullscreen` does (`window/mod.rs:1981-1993`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_simple_fullscreen(&self, enable: bool) -> Result<(), Error> {
        #[cfg(target_os = "macos")]
        {
            use tao::platform::macos::WindowExtMacOS;
            if let Some(window) = self.open_window()? {
                window.set_simple_fullscreen(enable);
            }
            Ok(())
        }
        #[cfg(not(target_os = "macos"))]
        self.set_fullscreen(enable)
    }

    /// tao's `Window::set_focus`.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_focus(&self) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            window.set_focus();
        }
        Ok(())
    }

    /// tao's `set_skip_taskbar` on Windows and Linux, whose answer Tauri
    /// drops; nothing on macOS, which has no taskbar
    /// (`src/lib.rs:3438-3448`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_skip_taskbar(&self, skip: bool) -> Result<(), Error> {
        let window = self.open_window()?;
        #[cfg(any(
            windows,
            target_os = "linux",
            target_os = "dragonfly",
            target_os = "freebsd",
            target_os = "netbsd",
            target_os = "openbsd"
        ))]
        if let Some(window) = window {
            #[cfg(not(windows))]
            use tao::platform::unix::WindowExtUnix;
            #[cfg(windows)]
            use tao::platform::windows::WindowExtWindows;
            let _ = window.set_skip_taskbar(skip);
        }
        #[cfg(target_os = "macos")]
        let _ = (window, skip);
        Ok(())
    }

    /// tao's `Window::set_cursor_grab`, whose answer Tauri drops.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_cursor_grab(&self, grab: bool) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            let _ = window.set_cursor_grab(grab);
        }
        Ok(())
    }

    /// tao's `Window::set_cursor_icon`.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_cursor_icon(&self, icon: RString) -> Result<(), Error> {
        let icon = cursor_icon(&icon.to_string()?);
        if let Some(window) = self.open_window()? {
            window.set_cursor_icon(icon);
        }
        Ok(())
    }

    /// tao's `Window::set_cursor_position`, whose answer Tauri drops.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn set_cursor_position(&self, dimensions: Dimensions) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            let _ = window.set_cursor_position(position(dimensions));
        }
        Ok(())
    }

    /// tao's `Window::drag_window`, whose answer Tauri drops.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread.
    pub fn drag_window(&self) -> Result<(), Error> {
        if let Some(window) = self.open_window()? {
            let _ = window.drag_window();
        }
        Ok(())
    }

    /// tao's `Window::drag_resize_window`, whose answer Tauri drops.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread, or `ArgumentError`
    /// for a name `Tokra::ResizeDirection` does not have.
    pub fn drag_resize_window(&self, direction: RString) -> Result<(), Error> {
        let direction = resize_direction(&direction.to_string()?)?;
        if let Some(window) = self.open_window()? {
            let _ = window.drag_resize_window(direction);
        }
        Ok(())
    }

    /// tao's `Window::set_theme`; `nil` follows the system.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the window's thread, or `ArgumentError`
    /// for a name `Tokra::Theme` does not have.
    pub fn set_theme(&self, name: Option<RString>) -> Result<(), Error> {
        let name = name.map(RString::to_string).transpose()?;
        let theme = theme(name.as_deref())?;
        if let Some(window) = self.open_window()? {
            window.set_theme(theme);
        }
        Ok(())
    }
}

/// Define the getters and setters on `Tokra::Native::Window`.
///
/// # Errors
///
/// Returns an error if method definition fails.
pub fn define_methods(class: RClass) -> Result<(), Error> {
    macro_rules! define {
        ($($name:ident / $arity:tt),* $(,)?) => {
            $(class.define_method(stringify!($name), method!(RbWindow::$name, $arity))?;)*
        };
    }
    define!(
        scale_factor / 0,
        inner_position / 0,
        outer_position / 0,
        inner_size / 1,
        outer_size / 0,
        is_fullscreen / 0,
        is_minimized / 0,
        is_maximized / 0,
        is_focused / 0,
        is_decorated / 0,
        is_resizable / 0,
        is_maximizable / 0,
        is_minimizable / 0,
        is_closable / 0,
        is_visible / 0,
        is_always_on_top / 0,
        theme / 0,
        current_monitor / 0,
        primary_monitor / 0,
        monitor_from_point / 2,
        available_monitors / 0,
        center / 0,
        request_user_attention / 1,
        set_maximizable / 1,
        set_minimizable / 1,
        set_closable / 1,
        set_maximized / 1,
        set_minimized / 1,
        set_visible / 1,
        set_always_on_bottom / 1,
        set_visible_on_all_workspaces / 1,
        set_content_protection / 1,
        set_focusable / 1,
        set_cursor_visible / 1,
        set_inner_size / 1,
        set_min_inner_size / 1,
        set_max_inner_size / 1,
        set_outer_position / 1,
        set_fullscreen / 1,
        set_simple_fullscreen / 1,
        set_focus / 0,
        set_skip_taskbar / 1,
        set_cursor_grab / 1,
        set_cursor_icon / 1,
        set_cursor_position / 1,
        drag_window / 0,
        drag_resize_window / 1,
        set_theme / 1,
    );
    Ok(())
}
