// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! The event loop's window target, which answers the app handle's monitor
//! and cursor getters (plan 041, decision 1).
//!
//! Tauri reads `primary_monitor`, `monitor_from_point`, and
//! `available_monitors` from its runtime context's window target, and asks
//! the loop for `cursor_position` (tauri-runtime-wry `src/lib.rs:2662-2695`,
//! `3999-4004`). tao hands out its `EventLoopWindowTarget` in two ways: an
//! `EventLoop` that has not run derefs to it (tao 0.34.5
//! `src/event_loop.rs:225-230`), and a running loop passes it to each call
//! of its callback. So `Native::EventLoop` answers from its own loop before
//! `run`, and while it runs from the target the loop lends for the length
//! of each callback (`lend`), which is when Ruby runs on the main thread.
//! Once the loop has ended neither exists, and each getter answers `nil`.

use std::cell::Cell;

use magnus::{method, prelude::*, Error, RClass};
use tao::event_loop::EventLoopWindowTarget;

use crate::event_loop::RbEventLoop;
use crate::user_event::UserEvent;
use crate::window_state::{monitor, Maybe, MonitorValue};

thread_local! {
    /// The window target the running loop lent its callback, or null
    /// outside one.
    static LENT: Cell<*const EventLoopWindowTarget<UserEvent>> = const { Cell::new(std::ptr::null()) };
}

/// Puts the lent target back as it was, even if the callback unwinds.
struct Restore(*const EventLoopWindowTarget<UserEvent>);

impl Drop for Restore {
    fn drop(&mut self) {
        LENT.set(self.0);
    }
}

/// Lends `target` to the getters on this thread while `callback` runs.
pub fn lend<R>(target: &EventLoopWindowTarget<UserEvent>, callback: impl FnOnce() -> R) -> R {
    let _restore = Restore(LENT.replace(std::ptr::from_ref(target)));
    callback()
}

/// `query` with the window target lent on this thread, if any.
#[allow(unsafe_code)]
fn with_lent<R>(query: impl FnOnce(&EventLoopWindowTarget<UserEvent>) -> R) -> Option<R> {
    let target = LENT.get();
    if target.is_null() {
        return None;
    }
    // SAFETY: `lend` stores a pointer from a live `&EventLoopWindowTarget`
    // only for as long as that borrow lasts: its `Restore` puts the
    // previous pointer back when the callback returns or unwinds, and the
    // cell is this thread's, so no other thread reads it. A non-null
    // pointer here is therefore the target of a `lend` still on this
    // thread's stack, and the shared reference made from it ends before
    // this function returns.
    Some(query(unsafe { &*target }))
}

impl RbEventLoop {
    /// `query` with the loop's window target: its own before `run`, the
    /// lent one while it runs, or `None` once it has ended.
    ///
    /// The lent target is whichever loop is running on this thread, so a
    /// loop that has ended, asked while a second one runs on the same
    /// thread, answers with the second loop's target. That is harmless:
    /// monitors and the cursor are the same for every loop in a process.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the loop's thread.
    fn with_target<R>(
        &self,
        query: impl FnOnce(&EventLoopWindowTarget<UserEvent>) -> R,
    ) -> Result<Option<R>, Error> {
        let cell = self.loop_cell()?;
        if let Ok(event_loop) = cell.try_borrow() {
            if let Some(event_loop) = event_loop.as_ref() {
                return Ok(Some(query(event_loop)));
            }
        }
        Ok(with_lent(query))
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: The window target's getters adapted from tauri-runtime-wry/src/lib.rs WryHandle

    /// `[[x, y]]` from tao's `EventLoopWindowTarget::cursor_position`,
    /// `[nil]` for its error, or `nil` once the loop has ended
    /// (`src/lib.rs:2690-2695`, `3999-4004`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the loop's thread.
    pub fn cursor_position(&self) -> Result<Option<Maybe<(f64, f64)>>, Error> {
        self.with_target(|target| {
            (target
                .cursor_position()
                .ok()
                .map(|position| (position.x, position.y)),)
        })
    }

    /// `[monitor]` for tao's `EventLoopWindowTarget::primary_monitor`
    /// (`[nil]` when it has none), or `nil` once the loop has ended
    /// (`src/lib.rs:2662-2669`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the loop's thread.
    pub fn primary_monitor(&self) -> Result<Option<Maybe<MonitorValue>>, Error> {
        self.with_target(|target| (target.primary_monitor().as_ref().map(monitor),))
    }

    /// `[monitor]` for tao's `EventLoopWindowTarget::monitor_from_point`
    /// (`[nil]` when no monitor holds the point), or `nil` once the loop
    /// has ended (`src/lib.rs:2671-2678`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the loop's thread.
    pub fn monitor_from_point(&self, x: f64, y: f64) -> Result<Option<Maybe<MonitorValue>>, Error> {
        self.with_target(|target| (target.monitor_from_point(x, y).as_ref().map(monitor),))
    }

    /// Every monitor tao's `EventLoopWindowTarget::available_monitors`
    /// lists, or `nil` once the loop has ended (`src/lib.rs:2680-2688`).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the loop's thread.
    pub fn available_monitors(&self) -> Result<Option<Vec<MonitorValue>>, Error> {
        self.with_target(|target| target.available_monitors().map(|m| monitor(&m)).collect())
    }

    // SPDX-SnippetEnd
}

/// Define the window target's getters on `Tokra::Native::EventLoop`.
///
/// # Errors
///
/// Returns an error if method definition fails.
pub fn define_methods(class: RClass) -> Result<(), Error> {
    class.define_method("cursor_position", method!(RbEventLoop::cursor_position, 0))?;
    class.define_method("primary_monitor", method!(RbEventLoop::primary_monitor, 0))?;
    class.define_method(
        "monitor_from_point",
        method!(RbEventLoop::monitor_from_point, 2),
    )?;
    class.define_method(
        "available_monitors",
        method!(RbEventLoop::available_monitors, 0),
    )?;
    Ok(())
}
