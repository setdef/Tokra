// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Ported from tauri-runtime-wry/src/undecorated_resizing.rs and src/util.rs

//! Resizing an undecorated window by its edges (plan 041, decision 5).
//!
//! A window without decorations has no frame for a person to drag. On
//! Windows Tauri covers it with a child window whose region is only a
//! border along the edges and answers that border's hit tests as the
//! frame's; on Linux it connects handlers to the window content's
//! webview that begin GTK's resize drag at the edges. This is Tauri's
//! module (tauri-runtime-wry `src/undecorated_resizing.rs`), with its
//! Windows helpers (`src/util.rs`). The translation changes no behavior:
//! `hit_test` takes its eight numbers as three tuples, `once_cell::Lazy`
//! is `std::sync::LazyLock`, integer casts are checked conversions, the
//! GTK edge is an `Option` instead of `WindowEdge::__Unknown`, a window
//! that is not GTK's is skipped where Tauri would panic, and the device
//! context `hwnd_dpi` borrows is released, where Tauri's leaks it.

#![cfg(any(
    windows,
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd",
    test
))]

const CLIENT: isize = 0b0000;
const LEFT: isize = 0b0001;
const RIGHT: isize = 0b0010;
const TOP: isize = 0b0100;
const BOTTOM: isize = 0b1000;
const TOPLEFT: isize = TOP | LEFT;
const TOPRIGHT: isize = TOP | RIGHT;
const BOTTOMLEFT: isize = BOTTOM | LEFT;
const BOTTOMRIGHT: isize = BOTTOM | RIGHT;

#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
pub use self::gtk::*;
#[cfg(windows)]
pub use self::windows::*;

/// Window coordinates: Win32's integers, GTK's doubles.
#[cfg(windows)]
type WindowPositions = i32;
/// Window coordinates: Win32's integers, GTK's doubles.
#[cfg(not(windows))]
type WindowPositions = f64;

/// Which part of the window a point is over.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
enum HitTestResult {
    Client,
    Left,
    Right,
    Top,
    Bottom,
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
    NoWhere,
}

/// The part of the window `(left, top, right, bottom)` that the cursor
/// `(cx, cy)` is over, with a resize border `(border_x, border_y)` wide
/// along each edge.
fn hit_test(
    (left, top, right, bottom): (
        WindowPositions,
        WindowPositions,
        WindowPositions,
        WindowPositions,
    ),
    (cx, cy): (WindowPositions, WindowPositions),
    (border_x, border_y): (WindowPositions, WindowPositions),
) -> HitTestResult {
    #[rustfmt::skip]
    let result = (LEFT * isize::from(cx < left + border_x))
               | (RIGHT * isize::from(cx >= right - border_x))
               | (TOP * isize::from(cy < top + border_y))
               | (BOTTOM * isize::from(cy >= bottom - border_y));

    match result {
        CLIENT => HitTestResult::Client,
        LEFT => HitTestResult::Left,
        RIGHT => HitTestResult::Right,
        TOP => HitTestResult::Top,
        BOTTOM => HitTestResult::Bottom,
        TOPLEFT => HitTestResult::TopLeft,
        TOPRIGHT => HitTestResult::TopRight,
        BOTTOMLEFT => HitTestResult::BottomLeft,
        BOTTOMRIGHT => HitTestResult::BottomRight,
        _ => HitTestResult::NoWhere,
    }
}

#[cfg(windows)]
#[allow(unsafe_code)]
mod windows {
    use std::ffi::c_void;

    use super::{hit_test, HitTestResult};

    use windows::core::{w, Free, Owned, PCWSTR};
    use windows::Win32::Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, POINTS, RECT, WPARAM};
    use windows::Win32::Graphics::Gdi::{CombineRgn, CreateRectRgn, SetWindowRgn, RGN_DIFF};
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::UI::Shell::{DefSubclassProc, SetWindowSubclass};
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DefWindowProcW, DestroyWindow, FindWindowExW, GetClientRect, GetParent,
        GetWindowLongPtrW, GetWindowPlacement, GetWindowRect, PostMessageW, RegisterClassExW,
        SendMessageW, SetWindowLongPtrW, SetWindowPos, CREATESTRUCTW, GWLP_USERDATA, GWL_STYLE,
        HCURSOR, HICON, HTBOTTOM, HTBOTTOMLEFT, HTBOTTOMRIGHT, HTLEFT, HTRIGHT, HTTOP, HTTOPLEFT,
        HTTOPRIGHT, HTTRANSPARENT, HWND_TOP, SM_CXFRAME, SM_CYFRAME, SWP_ASYNCWINDOWPOS,
        SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOOWNERZORDER, SWP_NOSIZE, SW_MAXIMIZE, WINDOWPLACEMENT,
        WINDOW_EX_STYLE, WINDOW_STYLE, WM_CREATE, WM_NCDESTROY, WM_NCHITTEST, WM_NCLBUTTONDOWN,
        WM_SIZE, WM_USER, WNDCLASSEXW, WNDCLASS_STYLES, WS_CHILD, WS_CLIPSIBLINGS, WS_SIZEBOX,
        WS_VISIBLE,
    };

    impl HitTestResult {
        /// The Win32 hit-test code for this part of the window.
        fn to_win32(self) -> i32 {
            let code = match self {
                Self::Left => HTLEFT,
                Self::Right => HTRIGHT,
                Self::Top => HTTOP,
                Self::Bottom => HTBOTTOM,
                Self::TopLeft => HTTOPLEFT,
                Self::TopRight => HTTOPRIGHT,
                Self::BottomLeft => HTBOTTOMLEFT,
                Self::BottomRight => HTBOTTOMRIGHT,
                _ => return HTTRANSPARENT,
            };
            i32::try_from(code).unwrap_or(HTTRANSPARENT)
        }
    }

    const CLASS_NAME: PCWSTR = w!("TAURI_DRAG_RESIZE_BORDERS");
    const WINDOW_NAME: PCWSTR = w!("TAURI_DRAG_RESIZE_WINDOW");

    const WM_UPDATE_UNDECORATED_SHADOWS: u32 = WM_USER + 100;

    struct UndecoratedResizingData {
        child: HWND,
        has_undecorated_shadows: bool,
    }

    /// The integer `GetWindowLongPtrW` and `SetWindowLongPtrW` speak:
    /// `isize`, or `i32` on 32-bit Windows, where the `windows` crate
    /// aliases them to `GetWindowLongW` and `SetWindowLongW`.
    #[cfg(target_pointer_width = "64")]
    type LongPtr = isize;
    /// The integer `GetWindowLongPtrW` and `SetWindowLongPtrW` speak.
    #[cfg(target_pointer_width = "32")]
    type LongPtr = i32;

    /// An address as the long `SetWindowLongPtrW` stores.
    #[cfg(target_pointer_width = "64")]
    const fn long_from(address: usize) -> LongPtr {
        address.cast_signed()
    }

    /// An address as the long `SetWindowLongPtrW` stores.
    #[cfg(target_pointer_width = "32")]
    fn long_from(address: usize) -> LongPtr {
        LongPtr::try_from(address.cast_signed()).unwrap_or_default()
    }

    /// The address a long holds.
    #[cfg(target_pointer_width = "64")]
    const fn address_from(long: LongPtr) -> usize {
        long.cast_unsigned()
    }

    /// The address a long holds.
    #[cfg(target_pointer_width = "32")]
    fn address_from(long: LongPtr) -> usize {
        usize::try_from(long.cast_unsigned()).unwrap_or_default()
    }

    /// A long's low 32 bits, as Tauri's `style as u32` keeps them.
    #[cfg(target_pointer_width = "64")]
    fn low_bits(long: LongPtr) -> u32 {
        u32::try_from(long.cast_unsigned() & 0xFFFF_FFFF).unwrap_or_default()
    }

    /// A long's low 32 bits, as Tauri's `style as u32` keeps them.
    #[cfg(target_pointer_width = "32")]
    const fn low_bits(long: LongPtr) -> u32 {
        long.cast_unsigned()
    }

    /// The default window procedure, which every message this module does
    /// not answer goes to.
    fn default_proc(child: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
        // SAFETY: `DefWindowProcW` takes any message for any window, as a
        // window procedure passes it on.
        unsafe { DefWindowProcW(child, msg, wparam, lparam) }
    }

    /// A window handle from tao's `isize`.
    const fn hwnd_from(hwnd: isize) -> HWND {
        HWND(std::ptr::with_exposed_provenance_mut(hwnd.cast_unsigned()))
    }

    /// The `LRESULT` for a hit-test code.
    fn hit_result(code: i32) -> LRESULT {
        LRESULT(isize::try_from(code).unwrap_or_default())
    }

    /// The window's `UndecoratedResizingData`, which `WM_CREATE` stored in
    /// its user data, or null before then.
    ///
    /// # Safety
    ///
    /// `child` must be a window of this module's class.
    unsafe fn child_data(child: HWND) -> *mut UndecoratedResizingData {
        // SAFETY: the caller passes a window of this class; reading its
        // user data has no other requirement.
        let long = unsafe { GetWindowLongPtrW(child, GWLP_USERDATA) };
        std::ptr::with_exposed_provenance_mut(address_from(long))
    }

    /// Whether the window may resize: its style has `WS_SIZEBOX`.
    fn parent_is_resizable(parent: HWND) -> bool {
        // SAFETY: `GetWindowLongPtrW` reads a style from any window handle
        // and answers 0 for one that is gone.
        let style = unsafe { GetWindowLongPtrW(parent, GWL_STYLE) };
        let style = WINDOW_STYLE(low_bits(style));
        (style & WS_SIZEBOX).0 != 0
    }

    /// The window's frame border at its DPI, as `SM_CXFRAME` and
    /// `SM_CYFRAME` measure it.
    fn frame_border(hwnd: HWND) -> (i32, i32) {
        // SAFETY: `hwnd_dpi` takes any window handle and answers a default
        // for a bad one.
        let dpi = unsafe { super::util::hwnd_dpi(hwnd) };
        (
            super::util::get_system_metrics_for_dpi(SM_CXFRAME, dpi),
            super::util::get_system_metrics_for_dpi(SM_CYFRAME, dpi),
        )
    }

    /// The width and height of the window's client area.
    fn client_size(hwnd: HWND) -> Option<(i32, i32)> {
        let mut rect = RECT::default();
        // SAFETY: `rect` is a live `RECT` the call writes.
        unsafe { GetClientRect(hwnd, &raw mut rect) }.ok()?;
        Some((rect.right - rect.left, rect.bottom - rect.top))
    }

    /// Covers `hwnd`, a window tao created, with the drag window, unless
    /// it already has one (`undecorated_resizing.rs:117-196`).
    pub fn attach_resize_handler(hwnd: isize, has_undecorated_shadows: bool) {
        let parent = hwnd_from(hwnd);

        // return early if we already attached
        // SAFETY: the class and window names are static wide strings.
        if unsafe { FindWindowExW(Some(parent), None, CLASS_NAME, WINDOW_NAME) }.is_ok() {
            return;
        }

        // SAFETY: a null module name asks for this process's module.
        let instance = HINSTANCE(
            unsafe { GetModuleHandleW(PCWSTR::null()) }
                .unwrap_or_default()
                .0,
        );
        let class = WNDCLASSEXW {
            cbSize: u32::try_from(std::mem::size_of::<WNDCLASSEXW>()).unwrap_or(u32::MAX),
            style: WNDCLASS_STYLES::default(),
            lpfnWndProc: Some(drag_resize_window_proc),
            cbClsExtra: 0,
            cbWndExtra: 0,
            hInstance: instance,
            hIcon: HICON::default(),
            hCursor: HCURSOR::default(),
            hbrBackground: windows::Win32::Graphics::Gdi::HBRUSH::default(),
            lpszMenuName: PCWSTR::null(),
            lpszClassName: CLASS_NAME,
            hIconSm: HICON::default(),
        };

        // SAFETY: `class` is a live `WNDCLASSEXW` whose size it names, with
        // a static class name and a window procedure of the right type.
        // Registering it again fails harmlessly, as in Tauri.
        unsafe { RegisterClassExW(&raw const class) };

        let Some((width, height)) = client_size(parent) else {
            return;
        };

        let data = Box::into_raw(Box::new(UndecoratedResizingData {
            child: HWND::default(),
            has_undecorated_shadows,
        }));

        // SAFETY: the class is registered above, `parent` is tao's live
        // window, and `data` is a box `WM_CREATE` stores and `WM_NCDESTROY`
        // frees.
        let created = unsafe {
            CreateWindowExW(
                WINDOW_EX_STYLE::default(),
                CLASS_NAME,
                WINDOW_NAME,
                WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
                0,
                0,
                width,
                height,
                Some(parent),
                None,
                GetModuleHandleW(None).ok().map(|h| HINSTANCE(h.0)),
                Some(data.cast::<c_void>().cast_const()),
            )
        };
        let Ok(drag_window) = created else {
            return;
        };

        // SAFETY: `drag_window` was just created, as a child of `parent`;
        // the subclass data is a box `subclass_parent` frees on
        // `WM_NCDESTROY`.
        unsafe {
            set_drag_hwnd_rgn(drag_window, width, height, has_undecorated_shadows);

            let _ = SetWindowPos(
                drag_window,
                Some(HWND_TOP),
                0,
                0,
                0,
                0,
                SWP_ASYNCWINDOWPOS | SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOOWNERZORDER | SWP_NOSIZE,
            );

            let data = Box::into_raw(Box::new(UndecoratedResizingData {
                child: drag_window,
                has_undecorated_shadows,
            }));

            let _ = SetWindowSubclass(
                parent,
                Some(subclass_parent),
                usize::try_from(WM_USER + 1).unwrap_or_default(),
                data.expose_provenance(),
            );
        }
    }

    /// The parent's subclass: keeps the drag window's size and region in
    /// step with the parent's (`undecorated_resizing.rs:198-257`).
    unsafe extern "system" fn subclass_parent(
        parent: HWND,
        msg: u32,
        wparam: WPARAM,
        lparam: LPARAM,
        _: usize,
        data: usize,
    ) -> LRESULT {
        let data = std::ptr::with_exposed_provenance_mut::<UndecoratedResizingData>(data);
        match msg {
            WM_SIZE => {
                // SAFETY: `data` is the box `attach_resize_handler` gave
                // this subclass, alive until `WM_NCDESTROY`.
                let data = unsafe { &*data };
                let child = data.child;
                let has_undecorated_shadows = data.has_undecorated_shadows;

                // when parent is maximized, remove the undecorated window drag resize region
                if is_maximized(parent).unwrap_or(false) {
                    // SAFETY: `child` is the drag window; `SetWindowPos`
                    // reports a bad handle as its answer.
                    let _ = unsafe {
                        SetWindowPos(
                            child,
                            Some(HWND_TOP),
                            0,
                            0,
                            0,
                            0,
                            SWP_ASYNCWINDOWPOS | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOMOVE,
                        )
                    };
                } else if let Some((width, height)) = client_size(parent) {
                    // otherwise updat the cutout region
                    // SAFETY: as above, and `set_drag_hwnd_rgn` takes the
                    // drag window.
                    unsafe {
                        let _ = SetWindowPos(
                            child,
                            Some(HWND_TOP),
                            0,
                            0,
                            width,
                            height,
                            SWP_ASYNCWINDOWPOS | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOMOVE,
                        );

                        set_drag_hwnd_rgn(child, width, height, has_undecorated_shadows);
                    }
                }
            }

            WM_UPDATE_UNDECORATED_SHADOWS => {
                // SAFETY: as in `WM_SIZE`; the main thread is the only one
                // that touches it.
                let data = unsafe { &mut *data };
                data.has_undecorated_shadows = wparam.0 != 0;
            }

            WM_NCDESTROY => {
                // SAFETY: the subclass's last message: the box is dropped
                // once, here.
                drop(unsafe { Box::from_raw(data) });
            }

            _ => {}
        }

        // SAFETY: passes the message on to the next subclass, as every
        // subclass procedure must.
        unsafe { DefSubclassProc(parent, msg, wparam, lparam) }
    }

    /// The hit test for the cursor at `lparam`, from the drag window's own
    /// rectangle and the frame border.
    fn edge_at(child: HWND, lparam: LPARAM) -> Option<HitTestResult> {
        let mut rect = RECT::default();
        // SAFETY: `rect` is a live `RECT` the call writes.
        unsafe { GetWindowRect(child, &raw mut rect) }.ok()?;
        let (cx, cy) = (
            i32::from(get_x_lparam(lparam)),
            i32::from(get_y_lparam(lparam)),
        );
        Some(hit_test(
            (rect.left, rect.top, rect.right, rect.bottom),
            (cx, cy),
            frame_border(child),
        ))
    }

    /// The drag window's procedure: answers hit tests over its border as
    /// the frame's, and passes a click there on to the parent as a press
    /// on that part of its frame (`undecorated_resizing.rs:259-401`).
    unsafe extern "system" fn drag_resize_window_proc(
        child: HWND,
        msg: u32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        match msg {
            WM_CREATE => {
                let create = std::ptr::with_exposed_provenance_mut::<CREATESTRUCTW>(
                    lparam.0.cast_unsigned(),
                );
                // SAFETY: `WM_CREATE`'s `lparam` is the `CREATESTRUCTW` of
                // this window's creation, whose `lpCreateParams` is the box
                // `attach_resize_handler` passed.
                unsafe {
                    let data = (*create).lpCreateParams.cast::<UndecoratedResizingData>();
                    (*data).child = child;
                    let _ = SetWindowLongPtrW(
                        child,
                        GWLP_USERDATA,
                        long_from(data.expose_provenance()),
                    );
                }
            }

            WM_NCHITTEST => {
                // SAFETY: `child` is a window of this class.
                let data = unsafe { child_data(child) };
                // SAFETY: `GetParent` takes any window handle.
                let parent = unsafe { GetParent(child) };
                let (false, Ok(parent)) = (data.is_null(), parent) else {
                    return default_proc(child, msg, wparam, lparam);
                };
                if !parent_is_resizable(parent) {
                    return default_proc(child, msg, wparam, lparam);
                }

                // if the window has undecorated shadows,
                // it should always be the top border,
                // ensured by the cutout drag window
                // SAFETY: `data` is the box `WM_CREATE` stored, alive until
                // `WM_NCDESTROY`.
                if unsafe { &*data }.has_undecorated_shadows {
                    return hit_result(HitTestResult::Top.to_win32());
                }

                let Some(res) = edge_at(child, lparam) else {
                    return default_proc(child, msg, wparam, lparam);
                };
                return hit_result(res.to_win32());
            }

            WM_NCLBUTTONDOWN => {
                // SAFETY: as in `WM_NCHITTEST`.
                let data = unsafe { child_data(child) };
                // SAFETY: as in `WM_NCHITTEST`.
                let parent = unsafe { GetParent(child) };
                let (false, Ok(parent)) = (data.is_null(), parent) else {
                    return default_proc(child, msg, wparam, lparam);
                };
                if !parent_is_resizable(parent) {
                    return default_proc(child, msg, wparam, lparam);
                }

                let (cx, cy) = (
                    i32::from(get_x_lparam(lparam)),
                    i32::from(get_y_lparam(lparam)),
                );

                // if the window has undecorated shadows,
                // it should always be the top border,
                // ensured by the cutout drag window
                // SAFETY: as in `WM_NCHITTEST`.
                let res = if unsafe { &*data }.has_undecorated_shadows {
                    HitTestResult::Top
                } else {
                    let Some(res) = edge_at(child, lparam) else {
                        return default_proc(child, msg, wparam, lparam);
                    };
                    res
                };

                if res != HitTestResult::NoWhere {
                    let points = POINTS {
                        x: i16::try_from(cx).unwrap_or_default(),
                        y: i16::try_from(cy).unwrap_or_default(),
                    };

                    // Tauri posts the address of `points` as the message's
                    // `lparam`, a number Windows reads as a position and
                    // never dereferences; so does this.
                    // SAFETY: `PostMessageW` copies its arguments.
                    let _ = unsafe {
                        PostMessageW(
                            Some(parent),
                            WM_NCLBUTTONDOWN,
                            WPARAM(
                                isize::try_from(res.to_win32())
                                    .unwrap_or_default()
                                    .cast_unsigned(),
                            ),
                            LPARAM((&raw const points).expose_provenance().cast_signed()),
                        )
                    };
                }

                return LRESULT(0);
            }

            WM_UPDATE_UNDECORATED_SHADOWS => {
                // SAFETY: as in `WM_NCHITTEST`.
                let data = unsafe { child_data(child) };
                if !data.is_null() {
                    // SAFETY: the box `WM_CREATE` stored, on its only thread.
                    unsafe { (*data).has_undecorated_shadows = wparam.0 != 0 };
                }
            }

            WM_NCDESTROY => {
                // SAFETY: as in `WM_NCHITTEST`.
                let data = unsafe { child_data(child) };
                if !data.is_null() {
                    // SAFETY: the window's last message: the box is dropped
                    // once, here.
                    drop(unsafe { Box::from_raw(data) });
                }
            }

            _ => {}
        }

        default_proc(child, msg, wparam, lparam)
    }

    /// Destroys the drag window over `hwnd`, if it has one
    /// (`undecorated_resizing.rs:403-411`).
    pub fn detach_resize_handler(hwnd: isize) {
        let hwnd = hwnd_from(hwnd);

        // SAFETY: as in `attach_resize_handler`.
        let Ok(child) = (unsafe { FindWindowExW(Some(hwnd), None, CLASS_NAME, WINDOW_NAME) })
        else {
            return;
        };

        // SAFETY: `child` is the drag window this module created.
        let _ = unsafe { DestroyWindow(child) };
    }

    /// Cuts the middle out of the drag window, so the webview and the
    /// parent get the clicks there (`undecorated_resizing.rs:413-441`).
    ///
    /// # Safety
    ///
    /// `hwnd` must be a drag window.
    unsafe fn set_drag_hwnd_rgn(hwnd: HWND, width: i32, height: i32, only_top: bool) {
        // The window used for drag resizing an undecorated window
        // is a child HWND that covers the whole window
        // and so we need create a cut out in the middle for the parent and other child
        // windows like the webview can receive mouse events.

        let (border_x, border_y) = frame_border(hwnd);

        // SAFETY: GDI region calls on regions this function creates; the
        // window owns `hrgn1` once `SetWindowRgn` takes it, and this frees
        // it when it does not, as Tauri does.
        unsafe {
            // hrgn1 must be mutable to call .free() later
            let mut hrgn1 = CreateRectRgn(0, 0, width, height);

            let x1 = if only_top { 0 } else { border_x };
            let y1 = border_y;
            let x2 = if only_top { width } else { width - border_x };
            let y2 = if only_top { height } else { height - border_y };

            // Wrap hrgn2 in Owned so it is automatically freed when going out of scope
            let hrgn2 = Owned::new(CreateRectRgn(x1, y1, x2, y2));

            CombineRgn(Some(hrgn1), Some(hrgn1), Some(*hrgn2), RGN_DIFF);

            // Try to set the window region
            if SetWindowRgn(hwnd, Some(hrgn1), true) == 0 {
                // If it fails, we must free hrgn1 manually
                hrgn1.free();
            }
        }
    }

    /// Reshapes the drag window over `hwnd` for a shadow, or none, and
    /// tells both windows (`undecorated_resizing.rs:443-476`).
    pub fn update_drag_hwnd_rgn_for_undecorated(hwnd: isize, has_undecorated_shadows: bool) {
        let hwnd = hwnd_from(hwnd);

        let Some((width, height)) = client_size(hwnd) else {
            return;
        };

        // SAFETY: as in `attach_resize_handler`.
        let Ok(child) = (unsafe { FindWindowExW(Some(hwnd), None, CLASS_NAME, WINDOW_NAME) })
        else {
            return;
        };

        // Tauri sends the flag in `lparam`, but both procedures read it
        // from `wparam`, which is always zero here, so they store `false`
        // whatever was set (`undecorated_resizing.rs:222-225`, `385-388`,
        // `458-472`). This copies Tauri as it is; the region set first
        // does follow the flag (plan 041, decision 5).
        // SAFETY: `child` is the drag window; the messages are this
        // module's own, which both procedures handle.
        unsafe {
            set_drag_hwnd_rgn(child, width, height, has_undecorated_shadows);

            SendMessageW(
                hwnd,
                WM_UPDATE_UNDECORATED_SHADOWS,
                None,
                Some(LPARAM(isize::from(has_undecorated_shadows))),
            );
            SendMessageW(
                child,
                WM_UPDATE_UNDECORATED_SHADOWS,
                None,
                Some(LPARAM(isize::from(has_undecorated_shadows))),
            );
        }
    }

    /// Whether the window is maximized, as its placement says.
    fn is_maximized(window: HWND) -> windows::core::Result<bool> {
        let mut placement = WINDOWPLACEMENT {
            length: u32::try_from(std::mem::size_of::<WINDOWPLACEMENT>()).unwrap_or(u32::MAX),
            ..WINDOWPLACEMENT::default()
        };
        // SAFETY: `placement` is a live `WINDOWPLACEMENT` whose `length`
        // names its size, as `GetWindowPlacement` requires.
        unsafe { GetWindowPlacement(window, &raw mut placement)? };
        Ok(placement.showCmd == SW_MAXIMIZE.0.cast_unsigned())
    }

    /// Implementation of the `GET_X_LPARAM` macro.
    fn get_x_lparam(lparam: LPARAM) -> i16 {
        u16::try_from(lparam.0.cast_unsigned() & 0xFFFF)
            .unwrap_or_default()
            .cast_signed()
    }

    /// Implementation of the `GET_Y_LPARAM` macro.
    fn get_y_lparam(lparam: LPARAM) -> i16 {
        u16::try_from((lparam.0.cast_unsigned() & 0xFFFF_0000) >> 16)
            .unwrap_or_default()
            .cast_signed()
    }
}

#[cfg(windows)]
#[allow(unsafe_code)]
mod util {
    use std::{iter::once, os::windows::ffi::OsStrExt, sync::LazyLock};

    use windows::{
        core::{HRESULT, PCSTR, PCWSTR},
        Win32::{
            Foundation::{FARPROC, HWND},
            Graphics::Gdi::{
                GetDC, GetDeviceCaps, MonitorFromWindow, ReleaseDC, HDC, HMONITOR, LOGPIXELSX,
                MONITOR_DEFAULTTONEAREST,
            },
            System::LibraryLoader::{GetProcAddress, LoadLibraryW},
            UI::{
                HiDpi::{MDT_EFFECTIVE_DPI, MONITOR_DPI_TYPE},
                WindowsAndMessaging::{
                    GetSystemMetrics, IsProcessDPIAware, SYSTEM_METRICS_INDEX,
                    USER_DEFAULT_SCREEN_DPI,
                },
            },
        },
    };

    fn encode_wide(string: impl AsRef<std::ffi::OsStr>) -> Vec<u16> {
        string.as_ref().encode_wide().chain(once(0)).collect()
    }

    // Helper function to dynamically load function pointer.
    // `library` and `function` must be zero-terminated.
    fn get_function_impl(library: &str, function: &str) -> FARPROC {
        let library = encode_wide(library);
        if !function.ends_with('\0') {
            return None;
        }

        // Library names we will use are ASCII so we can use the A version to avoid string conversion.
        // SAFETY: `library` is a zero-terminated wide string that lives
        // through the call.
        let module =
            unsafe { LoadLibraryW(PCWSTR::from_raw(library.as_ptr())) }.unwrap_or_default();
        if module.is_invalid() {
            return None;
        }

        // SAFETY: `function` is zero-terminated, checked above, and lives
        // through the call.
        unsafe { GetProcAddress(module, PCSTR::from_raw(function.as_ptr())) }
    }

    macro_rules! get_function {
        ($lib:expr, $func:ident) => {
            get_function_impl($lib, concat!(stringify!($func), '\0')).map(|f| {
                // SAFETY: `f` is the export of this name, whose signature
                // is the type of the same name, as Win32 documents it.
                unsafe { std::mem::transmute::<unsafe extern "system" fn() -> isize, $func>(f) }
            })
        };
    }

    type GetDpiForWindow = unsafe extern "system" fn(hwnd: HWND) -> u32;
    type GetDpiForMonitor = unsafe extern "system" fn(
        hmonitor: HMONITOR,
        dpi_type: MONITOR_DPI_TYPE,
        dpi_x: *mut u32,
        dpi_y: *mut u32,
    ) -> HRESULT;
    type GetSystemMetricsForDpi =
        unsafe extern "system" fn(nindex: SYSTEM_METRICS_INDEX, dpi: u32) -> i32;

    static GET_DPI_FOR_WINDOW: LazyLock<Option<GetDpiForWindow>> =
        LazyLock::new(|| get_function!("user32.dll", GetDpiForWindow));
    static GET_DPI_FOR_MONITOR: LazyLock<Option<GetDpiForMonitor>> =
        LazyLock::new(|| get_function!("shcore.dll", GetDpiForMonitor));
    static GET_SYSTEM_METRICS_FOR_DPI: LazyLock<Option<GetSystemMetricsForDpi>> =
        LazyLock::new(|| get_function!("user32.dll", GetSystemMetricsForDpi));

    /// The window's DPI (`src/util.rs:65-106`). Tauri never releases the
    /// device context it asks for; this does.
    ///
    /// # Safety
    ///
    /// `hwnd` must be a window handle, live or gone.
    pub unsafe fn hwnd_dpi(hwnd: HWND) -> u32 {
        // SAFETY: the caller passes a window handle; `GetDC` answers an
        // invalid context for a bad one.
        let hdc = unsafe { GetDC(Some(hwnd)) };
        if hdc.is_invalid() {
            return USER_DEFAULT_SCREEN_DPI;
        }
        let dpi = GET_DPI_FOR_WINDOW.map_or_else(
            || dpi_before_windows_10(hwnd, hdc),
            |get_dpi_for_window| {
                // We are on Windows 10 Anniversary Update (1607) or later.
                // SAFETY: the export of its name, given a window handle.
                match unsafe { get_dpi_for_window(hwnd) } {
                    0 => USER_DEFAULT_SCREEN_DPI, // 0 is returned if hwnd is invalid
                    dpi => dpi,
                }
            },
        );
        // SAFETY: `hdc` is the context `GetDC` gave for `hwnd`, released
        // once.
        unsafe { ReleaseDC(Some(hwnd), hdc) };
        dpi
    }

    /// The window's DPI before Windows 10's `GetDpiForWindow`: its
    /// monitor's on Windows 8.1, or the device context's.
    fn dpi_before_windows_10(hwnd: HWND, hdc: HDC) -> u32 {
        GET_DPI_FOR_MONITOR.map_or_else(
            || {
                // We are on Vista or later.
                // SAFETY: `IsProcessDPIAware` takes nothing, and
                // `GetDeviceCaps` takes the live context `hwnd_dpi` holds.
                unsafe {
                    if IsProcessDPIAware().as_bool() {
                        // If the process is DPI aware, then scaling must be handled by the application using
                        // this DPI value.
                        u32::try_from(GetDeviceCaps(Some(hdc), LOGPIXELSX))
                            .unwrap_or(USER_DEFAULT_SCREEN_DPI)
                    } else {
                        // If the process is DPI unaware, then scaling is performed by the OS; we thus return
                        // 96 (scale factor 1.0) to prevent the window from being re-scaled by both the
                        // application and the WM.
                        USER_DEFAULT_SCREEN_DPI
                    }
                }
            },
            |get_dpi_for_monitor| {
                // We are on Windows 8.1 or later.
                // SAFETY: `MonitorFromWindow` takes any window handle, and
                // the export of its name is given a monitor and two live
                // out-parameters.
                unsafe {
                    let monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
                    if monitor.is_invalid() {
                        return USER_DEFAULT_SCREEN_DPI;
                    }

                    let mut dpi_x = 0;
                    let mut dpi_y = 0;
                    if get_dpi_for_monitor(
                        monitor,
                        MDT_EFFECTIVE_DPI,
                        &raw mut dpi_x,
                        &raw mut dpi_y,
                    )
                    .is_ok()
                    {
                        dpi_x
                    } else {
                        USER_DEFAULT_SCREEN_DPI
                    }
                }
            },
        )
    }

    /// The system metric at `dpi`, or at the system's DPI before Windows 10
    /// (`src/util.rs:108-115`).
    pub fn get_system_metrics_for_dpi(nindex: SYSTEM_METRICS_INDEX, dpi: u32) -> i32 {
        GET_SYSTEM_METRICS_FOR_DPI.map_or_else(
            // SAFETY: Win32's own `GetSystemMetrics` takes any index.
            || unsafe { GetSystemMetrics(nindex) },
            // SAFETY: the export of its name takes any index and DPI.
            |get_system_metrics_for_dpi| unsafe { get_system_metrics_for_dpi(nindex, dpi) },
        )
    }
}

#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd"
))]
mod gtk {
    use super::{hit_test, HitTestResult};
    use tao::dpi::Pixel;

    const BORDERLESS_RESIZE_INSET: i32 = 5;

    impl HitTestResult {
        /// GDK's edge for this part of the window, or `None` inside it.
        const fn to_gtk_edge(self) -> Option<gtk::gdk::WindowEdge> {
            match self {
                Self::Client | Self::NoWhere => None,
                Self::Left => Some(gtk::gdk::WindowEdge::West),
                Self::Right => Some(gtk::gdk::WindowEdge::East),
                Self::Top => Some(gtk::gdk::WindowEdge::North),
                Self::Bottom => Some(gtk::gdk::WindowEdge::South),
                Self::TopLeft => Some(gtk::gdk::WindowEdge::NorthWest),
                Self::TopRight => Some(gtk::gdk::WindowEdge::NorthEast),
                Self::BottomLeft => Some(gtk::gdk::WindowEdge::SouthWest),
                Self::BottomRight => Some(gtk::gdk::WindowEdge::SouthEast),
            }
        }
    }

    /// The GTK window around the webview, when it is undecorated,
    /// resizable, and not maximized, as Tauri requires before it resizes:
    /// the webview's parent is tao's box, whose parent is the window.
    fn undecorated_window(
        webview: &impl gtk::prelude::IsA<gtk::Widget>,
    ) -> Option<gtk::gdk::Window> {
        use gtk::prelude::*;

        // This one should be GtkBox
        let window: gtk::Window = webview.parent()?.parent()?.downcast().ok()?;
        if window.is_decorated() || !window.is_resizable() || window.is_maximized() {
            return None;
        }
        window.window()
    }

    /// The edge of `window` under the root point, if any.
    fn edge(
        window: &gtk::gdk::Window,
        (root_x, root_y): (f64, f64),
    ) -> Option<gtk::gdk::WindowEdge> {
        let (window_x, window_y) = window.position();
        let (client_x, client_y) = (root_x - f64::from(window_x), root_y - f64::from(window_y));
        let border = f64::from(window.scale_factor() * BORDERLESS_RESIZE_INSET);
        hit_test(
            (
                0.0,
                0.0,
                f64::from(window.width()),
                f64::from(window.height()),
            ),
            (client_x, client_y),
            (border, border),
        )
        .to_gtk_edge()
    }

    /// `as i32` for a root coordinate: dpi's cast rounds, so this rounds a
    /// value already truncated.
    fn root_coordinate(value: f64) -> i32 {
        i32::from_f64(value.trunc())
    }

    /// Connects the handlers that begin a resize drag when the first
    /// button or a touch lands on an undecorated window's edge
    /// (`undecorated_resizing.rs:524-627`).
    pub fn attach_resize_handler(webview: &wry::WebView) {
        use gtk::{glib::Propagation, prelude::*};
        use wry::WebViewExtUnix;

        let webview = webview.webview();

        webview.add_events(
            gtk::gdk::EventMask::BUTTON1_MOTION_MASK
                | gtk::gdk::EventMask::BUTTON_PRESS_MASK
                | gtk::gdk::EventMask::TOUCH_MASK,
        );

        webview.connect_button_press_event(move |webview, event| {
            if event.button() == 1 {
                if let Some(window) = undecorated_window(webview) {
                    let root = event.root();
                    // we ignore the inside so the webview receives the click correctly if it is not on the edges.
                    if let Some(edge) = edge(&window, root) {
                        window.begin_resize_drag(
                            edge,
                            1,
                            root_coordinate(root.0),
                            root_coordinate(root.1),
                            event.time(),
                        );
                    }
                }
            }

            Propagation::Proceed
        });

        webview.connect_touch_event(move |webview, event| {
            if let Some(window) = undecorated_window(webview) {
                if let (Some(root), Some(device)) = (event.root_coords(), event.device()) {
                    // we ignore the inside so the window receives the click correctly if it is not on the edges.
                    if let Some(edge) = edge(&window, root) {
                        window.begin_resize_drag_for_device(
                            edge,
                            &device,
                            0,
                            root_coordinate(root.0),
                            root_coordinate(root.1),
                            event.time(),
                        );
                    }
                }
            }

            Propagation::Proceed
        });
    }
}

#[cfg(test)]
mod tests {
    use super::{hit_test, HitTestResult, WindowPositions};

    /// A number in the platform's coordinate type.
    fn n(value: i16) -> WindowPositions {
        WindowPositions::from(value)
    }

    /// Hit tests over a 100 by 80 window at (10, 20) with a 5 by 4 border.
    fn at(x: i16, y: i16) -> HitTestResult {
        hit_test((n(10), n(20), n(110), n(100)), (n(x), n(y)), (n(5), n(4)))
    }

    #[test]
    fn each_edge_and_corner_of_the_border_is_its_own_part() {
        assert_eq!(at(60, 60), HitTestResult::Client);
        assert_eq!(at(12, 60), HitTestResult::Left);
        assert_eq!(at(107, 60), HitTestResult::Right);
        assert_eq!(at(60, 22), HitTestResult::Top);
        assert_eq!(at(60, 98), HitTestResult::Bottom);
        assert_eq!(at(12, 22), HitTestResult::TopLeft);
        assert_eq!(at(107, 22), HitTestResult::TopRight);
        assert_eq!(at(12, 98), HitTestResult::BottomLeft);
        assert_eq!(at(107, 98), HitTestResult::BottomRight);
    }

    /// The border's inner edge belongs to the client on the left and top,
    /// and to the border on the right and bottom (`<` against `>=`).
    #[test]
    fn the_borders_inner_edges_follow_tauris_comparisons() {
        assert_eq!(at(15, 60), HitTestResult::Client);
        assert_eq!(at(105, 60), HitTestResult::Right);
        assert_eq!(at(60, 24), HitTestResult::Client);
        assert_eq!(at(60, 96), HitTestResult::Bottom);
    }

    /// A window narrower than its two borders is both left and right at
    /// once, which is nowhere.
    #[test]
    fn a_point_on_opposite_borders_is_nowhere() {
        let result = hit_test((n(0), n(0), n(4), n(100)), (n(2), n(50)), (n(5), n(4)));
        assert_eq!(result, HitTestResult::NoWhere);
    }
}

// SPDX-SnippetEnd
