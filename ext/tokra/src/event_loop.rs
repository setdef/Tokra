// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Event loop wrapper for tao.
//!
//! This module provides the Ruby-facing `Tokra::Native::EventLoop` class,
//! which wraps `tao::event_loop::EventLoop<UserEvent>`.

use std::cell::RefCell;
use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use magnus::{
    error::ErrorType, function, kwargs, method, prelude::*, rb_sys::AsRawValue, ArgList, Error,
    Exception, RClass, Ruby, Value,
};
use tao::{
    event::{Event, WindowEvent},
    event_loop::{ControlFlow, EventLoop, EventLoopBuilder, EventLoopProxy},
    platform::run_return::EventLoopExtRunReturn,
};

use crate::gvl_handoff::{idle_control_flow, GvlHandoff};
use crate::interrupt_check::{InterruptTicker, INTERRUPT_CHECK};
use crate::proxy::RbProxy;
use crate::runtime_error;
use crate::thread_bound::{wrong_thread, ThreadBound};
use crate::user_event::UserEvent;

/// The Ruby class name, for the wrong-thread error.
const CLASS: &str = "Tokra::Native::EventLoop";

/// The error for a loop that `run()` already took.
const CONSUMED: &str = "EventLoop has already been consumed by run()";

/// Ruby wrapper for `tao::event_loop::EventLoop<UserEvent>`.
///
/// The `EventLoop` owns the OS main thread and runs the window event pump.
///
/// tao's `EventLoop` is neither `Send` nor `Sync` (tao `src/event_loop.rs:40-43`),
/// because its platform loop belongs to the thread that built it, and
/// magnus wraps only `Send` types (magnus `src/typed_data.rs:411-413`). The
/// loop lives in a [`ThreadBound`], which is `Send` because it never reaches
/// the loop off that thread and leaks it rather than drop it there, so this
/// type needs no `unsafe impl` of its own. On macOS and Linux tao builds the
/// loop only on the main thread (`platform_impl/macos/event_loop.rs:166-167`,
/// `linux/event_loop.rs:211-213`).
#[magnus::wrap(class = "Tokra::Native::EventLoop", free_immediately, size)]
pub struct RbEventLoop {
    /// The inner event loop. Wrapped in Option because `run` consumes it.
    inner: ThreadBound<RefCell<Option<EventLoop<UserEvent>>>>,
    /// Proxy for creating `RbProxy` instances, from any thread.
    proxy: EventLoopProxy<UserEvent>,
}

impl RbEventLoop {
    /// Create a new `EventLoop`.
    ///
    /// # Errors
    ///
    /// This function is infallible but returns `Result` for consistency with Magnus FFI.
    pub fn new() -> Result<Self, Error> {
        let event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();

        let proxy = event_loop.create_proxy();

        Ok(Self {
            inner: ThreadBound::new(RefCell::new(Some(event_loop))),
            proxy,
        })
    }

    /// The loop's cell, on the thread that built it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` on any other thread.
    pub(crate) fn loop_cell(&self) -> Result<&RefCell<Option<EventLoop<UserEvent>>>, Error> {
        self.inner.get().ok_or_else(|| wrong_thread(CLASS))
    }

    /// The loop's proxy, for native objects that send themselves home.
    pub(crate) const fn proxy(&self) -> &EventLoopProxy<UserEvent> {
        &self.proxy
    }

    /// Create a Proxy for cross-thread and cross-Ractor communication.
    ///
    /// Any thread may call it: the proxy is the loop's thread-safe handle.
    #[must_use]
    pub fn create_proxy(&self) -> RbProxy {
        RbProxy::new(self.proxy.clone(), self.inner.owner())
    }

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: Mapping adapted from tauri-runtime-wry/src/lib.rs tao_activation_policy

    /// Set the activation policy the app takes when the loop starts.
    ///
    /// tao keeps the policy and applies it once `AppKit` has finished
    /// launching, just before it activates the app
    /// (`platform/macos.rs:310-319`, `341-345`; `platform_impl/macos/app_state.rs:285-295`,
    /// `456-469`). `policy` names a variant, as tauri-runtime-wry maps
    /// Tauri's `ActivationPolicy` onto tao's (`src/lib.rs:586-593`).
    /// macOS only, as tao defines it.
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the loop's thread, `ArgumentError` for a
    /// name that is not `Regular`, `Accessory`, or `Prohibited`, and an
    /// error once `run()` has consumed the loop, when the policy could no
    /// longer take effect.
    #[cfg(target_os = "macos")]
    pub fn set_activation_policy(
        ruby: &Ruby,
        rb_self: &Self,
        policy: magnus::RString,
    ) -> Result<(), Error> {
        use tao::platform::macos::{ActivationPolicy, EventLoopExtMacOS};

        let policy = policy.to_string()?;
        let policy = match policy.as_str() {
            "Regular" => ActivationPolicy::Regular,
            "Accessory" => ActivationPolicy::Accessory,
            "Prohibited" => ActivationPolicy::Prohibited,
            _ => {
                return Err(Error::new(
                    ruby.exception_arg_error(),
                    format!("unknown activation policy: {policy:?}"),
                ))
            }
        };
        rb_self
            .loop_cell()?
            .borrow_mut()
            .as_mut()
            .ok_or_else(|| Error::new(runtime_error(), CONSUMED))?
            .set_activation_policy(policy);
        Ok(())
    }

    // SPDX-SnippetEnd

    /// Run the event loop. It never returns: it ends the process.
    ///
    /// The callback Proc is invoked for each event.
    ///
    /// tao's `run` is `process::exit(run_return(handler))` on every desktop
    /// backend. Calling `process::exit` from inside Ruby skips Ruby's own
    /// exit: `at_exit` hooks, `ensure` clauses, and the flush of buffered
    /// output, so a piped `$stdout` loses everything it held. This method
    /// runs the same loop with `run_return` and then raises `SystemExit`
    /// with the loop's exit code, so the process still ends with that code,
    /// the way Ruby ends a process.
    ///
    /// The loop holds the GVL, and hands it to any other Ruby thread that
    /// waits for it (`gvl_handoff.rs`). It also wakes once per Ruby's
    /// default time slice, 100 ms, to run a pending interrupt, so a
    /// signal's handler, Ruby's default or the app's `trap`, runs even
    /// while nothing else happens (`interrupt_check.rs`, Plan 034).
    ///
    /// # Errors
    ///
    /// Returns `ThreadError` off the loop's thread, or an error if `run()`
    /// has already been called, consuming the event loop. Otherwise always
    /// returns `SystemExit` carrying the loop's exit code, or the
    /// `SystemExit` the callback raised for the last event (`deliver_last`).
    pub fn run(&self, callback: Value) -> Result<(), Error> {
        let mut event_loop = self
            .loop_cell()?
            .borrow_mut()
            .take()
            .ok_or_else(|| Error::new(runtime_error(), CONSUMED))?;
        let ruby = Ruby::get_with(callback);

        // Setup ctrlc handler to send Exit event
        let proxy_for_ctrlc = self.proxy.clone();
        let exit_sent = Arc::new(AtomicBool::new(false));
        ctrlc::set_handler(move || {
            if !exit_sent.swap(true, Ordering::SeqCst) {
                let _ = proxy_for_ctrlc.send_event(UserEvent::Exit);
            }
        })
        .ok(); // Ignore if already set

        let handoff = GvlHandoff::install(self.proxy.clone(), ruby.thread_main().as_raw());
        // Wakes the loop once per time slice to run a signal's handler
        // (interrupt_check.rs); it stops once the loop is gone.
        let ticks = self.proxy.clone();
        let ticker = InterruptTicker::start(INTERRUPT_CHECK, move || {
            ticks.send_event(UserEvent::Yield).is_ok()
        });
        let poll = handoff.is_none();
        let mut raised = None;
        let mut inbox = VecDeque::new();

        // Run the event loop - this is a blocking call
        let exit_code = event_loop.run_return(|event, _, control_flow| {
            let mut turn = Turn {
                callback,
                control_flow,
                raised: &mut raised,
                inbox: &mut inbox,
            };
            // SPDX-SnippetBegin
            // SPDX-License-Identifier: Apache-2.0 OR MIT
            // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
            // SPDX-SnippetComment: Keeping a requested exit adapted from tauri-runtime-wry/src/lib.rs handle_event_loop
            // Tauri resets the flow to Wait for each event unless an exit is
            // already set (tauri-runtime-wry lib.rs:4029-4031); tao's Linux
            // loop, for one, calls back again after an exit is set
            // (linux/event_loop.rs:1113-1126).
            if !turn.exiting() {
                let alone = poll && ruby.thread_alone();
                *turn.control_flow = idle_control_flow(poll, alone, Instant::now());
            }
            // SPDX-SnippetEnd
            if matches!(event, Event::MainEventsCleared) {
                // Once per iteration, after tao has drained its events:
                // deliver what the drain queued, then hand over the GVL if
                // another thread waits, so a busy thread gets one time slice
                // per turn of the loop and cannot starve the window, or if
                // Ruby has an interrupt pending, such as a signal, which
                // the hand-off runs.
                turn.deliver_inbox();
                let owed = handoff
                    .as_ref()
                    .map_or_else(|| poll && !ruby.thread_alone(), GvlHandoff::take_pending);
                if hands_over(owed || interrupt_pending(&ruby), turn.exiting()) {
                    turn.yield_gvl();
                }
            } else {
                turn.handle(event);
            }
        });
        // Unregister before the loop and its proxy go.
        drop(ticker);
        drop(handoff);

        // An interrupt that ended the loop (a signal's SignalException,
        // Thread#raise, Thread#kill) is raised again here, now that the loop
        // is down, the way Ruby would have raised it anywhere else.
        if let Some(error) = raised {
            return Err(error);
        }
        Err(system_exit(&ruby, exit_code))
    }
}

/// One event's worth of loop state: tao's control flow for this event, the
/// first exception that must end the loop, which `run` raises once the loop
/// is down, and the user events waiting for Ruby.
///
/// tao drains its user-event channel until it is empty before it finishes
/// an iteration (`platform_impl/macos/app_state.rs:110-121`,
/// `linux/event_loop.rs`'s `EventQueue` state). A Ruby callback inside that
/// drain loses the GVL for a whole time slice whenever another thread wants
/// it, so with a busy thread and a steady sender the drain never empties,
/// the iteration never ends, and neither the window nor an exit gets its
/// turn. So the drain only queues Ruby's events in `inbox`, which is fast,
/// and `MainEventsCleared` delivers the batch once per iteration. A close
/// request joins the same queue, so Ruby sees it after the user events
/// that arrived before it, as Tauri does: tao's macOS `cleared()` hands
/// over user events first, then the window events it held
/// (`app_state.rs:394-398`).
struct Turn<'a> {
    callback: Value,
    control_flow: &'a mut ControlFlow,
    raised: &'a mut Option<Error>,
    inbox: &'a mut VecDeque<ForRuby>,
}

/// An event waiting in the inbox for Ruby.
#[derive(Debug)]
enum ForRuby {
    User(UserEvent),
    CloseRequested,
    Destroyed,
}

/// Whether to hand the GVL over this turn: only when another thread is
/// owed it, or an interrupt is pending, and no exit is set, so an exit
/// never waits a time slice.
const fn hands_over(owed: bool, exiting: bool) -> bool {
    owed && !exiting
}

/// Whether a user event needs Ruby, and so waits in the inbox; the rest
/// are acted on as they arrive.
const fn needs_ruby(user_event: &UserEvent) -> bool {
    !matches!(
        user_event,
        UserEvent::Yield | UserEvent::Respond(_) | UserEvent::Release(_) | UserEvent::Exit
    )
}

impl Turn<'_> {
    /// Whether an exit is already set for this loop.
    const fn exiting(&self) -> bool {
        matches!(
            *self.control_flow,
            ControlFlow::Exit | ControlFlow::ExitWithCode(_)
        )
    }

    /// Deliver one tao event to Ruby, or act on it here.
    fn handle(&mut self, event: Event<'_, UserEvent>) {
        match event {
            Event::UserEvent(user_event) => self.queue_user_event(user_event),
            Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => self.inbox.push_back(ForRuby::CloseRequested),
            Event::WindowEvent {
                event: WindowEvent::Destroyed,
                ..
            } => self.inbox.push_back(ForRuby::Destroyed),
            // SPDX-SnippetBegin
            // SPDX-License-Identifier: Apache-2.0 OR MIT
            // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
            // SPDX-SnippetComment: Exit on loop destruction adapted from tauri-runtime-wry/src/lib.rs handle_event_loop
            Event::LoopDestroyed => {
                // The last event Ruby sees: run_return returns right after
                // it and `run` raises SystemExit. Tauri emits
                // RunEvent::Exit from it. Anything still queued goes first.
                self.deliver_inbox();
                self.deliver_last("::Tokra::Native::LoopDestroyedEvent");
            }
            // SPDX-SnippetEnd
            _ => {}
        }
    }

    /// Act at once on the events that need no Ruby, and queue the rest for
    /// `deliver_inbox`.
    fn queue_user_event(&mut self, user_event: UserEvent) {
        if needs_ruby(&user_event) {
            self.inbox.push_back(ForRuby::User(user_event));
            return;
        }
        match user_event {
            // Only wakes the loop: the hand-off waits for MainEventsCleared.
            UserEvent::Yield => {}
            UserEvent::Respond(answer) => answer.deliver(),
            UserEvent::Release(released) => {
                // Dropped here, on the main thread, where the window or
                // webview belongs.
                drop(released);
            }
            UserEvent::Exit => {
                *self.control_flow = ControlFlow::Exit;
            }
            for_ruby => self.handle_user_event(for_ruby),
        }
    }

    /// Deliver the queued events to Ruby, in order. Events that arrive
    /// meanwhile wait in tao's channel for the next iteration.
    fn deliver_inbox(&mut self) {
        let batch = std::mem::take(self.inbox);
        for event in batch {
            match event {
                ForRuby::User(user_event) => self.handle_user_event(user_event),
                // Ruby asks its handlers and closes the window unless one
                // prevents it (tauri-runtime-wry lib.rs:4262-4290).
                ForRuby::CloseRequested => self.deliver("::Tokra::Native::WindowCloseEvent", ()),
                // SPDX-SnippetBegin
                // SPDX-License-Identifier: Apache-2.0 OR MIT
                // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
                // SPDX-SnippetComment: Exit after the last window adapted from tauri-runtime-wry/src/lib.rs handle_event_loop
                // Ruby drops the window from its store and, with none left,
                // asks its handlers whether to exit; `true` means no one
                // prevented it (lib.rs:4168-4185).
                ForRuby::Destroyed => {
                    if self.ask("::Tokra::Native::WindowDestroyedEvent", ()) {
                        self.exit_with(0);
                    }
                } // SPDX-SnippetEnd
            }
        }
    }

    fn handle_user_event(&mut self, user_event: UserEvent) {
        match user_event {
            UserEvent::IpcMessage { url, body } => {
                // Data.define(:message, :url)
                self.deliver("::Tokra::Native::IpcEvent", (body, url));
            }
            UserEvent::HttpRequest {
                request_id,
                method,
                uri,
                headers,
                body,
            } => {
                // Data.define(:request_id, :method, :uri, :headers, :body);
                // the body arrives as a binary String holding the exact bytes.
                let body = Ruby::get_with(self.callback).str_from_slice(&body);
                self.deliver(
                    "::Tokra::Native::HttpRequestEvent",
                    (request_id, method, uri, headers, body),
                );
            }
            UserEvent::PageLoad { event, url } => {
                // Data.define(:event, :url)
                self.deliver("::Tokra::Native::PageLoadEvent", (event, url));
            }
            UserEvent::DragDrop { event, paths, x, y } => {
                // Data.define(:event, :paths, :x, :y)
                self.deliver("::Tokra::Native::DragDropEvent", (event, paths, x, y));
            }
            UserEvent::WakeUp(payload) => {
                // Data.define(:payload)
                self.deliver("::Tokra::Native::WakeUpEvent", (payload,));
            }
            UserEvent::Task => {
                // Data.define; the App runs the oldest queued task.
                self.deliver("::Tokra::Native::TaskEvent", ());
            }
            // SPDX-SnippetBegin
            // SPDX-License-Identifier: Apache-2.0 OR MIT
            // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
            // SPDX-SnippetComment: RequestExit and Close adapted from tauri-runtime-wry/src/lib.rs handle_event_loop
            UserEvent::RequestExit(code) => {
                // Data.define(:code); `true` means no handler prevented the
                // exit (lib.rs:4215-4227).
                if self.ask("::Tokra::Native::ExitRequestedEvent", (code,)) {
                    self.exit_with(code);
                }
            }
            // The close button's path (lib.rs:4229-4231).
            UserEvent::CloseWindow => self.deliver("::Tokra::Native::WindowCloseEvent", ()),
            // SPDX-SnippetEnd
            // Handled as they arrive (queue_user_event).
            UserEvent::Yield | UserEvent::Respond(_) | UserEvent::Release(_) | UserEvent::Exit => {}
        }
    }

    /// Build a `Tokra::Native` event and pass it to the Ruby callback.
    ///
    /// The callback is the `App` dispatcher, and an exception it raises must
    /// not vanish (see `report`).
    fn deliver<A: ArgList>(&mut self, class_path: &str, args: A) {
        self.ask(class_path, args);
    }

    /// Deliver an event as `deliver` does, and answer whether the callback
    /// returned `true`. An exception counts as any other answer once
    /// `report` has handled it.
    ///
    /// Tauri's runtime passes its callback a channel and reads it once the
    /// callback returns (tauri-runtime-wry `src/lib.rs:4177-4180`); Tokra's
    /// App answers with the dispatcher's result instead.
    fn ask<A: ArgList>(&mut self, class_path: &str, args: A) -> bool {
        let ruby = Ruby::get_with(self.callback);
        match self.call(&ruby, class_path, args) {
            Ok(answer) => answer.as_raw() == ruby.qtrue().as_raw(),
            Err(error) => {
                self.report(&ruby, error);
                false
            }
        }
    }

    /// Deliver the loop's last event, `LoopDestroyedEvent`.
    ///
    /// The loop is over, so a `SystemExit` raised here cannot set its
    /// control flow; it becomes the exception `run` raises instead of the
    /// loop's own status, as an `exit` in an `ensure` clause replaces the
    /// exception in flight. That is how a restart (`Tokra::Process.restart`)
    /// after `RunEvent::Exit` ends the process with status 0, as Tauri's
    /// `process::restart` does (Plan 039, decision 4). Anything else is
    /// handled as `report` handles it.
    fn deliver_last(&mut self, class_path: &str) {
        let ruby = Ruby::get_with(self.callback);
        if let Err(error) = self.call(&ruby, class_path, ()) {
            if system_exit_status(&ruby, &error).is_some() {
                *self.raised = Some(error);
            } else {
                self.report(&ruby, error);
            }
        }
    }

    /// Build a `Tokra::Native` event and pass it to the Ruby callback,
    /// answering what the callback returned or raised.
    fn call<A: ArgList>(&self, ruby: &Ruby, class_path: &str, args: A) -> Result<Value, Error> {
        ruby.eval::<RClass>(class_path)
            .and_then(|klass| klass.funcall::<_, _, Value>("new", args))
            .and_then(|event| self.callback.funcall::<_, _, Value>("call", (event,)))
    }

    /// End the loop with `code`, unless an exit is already set: the first
    /// exit wins, as tao keeps the first `ExitWithCode`.
    const fn exit_with(&mut self, code: i32) {
        if !self.exiting() {
            *self.control_flow = ControlFlow::ExitWithCode(code);
        }
    }

    /// Hand the GVL to whichever Ruby threads are waiting for it, and come
    /// back once they block or their time slice ends.
    ///
    /// `Thread.pass` is `rb_thread_schedule`, which also runs pending
    /// interrupts (Ruby v4.0.1 `thread.c:1495-1518`). magnus's `funcall` runs
    /// it under `rb_protect`, so an exception it raises comes back as an
    /// `Err` here instead of unwinding through tao. Anything it raises came
    /// from an interrupt, a signal's handler or `Thread#raise`, meant to
    /// unwind the main thread, so it ends the loop and `run` raises it.
    fn yield_gvl(&mut self) {
        let ruby = Ruby::get_with(self.callback);
        if let Err(error) = ruby.class_thread().funcall::<_, _, Value>("pass", ()) {
            if system_exit_status(&ruby, &error).is_some() {
                self.report(&ruby, error);
            } else {
                self.end_with(error);
            }
        }
    }

    /// Handle an exception raised while delivering an event.
    ///
    /// A `SystemExit` (from `AppHandle#exit` or `Kernel#exit`) ends the loop
    /// with its status. A `StandardError` is reported to stderr with its full
    /// message and backtrace, and the loop keeps running, since one failed
    /// event should not take down the window. Anything else, such as a
    /// `SignalException` or `Interrupt` from a signal, or a `Thread#kill`,
    /// is not a failure of the event but a request to unwind the main
    /// thread: it ends the loop and `run` raises it.
    fn report(&mut self, ruby: &Ruby, error: Error) {
        if let Some(status) = system_exit_status(ruby, &error) {
            *self.control_flow = ControlFlow::ExitWithCode(status);
            return;
        }
        match error.error_type() {
            ErrorType::Exception(exception)
                if exception.is_kind_of(ruby.exception_standard_error()) =>
            {
                let message = exception
                    .funcall::<_, _, String>("full_message", (kwargs!("highlight" => false),))
                    .unwrap_or_else(|_| error.to_string());
                warn(ruby, &message);
            }
            ErrorType::Error(..) => warn(ruby, &format!("Tokra event callback failed: {error}")),
            _ => self.end_with(error),
        }
    }

    /// End the loop, keeping the first exception that asked to.
    fn end_with(&mut self, error: Error) {
        *self.control_flow = ControlFlow::Exit;
        self.raised.get_or_insert(error);
    }
}

/// Whether Ruby has an interrupt pending for the main thread: a signal
/// whose handler has not run, a `Thread#raise`, or a `Thread#kill`.
///
/// Ruby's signal handler only raises the main thread's trap-interrupt flag;
/// the handler itself waits for the main thread's next interrupt check,
/// which the loop, waiting in tao, would otherwise make only when an event
/// or a hand-off reaches Ruby (`interrupt_check.rs`).
#[allow(unsafe_code)]
fn interrupt_pending(ruby: &Ruby) -> bool {
    let main_thread = ruby.thread_main().as_raw();
    // SAFETY: `rb_thread_interrupted` is public Ruby API
    // (`include/ruby/internal/intern/thread.h:375`) that type-checks its
    // argument as a `Thread` through `rb_thread_ptr` and only reads that
    // thread's interrupt flag (Ruby v4.0.1 `thread.c:1483-1487`,
    // `vm_core.h:2212-2216`). `ruby` proves this thread holds the GVL, and
    // `main_thread` is the live main thread's `Thread`, which
    // `rb_thread_main` always returns (`thread.c:3199-3203`).
    unsafe { rb_sys::rb_thread_interrupted(main_thread) != 0 }
}

/// The status of a `SystemExit`, or `None` for any other error.
fn system_exit_status(ruby: &Ruby, error: &Error) -> Option<i32> {
    match error.error_type() {
        ErrorType::Exception(exception) if exception.is_kind_of(ruby.exception_system_exit()) => {
            Some(exception.funcall::<_, _, i32>("status", ()).unwrap_or(1))
        }
        _ => None,
    }
}

/// Build the `SystemExit` that ends the process with the loop's exit code,
/// exactly as `Kernel#exit(exit_code)` would.
fn system_exit(ruby: &Ruby, exit_code: i32) -> Error {
    match ruby
        .exception_system_exit()
        .funcall::<_, _, Exception>("new", (exit_code,))
    {
        Ok(exception) => Error::from(exception),
        Err(error) => error,
    }
}

/// Write a message to Ruby's `$stderr` through `Kernel#warn`.
fn warn(ruby: &Ruby, message: &str) {
    if ruby
        .module_kernel()
        .funcall::<_, _, Value>("warn", (message,))
        .is_err()
    {
        eprintln!("{message}");
    }
}

/// Define the `EventLoop` class methods on the given Ruby module.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_class(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    let event_loop_class = native.define_class("EventLoop", ruby.class_object())?;
    event_loop_class.define_singleton_method("new", function!(RbEventLoop::new, 0))?;
    event_loop_class.define_method("create_proxy", method!(RbEventLoop::create_proxy, 0))?;
    event_loop_class.define_method("run", method!(RbEventLoop::run, 1))?;
    #[cfg(target_os = "macos")]
    event_loop_class.define_method(
        "set_activation_policy",
        method!(RbEventLoop::set_activation_policy, 1),
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{hands_over, needs_ruby, ForRuby, UserEvent, VecDeque};

    #[test]
    fn the_gvl_is_handed_over_only_when_owed_and_no_exit_is_set() {
        assert!(hands_over(true, false));
        assert!(
            !hands_over(true, true),
            "an exit must not wait a time slice"
        );
        assert!(!hands_over(false, false));
    }

    #[test]
    fn events_for_ruby_wait_in_the_inbox_and_the_rest_act_at_once() {
        assert!(needs_ruby(&UserEvent::Task));
        assert!(needs_ruby(&UserEvent::WakeUp(String::new())));
        assert!(!needs_ruby(&UserEvent::Yield));
        assert!(!needs_ruby(&UserEvent::Exit));
    }

    #[test]
    fn a_close_request_waits_behind_the_user_events_before_it() {
        // The inbox is the one queue both go through, as Turn::handle and
        // queue_user_event fill it.
        let mut inbox = VecDeque::new();
        inbox.push_back(ForRuby::User(UserEvent::WakeUp("first".into())));
        inbox.push_back(ForRuby::CloseRequested);
        let order: Vec<_> = inbox
            .into_iter()
            .map(|event| format!("{event:?}"))
            .collect();
        assert_eq!(order, ["User(WakeUp(\"first\"))", "CloseRequested"]);
    }
}
