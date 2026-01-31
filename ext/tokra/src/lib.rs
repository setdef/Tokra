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
//!
//! # Thread Safety Model
//!
// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Thread safety model documentation adapted from tauri-runtime-wry/lib.rs safety comments
//!
//! This module follows the same thread safety patterns as Tauri. `Window` and
//! `WebView` types are not inherently Send-safe because they're bound to the
//! main OS thread. However, we mark our wrappers as Send with the following
//! invariant:
//!
//! **INVARIANT: All access to `EventLoop`, `Window`, and `WebView` happens
//! exclusively on the main thread via the tao event loop callback.**
//!
//! Ruby's Ractors communicate with the main thread through the Proxy, which
//! sends messages to wake the event loop. The event loop then processes these
//! on the main thread where Window/WebView access is safe.
//!
//! This pattern is identical to Tauri's `tauri-runtime-wry` crate:
//! - `unsafe impl Send for WindowsStore {}` (lib.rs:433)
//! - `unsafe impl Send for DispatcherMainThreadContext<T> {}` (lib.rs:451)
//! - `unsafe impl Send for WindowBuilderWrapper {}` (lib.rs:809)
// SPDX-SnippetEnd

mod event_loop;
mod proxy;
mod responders;
mod user_event;
mod webview;
mod window;

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

    // Note: Event classes (IpcEvent, WakeUpEvent, etc.) are now defined in Ruby
    // using Data.define in lib/tokra/native/events.rb

    Ok(())
}
