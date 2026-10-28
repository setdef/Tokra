// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Runs a native call that blocks the main thread with the GVL released,
//! so other Ruby threads keep running while it blocks (plan 042,
//! decision 15).
//!
//! A context menu tracks the pointer in a nested run loop on the main
//! thread: `-[NSMenu popUpMenuPositioningItem:atLocation:inView:]` on
//! macOS, `TrackPopupMenu` on Windows, and on Linux muda's own loop of
//! `gtk::main_iteration` (muda 0.17.1 `platform_impl/gtk/mod.rs:1385-1460`).
//! The call returns only when the menu closes. In Tauri only the main
//! thread waits; in Tokra the main thread holds the GVL (ADR 012), so every
//! other Ruby thread would wait too.
//!
//! Releasing the GVL is sound here because no callback of Tokra's, tao's,
//! wry's, or muda's calls Ruby inside the nested loop. tao does not
//! re-enter its event handler while one runs: on macOS `wakeup` and
//! `cleared` return when the handler is in a callback (tao 0.34.5
//! `platform_impl/macos/app_state.rs:319-326`, `384-391`), on Windows the
//! runner buffers events while its handler is out
//! (`platform_impl/windows/event_loop/runner.rs:208-227`), and on Linux
//! GTK's handlers only queue events for the loop's own body
//! (`platform_impl/linux/event_loop.rs:1097-1131`). muda's event handler and
//! wry's handlers are Rust closures that send through the loop's proxy.
//!
//! Two exceptions never reach Ruby here. On macOS tao's `drawRect:`,
//! `open_urls`, and `reopen` call `handle_nonuser_event` without that
//! check (`app_state.rs:204-213`, `310-318`, `367-369`; `view.rs:353`);
//! during a popup they would block on the handler's lock, which the
//! running handler holds, as they would in Tauri. And a foreign callback
//! the app registers itself (a main-loop timeout, a Fiddle closure, a
//! ruby-gnome signal) runs as it would in any region without the GVL: it
//! takes the GVL back through `rb_thread_call_with_gvl`, whose interrupt
//! check on the way out can `longjmp` across GTK's or Win32's frames, the
//! hazard `gvl_handoff.rs` describes.
//!
//! The call goes through `rb_thread_call_without_gvl`, which checks
//! interrupts before it releases the GVL and after it takes it back, and
//! may raise there (Ruby v4.0.1 and v4.0.9 `thread.c:320-343`,
//! `1594-1643`). Magnus's
//! `protect` catches that raise, so it never `longjmp`s across a Rust frame
//! that owns anything, and returns it as an error. The call itself runs
//! inside `catch_unwind`, since a panic must not unwind through Ruby's C
//! frames; it resumes once the GVL is back. No unblocking function is
//! given: a signal or `Thread#raise` waits for the menu to close, as it
//! waits for any Ruby callback the loop runs.

use std::ffi::c_void;
use std::panic::{self, AssertUnwindSafe};
use std::ptr;

use magnus::Error;
use rb_sys::{rb_thread_call_without_gvl, Qnil, VALUE};

use crate::runtime_error;

/// The call, and its result once it ran.
struct Call<F, R> {
    call: Option<F>,
    result: Option<std::thread::Result<R>>,
}

/// Runs the `Call` behind `data` without the GVL. It calls no Ruby API.
extern "C" fn run<F: FnOnce() -> R, R>(data: *mut c_void) -> *mut c_void {
    // SAFETY: `data` is the `Call<F, R>` that `without_gvl` lent
    // `rb_thread_call_without_gvl`, which calls this once, on the calling
    // thread, while `without_gvl` waits for it (Ruby v4.0.1
    // `thread.c:1628-1631`); nothing else touches it meanwhile.
    #[allow(unsafe_code)]
    let state = unsafe { &mut *data.cast::<Call<F, R>>() };
    if let Some(call) = state.call.take() {
        state.result = Some(panic::catch_unwind(AssertUnwindSafe(call)));
    }
    ptr::null_mut()
}

/// Runs `call` with the GVL released and returns its result.
///
/// `call` must not touch Ruby: no Ruby objects, no Ruby API, no raising.
///
/// # Errors
///
/// Returns the exception a pending interrupt raises when Ruby checks for
/// one, before the call (which then never runs) or after it.
pub fn without_gvl<F: FnOnce() -> R, R>(call: F) -> Result<R, Error> {
    let mut state = Call {
        call: Some(call),
        result: None,
    };
    let data: *mut c_void = ptr::addr_of_mut!(state).cast();
    magnus::rb_sys::protect(|| {
        // SAFETY: `run::<F, R>` matches the function type Ruby calls
        // (`include/ruby/thread.h`, `rb_thread_call_without_gvl`), and
        // `data` points to `state`, which outlives the call. With no
        // unblocking function Ruby never interrupts it. A raise from the
        // interrupt checks unwinds to `protect` through this closure,
        // which owns nothing to drop.
        #[allow(unsafe_code)]
        unsafe {
            rb_thread_call_without_gvl(Some(run::<F, R>), data, None, ptr::null_mut());
        }
        Qnil as VALUE
    })?;
    match state.result {
        Some(Ok(value)) => Ok(value),
        Some(Err(payload)) => panic::resume_unwind(payload),
        None => Err(Error::new(runtime_error(), "the call did not run")),
    }
}
