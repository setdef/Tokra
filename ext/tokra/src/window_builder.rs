// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! The rows of `Tokra::WindowBuilder`, read into tao's `WindowBuilder`
//! (plan 052, phase 3).
//!
//! Ruby hands `Native::Window#open` one Hash of plain values, Tauri's
//! defaults already in it (decision c2). [`Attributes::read`] turns it into
//! tao's builder on the main thread, as tauri-runtime-wry's
//! `WindowBuilderWrapper` sets each row (`src/lib.rs:813-1260`), and keeps
//! what tao does not hold: `center`, the overflow margin, the parent, and
//! on macOS the tabbing identifier. [`Attributes::build`] then does what
//! `create_window` does before tao builds the window (`src/lib.rs:4318-4436`):
//! macOS's automatic tabbing, the centering and overflow sums, and the
//! parent's relation. No Ruby value outlives `read`, except the parent's
//! `Native::Window`, borrowed from the Hash for the length of `open`.
//!
//! A key the Hash lacks keeps tao's default, so a hand caller may pass
//! `{title: "x"}`; `Tokra::WindowBuilder` always passes every key.

use magnus::{Error, RHash, Ruby, TryConvert};
use tao::dpi::{
    LogicalPosition, LogicalSize, LogicalUnit, PhysicalPosition, PhysicalSize, PhysicalUnit,
    PixelUnit, Position, Size,
};
use tao::event_loop::EventLoopWindowTarget;
use tao::monitor::MonitorHandle;
use tao::window::{Fullscreen, Window, WindowBuilder, WindowSizeConstraints};

use crate::icon::RbIcon;
use crate::runtime_error;
use crate::user_event::UserEvent;
use crate::window::RbWindow;
use crate::window_state::Dimensions;

/// A size limit as Ruby passes it: whether it is physical, then its
/// number.
type Unit = (bool, f64);

/// The four limits of a `WindowSizeConstraints`, in Tauri's order.
type Limits = (Option<Unit>, Option<Unit>, Option<Unit>, Option<Unit>);

/// A color as Ruby passes it: red, green, blue, and alpha.
type Rgba = (u8, u8, u8, u8);

/// dpi's `PixelUnit` for a Ruby limit, as `window_ext.rs` makes one.
fn pixel_unit((physical, value): Unit) -> PixelUnit {
    if physical {
        PixelUnit::from(PhysicalUnit::new(value))
    } else {
        PixelUnit::from(LogicalUnit::new(value))
    }
}

/// The value under the Symbol `name`, or `None` when the Hash lacks it or
/// holds `nil`.
fn get<T: TryConvert>(ruby: &Ruby, attributes: RHash, name: &str) -> Result<Option<T>, Error> {
    attributes.lookup::<_, Option<T>>(ruby.to_symbol(name))
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The window builder's rows and create_window's sums adapted from
//                      tauri-runtime-wry/src/lib.rs WindowBuilderWrapper and create_window,
//                      and src/window/mod.rs calculate_window_center_position

/// tao's builder for one window, with what `create_window` reads beside it.
pub struct Attributes<'a> {
    builder: WindowBuilder,
    center: bool,
    prevent_overflow: Option<Size>,
    parent: Option<&'a RbWindow>,
    #[cfg(target_os = "macos")]
    tabbing_identifier: Option<String>,
}

impl Attributes<'_> {
    /// Reads `attributes` as `WindowBuilderWrapper` sets each row.
    ///
    /// # Errors
    ///
    /// Returns `TypeError` for a value of the wrong type, and
    /// `ArgumentError` for a theme or title bar style the Ruby classes do
    /// not have.
    pub fn read(ruby: &Ruby, attributes: RHash) -> Result<Self, Error> {
        let mut builder = WindowBuilder::new();
        if let Some(title) = get::<String>(ruby, attributes, "title")? {
            builder = builder.with_title(title);
        }
        if let Some((width, height)) = get::<(f64, f64)>(ruby, attributes, "inner_size")? {
            builder = builder.with_inner_size(LogicalSize::new(width, height));
        }
        if let Some((x, y)) = get::<(f64, f64)>(ruby, attributes, "position")? {
            builder = builder.with_position(LogicalPosition::new(x, y));
        }
        if let Some(limits) = get::<Limits>(ruby, attributes, "inner_size_constraints")? {
            let (min_width, min_height, max_width, max_height) = limits;
            builder = builder.with_inner_size_constraints(WindowSizeConstraints::new(
                min_width.map(pixel_unit),
                min_height.map(pixel_unit),
                max_width.map(pixel_unit),
                max_height.map(pixel_unit),
            ));
        }
        builder = Self::read_flags(ruby, attributes, builder)?;
        if let Some(icon) = get::<&RbIcon>(ruby, attributes, "icon")? {
            builder = builder.with_window_icon(Some(icon.icon()));
        }
        if let Some(name) = get::<String>(ruby, attributes, "theme")? {
            builder = builder.with_theme(crate::window_state::theme(Some(&name))?);
        }
        if let Some(color) = get::<Rgba>(ruby, attributes, "background_color")? {
            builder = builder.with_background_color(color);
        }
        builder = Self::read_platform(ruby, attributes, builder)?;
        Ok(Self {
            builder,
            center: get::<bool>(ruby, attributes, "center")?.unwrap_or(false),
            prevent_overflow: get::<Dimensions>(ruby, attributes, "prevent_overflow")?
                .map(crate::window_state::size),
            parent: get::<&RbWindow>(ruby, attributes, "parent")?,
            #[cfg(target_os = "macos")]
            tabbing_identifier: get::<String>(ruby, attributes, "tabbing_identifier")?,
        })
    }

    /// The boolean rows every platform has (`src/lib.rs:1014-1101`).
    fn read_flags(
        ruby: &Ruby,
        attributes: RHash,
        mut builder: WindowBuilder,
    ) -> Result<WindowBuilder, Error> {
        let flag = |name: &str| get::<bool>(ruby, attributes, name);
        if let Some(value) = flag("resizable")? {
            builder = builder.with_resizable(value);
        }
        if let Some(value) = flag("maximizable")? {
            builder = builder.with_maximizable(value);
        }
        if let Some(value) = flag("minimizable")? {
            builder = builder.with_minimizable(value);
        }
        if let Some(value) = flag("closable")? {
            builder = builder.with_closable(value);
        }
        if let Some(value) = flag("fullscreen")? {
            builder = builder.with_fullscreen(value.then_some(Fullscreen::Borderless(None)));
        }
        if let Some(value) = flag("focused")? {
            builder = builder.with_focused(value);
        }
        if let Some(value) = flag("focusable")? {
            builder = builder.with_focusable(value);
        }
        if let Some(value) = flag("maximized")? {
            builder = builder.with_maximized(value);
        }
        if let Some(value) = flag("visible")? {
            builder = builder.with_visible(value);
        }
        if let Some(value) = flag("decorations")? {
            builder = builder.with_decorations(value);
        }
        if let Some(value) = flag("always_on_bottom")? {
            builder = builder.with_always_on_bottom(value);
        }
        if let Some(value) = flag("always_on_top")? {
            builder = builder.with_always_on_top(value);
        }
        if let Some(value) = flag("visible_on_all_workspaces")? {
            builder = builder.with_visible_on_all_workspaces(value);
        }
        if let Some(value) = flag("content_protected")? {
            builder = builder.with_content_protection(value);
        }
        Ok(builder)
    }

    /// The rows only Windows reads: `transparent`, `skip_taskbar`,
    /// `window_classname`, `shadow`, and `drag_and_drop`
    /// (`src/lib.rs:1070-1074`, `1103-1113`, `1145-1149`, `1209-1221`,
    /// `1251-1255`).
    #[cfg(windows)]
    fn read_platform(
        ruby: &Ruby,
        attributes: RHash,
        mut builder: WindowBuilder,
    ) -> Result<WindowBuilder, Error> {
        use tao::platform::windows::WindowBuilderExtWindows;

        if let Some(value) = get::<bool>(ruby, attributes, "transparent")? {
            builder = builder.with_transparent(value);
        }
        if let Some(value) = get::<bool>(ruby, attributes, "skip_taskbar")? {
            builder = builder.with_skip_taskbar(value);
        }
        if let Some(classname) = get::<String>(ruby, attributes, "window_classname")? {
            builder = builder.with_window_classname(classname);
        }
        if let Some(value) = get::<bool>(ruby, attributes, "shadow")? {
            builder = builder.with_undecorated_shadow(value);
        }
        if let Some(value) = get::<bool>(ruby, attributes, "drag_and_drop")? {
            builder = builder.with_drag_and_drop(value);
        }
        Ok(builder)
    }

    /// The rows only Linux reads: `transparent`, `skip_taskbar`, and
    /// `cursor_moved_event`, which only `with_config` sets
    /// (`src/lib.rs:1070-1074`, `1209-1221`, `871-881`).
    #[cfg(any(
        target_os = "linux",
        target_os = "dragonfly",
        target_os = "freebsd",
        target_os = "netbsd",
        target_os = "openbsd"
    ))]
    fn read_platform(
        ruby: &Ruby,
        attributes: RHash,
        mut builder: WindowBuilder,
    ) -> Result<WindowBuilder, Error> {
        use tao::platform::unix::WindowBuilderExtUnix;

        if let Some(value) = get::<bool>(ruby, attributes, "transparent")? {
            builder = builder.with_transparent(value);
        }
        if let Some(value) = get::<bool>(ruby, attributes, "skip_taskbar")? {
            builder = builder.with_skip_taskbar(value);
        }
        Ok(with_cursor_moved_event(
            builder,
            get::<bool>(ruby, attributes, CURSOR_MOVED_EVENT)?,
            WindowBuilderExtUnix::with_cursor_moved_event,
        ))
    }

    /// The rows only macOS reads: `shadow`, `title_bar_style`,
    /// `hidden_title`, and `tabbing_identifier` (`src/lib.rs:1103-1113`,
    /// `1151-1195`). `transparent` needs `macos-private-api` there, which
    /// Tokra does not build in (plan 052, question 2), so it is not read.
    #[cfg(target_os = "macos")]
    fn read_platform(
        ruby: &Ruby,
        attributes: RHash,
        mut builder: WindowBuilder,
    ) -> Result<WindowBuilder, Error> {
        use tao::platform::macos::WindowBuilderExtMacOS;

        if let Some(value) = get::<bool>(ruby, attributes, "shadow")? {
            builder = builder.with_has_shadow(value);
        }
        if let Some(name) = get::<String>(ruby, attributes, "title_bar_style")? {
            let (transparent, fullsize) =
                crate::taskbar::title_bar(&name).map_err(crate::window_state::argument_error)?;
            builder = builder
                .with_titlebar_transparent(transparent)
                .with_fullsize_content_view(fullsize);
        }
        if let Some(value) = get::<bool>(ruby, attributes, "hidden_title")? {
            builder = builder.with_title_hidden(value);
        }
        if let Some(identifier) = get::<String>(ruby, attributes, "tabbing_identifier")? {
            builder = builder.with_tabbing_identifier(&identifier);
        }
        Ok(builder)
    }

    /// Builds the window from `target` as `create_window` does: macOS's
    /// automatic tabbing turned off without a tabbing identifier or for a
    /// transparent or undecorated window (`src/lib.rs:4348-4356`), the
    /// centering and overflow sums (`:4359-4436`), and the parent's
    /// relation, then tao's build.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` or `RuntimeError` when the parent is on
    /// another thread or closed, and `RuntimeError` when tao fails.
    pub fn build(self, target: &EventLoopWindowTarget<UserEvent>) -> Result<Window, Error> {
        let mut builder = self.builder;
        refuse_inverted(target, &builder.window.inner_size_constraints)?;
        #[cfg(target_os = "macos")]
        if self.tabbing_identifier.is_none()
            || builder.window.transparent
            || !builder.window.decorations
        {
            use tao::platform::macos::WindowBuilderExtMacOS;
            builder = builder.with_automatic_window_tabbing(false);
        }
        if self.prevent_overflow.is_some() || self.center {
            if let Some(monitor) = target_monitor(target, builder.window.position) {
                let placement = place(
                    builder.window.inner_size,
                    &builder.window.inner_size_constraints,
                    self.prevent_overflow,
                    self.center,
                    &Screen::of(&monitor),
                    frame(builder.window.decorations),
                );
                if let Some(inner_size) = placement.inner_size {
                    builder.window.inner_size = Some(inner_size.into());
                }
                if let Some(position) = placement.position {
                    builder = builder.with_position(position);
                }
            }
        }
        let parent = self.parent.map(RbWindow::window).transpose()?;
        if let Some(parent) = &parent {
            builder = with_parent(builder, parent);
        }
        builder
            .build(target)
            .map_err(|e| Error::new(runtime_error(), e.to_string()))
    }
}

/// The key `Tokra::WindowBuilder` sends for tao's Linux row for the
/// pointer's `CursorMoved` events, which `with_config` turns off: "Mouse
/// event is disabled on Linux since sudden event bursts could block event
/// loop" (`src/lib.rs:871-881`; tao `src/platform/unix.rs:150-153`,
/// `192-195`).
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
const CURSOR_MOVED_EVENT: &str = "cursor_moved_event";

/// `builder` with the `cursor_moved_event` row Ruby sent handed to `set`,
/// or as it was when the Hash lacks it, which keeps tao's default of on.
/// `read_platform` passes tao's own `with_cursor_moved_event` as `set`, so
/// no code of Tokra's stands between the value and tao. tao keeps the flag
/// where no caller can read it back, so a test passes a recorder instead.
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
fn with_cursor_moved_event<B>(
    builder: B,
    cursor_moved: Option<bool>,
    set: impl FnOnce(B, bool) -> B,
) -> B {
    match cursor_moved {
        Some(cursor_moved) => set(builder, cursor_moved),
        None => builder,
    }
}

/// What `open` raises for a minimum inner size larger than the maximum.
const INVERTED_CONSTRAINTS: &str = "the window's minimum inner size is larger than its maximum";

/// Whether dpi's `Size::clamp` can take `constraints` at `scale_factor`:
/// it clamps each side with `f64::clamp`, which panics when the minimum is
/// above the maximum or either is NaN (dpi 0.1.1 `src/lib.rs:715-725`). tao
/// clamps a new window's size with it as it builds one (`platform_impl/macos/window.rs:194-199`,
/// `platform_impl/windows/window.rs:1211`), and so do the sums.
fn check_constraints(constraints: &WindowSizeConstraints, scale_factor: f64) -> Result<(), String> {
    let min: PhysicalSize<f64> = constraints.min_size_physical(scale_factor);
    let max: PhysicalSize<f64> = constraints.max_size_physical(scale_factor);
    if min.width <= max.width && min.height <= max.height {
        Ok(())
    } else {
        Err(INVERTED_CONSTRAINTS.to_string())
    }
}

/// Refuses `constraints` that would panic in tao's clamp at the scale
/// factor of any monitor the window could open on, or at 1 without one.
/// Tauri panics there, ending the process; Tokra raises `RuntimeError`, so
/// the window fails as any other does (plan 052, review fix 1).
///
/// # Errors
///
/// Returns `RuntimeError` with [`INVERTED_CONSTRAINTS`].
fn refuse_inverted(
    target: &EventLoopWindowTarget<UserEvent>,
    constraints: &WindowSizeConstraints,
) -> Result<(), Error> {
    target
        .available_monitors()
        .map(|monitor| monitor.scale_factor())
        .chain(std::iter::once(1.0))
        .try_for_each(|scale_factor| check_constraints(constraints, scale_factor))
        .map_err(|message| Error::new(runtime_error(), message))
}

/// The parent as Tauri's `WindowBuilder::parent` relates it on Windows: an
/// owner (`window/mod.rs:728-731`, `src/lib.rs:1115-1119`).
#[cfg(windows)]
fn with_parent(builder: WindowBuilder, parent: &Window) -> WindowBuilder {
    use tao::platform::windows::{WindowBuilderExtWindows, WindowExtWindows};

    builder.with_owner_window(parent.hwnd())
}

/// The parent as Tauri's `WindowBuilder::parent` relates it on Linux:
/// transient for it (`window/mod.rs:733-742`, `src/lib.rs:1133-1143`).
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
fn with_parent(builder: WindowBuilder, parent: &Window) -> WindowBuilder {
    use tao::platform::unix::{WindowBuilderExtUnix, WindowExtUnix};

    builder.with_transient_for(parent.gtk_window())
}

/// The parent as Tauri's `WindowBuilder::parent` relates it on macOS: an
/// `AppKit` child window (`window/mod.rs:744-747`, `src/lib.rs:1127-1131`).
/// tao adds it with `addChildWindow:ordered:` as it builds the window, while
/// the caller holds the parent's borrow, so the parent lives through it.
#[cfg(target_os = "macos")]
fn with_parent(builder: WindowBuilder, parent: &Window) -> WindowBuilder {
    use tao::platform::macos::{WindowBuilderExtMacOS, WindowExtMacOS};

    builder.with_parent_window(parent.ns_window())
}

/// The monitor `create_window` sums against: the one holding the asked-for
/// position, or the primary one (`src/lib.rs:4360-4376`).
fn target_monitor(
    target: &EventLoopWindowTarget<UserEvent>,
    position: Option<Position>,
) -> Option<MonitorHandle> {
    let Some(position) = position else {
        return target.primary_monitor();
    };
    target.available_monitors().find(|monitor| {
        let point = position.to_physical::<i32>(monitor.scale_factor());
        holds(monitor.position(), monitor.size(), point)
    })
}

/// Whether the rectangle at `origin` of `size` holds `point`, its right and
/// bottom edges out (`src/lib.rs:4368-4371`).
const fn holds(
    origin: PhysicalPosition<i32>,
    size: PhysicalSize<u32>,
    point: PhysicalPosition<i32>,
) -> bool {
    origin.x <= point.x
        && point.x < origin.x.saturating_add(size.width.cast_signed())
        && origin.y <= point.y
        && point.y < origin.y.saturating_add(size.height.cast_signed())
}

/// A monitor as the sums read it: its work area and scale factor.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Screen {
    work_position: PhysicalPosition<i32>,
    work_size: PhysicalSize<u32>,
    scale_factor: f64,
}

impl Screen {
    /// The monitor's work area, as Tauri's `MonitorExt::work_area` reads it
    /// (`window_state.rs`).
    fn of(monitor: &MonitorHandle) -> Self {
        let (work_position, work_size) = crate::window_state::work_area(monitor);
        Self {
            work_position,
            work_size,
            scale_factor: monitor.scale_factor(),
        }
    }
}

/// What a decorated window adds to its inner size on Windows, in physical
/// pixels: the shadow's width, which counts toward centering, and the
/// title bar's height, which counts toward both sums (`src/lib.rs:4389-4404`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Frame {
    shadow_width: u32,
    top: u32,
}

/// The frame `AdjustWindowRect` gives `WS_OVERLAPPEDWINDOW`, for a decorated
/// window, as `create_window` asks it (`src/lib.rs:4393-4404`); none when
/// the call fails or the window is undecorated.
#[cfg(windows)]
#[allow(unsafe_code)]
fn frame(decorations: bool) -> Frame {
    use windows::Win32::Foundation::RECT;
    use windows::Win32::UI::WindowsAndMessaging::{AdjustWindowRect, WS_OVERLAPPEDWINDOW};

    if !decorations {
        return Frame::default();
    }
    let mut rect = RECT::default();
    // SAFETY: `rect` is a live, zeroed `RECT` on this stack frame, which
    // `AdjustWindowRect` reads as the client rectangle and overwrites with
    // the window rectangle, writing nothing else; `WS_OVERLAPPEDWINDOW` is a
    // style Win32 defines, as Tauri passes it (tauri-runtime-wry
    // `src/lib.rs:4398`). windows 0.61.3 takes the pointer as `*mut RECT`
    // (`Win32/UI/WindowsAndMessaging/mod.rs:2-5`).
    if unsafe { AdjustWindowRect(&raw mut rect, WS_OVERLAPPEDWINDOW, false) }.is_err() {
        return Frame::default();
    }
    Frame {
        shadow_width: (rect.right - rect.left).cast_unsigned(),
        top: rect.top.saturating_neg().cast_unsigned(),
    }
}

/// No frame counts off Windows (`src/lib.rs:4389-4392`).
#[cfg(not(windows))]
const fn frame(_decorations: bool) -> Frame {
    Frame {
        shadow_width: 0,
        top: 0,
    }
}

/// Where the sums put the window: a new inner size, when the overflow check
/// trimmed it, and a logical position, when it is centered.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Placement {
    inner_size: Option<PhysicalSize<u32>>,
    position: Option<LogicalPosition<f64>>,
}

/// `create_window`'s sums (`src/lib.rs:4377-4434`): the inner size asked for,
/// or 800 by 600, clamped by `constraints`; trimmed to the work area less
/// `prevent_overflow`'s margin when it overflows; and centered in the work
/// area when `center`. Tauri subtracts the margin from the work area as
/// `u32`, which panics or wraps for a wider margin; this saturates, so the
/// limit is zero (plan 052, decision c3).
fn place(
    inner_size: Option<Size>,
    constraints: &WindowSizeConstraints,
    prevent_overflow: Option<Size>,
    center: bool,
    screen: &Screen,
    frame: Frame,
) -> Placement {
    let scale_factor = screen.scale_factor;
    let desired = inner_size.unwrap_or_else(|| PhysicalSize::new(800, 600).into());
    // `build` refuses constraints the clamp would panic on; should any reach
    // here, the size goes unclamped rather than end the process.
    let clamped = if check_constraints(constraints, scale_factor).is_ok() {
        constraints.clamp(desired, scale_factor)
    } else {
        desired
    };
    let mut inner: PhysicalSize<u32> = clamped.to_physical(scale_factor);
    let mut window_size = inner;
    window_size.height = window_size.height.saturating_add(frame.top);
    let mut trimmed = None;
    if let Some(margin) = prevent_overflow {
        let margin: PhysicalSize<u32> = margin.to_physical(scale_factor);
        let limit = PhysicalSize::new(
            screen.work_size.width.saturating_sub(margin.width),
            screen.work_size.height.saturating_sub(margin.height),
        );
        if window_size.width > limit.width || window_size.height > limit.height {
            if window_size.width > limit.width {
                inner.width = inner.width.saturating_sub(window_size.width - limit.width);
                window_size.width = limit.width;
            }
            if window_size.height > limit.height {
                inner.height = inner
                    .height
                    .saturating_sub(window_size.height - limit.height);
                window_size.height = limit.height;
            }
            trimmed = Some(inner);
        }
    }
    let position = center.then(|| {
        window_size.width = window_size.width.saturating_add(frame.shadow_width);
        crate::window_state::centered_in(window_size, screen.work_position, screen.work_size)
            .to_logical(scale_factor)
    });
    Placement {
        inner_size: trimmed,
        position,
    }
}

// SPDX-SnippetEnd

#[cfg(test)]
mod tests {
    use super::*;

    /// A 1512-by-982 logical screen at 2x, its work area below a 37-point
    /// menu bar, as a `MacBook`'s.
    const SCREEN: Screen = Screen {
        work_position: PhysicalPosition { x: 0, y: 74 },
        work_size: PhysicalSize {
            width: 3024,
            height: 1890,
        },
        scale_factor: 2.0,
    };

    #[cfg(any(
        target_os = "linux",
        target_os = "dragonfly",
        target_os = "freebsd",
        target_os = "netbsd",
        target_os = "openbsd"
    ))]
    #[test]
    fn the_cursor_moved_event_row_reaches_the_setter_and_its_absence_keeps_taos_default() {
        let record = |mut calls: Vec<bool>, cursor_moved: bool| {
            calls.push(cursor_moved);
            calls
        };

        assert_eq!(
            with_cursor_moved_event(Vec::new(), Some(false), record),
            [false]
        );
        assert_eq!(
            with_cursor_moved_event(Vec::new(), Some(true), record),
            [true]
        );
        assert_eq!(
            with_cursor_moved_event(Vec::new(), None, record),
            Vec::<bool>::new()
        );
        // The key lib/tokra/window_builder.rb sends.
        assert_eq!(CURSOR_MOVED_EVENT, "cursor_moved_event");
    }

    fn logical(width: f64, height: f64) -> Size {
        LogicalSize::new(width, height).into()
    }

    #[test]
    fn a_centered_window_sits_in_the_middle_of_the_work_area() {
        let placement = place(
            Some(logical(400.0, 300.0)),
            &WindowSizeConstraints::default(),
            None,
            true,
            &SCREEN,
            Frame::default(),
        );
        // (3024 - 800) / 2 = 1112, (1890 - 600) / 2 + 74 = 719, halved.
        assert_eq!(placement.position, Some(LogicalPosition::new(556.0, 359.5)));
        assert_eq!(placement.inner_size, None);
    }

    #[test]
    fn without_a_size_tauri_centers_800_by_600_physical() {
        let placement = place(
            None,
            &WindowSizeConstraints::default(),
            None,
            true,
            &SCREEN,
            Frame::default(),
        );
        // (3024 - 800) / 2 = 1112, (1890 - 600) / 2 + 74 = 719.
        assert_eq!(placement.position, Some(LogicalPosition::new(556.0, 359.5)));
    }

    #[test]
    fn the_constraints_clamp_the_size_centered() {
        let minimum = WindowSizeConstraints::new(
            Some(LogicalUnit::new(600.0).into()),
            Some(LogicalUnit::new(500.0).into()),
            None,
            None,
        );
        let placement = place(
            Some(logical(400.0, 300.0)),
            &minimum,
            None,
            true,
            &SCREEN,
            Frame::default(),
        );
        // A 1200-by-1000 physical window: (3024 - 1200) / 2, (1890 - 1000) / 2 + 74.
        assert_eq!(placement.position, Some(LogicalPosition::new(456.0, 259.5)));
        assert_eq!(placement.inner_size, None, "clamping alone changes no size");
    }

    #[test]
    fn the_windows_frame_counts_toward_both_sums() {
        let frame = Frame {
            shadow_width: 16,
            top: 62,
        };
        let placement = place(
            Some(logical(400.0, 300.0)),
            &WindowSizeConstraints::default(),
            None,
            true,
            &SCREEN,
            frame,
        );
        // (3024 - 816) / 2 = 1104, (1890 - 662) / 2 + 74 = 688.
        assert_eq!(placement.position, Some(LogicalPosition::new(552.0, 344.0)));
    }

    #[test]
    fn an_overflowing_window_is_trimmed_to_the_work_area() {
        let zero = Some(PhysicalSize::new(0, 0).into());
        let placement = place(
            Some(logical(2000.0, 1200.0)),
            &WindowSizeConstraints::default(),
            zero,
            false,
            &SCREEN,
            Frame::default(),
        );
        assert_eq!(placement.inner_size, Some(PhysicalSize::new(3024, 1890)));
        assert_eq!(placement.position, None);
    }

    #[test]
    fn only_the_overflowing_side_is_trimmed_and_the_frame_is_left_room() {
        let zero = Some(PhysicalSize::new(0, 0).into());
        let frame = Frame {
            shadow_width: 16,
            top: 62,
        };
        let placement = place(
            Some(logical(400.0, 1200.0)),
            &WindowSizeConstraints::default(),
            zero,
            false,
            &SCREEN,
            frame,
        );
        assert_eq!(
            placement.inner_size,
            Some(PhysicalSize::new(800, 1890 - 62))
        );
    }

    #[test]
    fn a_window_that_fits_keeps_its_size() {
        let zero = Some(PhysicalSize::new(0, 0).into());
        let placement = place(
            Some(logical(400.0, 300.0)),
            &WindowSizeConstraints::default(),
            zero,
            false,
            &SCREEN,
            Frame::default(),
        );
        assert_eq!(
            placement,
            Placement {
                inner_size: None,
                position: None
            }
        );
    }

    #[test]
    fn a_margin_keeps_its_kind_and_shrinks_the_limit() {
        let margin = Some(logical(100.0, 50.0));
        let placement = place(
            Some(logical(2000.0, 1200.0)),
            &WindowSizeConstraints::default(),
            margin,
            true,
            &SCREEN,
            Frame::default(),
        );
        assert_eq!(placement.inner_size, Some(PhysicalSize::new(2824, 1790)));
        // The trimmed window is centered: (3024 - 2824) / 2, (1890 - 1790) / 2 + 74.
        assert_eq!(placement.position, Some(LogicalPosition::new(50.0, 62.0)));
    }

    #[test]
    fn a_margin_wider_than_the_work_area_saturates_where_tauri_would_panic() {
        let margin = Some(PhysicalSize::new(5000, 5000).into());
        let placement = place(
            Some(logical(400.0, 300.0)),
            &WindowSizeConstraints::default(),
            margin,
            false,
            &SCREEN,
            Frame::default(),
        );
        assert_eq!(placement.inner_size, Some(PhysicalSize::new(0, 0)));
    }

    fn inverted() -> WindowSizeConstraints {
        WindowSizeConstraints::new(
            Some(LogicalUnit::new(900.0).into()),
            Some(LogicalUnit::new(700.0).into()),
            Some(LogicalUnit::new(300.0).into()),
            Some(LogicalUnit::new(200.0).into()),
        )
    }

    #[test]
    fn a_minimum_larger_than_the_maximum_is_refused() {
        assert_eq!(
            check_constraints(&inverted(), 2.0),
            Err(INVERTED_CONSTRAINTS.to_string())
        );
        let wide_only = WindowSizeConstraints::new(
            Some(LogicalUnit::new(900.0).into()),
            None,
            Some(LogicalUnit::new(300.0).into()),
            None,
        );
        assert!(
            check_constraints(&wide_only, 1.0).is_err(),
            "the width alone suffices"
        );
        let tall_only = WindowSizeConstraints::new(
            None,
            Some(LogicalUnit::new(700.0).into()),
            None,
            Some(LogicalUnit::new(200.0).into()),
        );
        assert!(
            check_constraints(&tall_only, 1.0).is_err(),
            "the height alone suffices"
        );
        let nan =
            WindowSizeConstraints::new(Some(LogicalUnit::new(f64::NAN).into()), None, None, None);
        assert!(
            check_constraints(&nan, 1.0).is_err(),
            "a NaN limit is no limit f64::clamp takes"
        );
        assert_eq!(
            check_constraints(&WindowSizeConstraints::default(), 1.0),
            Ok(())
        );
        let equal = WindowSizeConstraints::new(
            Some(LogicalUnit::new(300.0).into()),
            None,
            Some(LogicalUnit::new(300.0).into()),
            None,
        );
        assert_eq!(check_constraints(&equal, 2.0), Ok(()));
    }

    #[test]
    fn the_sums_skip_a_clamp_that_would_panic() {
        let placement = place(
            Some(logical(400.0, 300.0)),
            &inverted(),
            None,
            true,
            &SCREEN,
            Frame::default(),
        );
        // The asked-for 800-by-600 physical, unclamped.
        assert_eq!(placement.position, Some(LogicalPosition::new(556.0, 359.5)));
    }

    #[test]
    fn a_monitor_holds_its_top_left_and_not_its_far_edges() {
        let origin = PhysicalPosition::new(100, 50);
        let size = PhysicalSize::new(200, 100);
        assert!(holds(origin, size, PhysicalPosition::new(100, 50)));
        assert!(holds(origin, size, PhysicalPosition::new(299, 149)));
        assert!(!holds(origin, size, PhysicalPosition::new(300, 60)));
        assert!(!holds(origin, size, PhysicalPosition::new(150, 150)));
        assert!(!holds(origin, size, PhysicalPosition::new(99, 60)));
    }
}
