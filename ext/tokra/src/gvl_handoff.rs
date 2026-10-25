// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Hands the GVL to other Ruby threads while the event loop waits.
//!
//! tao's loop runs on the main thread and holds the GVL: every event reaches
//! Ruby from inside tao's callback, and Ruby code needs the GVL. While the
//! loop waits for the next event, nothing in it gives the GVL up, so every
//! other Ruby thread stops until something wakes the loop.
//!
//! Releasing the GVL around the wait is not sound here. The only public way
//! to take it back inside tao's callback is `rb_thread_call_with_gvl`, and on
//! its way out it checks interrupts (`unblock_function_set` at Ruby v4.0.1
//! `thread.c:320-343`, called from `rb_thread_call_with_gvl` at
//! `thread.c:2063-2091`). A signal trap that raises, such as
//! `trap("TERM") { exit }`, or a `Thread#raise`, would then `longjmp` across
//! tao's and the platform's frames.
//!
//! So the loop keeps the GVL and hands it over on demand. Ruby calls a READY
//! thread-event hook whenever a thread starts waiting for the GVL
//! (`thread_sched_to_ready_common`, `thread_pthread.c:794-801`), including
//! at every time-slice switch (`thread_pthread.c:1128-1141`). The hook only
//! marks a hand-off [`Pending`], and wakes the loop with `UserEvent::Yield`
//! when the mark was not already set, so a busy thread cannot flood the
//! loop's queue. The loop clears the mark and calls `Thread.pass` once per
//! iteration, at `MainEventsCleared`, never while tao drains its user
//! events, so the window keeps turning between hand-offs however busy the
//! other threads are. `Thread.pass` runs through magnus's protected
//! `funcall`, inside tao's callback, so an exception lands in magnus's
//! `rb_protect` and never crosses tao.
//!
//! Ruby implements thread-event hooks with pthreads only; on Windows
//! `rb_internal_thread_add_event_hook` returns `NULL` (`thread_win32.c:34-45`),
//! and [`GvlHandoff::install`] returns `None` so the loop polls instead
//! ([`idle_control_flow`]).

use std::ffi::c_void;
use std::ptr::NonNull;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use rb_sys::{
    rb_event_flag_t, rb_internal_thread_add_event_hook, rb_internal_thread_event_data_t,
    rb_internal_thread_event_hook_t, rb_internal_thread_remove_event_hook,
    RUBY_INTERNAL_THREAD_EVENT_READY, VALUE,
};
use tao::event_loop::{ControlFlow, EventLoopProxy};

use crate::user_event::UserEvent;

/// How often the loop hands the GVL over where Ruby has no thread-event
/// hooks, while other Ruby threads exist.
pub const POLL_INTERVAL: Duration = Duration::from_millis(10);

/// Whether a hand-off is owed: set by the hook, cleared by the loop.
#[derive(Debug, Default)]
pub struct Pending(AtomicBool);

impl Pending {
    /// Marks a hand-off owed. Returns `true` only when it was not owed
    /// already, the one time the loop needs waking for it.
    pub fn request(&self) -> bool {
        !self.0.swap(true, Ordering::AcqRel)
    }

    /// Clears the mark, returning whether a hand-off was owed.
    pub fn take(&self) -> bool {
        self.0.swap(false, Ordering::AcqRel)
    }
}

/// Whether a READY event for `thread` should wake the loop. The main
/// thread's own waits for the GVL need no hand-off: the loop is the main
/// thread.
#[must_use]
pub const fn wakes_loop(thread: VALUE, main_thread: VALUE) -> bool {
    thread != main_thread
}

/// How the loop waits between events: until the next one, or, polling for
/// lack of a hook, for at most `POLL_INTERVAL` while another Ruby thread
/// exists, so that thread still gets the GVL.
#[must_use]
pub fn idle_control_flow(poll: bool, alone: bool, now: Instant) -> ControlFlow {
    if poll && !alone {
        ControlFlow::WaitUntil(now + POLL_INTERVAL)
    } else {
        ControlFlow::Wait
    }
}

/// What the hook reads on whichever thread runs it.
struct HookData {
    /// Wakes the loop. tao's proxy is `Send + Sync` (`proxy.rs`).
    proxy: EventLoopProxy<UserEvent>,
    /// The main thread's `Thread` object, to skip its own waits. Compared by
    /// value, never dereferenced; if compaction moves the object, the main
    /// thread's own waits ask for a hand-off it does not need, which costs
    /// one `Thread.pass`.
    main_thread: VALUE,
    pending: Pending,
}

impl HookData {
    /// Owes a hand-off, waking the loop if it was not owed already.
    fn request(&self) {
        if self.pending.request() {
            let _ = self.proxy.send_event(UserEvent::Yield);
        }
    }
}

/// A registered READY hook. Dropping it unregisters the hook.
pub struct GvlHandoff {
    hook: NonNull<rb_internal_thread_event_hook_t>,
    /// The hook's own reference, from `Arc::into_raw`; reclaimed in `Drop`,
    /// after the hook is gone.
    hook_data: *const HookData,
    /// The loop's reference to the same data.
    data: Arc<HookData>,
}

impl GvlHandoff {
    /// Registers the hook, or returns `None` where Ruby has no thread-event
    /// hooks (Windows). Call it on the main thread, holding the GVL, and
    /// never from a hook (`include/ruby/thread.h:263-283`).
    ///
    /// A thread that began waiting for the GVL before the hook existed
    /// fired its READY event already, so the first hand-off is owed from
    /// the start.
    #[allow(unsafe_code)]
    pub fn install(proxy: EventLoopProxy<UserEvent>, main_thread: VALUE) -> Option<Self> {
        let data = Arc::new(HookData {
            proxy,
            main_thread,
            pending: Pending::default(),
        });
        let hook_data = Arc::into_raw(Arc::clone(&data));
        // SAFETY: `on_ready` matches `rb_internal_thread_event_callback`
        // (`include/ruby/thread.h:260-263`). `hook_data` points to a live
        // `HookData` that this `GvlHandoff` reclaims only after removing the
        // hook (see `Drop`), and the hook only reads it. Ruby copies the
        // three arguments into a hook it allocates
        // (`thread_pthread.c:3405-3425`). The caller holds the GVL on the
        // main thread and is not a hook.
        let hook = unsafe {
            rb_internal_thread_add_event_hook(
                Some(on_ready),
                RUBY_INTERNAL_THREAD_EVENT_READY,
                hook_data.cast_mut().cast(),
            )
        };
        let Some(hook) = NonNull::new(hook) else {
            // SAFETY: Ruby registered nothing, so nothing else holds
            // `hook_data`, which came from `Arc::into_raw` above.
            drop(unsafe { Arc::from_raw(hook_data) });
            return None;
        };
        data.request();
        Some(Self {
            hook,
            hook_data,
            data,
        })
    }

    /// Clears the mark, returning whether another thread is owed the GVL.
    #[must_use]
    pub fn take_pending(&self) -> bool {
        self.data.pending.take()
    }
}

impl Drop for GvlHandoff {
    #[allow(unsafe_code)]
    fn drop(&mut self) {
        // SAFETY: `hook` is the pointer `rb_internal_thread_add_event_hook`
        // returned, not yet removed. Removal takes the hooks' write lock,
        // and every hook call holds its read lock
        // (`thread_pthread.c:3428-3456`, `3463-3485`), so once it returns
        // no thread is running `on_ready` with `hook_data`. It runs on the
        // main thread, which is not a hook.
        unsafe { rb_internal_thread_remove_event_hook(self.hook.as_ptr()) };
        // SAFETY: the hook is gone (above), so nothing reads through
        // `hook_data` any more; it came from `Arc::into_raw` in `install`.
        drop(unsafe { Arc::from_raw(self.hook_data) });
    }
}

/// The READY hook: another Ruby thread is waiting for the GVL, so owe it a
/// hand-off.
///
/// Ruby runs it without the GVL, holding its scheduler lock, on any thread
/// (`include/ruby/thread.h:226-231`, `263-275`). It calls no Ruby API and
/// takes no lock that the main thread holds while it waits for the
/// scheduler: an atomic swap and, at most once per hand-off, tao's
/// `send_event`, a channel send and a run-loop wake-up.
#[allow(unsafe_code)]
unsafe extern "C" fn on_ready(
    _event: rb_event_flag_t,
    event_data: *const rb_internal_thread_event_data_t,
    user_data: *mut c_void,
) {
    // SAFETY: `user_data` is the `HookData` pointer passed to
    // `rb_internal_thread_add_event_hook`, alive until `GvlHandoff` removes
    // the hook, and only read.
    let data = unsafe { &*user_data.cast::<HookData>() };
    // SAFETY: Ruby passes a pointer to event data on its own stack, valid
    // for this call (`thread_pthread.c:3470-3476`).
    let thread = unsafe { (*event_data).thread };
    if wakes_loop(thread, data.main_thread) {
        data.request();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_first_request_wakes_the_loop_until_the_loop_takes_it() {
        let pending = Pending::default();
        assert!(pending.request(), "the first request wakes the loop");
        assert!(!pending.request(), "a second one while owed must not");
        assert!(!pending.request());
        assert!(pending.take(), "the loop sees the hand-off owed");
        assert!(!pending.take(), "and owes it once, however many asked");
        assert!(
            pending.request(),
            "after the hand-off, a new request wakes it again"
        );
    }

    #[test]
    fn nothing_is_owed_at_first() {
        assert!(!Pending::default().take());
    }

    #[test]
    fn only_other_threads_wake_the_loop() {
        assert!(!wakes_loop(8, 8), "the main thread's own wait");
        assert!(wakes_loop(16, 8));
    }

    #[test]
    fn polling_waits_a_short_while_only_when_other_threads_exist() {
        let now = Instant::now();
        assert_eq!(
            idle_control_flow(true, false, now),
            ControlFlow::WaitUntil(now + POLL_INTERVAL)
        );
        assert_eq!(idle_control_flow(true, true, now), ControlFlow::Wait);
        assert_eq!(
            idle_control_flow(false, false, now),
            ControlFlow::Wait,
            "with a hook the loop sleeps until woken"
        );
    }
}
