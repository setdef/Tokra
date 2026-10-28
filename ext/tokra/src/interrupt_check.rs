// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Wakes the event loop once per Ruby time slice, so it can run a pending
//! Ruby interrupt, such as a signal, that nothing else would wake it for.
//!
//! Ruby never runs a signal's handler in C signal context. Its handler only
//! raises the main thread's trap-interrupt flag and calls the main thread's
//! unblocking function (Ruby v4.0.1 `signal.c:697-716`,
//! `thread_pthread.c:2607-2631`); the handler itself, Ruby's default
//! `SignalException` or the app's `trap`, runs at the main thread's next
//! interrupt check (`thread.c:2617-2660`). A thread has an unblocking
//! function only inside a blocking region (`thread.c:1523-1543`), and the
//! loop's main thread never is in one: it waits in tao holding the GVL
//! (ADR 012). So no signal wakes the loop, and while it waits it makes no
//! interrupt check.
//!
//! [`InterruptTicker`] sends the loop `UserEvent::Yield` every
//! [`INTERRUPT_CHECK`], from a thread that calls no Ruby API, and the loop
//! hands over at the end of that turn when Ruby has an interrupt pending
//! (`event_loop.rs`). A deadline in tao's control flow cannot do this
//! everywhere: tao 0.34.5's Linux loop adds no timeout for
//! `ControlFlow::WaitUntil` and blocks in `gtk::main_iteration_do(true)`
//! until some GTK event arrives (`platform_impl/linux/event_loop.rs:1062-1086`,
//! `1131`). A proxy event wakes every backend.

use std::sync::mpsc::{self, RecvTimeoutError, Sender};
use std::thread::{self, JoinHandle};
use std::time::Duration;

/// How often the loop looks for a pending Ruby interrupt: Ruby's default
/// time slice, 100 ms (Ruby v4.0.1 `thread.c:118`), the delay Ruby already
/// allows a busy thread before it sees an interrupt. `RUBY_THREAD_TIMESLICE`
/// changes Ruby's slice, not this.
pub const INTERRUPT_CHECK: Duration = Duration::from_millis(100);

/// A thread that calls `wake` once per interval until it is dropped, or
/// until `wake` returns `false` because the loop is gone.
pub struct InterruptTicker {
    /// Dropping it ends the thread's wait at once.
    stop: Option<Sender<()>>,
    thread: Option<JoinHandle<()>>,
}

impl InterruptTicker {
    /// Starts the ticker. If the thread cannot start, the loop runs as it
    /// did before Plan 034: a signal waits for the next event.
    pub fn start(interval: Duration, mut wake: impl FnMut() -> bool + Send + 'static) -> Self {
        let (stop, stopped) = mpsc::channel::<()>();
        let thread = thread::Builder::new()
            .name("tokra-interrupt-check".into())
            .spawn(move || {
                while stopped.recv_timeout(interval) == Err(RecvTimeoutError::Timeout) {
                    if !wake() {
                        break;
                    }
                }
            })
            .ok();
        Self {
            stop: Some(stop),
            thread,
        }
    }
}

impl Drop for InterruptTicker {
    fn drop(&mut self) {
        drop(self.stop.take());
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::time::Instant;

    #[test]
    fn the_loop_is_woken_once_per_ruby_time_slice() {
        assert_eq!(INTERRUPT_CHECK, Duration::from_millis(100));
    }

    #[test]
    fn it_wakes_the_loop_again_and_again_until_dropped() {
        let ticks = Arc::new(AtomicUsize::new(0));
        let counted = Arc::clone(&ticks);
        let ticker = InterruptTicker::start(Duration::from_millis(5), move || {
            counted.fetch_add(1, Ordering::SeqCst);
            true
        });
        let started = Instant::now();
        while ticks.load(Ordering::SeqCst) < 3 {
            assert!(
                started.elapsed() < Duration::from_secs(5),
                "it stopped ticking"
            );
            thread::sleep(Duration::from_millis(1));
        }
        drop(ticker);
        let after_drop = ticks.load(Ordering::SeqCst);
        thread::sleep(Duration::from_millis(30));
        assert_eq!(
            ticks.load(Ordering::SeqCst),
            after_drop,
            "it ticked after drop"
        );
    }

    #[test]
    fn dropping_it_does_not_wait_out_the_interval() {
        let ticker = InterruptTicker::start(Duration::from_secs(60), || true);
        let started = Instant::now();
        drop(ticker);
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn it_stops_once_the_loop_is_gone() {
        let ticks = Arc::new(AtomicUsize::new(0));
        let counted = Arc::clone(&ticks);
        let ticker = InterruptTicker::start(Duration::from_millis(1), move || {
            counted.fetch_add(1, Ordering::SeqCst);
            false
        });
        thread::sleep(Duration::from_millis(30));
        assert_eq!(ticks.load(Ordering::SeqCst), 1);
        drop(ticker);
    }
}
