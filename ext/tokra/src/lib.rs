// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Tokra Native Extension
//!
//! Thin Magnus bindings around `tao` (windowing) and `wry` (`WebView`).
//! Follows the "dumb pipe" principle: Rust handles platform-native operations
//! while Ruby manages all application logic, state, and routing.
//!
//! # Module Structure
//!
//! This crate is organized to mirror Tauri's architecture:
//!
//! - [`user_event`] - Cross-thread communication payload enum
//! - [`event_loop`] - Main event loop wrapper (`Tokra::Native::EventLoop`)
//! - [`window`] - Window wrapper (`Tokra::Native::Window`)
//! - [`webview`] - `WebView` wrapper with custom protocol (`Tokra::Native::WebView`)
//! - [`proxy`] - Ractor-safe proxy for cross-thread communication (`Tokra::Native::Proxy`)
//! - [`responders`] - Async protocol responder storage
//! - [`image`] - PNG/ICO decoding (`Tokra::Native.image_from_bytes`)
//! - [`fs`] - File reading with std's errors (`Tokra::Native.fs_read`)
//! - [`menu`] - muda's menus (`Tokra::Native::Menu` and its items)
//! - [`tray`] - tray-icon's tray icons (`Tokra::Native::TrayIcon`)
//! - [`thread_bound`] - Values usable only on the thread that created them
//! - [`gvl_handoff`] - Hands the GVL to other Ruby threads while the loop waits
//!
//! # Thread Safety Model
//!
// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Thread safety model adapted from tauri-runtime-wry/lib.rs safety comments
//!
//! tao's `EventLoop` and wry's `WebView` are not `Send`: they belong to the
//! thread that built them, the main thread. Tauri marks its own main-thread
//! types `Send` with "we ensure this type is only used on the main thread"
//! (tauri-runtime-wry `lib.rs:431-454`), and its dispatcher keeps that
//! promise by running every call there (`send_user_message`,
//! `lib.rs:234-254`).
//!
//! Tokra enforces the same invariant in two layers:
//!
//! - **Here**, [`thread_bound::ThreadBound`] holds each non-`Send` value with
//!   the id of its thread, hands it out only on that thread, and leaks it
//!   rather than drop it anywhere else. Every `EventLoop`, `Window`, and
//!   `WebView` method raises `ThreadError` on another thread, so no Ruby
//!   code can reach a platform object from the wrong thread, and a garbage
//!   collection on another thread can never run its destructor there
//!   (a webview is sent home to be dropped, `webview.rs`).
//! - **In Ruby**, `Tokra::RuntimeContext` mirrors Tauri's dispatcher: a call
//!   on the main thread runs at once, and a call from any other thread is
//!   queued and run by the loop (`UserEvent::Task`).
//!
//! The loop holds the GVL while it waits, and [`gvl_handoff`] wakes it to
//! hand the GVL to any other Ruby thread that wants it. Ractors cannot call
//! these types at all: the extension never calls `rb_ext_ractor_safe`, so
//! Ruby refuses its methods to every non-main Ractor (Ruby v4.0.1
//! `doc/extension.rdoc:2215-2220`). Only `Proxy` is shared across threads
//! and Ractors by design.
// SPDX-SnippetEnd

mod event_loop;
mod event_loop_target;
mod fs;
mod gvl_handoff;
mod icon;
mod image;
mod interrupt_check;
mod menu;
mod path;
mod proxy;
mod raw_handle;
mod responders;
mod thread_bound;
mod tray;
mod undecorated_resizing;
mod user_event;
mod webview;
mod window;
mod window_ext;
mod window_state;
mod without_gvl;

// Re-export for use by other modules
pub use event_loop::RbEventLoop;
pub use proxy::RbProxy;
pub use user_event::UserEvent;
pub use webview::RbWebView;
pub use window::RbWindow;

use magnus::{prelude::*, Error, Ruby};

// =============================================================================
// Helper Functions
// =============================================================================

/// Get the Ruby `RuntimeError` exception class.
///
/// This is a helper to avoid using the deprecated `magnus::exception::runtime_error()`.
///
/// # Panics
///
/// Panics if called outside the Ruby VM context (e.g., before Ruby is initialized).
#[must_use]
pub fn runtime_error() -> magnus::ExceptionClass {
    Ruby::get()
        .expect("Ruby VM not initialized")
        .exception_runtime_error()
}

// =============================================================================
// Module Initialization
// =============================================================================

/// Initialize the Tokra Ruby module.
///
/// # Errors
///
/// Returns an error if module or method definition fails.
#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let tokra = ruby.define_module("Tokra")?;
    let native = tokra.define_module("Native")?;

    // Define all classes
    event_loop::define_class(ruby, native)?;
    window::define_class(ruby, native)?;
    webview::define_class(ruby, native)?;
    proxy::define_class(ruby, native)?;
    icon::define_class(ruby, native)?;
    menu::define_classes(ruby, native)?;
    tray::define_classes(ruby, native)?;

    // Path resolution functions (thin wrapper around dirs crate)
    path::define_functions(ruby, native)?;

    // Image decoding functions (thin wrapper around image crate)
    image::define_functions(ruby, native)?;

    // File reading (thin wrapper around std::fs::read)
    fs::define_functions(ruby, native)?;

    // Note: Event classes (IpcEvent, WakeUpEvent, etc.) are now defined in Ruby
    // using Data.define in lib/tokra/native/events.rb

    Ok(())
}
