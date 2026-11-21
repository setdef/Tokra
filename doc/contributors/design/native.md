<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Native Layer

This document says how Tokra's Rust extension, `ext/tokra`, meets Ruby:
which crates it links and which it leaves to Ferro, how a crate's API
becomes Ruby, what a window's handles are, which thread its objects
belong to, and how the event loop shares Ruby's GVL with the app's other
threads. It is for Tokra's contributors. Why crates live where they do
is ADR 011, and why the loop keeps the GVL is ADR 012. Each module's own
documentation in `ext/tokra/src/` holds the sources it rests on.

## Where each crate lives

Tokra's extension links the windowing stack: tao, wry, muda, and
tray-icon. Every other crate a plugin needs comes from a Ferro gem, and
the plugin is pure Ruby. A crate in the table below gets exactly one
native home: no two gems that one app might load link it. tray-icon and
muda share one home, as do ratatui and crossterm, since tray-icon takes
muda's menu objects and ratatui takes crossterm's backend.

Each extension keeps its Rust symbols private (rustc exports only
`Init_*` and `ruby_abi_version`), so two copies of a crate never share
code. The danger is state the operating system keeps once per process:

| Crate | A second copy in the process |
|---|---|
| tao, every version | crashes: fixed Objective-C class names, and NSApp's one delegate |
| tray-icon, every version | crashes: the fixed `TaoTrayTarget` class |
| wry before 0.54.3 (Tokra locks 0.54.1) | crashes: fixed class names |
| muda, with objc2 0.6.3 in either lockfile | crashes; on Windows, menu IDs also clash on a shared window |
| global-hotkey | misroutes: on macOS the last copy swallows every hotkey |
| notify-rust (macOS) | misroutes: each copy undoes the other's bundle hook and steals its delegate |
| crossterm | misroutes: two copies race on stdin and terminal mode |

arboard, rfd, open, os_info, sys-locale, auto-launch, keyring, image,
dirs, url, idna, and time keep no such state. A second copy of them,
even at another version, is harmless: Tokra's extension links url and
idna through wry while ferro-url links its own, and time through wry's
cookie while ferro-time links its own. This was read from objc2 0.6.3
and 0.6.5 (`define_class.rs`), tao 0.37.2, wry 0.54.1 and 0.57.1
(commit 40a7032, "fix(macOS): panic when loading multiple dylibs"), muda
0.21.2, tray-icon 0.26.1, global-hotkey 0.9.0, mac-notification-sys
0.6.15, and crossterm 0.29.0.

One more coupling reaches into the event loop: muda's keyboard
accelerators on Windows need the loop that owns the window to call
`TranslateAcceleratorW`. The rest of the windowing crates need an OS
event loop on the right thread, not tao's, and global-hotkey on Linux
runs its own thread.

A Rust value cannot enter another gem's Rust API: magnus checks every
wrapped object against its own gem's type record, so handing one gem's
window to another gem's method raises `TypeError` (magnus
`r_typed_data.rs:380-400`). Plain Ruby values and byte strings cross
freely, and so do raw window handles passed as Integers, which wry and
rfd take as any `HasWindowHandle` and muda as an `isize` HWND or a GTK
window. A raw handle is unsafe: nothing tracks the window's lifetime,
and the handle works only on the thread that owns the window. So a raw
handle crosses into another gem only when that gem's crate never
dereferences it ("Window handles").

## Translating a crate's API

Tokra's native values and Ferro's gems translate a crate's API into Ruby
by one table, after AGENTS.md's design precedence: Rust constructs with
no Ruby meaning are translated, never ported.

| Rust | Ruby |
|---|---|
| crate `arboard` | gem `ferro-arboard`, `require "ferro/arboard"`, module `Ferro::Arboard` |
| type, method, and variant names | kept: `Clipboard#get_text`, `ImageData`, `Error::ContentNotAvailable` |
| `Result<T, E>` | returns `T`, or raises |
| an error enum | an exception class per variant under the crate's `Error < StandardError`, with the crate's `Display` text as the message |
| `Option<T>` | `T` or `nil` |
| `String`, `&str`, `Cow<str>`, `impl Into<Cow<str>>` | `String` |
| `Vec<u8>`, `&[u8]`, `Cow<[u8]>` | binary `String` |
| `PathBuf`, `&Path`, `impl AsRef<Path>` | `String` |
| a struct with public fields | `Data.define` |
| a borrowing builder (`clipboard.get().text()`) | an object that holds its clipboard: `clipboard.get.text` |
| lifetimes, `self` consumption, `Send`/`Sync` bounds | dropped; documented where they change behavior |
| a Cargo feature | an additive feature is built in; one that relaxes a safety default stays off |
| a `#[cfg(target_os)]` item or platform trait | defined only on that platform, so `respond_to?` answers |

A Cargo feature that adds behavior, such as a codec or a platform
backend, is built in. A feature that relaxes a safety default, such as
Tauri's `process-relaunch-dangerous-allow-symlink-macos`, stays off. If
one is ever exposed, it becomes an opt-in the app developer sets in
code, named after the feature and off by default, never an environment
variable, so whoever runs the app cannot turn it on. This rule was
recorded on 2026-10-28 for plan 039.

The crate's rustdoc, examples, and tests are the answer key, and tests
run against the real crate, never a stub. A deviation the table does
not cover is a design call, written down in the docs of the gem or class
that makes it.

## Window handles

Tauri's `Window` implements raw-window-handle's `HasWindowHandle` by
asking its dispatcher, so the handle is read on the main thread whichever
thread asks, and any failure of the getter becomes
`HandleError::Unavailable`, as it does for a closed window
(`crates/tauri/src/window/mod.rs:943-949`; tauri-runtime-wry
`src/lib.rs:2012-2018`, `3244-3253`). `Window`, `WebviewWindow`, `App`,
and `AppHandle` implement `HasDisplayHandle` through the runtime handle,
on the calling thread (`window/mod.rs:951-957`,
`webview/webview_window.rs:1410-1426`, `app.rs:2353-2367`).

`Tokra::Window#window_handle` and `#display_handle`,
`Tokra::AppHandle#display_handle`, and `Tokra::App#display_handle` port
those impls; Tokra has no `WebviewWindow` for the fourth. Each returns a
`Tokra::RawWindowHandle` value or raises its error. The values are one
`Data` class per struct tao can answer with, with raw-window-handle
0.6.2's field names: `Win32WindowHandle(hwnd, hinstance)`,
`WindowsDisplayHandle`, `AppKitWindowHandle(ns_view, window_number)`,
`AppKitDisplayHandle`, `XlibWindowHandle(window, visual_id)`,
`XlibDisplayHandle(display, screen)`, `WaylandWindowHandle(surface)`,
and `WaylandDisplayHandle(display)`. The crate's enums wrap one struct
per variant; in Ruby the struct is the variant, and the same holds for
dpi's `Position` and `Size`. The borrowed `WindowHandle<'a>` and its
`as_raw` drop with the lifetime they carry. `HandleError` is a
`StandardError` with a subclass per variant, `NotSupported` and
`Unavailable`, whose messages are the crate's `Display` text.
`AppKitWindowHandle#window_number`, the window's `-[NSWindow
windowNumber]`, has no raw-window-handle field: a number names a window
AppKit can look up, where an address from Ruby can point anywhere, so a
binding such as ferro-rfd asks AppKit for the window instead of trusting
`ns_view`, which keeps the crate's meaning.

What tao 0.34.5 answers (`src/window.rs:1422-1437`,
`src/event_loop.rs:344-350`):

| Platform | Window handle | Display handle |
|---|---|---|
| Windows | `Win32 { hwnd, hinstance }` (`platform_impl/windows/window.rs:438-457`) | `Windows`, empty |
| macOS | `AppKit { ns_view }`, the content view (`macos/window.rs:1494-1510`, `1561-1563`) | `AppKit`, empty |
| Linux, X11 | `Xlib { window, visual_id: 0 }`, GDK's XID | `Xlib { display, screen }` from a new `XOpenDisplay` (`linux/window.rs:948-999`) |
| Linux, Wayland | `Wayland { surface }` | `Wayland { display }`, GDK's |

tao never answers Xcb, and an X11 window lacks a GDK window only before
it is realized, when tao answers `Unavailable`.

Every handle is read on the main thread, through `RuntimeContext`'s
getter; a getter that cannot reach the loop, or whose answer never
comes, raises `Unavailable`, as Tauri maps its getter's failure. Tauri
reads the display handle on the calling thread; Tokra cannot, since its
event loop is inside `run_return` while the app runs and its native
objects answer only the main thread, so `AppHandle#display_handle` asks
the app's first window for tao's `Window: HasDisplayHandle` through the
same getter. tao builds both answers from the same default display.
Before `App#run` builds the window, as in the setup hook, there is
nothing to ask, and the call raises `Unavailable`. A Tokra window
closes only when its event loop ends; after that a call from another
thread raises `Unavailable`, and a call on the main thread, in a
`RunEvent::Exit` handler or an `at_exit` hook, still runs.

tao's X11 display handle opens a connection to the X server on every
call and never closes it, and when `XOpenDisplay` fails, tao 0.34.5
passes the null pointer on, which faults inside libX11: undefined
behavior. Tauri reads the display handle for each dialog's parent on
Linux, so each leaks a connection. Tokra asks tao for the X11 display
handle once and answers every later call with that first display, which
stays open for the life of the process (`raw_handle.rs`). The cache is
set only from a successful answer, and Wayland's display is GDK's own,
so it needs none. Every consumer shares one Xlib connection, which is
sound only on the main thread, since nothing in Tokra calls
`XInitThreads`. When Tokra moves to tao 0.37 or later, the null check
is tao's (`linux/window.rs:984-992`), and the cache remains only for the
leak.

A handle is safe to read and unsafe to use. The native layer copies each
field out of tao's answer: a pointer becomes its address, an ID its
number, and nothing reads through a pointer. The danger is a consumer
that turns the Integer back into a pointer, such as Fiddle or another
gem's Rust: raw-window-handle promises a borrowed handle's pointers only
for the borrow's lifetime (`src/borrowed.rs:200-257`), and Ruby has no
lifetime to hold it to. `RawWindowHandle`'s RDoc says to use a handle on
the main thread, while the window is open, with a library that says it
takes one. An XID or `HWND` that outlives its window names nothing, or a
later window; an `NSView` or `wl_surface` address that outlives it
points at freed memory. How `tokra-dialog` parents its dialogs with
these handles is in its README. A Wayland dialog has no parent because
rfd builds the portal's `wayland:<handle>` from the raw surface; a
binding that took a handle exported with `xdg-foreign`, which GDK can
make (`gdk_wayland_window_export_handle`), would never follow a pointer,
and is a Ferro follow-up.

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
