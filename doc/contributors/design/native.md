<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Native Layer

This document says how Tokra's Rust extension, `ext/tokra`, meets Ruby:
which thread its objects belong to, and how the event loop shares Ruby's
GVL with the app's other threads. It is for Tokra's contributors. Why the
loop keeps the GVL is ADR 012. Each module's own documentation in
`ext/tokra/src/` holds the sources it rests on.

## Threads

tao's `EventLoop` and wry's `WebView` belong to the thread that built
them, the main thread. Tauri marks its main-thread types `Send` and
keeps the promise with a dispatcher: a call on the main thread runs at
once, and a call from any other thread travels through the event loop
proxy and runs there (tauri-runtime-wry `send_user_message`,
`src/lib.rs:234-254`). Ruby can hand any object to any thread, and its
garbage collector frees an object on whichever thread sweeps it, so
Tokra keeps the same promise in two layers.

- **The native layer enforces it.** `ThreadBound<T>` (`thread_bound.rs`)
  holds each platform value, the loop, every window, and every webview,
  with its thread's id, hands it out only there, and leaks it rather
  than drop it anywhere else. Every `EventLoop`, `Window`, and `WebView`
  method raises `ThreadError` on another thread. A window or webview
  that Ruby frees on another thread is sent to the loop and dropped on
  the main thread. tao calls its `Window` `Send + Sync`, but on macOS
  dropping one closes it with a synchronous dispatch to the main thread
  (`platform_impl/macos/window.rs:1734-1739`, `util/async.rs:242-249`),
  which deadlocks when the dropping thread holds the GVL the main thread
  waits for, so windows get the same wrapper. Only `Proxy` crosses
  threads.
- **Ruby dispatches.** `Tokra::RuntimeContext` is Tauri's dispatcher.
  `Window`, `Webview`, and `AppHandle` send every native call through it,
  and `run_on_main_thread` lands on all of them, as in Tauri. Ruby blocks
  stay in a Ruby queue; the native event (`UserEvent::Task`) only wakes
  the loop, so Rust never holds a Ruby object across threads.

A main-thread callback that waits on a thread which waits on the main
thread deadlocks, as in Tauri.

## The GVL hand-off

tao's loop runs inside `EventLoop#run`, holding the GVL. The loop keeps
it, and hands it over once per iteration (`gvl_handoff.rs`): a READY
thread-event hook (`rb_internal_thread_add_event_hook`) fires whenever a
thread starts waiting for the GVL, which includes every time-slice
switch. It only marks a hand-off owed, and wakes the loop when the mark
was clear, so a busy thread cannot flood the loop. The loop clears the
mark and calls `Thread.pass`, through magnus's protected `funcall`, at
`MainEventsCleared`, after the platform's events are in. Installing the
hook marks a hand-off owed at once, for threads that were already
waiting. A CPU-bound thread gets one time slice per turn of the loop, so
each busy thread adds about one time slice to how long an event waits.

Ruby has no thread-event hook on Windows, where a ticker thread sends
the loop a `UserEvent::Yield` every 10 ms while other Ruby threads
exist. The loop always waits with `ControlFlow::Wait`, as Tauri's does: a
`WaitUntil` deadline made tao's wait thread start an iteration without
checking for a running handler, and inside a context menu's nested
message loop tao panicked "either event handler is re-entrant". tao
buffers a user event there instead.

## Events wait for the end of the iteration

tao drains its user-event channel until it is empty before it ends an
iteration (`platform_impl/macos/app_state.rs:110-121`). A Ruby callback
inside the drain loses the GVL for a full time slice whenever another
thread wants it, so a busy thread and a steady sender would keep the
iteration from ever ending. The drain only queues the events Ruby needs,
and `MainEventsCleared` delivers that batch (`event_loop.rs`). A window's
close request joins the same queue in arrival order, so Ruby still sees
the user events that came before it first, as in Tauri: tao's macOS
`cleared()` hands over user events, then the window events it held
(`app_state.rs:394-398`).

## Interrupts and signals

`Thread.pass` runs pending interrupts. A `SignalException` from Ruby's
default handler for TERM, HUP, or QUIT, an `Interrupt`, a `Thread#raise`
aimed at the main thread, or any other exception that is not a
`StandardError`, raised there or in a callback, ends the loop and is
raised again by `EventLoop#run` once the loop is down. A `StandardError`
from a callback is reported and the loop keeps running; `SystemExit`
ends it with its status. The loop keeps an exit already set instead of
resetting the flow for the next event, as Tauri does (tauri-runtime-wry
`lib.rs:4029-4031`).

No signal wakes a loop that waits in tao holding the GVL, so a ticker
thread (`interrupt_check.rs`) wakes the loop every 100 ms, Ruby's default
time slice, and the loop hands over whenever Ruby has an interrupt
pending. A signal's handler, Ruby's default or an app's `trap`, runs
within about 100 ms even when nothing else happens, and the idle loop
pays about ten wake-ups a second.

## Protocol answers from other threads

WebKit answers a scheme task on the main run loop and makes any other
thread wait (`-[WKURLSchemeTaskImpl didReceiveResponse:]` calls
`callOnMainRunLoopAndWait`). A Ruby thread waiting there holds the GVL
the main thread needs, so neither moves. So `Proxy#respond` answers
directly on the main thread, and from any other thread sends the answer
to the loop, which answers on the main thread. Tauri needs no such step:
it has no GVL.

## Menus that block the main thread

A context menu blocks the main thread in a nested run loop until it
closes. That one native call releases the GVL (`without_gvl.rs`), so
other Ruby threads keep running, as Rust threads do in Tauri. It is
sound because no callback of Tokra's, tao's, wry's, or muda's calls Ruby
in the nested loop; the module names the exceptions. Events and blocks
for the main thread wait for the menu to close, as in Tauri, and so does
a signal.

On Windows a menu that tracks outside tao's handler, such as the tray's
menu, the menu bar, and the system menu, keeps the GVL. A thread-level
`WH_MSGFILTER` hook on the loop's thread hears each message the menu's
modal loop peeks (`menu_loop.rs`). Whenever this thread holds the GVL it
calls `Thread.pass` once per tick of the poll ticker, and whenever Ruby
has an interrupt pending, so a signal's handler runs while a menu tracks
even with no other thread. An exception from that hand-off ends the menu
with `EndMenu` and waits for the next `MainEventsCleared`, which handles
it as it handles its own.
