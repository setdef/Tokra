// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Values that belong to the thread that created them.
//!
//! tao's `EventLoop` and wry's `WebView` are not `Send`: the platform objects
//! they hold work only on the thread that built them. magnus wraps only
//! `Send` types (magnus `src/typed_data.rs:411-413`), because Ruby can hand
//! any object to any Ruby thread, and Ruby's garbage collector frees an
//! unreachable object on whichever thread sweeps it (Ruby v4.0.1
//! `gc.c:1182-1222`, `gc/default/default.c:2062-2120`).
//!
//! [`ThreadBound`] closes that gap by construction instead of by
//! convention. It records the thread that created its value, hands the
//! value out only on that thread, and on any other thread forgets the value
//! instead of dropping it. Tauri states the same invariant for its
//! main-thread types and keeps it with a dispatcher (tauri-runtime-wry
//! `src/lib.rs:431-454`); Tokra keeps it with this type and with
//! `Tokra::RuntimeContext`, which brings Ruby's calls to the main thread.

use std::thread::{self, ThreadId};

use magnus::{Error, Ruby};

/// The thread a native object belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OwnerThread(ThreadId);

impl OwnerThread {
    /// The calling thread.
    #[must_use]
    pub fn current() -> Self {
        Self(thread::current().id())
    }

    /// Whether the calling thread is this one. A `ThreadId` is never
    /// reused while the process runs (std `thread::ThreadId`), so a thread
    /// that ended cannot be mistaken for a later one.
    #[must_use]
    pub fn is_current(self) -> bool {
        thread::current().id() == self.0
    }
}

/// The `ThreadError` a native object raises on a thread it does not
/// belong to.
///
/// # Panics
///
/// Panics if called outside the Ruby VM, which never happens: only a Ruby
/// method call reaches it.
#[must_use]
pub fn wrong_thread(class: &str) -> Error {
    let ruby = Ruby::get().expect("Ruby VM not initialized");
    Error::new(
        ruby.exception_thread_error(),
        format!("{class} can only be used on the thread that created it"),
    )
}

/// A value usable and dropped only on the thread that created it.
#[derive(Debug)]
pub struct ThreadBound<T> {
    owner: OwnerThread,
    value: Option<T>,
}

impl<T> ThreadBound<T> {
    /// Binds `value` to the calling thread.
    pub fn new(value: T) -> Self {
        Self {
            owner: OwnerThread::current(),
            value: Some(value),
        }
    }

    /// The thread the value belongs to.
    #[must_use]
    pub const fn owner(&self) -> OwnerThread {
        self.owner
    }

    /// The value, on its own thread; `None` on any other, or once taken.
    #[must_use]
    pub fn get(&self) -> Option<&T> {
        if self.owner.is_current() {
            self.value.as_ref()
        } else {
            None
        }
    }

    /// Moves the value into a new `ThreadBound` with the same owner, leaving
    /// this one empty. Any thread may call it: the value moves between two
    /// wrappers and is never reached.
    #[must_use]
    pub const fn take(&mut self) -> Self {
        Self {
            owner: self.owner,
            value: self.value.take(),
        }
    }
}

impl<T> Drop for ThreadBound<T> {
    fn drop(&mut self) {
        if !self.owner.is_current() {
            // Dropping a platform object on the wrong thread is undefined
            // behavior; leaking it is only memory.
            if let Some(value) = self.value.take() {
                std::mem::forget(value);
            }
        }
    }
}

// SAFETY: `Send` lets another thread own a `ThreadBound<T>`. On any thread
// but the owner, `get` returns `None` and `Drop` forgets the value, so no
// thread but the owner ever creates a reference to `T` or runs its
// destructor; `take` only moves the `Option<T>` between two wrappers.
// Other threads read `owner`, a `ThreadId`, which is `Send + Sync`. This is
// the soundness argument the send_wrapper crate makes for the same
// pattern, with a leak where it panics.
#[allow(unsafe_code)]
#[allow(clippy::non_send_fields_in_send_ty)]
unsafe impl<T> Send for ThreadBound<T> {}

#[cfg(test)]
mod tests {
    use super::*;
    use std::rc::Rc;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;

    /// Records whether it was dropped. The `Rc` makes it `!Send`, like a
    /// platform object.
    struct Platform {
        dropped: Arc<AtomicBool>,
        _not_send: Rc<()>,
    }

    impl Drop for Platform {
        fn drop(&mut self) {
            self.dropped.store(true, Ordering::SeqCst);
        }
    }

    fn platform() -> (ThreadBound<Platform>, Arc<AtomicBool>) {
        let dropped = Arc::new(AtomicBool::new(false));
        let bound = ThreadBound::new(Platform {
            dropped: dropped.clone(),
            _not_send: Rc::new(()),
        });
        (bound, dropped)
    }

    #[test]
    fn the_owner_thread_gets_the_value() {
        let (bound, _) = platform();
        assert!(bound.get().is_some());
        assert!(bound.owner().is_current());
    }

    #[test]
    fn another_thread_gets_nothing() {
        let (bound, _) = platform();
        let reached = thread::spawn(move || {
            let reached = bound.get().is_some();
            // Hand it back so the owner drops it.
            (reached, bound)
        })
        .join()
        .unwrap();
        assert!(!reached.0, "another thread reached the value");
        assert!(reached.1.get().is_some(), "the owner still reaches it");
    }

    #[test]
    fn dropped_on_its_owner_the_value_drops() {
        let (bound, dropped) = platform();
        drop(bound);
        assert!(dropped.load(Ordering::SeqCst));
    }

    #[test]
    fn dropped_on_another_thread_the_value_leaks_instead() {
        let (bound, dropped) = platform();
        thread::spawn(move || drop(bound)).join().unwrap();
        assert!(
            !dropped.load(Ordering::SeqCst),
            "the value's destructor ran off its thread"
        );
    }

    #[test]
    fn take_keeps_the_owner_and_empties_the_original() {
        let (mut bound, dropped) = platform();
        let taken = thread::spawn(move || {
            let taken = bound.take();
            assert!(bound.get().is_none());
            drop(bound); // empty: nothing to leak
            taken
        })
        .join()
        .unwrap();
        assert!(taken.get().is_some(), "the owner reaches the taken value");
        drop(taken);
        assert!(dropped.load(Ordering::SeqCst));
    }

    #[test]
    fn is_current_only_on_the_owner() {
        let owner = OwnerThread::current();
        assert!(owner.is_current());
        assert!(!thread::spawn(move || owner.is_current()).join().unwrap());
    }
}
