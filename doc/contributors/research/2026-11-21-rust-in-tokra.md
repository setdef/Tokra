<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# The Rust in Tokra: what each line is, and what it takes to ship none

2026-11-21. A read-only audit, made from `trunk` at `c1c8ef7`. Nothing
but this file was changed. No build, test, or gate ran on the
workstation; every count below comes from reading files, `wc`, `grep`,
and `cargo metadata`, and the facts about Ruby's behavior come from two
short runs on a Linux build machine, recorded in "Spikes".

It sizes a decision already made: Tokra will ship no native extension.
The crates Tauri depends on for windowing (tao, wry, muda, tray-icon)
will be bound one to one in Ferro, and Tauri's own logic, which today is
partly Rust inside `ext/tokra`, will be Ruby in Tokra. The note does not
argue the decision. It says what the 14,480 lines in `ext/tokra/src` are,
what of them can become Ruby, what must stay native somewhere, how big
the Ferro gem will be, and a path of small steps from here to there.

In January the Rust layer was estimated at about 500 lines for the whole
port, with 300 to 400 more for menus, trays, and dialogs
(`doc/contributors/chats/006.md:655-760`). The dialogs and notifications
did go to Ferro. The rest grew for three reasons this note measures:
Tauri's own runtime logic was ported into Rust (about a quarter of the
code), the GVL and the platform's main thread needed glue nobody had
counted (about a sixth), and a binding that never panics Ruby's VM costs
guards the estimate left out.

What it was read against:

- Tauri: the pinned submodule `vendor/tauri` at `9f0306fbc`. Paths under
  `crates/` are in that submodule.
- The crates as `cargo metadata --format-version 1` in `ext/tokra`
  resolves them from `Cargo.lock`: tao 0.34.5, wry 0.54.1, muda 0.17.1,
  tray-icon 0.21.0, window-vibrancy 0.6.0, png 0.17.16, ico 0.5.0,
  windows 0.61.3, objc2-app-kit 0.3.2, gtk 0.18.2, webview2-com 0.38.2,
  dpi 0.1.2, raw-window-handle 0.6.2, read in Cargo's registry copy.
- Ruby: the `ruby/ruby` checkout at master `b84532add7` (2026-11-20),
  whose `NEWS.md` is the 4.1.0 development NEWS; fiddle 1.1.8 as Ruby
  4.0.9 bundles it.
- Ferro: its repository as it stands, read only: `AGENTS.md`, the former ADR 001 (now ADR 020),
  `doc/contributors/design/translation.md` and `repository.md`, the
  `bind-crate` skill, its plans 001 to 010, and the seven gems in
  `gems/`.

## Summary

**What the lines are.** Every line of `ext/tokra/src` was sorted into
one of six kinds, by region, with the file and line where each region
starts (the method is under "How the lines were sorted"). "Code" counts
lines that are neither blank nor comment; the 9,222 code lines include
the tests.

| Kind | All lines | Code lines | Share of code |
|---|---:|---:|---:|
| (a) One-to-one wrapper over a crate's call | 5,883 | 3,443 | 37% |
| (b1) Glue needed wherever app code runs: thread affinity, signals, exceptions | 813 | 425 | 5% |
| (b2) Glue needed only because Ruby threads share the main Ractor's lock with the loop | 1,123 | 611 | 7% |
| (c) Tauri's own behavior, written in Rust | 3,383 | 2,137 | 23% |
| (d) Tests | 2,500 | 2,176 | 24% |
| (e) Guards that keep a crate from panicking or aborting Ruby's VM | 778 | 430 | 5% |
| **Total** | **14,480** | **9,222** | |

**What can become Ruby.** All of (c), 3,383 lines, ports Tauri's
`tauri-runtime-wry`, `tauri`, and `tauri-codegen`, and none of it is
behavior Ruby cannot express. About 1,750 of those lines are Ruby over a
one-to-one binding of tao, wry, muda, tray-icon, window-vibrancy, png,
and ico: name tables, the window-id map, the web-context store, window
placement sums, event mapping. The other 1,630 lines are code where
Tauri itself calls the operating system directly, through the `windows`
crate, objc2's AppKit, GTK, or WebView2's COM interfaces; undecorated
window resizing is 1,016 of them. Plain calls among those can be Ruby
through Fiddle, except where a C struct passes by value, which Fiddle
cannot do. The one thing Ruby cannot soundly do with the tools it ships
is be the callback that Windows or GTK calls inside the native event
loop: a window procedure, a subclass procedure, a GTK signal handler.
Fiddle's closures re-take the GVL with the call ADR 012 found unsound,
and let a Ruby exception unwind through Rust's frames. That covers the
undecorated-resizing handlers and the Windows focus handler, about 990
lines.

**What must stay native, somewhere.** The glue in (b1) is needed whoever
runs app code and wherever: tao's and wry's objects belong to the main
thread, Ruby's garbage collector frees objects on whichever thread
sweeps, Ruby's signals reach a loop that holds the lock only if
something wakes it, and a Ruby exception must not unwind through tao's
frames. Any Ruby binding of tao carries it, so it moves to Ferro with
the binding. The glue in (b2) exists because app code and Tokra's
dispatcher run as Ruby threads in the main Ractor, beside a loop that
holds that Ractor's lock. It stays as long as Tokra lets an app start a
`Thread`, which Tauri's fidelity asks it to, even after commands marked
async run in Ractors. Ruby 4.1's new `rb_nogvl` flag does not change why
ADR 012 rejected releasing the GVL around the whole loop. Ruby 4.1's
per-Ractor garbage collection does change what Ractors can do beside
the loop: on Ruby 4.0.9 a worker Ractor stopped dead for the whole three
seconds the main Ractor held its lock in a native call, because the
worker needed a collection; on 4.1 it ran and collected throughout.

**How big the Ferro gem is.** The four crates' public APIs, at Tokra's
locked versions, have about 860 items (functions, methods, types, trait
methods, public fields) and about 790 enum variants, 512 of them tao's
keyboard keys. Tokra binds about half of the methods by name today.
Measured by what Ferro's seven gems cost, 10 to 28 lines of non-test
Rust per item with a median of 15, binding all of it is about 13,000
lines of non-test Rust (8,600 to 24,000), and binding only what Tauri
calls is about 9,600 (6,400 to 17,900), plus about 1,000 lines of the
glue above. Today's extension has 7,046 non-test code lines. So
shipping no extension in Tokra moves Rust into Ferro and grows it; what
shrinks is Tauri's logic in Rust, which goes to Ruby. the former ADR 011 (now ADR 020)'s reason
for one native library still holds: wry builds into tao's window, muda
and window-vibrancy follow the window's pointers, and tray-icon takes
muda's menus as Rust values. One native library, however many Ruby gems
sit over it.

**A path.** About fifty steps, each landing on trunk alone. Tauri's
logic moves to Ruby first, over today's extension, which exposes the
one-to-one calls it needs; then Tokra's Ruby talks to its native layer
through one seam; then the Ferro gem grows behind that seam until a
process can load it instead of `ext/tokra`, never beside it. Seven
steps are large. The async commands and the Ractor-crossing responder
meet this work at the event-loop proxy and the protocol responder, which
should be designed once, in the Ferro binding.

## How the lines were sorted

Each file was read for its `//!` header, its items (a script listed
every `fn`, `struct`, `impl`, and `mod` with its line span), its SPDX
snippets, which name the Tauri source a region adapts, and the code of
each region where the name was not enough. A region runs from its first
line to the next region's first line, so doc comments and blank lines
count with the code they precede. Module headers and `use` lines count
with the file's first region.

The kinds:

- **(a) Wrapper.** The region calls a crate's function or method, and
  converts its arguments and answer between Ruby and Rust. Registering
  methods with Ruby counts here. A Tauri runtime arm whose body is one
  tao call (`window.set_title(t)`) is a wrapper; Tauri's logic around it
  is the dispatch, and Tokra's Ruby already does that.
- **(b1) Glue needed wherever app code runs.** Thread affinity of
  platform objects, dropping them on their own thread, waking the loop
  for Ruby's signals, Ruby exceptions inside the loop's callback.
- **(b2) Glue needed only for Ruby threads in the main Ractor.** Handing
  the main Ractor's lock to other Ruby threads while the loop waits or a
  menu tracks.
- **(c) Tauri's behavior.** The region decides what Tauri decides: a
  name table, a sum, a per-platform choice of calls, a store, a direct
  platform call. Each is cited to the Tauri file it ports.
- **(d) Tests.** Rust test modules.
- **(e) Guards.** Code that refuses, before the crate sees it, an input
  the crate would panic or abort on, which would end Ruby's VM. Ferro's
  `AGENTS.md` asks every binding for exactly this ("No input reachable
  from Ruby may panic the crate"), so these move with the binding.

A file whose header says "wrapper" but whose code decides what Tauri
decides was sorted by the code. Where a region mixes kinds, it went to
the larger. The counts are within a few dozen lines per file of any
other careful reading; the totals by kind are within a few percent.

## 1. What every line is

### Per file

All lines / code lines, by kind. b1 and b2 as in the summary.

| File | Lines | a | b1 | b2 | c | d | e |
|---|---:|---:|---:|---:|---:|---:|---:|
| `app_icon.rs` | 74 | | | | 74/30 | | |
| `cached_icon.rs` | 481 | 11/5 | | | 160/78 | 154/111 | 156/90 |
| `cookie.rs` | 326 | 230/158 | | | | 96/86 | |
| `event_loop.rs` | 1,011 | 324/205 | 316/172 | 170/105 | 120/60 | 81/73 | |
| `event_loop_target.rs` | 234 | 143/57 | | 76/44 | | 15/14 | |
| `fs.rs` | 287 | 109/39 | 95/57 | | | 83/76 | |
| `gvl_handoff.rs` | 361 | | | 293/141 | | 68/63 | |
| `icon.rs` | 165 | 64/30 | | | | 46/41 | 55/33 |
| `image.rs` | 54 | 54/20 | | | | | |
| `interrupt_check.rs` | 134 | | 75/35 | | | 59/55 | |
| `lib.rs` | 169 | 137/64 | 32/0 | | | | |
| `menu.rs` | 1,660 | 1,117/789 | 28/19 | 44/35 | 144/104 | 32/31 | 295/166 |
| `menu_loop.rs` | 728 | | | 351/208 | | 377/310 | |
| `path.rs` | 34 | 34/12 | | | | | |
| `proxy.rs` | 289 | 263/123 | | 26/16 | | | |
| `raw_handle.rs` | 165 | 149/91 | | | | | 16/1 |
| `responders.rs` | 152 | 66/18 | | | | 86/67 | |
| `taskbar.rs` | 217 | 107/68 | | | 81/51 | 29/27 | |
| `thread_bound.rs` | 307 | | 163/85 | | | 144/127 | |
| `tray.rs` | 669 | 370/225 | 14/11 | | 102/72 | 108/98 | 75/38 |
| `undecorated_resizing.rs` | 1,063 | | | | 1,016/698 | 47/34 | |
| `user_event.rs` | 414 | 127/37 | 44/18 | 53/25 | | 190/172 | |
| `vibrancy.rs` | 285 | 11/4 | | | 219/150 | 55/51 | |
| `web_context.rs` | 573 | | | | 320/180 | 253/217 | |
| `webview.rs` | 1,629 | 1,086/639 | 24/12 | | 127/60 | 249/226 | 143/81 |
| `webview_focus.rs` | 95 | | | | 95/51 | | |
| `window.rs` | 481 | 459/232 | 22/16 | | | | |
| `window_builder.rs` | 874 | 306/225 | | | 248/180 | 282/256 | 38/21 |
| `window_ext.rs` | 378 | 134/67 | | | 244/137 | | |
| `window_labels.rs` | 162 | | | | 116/52 | 46/41 | |
| `window_state.rs` | 899 | 582/335 | | | 317/234 | | |
| `without_gvl.rs` | 110 | | | 110/37 | | | |
| **Total** | **14,480** | **5,883/3,443** | **813/425** | **1,123/611** | **3,383/2,137** | **2,500/2,176** | **778/430** |

### The regions

Where each file's regions start, and what they are. Line numbers are at
`c1c8ef7`.

- `app_icon.rs` 1 (c): Tauri sets the dev icon on `NSApp`
  (`crates/tauri/src/app.rs:2413-2429`), calling AppKit through
  objc2-app-kit.
- `cached_icon.rs` 1 (c): tauri-codegen's `CachedIcon` over png and ico
  (`crates/tauri-codegen/src/image.rs:50-99`); 117 (e): refusing an ICO
  whose claims run past its bytes, before ico aborts on the allocation;
  273 (c): the panic text codegen would give; 317 (a); 328 (d).
- `cookie.rs` 1 (a): wry's `cookie::Cookie` to and from plain values;
  231 (d).
- `event_loop.rs` 1 (a): tao's `EventLoopBuilder`, its proxy, the
  activation policy; 200 (b1): the Ctrl-C handler and interrupt ticker;
  252 (b2): the GVL hand-off hook, Windows' poll ticker and menu hook;
  294 (c): keeping a requested exit (`tauri-runtime-wry/src/lib.rs:4029-4031`);
  306 (b1): `run_return` and raised errors; 371 (b2): the turn and the
  inbox, where events wait for the end of the iteration (ADR 012);
  402 (c): `WindowEventWrapper::map_from_tao`, the window-id lookup,
  `map_theme`; 479 and 506 (b2): when to hand over, and the batch;
  576 and 596 (a): events into Ruby values; 583 (c): exit after the last
  window; 694 (c): `RequestExit` asks the handlers; 712 (b1): Ruby
  exceptions across the loop; 911 (a); 931 (d).
- `event_loop_target.rs` 1 (a): tao's window target, lent for each
  callback, and its monitor, cursor, and theme getters; 28 (b2): the
  menu hand-off flag; 104 (a); 220 (d).
- `fs.rs` 1 (a): std's `fs::read` error text; 35 (b1): the read without
  the GVL, with its retry loop; 130 (a); 205 (d).
- `gvl_handoff.rs` 1 (b2); 294 (d).
- `icon.rs` 1 (a): tao's `Icon::from_rgba`; 53 (e): tao's checks
  restated, since GTK panics on a short buffer on Linux; 108 (a); 120 (d).
- `image.rs` 1 (a): the image crate's decoder.
- `interrupt_check.rs` 1 (b1); 76 (d).
- `lib.rs` 1 (a): module list and `init`; 31 (b1): the thread-safety
  model, in prose; 63 (a).
- `menu.rs` 1 (a): muda's event handler through the loop's proxy;
  76 (b1): drop on the main thread; 104 (a); 123 (e): accelerators
  remembered against a muda GTK panic; 172 (a): the item classes;
  296 (e): refusing a submenu cycle and a position past the end; 328 (a);
  759 (e): RGBA checks restated from muda, tray-icon, and tao;
  817 (c): Tauri's 56 `NativeIcon` names (`crates/tauri/src/menu/mod.rs`);
  898 (a): `init_for_nsapp` and its siblings; 935 (c): the Windows
  message hook that translates accelerators (`crates/tauri/src/app.rs:2146-2160`);
  998 (a); 1126 (e): a window's menus kept alive while muda's subclass
  can call into them; 1202 (a): window menus; 1410 (e); 1427 (a):
  context menus; 1488 (b2): the context menu without the GVL; 1532 (a);
  1555 (e): GTK's refusal of items it cannot build; 1618 (a); 1629 (d).
- `menu_loop.rs` 1 (b2): Windows' `WH_MSGFILTER` hook that passes the
  GVL, and runs signal handlers, while a menu tracks; 350 and 560 (d).
- `path.rs` 1 (a): the dirs crate.
- `proxy.rs` 1 (a): tao's `EventLoopProxy` and wry's responder;
  244 (b2): answering on the main thread when called off it (WebKit
  waits on the main run loop, which the GVL would block); 270 (a).
- `raw_handle.rs` 1 (a); 31 (e): the X11 display cached against tao's
  leak and null dereference; 47 (a).
- `responders.rs` 1 (a); 67 (d).
- `taskbar.rs` 1 (c): progress state and title-bar names; 46 (a);
  76 (c): the badge count per platform (`tauri-runtime-wry/src/lib.rs:3482-3534`);
  112 (a); 189 (d).
- `thread_bound.rs` 1 (b1); 164 (d).
- `tray.rs` 1 (a): tray-icon's event handler; 53 (c): Tauri's
  `TrayIconEvent` conversion (`crates/tauri/src/tray/mod.rs`); 155 (a);
  393 (b1): drop on the main thread; 407 (a); 438 (e): refusing a
  missing libappindicator before tray-icon panics; 513 (a); 562 (d).
- `undecorated_resizing.rs` 1 (c): Tauri's module, whole
  (`tauri-runtime-wry/src/undecorated_resizing.rs`, 628 lines, and
  `src/util.rs`, 118): the shared hit test to 109, the Windows child
  window and subclass from 110, the Windows DPI helpers from 716, GTK
  from 894; 1017 (d).
- `user_event.rs` 1 (b1): objects sent to the main thread to drop;
  45 (b2): a protocol answer sent to the main thread; 78 (a): the loop's
  message type; 205 (b2): `Yield`, `Release`, `Respond`; 225 (d).
- `vibrancy.rs` 1 (c): Tauri's `vibrancy` module over window-vibrancy
  (`tauri-utils/src/lib.rs`, `crates/tauri/src/vibrancy/`); 220 (a);
  231 (d).
- `web_context.rs` 1 (c): Tauri runtime's web-context store, one per
  data directory (`tauri-runtime-wry/src/lib.rs`); 321 (d).
- `webview.rs` 1 (a): wry's handlers forwarding IPC and protocol
  requests; 122 (e): a scheme holding NUL; 141 (c): registering a scheme
  once per context, placing the webview, the resize handler
  (`create_webview`); 236 and 498 (a): wry's builder; 684 (c): Windows'
  webview takes its window's theme; 716 (a); 739 (b1): drop on the main
  thread; 763 (a): the webview's methods; 1222 (e): `catch_unwind` at
  wry's known `unwrap` sites; 1346 (a); 1381 (d).
- `webview_focus.rs` 1 (c): Windows focus from WebView2's
  `GotFocus`/`LostFocus` (`tauri-runtime-wry/src/lib.rs:521-549`, `5070-5128`),
  through webview2-com.
- `window.rs` 1 (a); 57 (b1): drop on the main thread; 79 (a).
- `window_builder.rs` 1 (a): tao's builder rows, read from a Hash;
  270 (c): `create_window`'s tabbing, centering, overflow, and parent;
  319 (a); 356 (e): inverted size constraints, which panic in dpi's
  clamp; 394 (c): the parent per platform, the target monitor, the frame,
  the placement sums; 593 (d).
- `window_ext.rs` 1 (a); 41 (c): `WindowExt::set_enabled` per platform
  (`tauri-runtime-wry/src/window/{macos,linux,windows}.rs`): an AppKit
  sheet, GTK's sensitivity, Win32's `EnableWindow`; 200 (a); 223 (c):
  resizable, decorations, and shadow with Windows' undecorated resizing;
  308 (a).
- `window_labels.rs` 1 (c): the runtime's `window_id_map`
  (`tauri-runtime-wry/src/lib.rs:4126-4150`); 117 (d).
- `window_state.rs` 1 (a): sizes, positions, monitors; 70 (c): the
  runtime's name tables for theme, cursor icon, attention, and resize
  direction; 166 (a); 182 (c): `MonitorExt::work_area` through
  `NSScreen`, GDK, and `GetMonitorInfoW` (`tauri-runtime-wry/src/monitor/`),
  centering through `-[NSWindow center]` and `DwmGetWindowAttribute`,
  and the macOS webview's size; 403 (a): tao's getters and setters.
- `without_gvl.rs` 1 (b2).

### The headers, checked against the code

Most headers say what their file does. These do not:

- `lib.rs:1-5` calls the crate "Thin Magnus bindings around `tao`
  (windowing) and `wry`" that "Follows the 'dumb pipe' principle: Rust
  handles platform-native operations while Ruby manages all application
  logic, state, and routing." The crate also binds muda, tray-icon,
  window-vibrancy, image, png, ico, dirs, and std, holds state (the
  web-context store, the window labels, the responder table, the
  accelerator menus), and carries 3,383 lines of Tauri's logic. Its
  module list (`lib.rs:14-27`) names 14 of the 31 modules.
- `event_loop.rs:4-7` says "Event loop wrapper for tao." About half the
  file is glue between the loop and Ruby's threads, and 120 lines are
  Tauri's `handle_event_loop`.
- `webview.rs:4-7` says "`WebView` wrapper for wry." It also holds
  Tauri's `create_webview` decisions and wry's panic guards.
- `proxy.rs:4-7` and `:20-21` call the proxy a handle "for cross-Ractor
  communication" and "for waking up the event loop from Ractors". No
  Ractor but the main one can call it: the extension never calls
  `rb_ext_ractor_safe`, so Ruby raises `Ractor::UnsafeError` for every
  method it defines when another Ractor calls one
  (`vm_insnhelper.c:3597-3600` at Ruby master `b84532add7`). The proxy
  can be shared with a Ractor; it cannot be used there.

`undecorated_resizing.rs`, `web_context.rs`, `window_labels.rs`,
`window_ext.rs`, `vibrancy.rs`, and `webview_focus.rs` say plainly that
they are Tauri's code.

## 2. What of (c) can be Ruby, and what it would need

Each piece of Tauri behavior now in Rust, what a Tokra app developer
gets from it, and the calls a Ruby port needs. "Ruby over the binding"
means Ruby code calling one-to-one methods of a Ferro binding of tao,
wry, muda, tray-icon, or window-vibrancy, which section 4 sizes.

### Ruby over a one-to-one binding (about 1,750 lines)

| What the app developer gets | Lines | Tauri source | What the Ruby needs |
|---|---:|---|---|
| The app exits after its last window, and an exit request asks the handlers first | 120 | `tauri-runtime-wry/src/lib.rs`, `handle_event_loop` | tao's `Event`, `WindowEvent`, and `ControlFlow` in the loop's callback |
| Window events name the window by label, and an unknown window's events are dropped | 116 | `lib.rs:4126-4150` | tao's `WindowId` as a value Ruby can hash |
| Themes, cursor icons, attention types, and resize directions by Tauri's names | 96 | `lib.rs:578-584`, `695-753`, `3467-3478`, `5224-5230` | tao's enum variants by name |
| The taskbar's progress state, title-bar style, and the badge count per platform | 81 | `lib.rs:3482-3534` | tao's `set_progress_bar`, `set_badge_label` (macOS), `set_badge_count` (Linux) |
| A window built centered, kept on its monitor, tabbed or not, with its parent | 248 | `lib.rs:813-1260`, `4318-4436`; `crates/tauri/src/window/mod.rs:62-72` | tao's `WindowBuilder` methods and platform builder traits, and its monitor getters |
| Webviews that share a data directory share one web context, and register each scheme once | 320 + 75 | `lib.rs`, the web-context store and `create_webview` | wry's `WebContext`, `WebViewBuilder::new_with_web_context`, `build`, and on Linux `build_gtk` with tao's `default_vbox` |
| On Windows the webview takes its window's theme | 22 | `create_webview` | wry's `WebViewBuilderExtWindows::with_theme`, tao's `theme` |
| The 56 native menu icons by Tauri's names | 80 | `crates/tauri/src/menu/mod.rs` | muda's `NativeIcon` variants |
| Tray events in Tauri's shape | 102 | `crates/tauri/src/tray/mod.rs` | tray-icon's `TrayIconEvent` values |
| Window effects: vibrancy on macOS, Mica, Acrylic, Blur, and Tabbed on Windows | 219 | `tauri-utils/src/lib.rs`, `crates/tauri/src/vibrancy/` | window-vibrancy's `apply_*` and `clear_*`, bound in the same native library as tao (section 4) |
| Resizable, decorations, and shadow setters that attach Windows' resize border | 85 | `lib.rs`, `handle_user_message` | tao's setters, and the undecorated resizing below |
| The window and tray icons from `tauri.conf.json`, decoded as codegen decodes them | 160 | `crates/tauri-codegen/src/image.rs:50-99` | png 0.17.16's `Decoder` and ico 0.5.0's `IconDir`, each a Ferro gem of its own; neither keeps process-wide state |

All of these are Ruby that reads and writes values: tables, a Hash, sums
of integers, a choice of which method to call. None of them is hard in
Ruby. The work is in the binding they stand on.

### Where Tauri calls the platform directly (about 1,630 lines)

Tauri's runtime depends on four crates for these calls
(`crates/tauri-runtime-wry/Cargo.toml`): `windows` 0.61 (Win32),
`webview2-com` 0.38 (WebView2's COM interfaces), `objc2`,
`objc2-foundation`, and `objc2-app-kit` 0.3 (AppKit), and `gtk` 0.18
with `webkit2gtk` 2.0. Tokra links the same, except webkit2gtk, which it
reaches through wry.

| What the app developer gets | Lines | Calls | Kind of call |
|---|---:|---|---|
| An undecorated window resizes by its edges on Windows | 776 | `CreateWindowExW` of a child window, `SetWindowSubclass` with a subclass procedure, `SetWindowRgn`, hit tests answered from `WM_NCHITTEST`, DPI through `GetProcAddress` | a window procedure Windows calls |
| The same on Linux | 122 | GTK's `connect_button_press_event`, `connect_motion_notify_event`, and `connect_touch_event` on wry's WebKitGTK view, then `begin_resize_drag` | a signal handler GTK calls |
| A window's focus on Windows follows its webview | 95 | WebView2's `add_GotFocus`, `add_LostFocus` on wry's controller | a COM event handler WebView2 calls |
| Accelerators work on Windows | 63 | tao's `with_msg_hook`, then `TranslateAcceleratorW` with muda's `haccel` | a hook tao calls for every message, then one Win32 call |
| A monitor's work area, and centering a window in it | 221 | `-[NSScreen visibleFrame]`, `-[NSWindow center]`, GDK's `workarea`, `GetMonitorInfoW`, `DwmGetWindowAttribute`, `-[WKWebView frame]` | plain calls; AppKit's return an `NSRect` by value |
| A disabled window | 159 | an AppKit sheet built with `initWithContentRect:styleMask:backing:defer:`, GTK's `set_sensitive`, Win32's `EnableWindow` and `IsWindowEnabled` | plain calls; AppKit's takes an `NSRect` by value |
| The Dock's icon in development on macOS | 74 | `NSData`, `-[NSImage initWithData:]`, `-[NSApplication setApplicationIconImage:]` | plain calls |

The ways Ruby could reach them, weighed against the goals:

- **Fiddle**, bundled with Ruby (1.1.8 in 4.0.9). It calls C functions
  by address: Win32's exports, GTK's, and AppKit's through
  `objc_msgSend`. Three limits, each read in its source. It cannot pass
  or return a C struct by value: `ext/fiddle/` has no struct type for
  libffi, so `visibleFrame` and `initWithContentRect:` are out of reach
  as written. Its methods work only in the main Ractor: `fiddle.c` never
  calls `rb_ext_ractor_safe`. And its closures, the callbacks C calls
  back into Ruby, re-take the GVL with `rb_thread_call_with_gvl` when
  called without it (`ext/fiddle/closure.c:229-232`) and do not rescue
  an exception, so a Ruby error raised in one unwinds through whatever
  called it. A window procedure runs inside tao's Rust message pump, and
  inside `without_gvl` while a context menu tracks; unwinding through
  Rust's frames is undefined behavior, and the re-take is the call ADR
  012 found unsound. So Fiddle serves the plain calls without structs:
  the Dock icon, `EnableWindow`, `GetMonitorInfoW` (it fills a struct
  through a pointer, which Fiddle can), `TranslateAcceleratorW`, GTK's
  `set_sensitive`. It does not serve the callbacks.
- **The ffi gem**, a C extension maintained outside Ruby. It documents
  structs passed by value, which would reach the AppKit calls. Whether
  its callbacks rescue exceptions and how they take the GVL was not
  read; only a compiled copy is on the workstation ("What is not
  known").
- **Ferro bindings of the platform crates.** Ferro binds a crate's whole
  public API. At Tokra's locked versions, with every module counted,
  `windows` has about 100,900 public functions, `objc2-app-kit` about
  8,800, and `gtk` about 6,900. A one-to-one binding of any of them is
  out of proportion to the 1,630 lines it would replace, and a binding
  of only what Tauri calls breaks Ferro's rule. Either needs a Ferro
  decision.
- **A safe address, where one exists.** A pointer passed as an Integer
  is unsafe in Ruby (the former ADR 011 (now ADR 020)). Win32's `HWND` is a handle the system
  checks, so a stale one fails a call instead of crashing it. AppKit's
  `NSWindow` can be found by its window number, as ferro-rfd does (Ferro
  plan 008), so Ruby need not trust an address. GTK's widgets and
  WebView2's COM objects have no such safe name.

Where I think Ruby truly cannot, with what it ships: be the window
procedure, subclass procedure, COM handler, or GTK signal handler that
the platform calls synchronously inside the native loop. That is the
Windows and Linux undecorated resizing and the Windows focus handler,
about 990 lines with their helpers. "Slow" is not the reason: a hit test
in Ruby per mouse move would be fast enough. The reason is soundness:
the callback runs inside Rust's frames, sometimes without the GVL, and
Fiddle's closures neither keep a Ruby exception out of those frames nor
take the GVL back without the interrupt check ADR 012 rejected. A Ruby
callback that never raises and is never called without the GVL would be
sound; nothing in Fiddle can promise either. The ffi gem might, and is
the first thing to read. Failing that, goal 6's last sentence governs:
what Tauri has is implemented, even in Rust, and these handlers would be
Tauri's Rust kept in the windowing gem, with a recorded exception to
Ferro's rule against adding what the crate lacks.

The accelerator hook is a fourth case: tao calls it for every Windows
message. A Ruby block per message is a callback inside the loop too, but
tao calls it from its own Rust, with the GVL held on the main thread, so
a binding of `with_msg_hook` can protect it as it protects the loop's
callback. Its cost per message is unmeasured.

## 3. What of the glue must stay native, on Ruby 4.1

Read against Ruby master `b84532add7`'s `NEWS.md` (4.1.0 development),
`doc/language/ractor.md`, `doc/contributing/concurrency_guide.md`,
`thread.c`, and Tokra's ADR 012 and `doc/contributors/design/native.md`
("Threads" onward).

### Glue that exists only because app code runs as Ruby threads in the main Ractor (b2, 1,123 lines)

The main thread runs tao's loop holding the main Ractor's lock. Every
other Ruby thread in that Ractor needs the same lock to run, so Tokra
hands it over:

- The READY thread-event hook that marks a hand-off owed, and the
  hand-off at `MainEventsCleared` (`gvl_handoff.rs`, `event_loop.rs`
  252-293, 371-575).
- The inbox, where events wait for the end of the iteration, since a
  Ruby callback inside tao's drain loses the lock for a time slice
  (`event_loop.rs` 371-575).
- The context menu run without the GVL (`without_gvl.rs`, `menu.rs`
  1488-1531), and the Windows message-filter hook that hands over while
  a menu tracks (`menu_loop.rs`).
- Answering a protocol request on the main thread when another Ruby
  thread answers, because WebKit makes that thread wait for the main run
  loop, which waits for the lock the thread holds (`proxy.rs` 244-269,
  `user_event.rs` 45-77).
- The flag that tells a getter it ran inside a menu's hand-off
  (`event_loop_target.rs` 28-103).

Today all of it is on the path of every command, because Tokra's
dispatcher (`Tokra::RuntimeContext`) brings other threads' calls to the
main thread and app code may run on any Ruby thread.

### Glue still needed if commands marked async ran in Ractors

All of b2, as long as an app can start a `Thread`. A Tauri app spawns
threads freely and they run beside the loop; goal 1 asks the same of a
Ruby thread, and nothing but the hand-off lets one run while the loop
waits. What changes is that it leaves the hot path: an async command in
a Ractor runs under that Ractor's own lock.

Ractors would need two things b2 does not give. First, a worker Ractor
must be able to call something: today it can call nothing of the
extension (section 1, `proxy.rs`), and the responder captures its
webview (`doc/contributors/design/ipc.md`, "Where commands run"). The
responder is already a request id, an Integer, plus the proxy
(`proxy.rs:175-208`, `responders.rs`); a proxy callable from any Ractor
and an id would cross. Second, the loop must not stop the Ractors. Spike
1 shows that on Ruby 4.0.9 it does: a worker Ractor that allocates
stopped for the whole three seconds the main Ractor held its lock in a
native call, with its collection count flat, while one that did not need
a collection ran on (spike 2). On 4.1 the same worker ran and collected
throughout, since 4.1's collector runs per Ractor and stops the world
only for a global collection (`NEWS.md:609-613`). On 4.0.9, async
commands in Ractors would stall whenever one needed a collection until
the loop next checked interrupts. Two other paths still go through the
main thread on 4.1: a worker's `require` runs on the main thread by
interrupt (`concurrency_guide.md`, "Ruby Interrupt Handling"), and a
global collection still stops every Ractor. Both wait for the loop's
next interrupt check, which the interrupt ticker bounds at about
100 ms.

### Glue needed whatever runs where (b1, 813 lines)

- **Thread affinity.** tao's and wry's objects work only on the thread
  that built them, and Ruby's collector frees an object on whichever
  thread sweeps it (`thread_bound.rs:4-12`). In 4.1 each Ractor collects
  its own heap, but the main Ractor's Ruby threads still share one heap,
  so a window can still be swept on a thread that is not the main one.
  `ThreadBound` and the drops sent to the main thread (`window.rs`,
  `webview.rs`, `tray.rs`, `menu.rs`, `user_event.rs`) stay.
- **Signals.** Ruby runs a signal's handler at the main thread's next
  interrupt check, and the loop's main thread waits in tao holding the
  lock, outside any blocking region, so no signal wakes it
  (`interrupt_check.rs:4-17`). The ticker that wakes it every 100 ms,
  and Ctrl-C's handler, stay.
- **Exceptions inside the loop.** Every Ruby call from tao's callback is
  protected, and an exception that is not a `StandardError` ends the
  loop and is raised once `run` returns (`event_loop.rs` 712-910). Any
  binding whose `run` takes a Ruby block needs this.
- **Reading a file without the lock** (`fs.rs` 35-129), which Ferro's
  translation rule asks of any blocking call.

All of b1 and b2 is machinery of a Ruby binding of tao's loop, not
Tauri's logic, so in a Tokra with no extension it lives in the Ferro
gem. Ferro's translation design says a gem "never runs blocking work
with the GVL held" (`translation.md`, "The error rule"); tao's `run`
must hold it (ADR 012), so the Ferro gem needs that rule's exception,
recorded with ADR 012's reasons.

### Does `RB_NOGVL_PENDING_INTR_FAIL` change ADR 012?

No. ADR 012 rejected releasing the GVL around the whole loop because
`rb_thread_call_with_gvl`, the only public way back into Ruby from
inside tao's callback, checks interrupts on its way out, so a trap such
as `trap("TERM") { exit }` would raise and unwind across tao's and the
platform's frames. On master `b84532add7` that exit path still re-enters
the blocking region with no flags,
`blocking_region_begin(th, brb, prev_unblock.func, prev_unblock.arg, FALSE)`
(`thread.c:2354`), and `unblock_function_set` then runs
`RUBY_VM_CHECK_INTS` (`thread.c:332-345`). The new flag is read only by
`rb_nogvl` on entry (`thread.c:1783-1792`) and inside
`unblock_function_set` when a caller passes it (`thread.c:343-347`);
`rb_thread_call_with_gvl` passes none. And a trap's handler runs whatever
`Thread.handle_interrupt` masks (`thread.c:2915-2924`), so masking does
not help either.

What the flag does offer: a native call can decline to start while an
interrupt is pending, without the check raising. `fs.rs`'s retry loop
and `without_gvl.rs` could use it to enter their blocking calls only
when nothing is pending. It does not make releasing the lock around the
loop sound.

## 4. How big the Ferro gem would be

### The four crates' public APIs

A script read each crate's public files (it skips `platform_impl/` and
wry's private backends, which are not public API) and counted public
functions and methods, public types, trait methods of public traits
(tao's platform extension traits are most of them), public fields, and
enum variants. The counts are approximate (macros and re-exports are
missed), but the same script counted Ferro's crates, so the ratio below
compares like with like.

| Crate | Functions | Types | Trait methods | Fields | Items | Variants |
|---|---:|---:|---:|---:|---:|---:|
| tao 0.34.5 | 137 | 81 | 114 | 47 | 379 | 651, 512 of them keyboard keys |
| wry 0.54.1 | 70 | 34 | 43 | 45 | 192 | 48 |
| muda 0.17.1 | 177 | 29 | 15 | 12 | 233 | 76 |
| tray-icon 0.21.0 | 36 | 13 | 0 | 9 | 58 | 16 |
| **Four crates** | | | | | **862** | **791** |
| window-vibrancy 0.6.0 | 26 | 7 | 0 | 1 | 34 | 26 |

tao's API also returns types of dpi 0.1.2 (about 94 items) and
raw-window-handle 0.6.2 (about 111), which it re-exports; a binding
needs at least the ones tao hands out.

### What Tokra binds today, and what Tauri calls

By distinct method name (a coarse measure, since one name can belong to
several crates): of 322 names across the four crates, Tauri's
`tauri-runtime-wry` and `tauri` call 237, about three quarters (tao 91
of 117, wry 51 of 65, muda 72 of 109, tray-icon 23 of 31), and Tokra's
extension calls 174, about half. Tokra calls only four names Tauri does
not.

### What it costs per item in Ferro

Non-test Rust code lines in each Ferro gem, against its crate's items
counted the same way:

| Gem | Items | Non-test Rust | Per item | Ruby in `lib/` |
|---|---:|---:|---:|---:|
| ferro-idna | 41 | 423 | 10 | 1,410 |
| ferro-url | 141 | 1,516 | 11 | 3,196 |
| ferro-rfd | 92 | 1,112 | 12 | 2,700 |
| ferro-arboard | 44 | 777 | 18 | 1,549 |
| ferro-notify-rust | 102 | 2,272 | 22 | 3,562 |
| ferro-global-hotkey | 28 | 785 | 28 | 3,302 |

The median is 15 lines per item, and 10 to 28 the range. ferro-time
was left out: its crate's items are mostly constants and macros the
script miscounts. Variants cost a line or two each, since a gem binds an
enum by table. Each gem's Ruby side is about twice its Rust.

### The estimate

| Scope | Items | Non-test Rust at 10 / 15 / 28 per item | Plus variants | Plus the loop's glue |
|---|---:|---:|---:|---:|
| The four crates' whole public API | 862 | 8,600 / 12,900 / 24,100 | about 800 | about 1,000 |
| Only what Tauri calls (three quarters) | about 640 | 6,400 / 9,600 / 17,900 | about 600 | about 1,000 |
| Add window-vibrancy, and dpi's and raw-window-handle's types tao returns | up to 240 more | 2,400 / 3,600 / 6,700 | | |

The glue is today's b1 and b2 (1,036 code lines), which section 3 puts
in the binding. The guards in (e), 430 code lines today, are part of
what Ferro's per-item cost already pays for.

Today's extension has 7,046 lines of non-test code, of which the
wrappers and guards are 3,873, binding about half the names at about 8
lines per item: cheaper than Ferro, because Ferro's gems wrap every call
in `catch_unwind`, bind each error variant as a class, and expose
`debug`, iterators, and platform traits the way the translation table
says. So the Ferro gem is likely larger than the extension it replaces:
about 11,000 to 15,000 lines of non-test Rust at the median, with its
Ruby, RBS, and tests on top. What leaves Rust is Tauri's logic, 2,137
code lines, which becomes Ruby in Tokra.

### Does the former ADR 011 (now ADR 020)'s one native library still hold?

Yes, and the code shows why each crate needs the others' Rust values or
pointers:

- wry builds its webview into tao's window as a Rust value: `build` with
  the window on macOS and Windows, and on Linux `build_gtk` with tao's
  `default_vbox`, a GTK object (`webview.rs:175-191`).
- muda follows the window's pointer: `init_for_hwnd_with_theme`,
  `show_context_menu_for_nsview`, `show_context_menu_for_hwnd`, and
  `init_for_gtk_window` take a window from tao (`menu.rs:1262`,
  `:1274`, `:1510`, `:1520`, `:1527`).
- tray-icon takes muda's menu as a Rust value (`tray.rs:408-436`).
- The accelerator hook joins tao's builder to muda's accelerator table
  (`event_loop.rs:85-89`, `menu.rs:935-980`).
- window-vibrancy follows the window's `HWND` or `NSView`, so it joins
  the same library.

A Rust value cannot enter another gem's Rust API, and a pointer that
crosses as an Integer is unsound in a crate that follows it (the former ADR 011 (now ADR 020);
Ferro `repository.md`, "Which crates, in which gem"). And tao and
tray-icon crash as a second copy at every version, wry before 0.54.3,
and muda with objc2 0.6.3 (`native.md`, "Where each crate lives").

What it means for gems: one native library for tao, wry, muda,
tray-icon, and window-vibrancy. Ferro's rule is one gem per crate, but
its `repository.md` already says tray-icon and muda "would share one
gem". Two shapes fit: one Ferro gem that binds all five crates, or one
native gem with a small Ruby gem per crate over it, each with its crate
as its answer key. the former ADR 011 (now ADR 020) rejected moving the stack to Ferro because it
"would give the same native library another name and add a release step
to every windowing change." With Tauri's logic in Ruby, a windowing
change to Tokra rarely touches the binding, so that reason no longer
weighs as it did.

## 5. A path of small steps

Every step below lands on trunk by itself and keeps the gate green.
Steps marked **large** take several sessions or a new subsystem; the
rest are one change each. The path is branch by abstraction: Tokra's
Ruby keeps working over today's extension while the replacement grows,
and the switch happens behind one seam.

One fact shapes the whole path: a process can never load Tokra's
extension and the Ferro gem together, since tao and tray-icon crash as a
second copy. So the replacement cannot take over one class at a time
inside a process. It takes over a whole process at once, behind a seam
chosen when Tokra loads, and the tests can run each backend in its own
process long before the Ferro one is the default.

### A. Tauri's logic moves to Ruby, over today's extension

Each step exposes in `ext/tokra` the one-to-one calls a piece needs,
moves the piece into `lib/`, and deletes its Rust. Steps A1 to A6 are
independent and can run in parallel; A7 and A8 touch `event_loop.rs`
and go one after the other.

1. The name tables in `window_state.rs`, Ruby passing tao's variant
   names.
2. The taskbar's tables and the badge per platform.
3. The 56 native menu icons.
4. The tray event's conversion.
5. Window effects, over a one-to-one binding of window-vibrancy in the
   extension.
6. The config's icons, over two new Ferro gems, ferro-png and ferro-ico
   (two steps in Ferro and a release first; the ICO guards move there).
7. The window-id map, with tao's `WindowId` as a Ruby value.
8. The loop's exits: after the last window, on request, and a requested
   exit kept, with tao's `ControlFlow` set from Ruby.
9. `create_window`'s sums and parent, over a one-to-one `WindowBuilder`
   object in place of the Hash (**large**: `window_builder.rs` and the
   window tests).
10. The web-context store, over a `WebContext` class.
11. `create_webview`'s scheme registration, placement, and Windows
    theme.

### B. Choose the avenue for the platform's own calls

12. A spike, then a decision: Fiddle, the ffi gem, or Rust kept in the
    windowing gem, for each kind of call in section 2's second table.
13. The Dock icon, `EnableWindow`, GTK's sensitivity, and the work area
    on Windows and Linux, by the chosen avenue (one step per platform
    where it is Fiddle).
14. The AppKit calls that pass an `NSRect`, by the chosen avenue.
15. The accelerator hook, as a binding of tao's `with_msg_hook` with a
    Ruby block, if its cost per message allows.
16. Undecorated resizing on Linux.
17. Undecorated resizing on Windows (**large**).
18. Windows focus from WebView2.

Steps 16 to 18 are the callbacks of section 2; if Ruby cannot host them
soundly, each becomes "move this Rust into the windowing gem" in phase
D instead.

### C. One seam between Tokra's Ruby and its native layer

19. A backend seam in `lib/`: every call into `Tokra::Native` goes
    through one module, chosen at load.
20. to 29. One step per native class, each reshaped to its crate's
    one-to-one API behind the seam: the event loop and its events, the
    proxy, the window, the monitor, the webview and its builder, the web
    context, the menu items, the tray icon, the raw handles, and the
    images and paths (images go to the image crate's binding, paths to
    the dirs crate's, each a Ferro gem without process-wide state).

### D. The Ferro gem

30. A Ferro decision: one gem for the five crates, or one native gem
    under five Ruby gems; and the exceptions to its rules this needs
    (the loop holding the GVL; any Tauri Rust kept from phase B).
31. A Ferro plan that enumerates the five crates' public APIs, each item
    bound, translated, or deferred.
32. The gem's skeleton and tao's event loop with the glue of section 3:
    thread affinity, the hand-off, signals, and exceptions (**large**).
33. to 40. One step per group: tao's windows and builder (**large**),
    monitors and dpi, events and keyboard, each platform's extension
    traits, wry's webview and builder (**large**), wry's web context and
    cookies, muda's items and menus (**large**), tray-icon, and
    window-vibrancy.
41. A release, tagged, for Tokra to name.

Phase D can start at once, in parallel with A to C: it is another
repository, and its answer key is the crates, not Tokra.

### E. The switch

42. A second backend behind the seam, over the Ferro gem, with a rake
    task that runs Tokra's suite in processes that load only it
    (**large**).
43. to 46. That task joins the gate area by area, as the backend passes
    it: windows, webviews, menus and trays, the plugins.
47. The default flips to the Ferro backend.
48. `ext/tokra` is deleted, the gemspec loses its extension, and the
    packaging check proves the gem loads with no compiler.
49. The records: the former ADR 001 (now ADR 020), 011, and 012 superseded or amended, and
    `native.md` moved to the Ferro gem's design.

Forty-nine steps, seven of them large. The order puts the smallest,
surest steps first (A1 to A4 are tables), so that the Rust starts
shrinking at once and the pattern is proven before anything depends on
it; the seam comes before the Ferro backend because it is what the
switch swaps behind; and the platform's own calls wait for the spike
in step 12, which is the largest unknown.

### Where this meets the async commands and the Ractor responder

Tauri runs a command in one of three places
(`crates/tauri-macros/src/command/wrapper.rs:236-245`): `sync` on the
main thread, `async` on its async runtime, and `sync_threadpool` for a
command marked async that is not an `async fn`. Tokra has only the
first (`ipc.md`, "Where commands run").

- Async commands on Ruby threads in the main Ractor need nothing new
  from the native layer: b2 already lets those threads run. They can
  land before, during, or after this path, and touch only Ruby
  (`Tokra::RuntimeContext` and the IPC dispatch).
- Async commands in Ractors need a proxy and responder a worker Ractor
  can call, and Ruby 4.1, since on 4.0.9 such a worker stalls whenever
  it needs a collection (spike 1). Both meet this path at one place:
  tao's `EventLoopProxy` and wry's `RequestAsyncResponder`, which are
  `Send` and so may be called from any Ractor by Ferro's rule
  (`translation.md`, "Ractors"). Designed once in step 32 and in the
  webview group of step 33 to 40, they serve both works. Built first in
  `ext/tokra`, they are built twice.
- Step 8 (the loop's exits) and step 19 (the seam) touch the code the
  async dispatch will touch; sequence those with it, not beside it.

## 6. What is not known

Each unknown that could change an answer above, and the smallest thing
that would settle it.

1. **Whether the ffi gem's callbacks are sound inside tao's loop**: do
   they rescue a Ruby exception, and how do they take the GVL back? It
   decides whether undecorated resizing and the focus handler can be
   Ruby. Settle: read `ext/ffi_c/Function.c` at the version Tokra would
   pin.
2. **Whether Ruby-GNOME can wrap a GTK widget that tao or wry made**,
   from its address. It decides whether GTK's calls and signal handlers
   can go through GObject introspection instead of Fiddle. Settle: read
   Ruby-GNOME's `GLib::Object` source for a constructor from a pointer.
3. **What a one-to-one event stream costs.** Today Rust drops the window
   events Ruby does not hear (`event_loop.rs:427-442`); a binding hands
   Ruby every tao event, cursor moves included, and every Windows
   message to an accelerator hook. Settle: in step 32, count events per
   second under Xvfb while a pointer moves, and time one Ruby callback.
4. **Which crate versions the Ferro gem binds.** Ferro binds a crate's
   latest release; Tokra's fidelity is to the versions the pinned Tauri
   locks (tao 0.34.5, wry 0.54, muda 0.17.1, tray-icon 0.21.0). The gap
   changes behavior and the API counts above. Settle: the Ferro decision
   in step 30.
5. **Whether Ferro accepts one native library for five crates**, and
   the GVL exception. Settle: step 30.
6. **Whether Tokra must keep supporting app code on Ruby threads in the
   main Ractor.** If an app may never start a `Thread` that touches
   Tokra, b2 shrinks to the menu and signal cases. Settle: the
   maintainer's call, by goal 1.
7. **Whether 4.1.0 ships per-Ractor collection as master has it.**
   Spike 1 ran a 4.1.0 development build of 2026-11-20. Settle: run
   spike 1 again on 4.1.0's first preview or release.
8. **Whether the interrupt ticker lets a worker Ractor's collection
   through on 4.0.9**, bounding spike 1's stall at about 100 ms instead
   of the length of the native call. It matters only if Ractor commands
   come before Ruby 4.1. Settle: a spike in which the main Ractor holds
   its lock in 100 ms native calls and calls `Thread.pass` between them
   when `Thread.pending_interrupt?` or the ticker's check says so.
9. **The item counts.** The script misses macro-made items and counts by
   line pattern. Settle: the Ferro plan in step 31 enumerates them by
   hand, as Ferro's skill requires.

## Spikes

Two runs on a Linux build machine, from `trunk` at `c1c8ef7`, nothing of
Tokra loaded. Ruby 4.1 was a development build of master `b84532add7`,
built from source; the two Rubies ran on two different machines, so
compare the shapes, not the rates.

### Spike 1: a worker Ractor while the main Ractor holds its lock

Fiddle calls libc's `sleep(3)` with `need_gvl: true`, so the main
Ractor's thread keeps the main Ractor's lock for three seconds, as
Tokra's loop keeps it while tao waits. A thread in the main Ractor ticks
every 0.1 s, to show the lock was held. A worker Ractor allocates and
reports its progress and collection count every 0.25 s.

```ruby
require "fiddle"
$stdout.sync = true
puts RUBY_DESCRIPTION
libc = Fiddle.dlopen(nil)
held = Fiddle::Function.new(libc["sleep"], [Fiddle::TYPE_UINT], Fiddle::TYPE_UINT, need_gvl: true)
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
t0 = clock.()
ticks = []
ticker = Thread.new { loop { ticks << (clock.() - t0); sleep 0.1 } }
worker = Ractor.new(t0) do |start|
  samples = []
  n = 0
  last = 0.0
  loop do
    Array.new(2000) { "x" * 40 }
    n += 1
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    if now - last >= 0.25
      samples << [now, n, GC.count]
      last = now
    end
    break if now > 5.5
  end
  samples
end
sleep 1
a = clock.() - t0
held.call(3)
b = clock.() - t0
puts format("main Ractor held its lock in sleep(3) from %.2fs to %.2fs", a, b)
samples = worker.respond_to?(:value) ? worker.value : worker.take
ticker.kill
during = ticks.count { |t| t > a + 0.15 && t < b - 0.05 }
puts "main-Ractor thread ticks while held: #{during} (#{ticks.size} in all, one per 0.1s when free)"
samples.each do |t, n, gc|
  puts format("worker t=%5.2fs iterations=%7d GC.count=%5d%s", t, n, gc, (t > a && t < b) ? "  <- main held" : "")
end
```

Ruby 4.0.9:

```
ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-linux]
main Ractor held its lock in sleep(3) from 1.00s to 4.00s
main-Ractor thread ticks while held: 0 (25 in all, one per 0.1s when free)
worker t= 0.25s iterations=   1255 GC.count=  452
worker t= 0.50s iterations=   2526 GC.count=  906
worker t= 0.75s iterations=   3857 GC.count= 1381
worker t= 1.00s iterations=   5083 GC.count= 1819  <- main held
worker t= 4.00s iterations=   5084 GC.count= 1819
worker t= 4.25s iterations=   6321 GC.count= 2269
worker t= 4.50s iterations=   7659 GC.count= 2756
worker t= 4.75s iterations=   8977 GC.count= 3235
worker t= 5.00s iterations=  10206 GC.count= 3682
worker t= 5.25s iterations=  11522 GC.count= 4160
```

Ruby 4.1.0dev:

```
ruby 4.1.0dev (2026-11-20T13:18:13Z master b84532add7) +PRISM [x86_64-linux]
main Ractor held its lock in sleep(3) from 1.00s to 4.00s
main-Ractor thread ticks while held: 0 (25 in all, one per 0.1s when free)
worker t= 0.25s iterations=    499 GC.count=  995
worker t= 0.50s iterations=    982 GC.count= 1961
worker t= 0.75s iterations=   1473 GC.count= 2942
worker t= 1.00s iterations=   1975 GC.count= 3947  <- main held
worker t= 1.25s iterations=   2547 GC.count= 5091  <- main held
worker t= 1.50s iterations=   3067 GC.count= 6131  <- main held
...
worker t= 3.75s iterations=   8497 GC.count=16990  <- main held
worker t= 4.00s iterations=   9208 GC.count=18413
...
worker t= 5.25s iterations=  12378 GC.count=24753
```

On 4.0.9 the worker made one iteration in the three seconds and no
collection: it waited for the main Ractor to join the collection's
barrier. On 4.1 it collected about 14,000 times while the main Ractor
held its lock. On both, no thread in the main Ractor ran while the lock
was held, which is the case b2 exists for.

### Spike 2: which worker stalls on Ruby 4.0.9

The same held call, with three worker Ractors: one allocating, one
allocating after `GC.disable`, one adding integers.

```ruby
require "fiddle"
$stdout.sync = true
puts RUBY_DESCRIPTION
libc = Fiddle.dlopen(nil)
held = Fiddle::Function.new(libc["sleep"], [Fiddle::TYPE_UINT], Fiddle::TYPE_UINT, need_gvl: true)
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
workers = %i[allocates allocates_gc_disabled integers].map do |kind|
  Ractor.new(t0, kind) do |start, mode|
    GC.disable if mode == :allocates_gc_disabled
    n = 0
    marks = {}
    loop do
      if mode == :integers
        x = 0
        1000.times { |i| x += i }
      else
        Array.new(200) { "x" * 40 }
      end
      n += 1
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      marks[:at_1_2] ||= n if now >= 1.2
      marks[:at_3_8] ||= n if now >= 3.8
      break if now > 4.5
    end
    [mode, marks[:at_1_2], marks[:at_3_8], GC.count]
  end
end
sleep 1
a = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
held.call(3)
b = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
puts format("main held its lock from %.2fs to %.2fs", a, b)
workers.each do |w|
  mode, n1, n2, gc = w.respond_to?(:value) ? w.value : w.take
  puts format("%-22s iterations at 1.2s=%8d at 3.8s=%8d  progress while held=%8d  GC.count=%d", mode, n1, n2, n2 - n1, gc)
end
```

Ruby 4.0.9:

```
ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-linux]
main held its lock from 1.01s to 4.03s
allocates              iterations at 1.2s=    5756 at 3.8s=   20336  progress while held=   14580  GC.count=5
allocates_gc_disabled  iterations at 1.2s=    6091 at 3.8s=   19708  progress while held=   13617  GC.count=5
integers               iterations at 1.2s=    7366 at 3.8s=   22561  progress while held=   15195  GC.count=5
```

All three ran while the main Ractor held its lock, and no collection
happened: on 4.0, `GC.disable` in one Ractor turns collection off for
the process (4.1's `NEWS.md:624-626` records the change to per-Ractor
holds). With spike 1, this places the 4.0.9 stall at the collection: a
worker Ractor runs beside the held lock until it needs to collect, and
then waits for the main Ractor. (The 4.1 build was not in this run's
workspace, so spike 2 ran on 4.0.9 only.)

## Recorded statements this audit found untrue

| Where | What it says | What is true |
|---|---|---|
| `AGENTS.md:10` | "Rust (rb_sys + magnus, in `ext/`) is a thin binding over tao and wry; Ruby owns all logic (the former ADR 001 (now ADR 020))." | The extension binds muda, tray-icon, window-vibrancy, image, png, ico, dirs, and std as well, and 3,383 of its lines (2,137 code) are Tauri's logic: `tauri-runtime-wry`'s event mapping, window placement, web-context store, window-id map, undecorated resizing, and `WindowExt`; `tauri`'s vibrancy, native icons, tray events, accelerator hook, and dev icon; `tauri-codegen`'s icon decoding. |
| `doc/contributors/adr/001.md:44-46` | "The Rust layer is a dumb pipe: a magnus extension ... that wraps tao and wry and knows nothing of commands or state, and everything else is Ruby." | It knows nothing of commands. It holds state (the web contexts by data directory, the window labels, the pending responders, the accelerator menus) and the Tauri logic above. |
| `doc/contributors/adr/001.md:73-74` | "AGENTS.md states the rule, that Rust is a thin binding and Ruby owns all logic". | The rule is stated, and nothing checks it; the code does not follow it (above). |
| `doc/contributors/design/native.md:20-22` | "The extension wraps platform types and holds no application logic (the former ADR 001 (now ADR 020)): it passes raw events and messages to Ruby, and Ruby owns command routing, security checks, and state." | Command routing and security checks are Ruby. Events reach Ruby filtered and mapped as Tauri's runtime maps them (`event_loop.rs:402-478`), and the state above is Rust's. |
| `doc/contributors/design/native.md:22-25` | "The Rust side wraps the crate's type in a magnus class under `Tokra::Native` and exposes the crate's own methods". | Many classes expose Tauri's runtime messages rather than the crate's methods: a window opens from one Hash of Tauri's builder rows (`window_builder.rs:79-126`), and its setters are `handle_user_message` arms. |
| `ext/tokra/src/proxy.rs:4-7`, `:20-21`; `lib.rs:20` | The proxy is "for cross-Ractor communication", "for waking up the event loop from Ractors", "Ractor-safe". | It can be shared with a Ractor, but only the main Ractor can call it: the extension never calls `rb_ext_ractor_safe`, so Ruby raises `Ractor::UnsafeError` for its methods in any other Ractor (`vm_insnhelper.c:3597-3600`), as `native.md:245-247` itself says. Nothing in `test/` starts a Ractor. |
| `ext/tokra/src/lib.rs:1-5` | "Thin Magnus bindings around `tao` (windowing) and `wry` ... Ruby manages all application logic, state, and routing." | As for `AGENTS.md:10`. Its module list names 14 of 31 modules. |
| `doc/contributors/adr/001.md:46-49` | "the target is for the app's logic, file I/O, and heavy computation to run in a worker Ractor". | Not untrue as a target, but on Ruby 4.0.9 a worker Ractor stops whenever it needs a collection while the main Ractor waits in tao holding its lock (spike 1); the target needs Ruby 4.1 or an interrupt check in the loop that lets the collection through. |

ADR 012's reason for rejecting a loop that releases the GVL still holds
on Ruby 4.1's development source (section 3).
