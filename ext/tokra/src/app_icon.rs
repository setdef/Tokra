// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! The app's icon on `NSApp`, which Tauri sets in development.
//!
//! A Tauri app run from its sources on macOS has no bundle, so the Dock
//! shows a generic icon. Tauri's `App` sets the icon its codegen read from
//! `icons/` on `NSApp` when the runtime is ready (`app.rs:2413-2429` at
//! vendor/tauri `9f0306fbc`). `Tokra::App#run` calls
//! `Native.set_app_icon_for_nsapp` at the same point (plan 054, phase 3).
//! macOS only: the function is not defined elsewhere.

#[cfg(target_os = "macos")]
use magnus::{function, Error, RString, Ruby};

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: adapted from tauri/crates/tauri/src/app.rs:2413-2429 at vendor/tauri 9f0306fbc

/// Makes `bytes`, an image file's raw contents, `NSApp`'s icon image:
/// `NSData` over a copy of the bytes, an `NSImage` from that data, and
/// `-[NSApplication setApplicationIconImage:]`.
///
/// # Errors
///
/// `RuntimeError` "creating icon" when `NSImage` cannot read the bytes,
/// the message of Tauri's `expect`, which panics (plan 054, decision 8).
/// `ThreadError` off the main thread: Tauri skips the check (its "TODO:
/// Enable this check"), which Tokra does not, since `AppKit` must be
/// called on the main thread.
#[cfg(target_os = "macos")]
#[allow(unsafe_code)]
fn set_app_icon_for_nsapp(ruby: &Ruby, bytes: RString) -> Result<(), Error> {
    use objc2::{AllocAnyThread, MainThreadMarker};
    use objc2_app_kit::{NSApplication, NSImage};
    use objc2_foundation::NSData;

    let Some(mtm) = MainThreadMarker::new() else {
        return Err(Error::new(
            ruby.exception_thread_error(),
            "the app icon can only be set on the main thread",
        ));
    };
    let data = NSData::with_bytes(&bytes.to_bytes());
    let app = NSApplication::sharedApplication(mtm);
    let Some(app_icon) = NSImage::initWithData(NSImage::alloc(), &data) else {
        return Err(Error::new(ruby.exception_runtime_error(), "creating icon"));
    };
    // SAFETY: `setApplicationIconImage:` is marked unsafe only because the
    // property "might not allow `None`" (objc2-app-kit 0.3.2
    // `src/generated/NSApplication.rs:729-737`); this passes `Some`, a
    // live `NSImage` just made, on the main thread (`mtm`), as Tauri
    // calls it (`app.rs:2427`).
    unsafe { app.setApplicationIconImage(Some(&app_icon)) };
    Ok(())
}

// SPDX-SnippetEnd

/// Defines `Native.set_app_icon_for_nsapp` on macOS, and nothing
/// elsewhere.
///
/// # Errors
///
/// Returns an error if function definition fails.
#[cfg(target_os = "macos")]
pub fn define_functions(_ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    native.define_module_function(
        "set_app_icon_for_nsapp",
        function!(set_app_icon_for_nsapp, 1),
    )?;
    Ok(())
}
