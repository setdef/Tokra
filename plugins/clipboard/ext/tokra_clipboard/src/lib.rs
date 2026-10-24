// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Native clipboard bindings for Tokra using arboard.
//!
//! This extension provides clipboard access that is Ractor-safe via
//! `frozen_shareable` and `rb_ext_ractor_safe(true)`.

use magnus::{function, method, prelude::*, Error, RString, Ruby};
use std::borrow::Cow;
use std::sync::Mutex;

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Clipboard struct and methods adapted from
// tauri-plugin-clipboard-manager/src/desktop.rs

/// Clipboard wrapper with internal Mutex for thread-safe access.
///
/// Mirrors Tauri's `Clipboard` struct (desktop.rs:22-28). A construction
/// failure is stored rather than raised, so an app on a clipboard-less
/// system still boots and each operation reports the error at call time,
/// exactly as Tauri's per-method match arms do. The `Mutex<Option<_>>`
/// provides interior mutability so methods work on frozen
/// (Ractor-shareable) objects, and lets `cleanup` drop the clipboard
/// before process exit as arboard requires.
pub struct RbClipboard {
    inner: Result<Mutex<Option<arboard::Clipboard>>, String>,
}

impl RbClipboard {
    fn new() -> Self {
        Self {
            inner: arboard::Clipboard::new()
                .map(|c| Mutex::new(Some(c)))
                .map_err(|e| e.to_string()),
        }
    }

    /// Runs `f` against the live clipboard, translating every failure
    /// into a Ruby `RuntimeError`.
    ///
    /// Guard order mirrors Tauri's per-method match arms (desktop.rs:31-42):
    /// a stored construction error raises its message; arboard errors raise
    /// their own Display message, which is exactly what Tauri's
    /// `Error::Clipboard(String)` serializes to the frontend.
    ///
    /// Deviation: Tauri panics on use-after-cleanup (`.as_mut().unwrap()`,
    /// unreachable in Tauri because cleanup only runs at exit). A panic
    /// would abort the Ruby VM, so this raises "Clipboard has been cleaned
    /// up" instead.
    fn with_clipboard<T>(
        &self,
        f: impl FnOnce(&mut arboard::Clipboard) -> Result<T, arboard::Error>,
    ) -> Result<T, Error> {
        let ruby = Ruby::get().unwrap();
        let mutex = self
            .inner
            .as_ref()
            .map_err(|msg| Error::new(ruby.exception_runtime_error(), msg.clone()))?;
        let mut guard = mutex.lock().unwrap();
        let result = guard.as_mut().map_or_else(
            || {
                Err(Error::new(
                    ruby.exception_runtime_error(),
                    "Clipboard has been cleaned up",
                ))
            },
            |clipboard| {
                f(clipboard).map_err(|e| Error::new(ruby.exception_runtime_error(), e.to_string()))
            },
        );
        drop(guard);
        result
    }

    /// Reads text from the clipboard, mirroring desktop.rs:62-70.
    ///
    /// An empty clipboard raises arboard's `ContentNotAvailable` message,
    /// exactly as Tauri's `get_text()?` propagates it.
    ///
    /// Warning: This method should not be used on the main thread!
    /// Otherwise the underlying libraries may deadlock on Linux, freezing
    /// the whole app, when trying to copy data copied from this app, for
    /// example if the user copies text from the `WebView`.
    fn read_text(&self) -> Result<String, Error> {
        self.with_clipboard(arboard::Clipboard::get_text)
    }

    /// Writes text to the clipboard, mirroring desktop.rs:31-42.
    fn write_text(&self, text: String) -> Result<(), Error> {
        self.with_clipboard(|clipboard| clipboard.set_text(text))
    }

    /// Reads an image from the clipboard, mirroring desktop.rs:103-116.
    ///
    /// Returns `(rgba, width, height)` where `rgba` is a binary Ruby
    /// String in row-major order from top to bottom — the same shape as
    /// `Tokra::Native.image_from_bytes`. An empty clipboard raises
    /// arboard's `ContentNotAvailable` message, exactly as Tauri's
    /// `get_image()?` propagates it.
    ///
    /// Warning: This method should not be used on the main thread!
    /// Otherwise the underlying libraries may deadlock on Linux, freezing
    /// the whole app, when trying to copy data copied from this app, for
    /// example if the user copies text from the `WebView`.
    fn read_image(&self) -> Result<(RString, usize, usize), Error> {
        let image = self.with_clipboard(arboard::Clipboard::get_image)?;
        let ruby = Ruby::get().unwrap();
        Ok((ruby.str_from_slice(&image.bytes), image.width, image.height))
    }

    /// Writes an RGBA image to the clipboard, mirroring desktop.rs:44-59.
    ///
    /// Deviation: Tauri passes the image straight to arboard, but arboard
    /// 3.6.1's macOS backend panics on shapes it cannot draw: a byte count
    /// that does not match the dimensions (unwrap on None, platform/osx.rs:88;
    /// fixed on arboard main) and a zero width or height, for which
    /// `CGImageCreate` returns null (platform/osx.rs:73-87). A panic surfaces
    /// as Ruby's uncatchable `fatal`, so these shapes raise arboard's own
    /// `ConversionFailure` message instead, what the other backends report.
    /// The check runs inside the clipboard guard, so a failed or cleaned-up
    /// clipboard reports its own error first, as Tauri's match arms do.
    fn write_image(&self, rgba: RString, width: usize, height: usize) -> Result<(), Error> {
        let bytes = rgba.to_bytes();
        self.with_clipboard(|clipboard| {
            if !is_drawable_rgba(bytes.len(), width, height) {
                return Err(arboard::Error::ConversionFailure);
            }
            clipboard.set_image(arboard::ImageData {
                width,
                height,
                bytes: Cow::Borrowed(&bytes),
            })
        })
    }

    /// Writes HTML to the clipboard, mirroring desktop.rs:72-87.
    ///
    /// `alt_text`, when present, becomes the plain-text flavor that
    /// non-HTML consumers read.
    fn write_html(&self, html: String, alt_text: Option<String>) -> Result<(), Error> {
        self.with_clipboard(|clipboard| clipboard.set_html(html, alt_text))
    }

    /// Clears the clipboard, mirroring desktop.rs:89-100.
    fn clear(&self) -> Result<(), Error> {
        self.with_clipboard(arboard::Clipboard::clear)
    }

    /// Drops the clipboard, mirroring desktop.rs:118-122.
    ///
    /// According to arboard docs the clipboard must be dropped before
    /// exit. Since Ruby does not guarantee finalizer order at exit, the
    /// plugin calls this on `RunEvent::Exit`.
    fn cleanup(&self) {
        if let Ok(mutex) = &self.inner {
            mutex.lock().unwrap().take();
        }
    }
}

// SPDX-SnippetEnd

/// Whether arboard can draw an RGBA buffer of `len` bytes as a
/// `width` by `height` image: both dimensions non-zero and exactly four
/// bytes per pixel.
const fn is_drawable_rgba(len: usize, width: usize, height: usize) -> bool {
    width != 0 && height != 0 && len != 0 && len == width.saturating_mul(height).saturating_mul(4)
}

impl magnus::DataTypeFunctions for RbClipboard {}

// SAFETY: Result<Mutex<Option<arboard::Clipboard>>, String> is Send + Sync.
// arboard::Clipboard is Send + Sync on all platforms.
// This enables frozen_shareable for Ractor shareability.
#[allow(unsafe_code)]
unsafe impl magnus::TypedData for RbClipboard {
    fn class(ruby: &magnus::Ruby) -> magnus::RClass {
        use magnus::Class;
        static CLASS: magnus::value::Lazy<magnus::RClass> = magnus::value::Lazy::new(|ruby| {
            let module = ruby.define_module("TokraClipboard").unwrap();
            let native = module.define_module("Native").unwrap();
            let class = native
                .define_class("Clipboard", ruby.class_object())
                .unwrap();
            class.undef_default_alloc_func();
            class
        });
        ruby.get_inner(&CLASS)
    }

    fn data_type() -> &'static magnus::DataType {
        static DATA_TYPE: magnus::DataType =
            magnus::typed_data::DataTypeBuilder::<RbClipboard>::new(
                c"TokraClipboard::Native::Clipboard",
            )
            .free_immediately()
            .size()
            .frozen_shareable()
            .build();
        &DATA_TYPE
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    use magnus::Class;

    // Mark this extension as Ractor-safe.
    // This allows methods to be called from non-main Ractors.
    // SAFETY: We ensure thread safety via Mutex<Option<Clipboard>>.
    #[allow(unsafe_code)]
    unsafe {
        rb_sys::rb_ext_ractor_safe(true);
    }

    let module = ruby.define_module("TokraClipboard")?;
    let native = module.define_module("Native")?;

    let clipboard_class = native.define_class("Clipboard", ruby.class_object())?;
    clipboard_class.undef_default_alloc_func();
    clipboard_class.define_singleton_method("new", function!(RbClipboard::new, 0))?;
    clipboard_class.define_method("read_text", method!(RbClipboard::read_text, 0))?;
    clipboard_class.define_method("write_text", method!(RbClipboard::write_text, 1))?;
    clipboard_class.define_method("read_image", method!(RbClipboard::read_image, 0))?;
    clipboard_class.define_method("write_image", method!(RbClipboard::write_image, 3))?;
    clipboard_class.define_method("write_html", method!(RbClipboard::write_html, 2))?;
    clipboard_class.define_method("clear", method!(RbClipboard::clear, 0))?;
    clipboard_class.define_method("cleanup", method!(RbClipboard::cleanup, 0))?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::is_drawable_rgba;

    #[test]
    fn accepts_four_bytes_per_pixel() {
        assert!(is_drawable_rgba(8, 2, 1));
        assert!(is_drawable_rgba(8, 1, 2));
    }

    #[test]
    fn rejects_zero_dimensions_and_empty_bytes() {
        assert!(!is_drawable_rgba(0, 0, 0));
        assert!(!is_drawable_rgba(0, 0, 5));
        assert!(!is_drawable_rgba(0, 5, 0));
        assert!(!is_drawable_rgba(4, 0, 1));
    }

    #[test]
    fn rejects_mismatched_byte_counts() {
        assert!(!is_drawable_rgba(7, 2, 1));
        assert!(!is_drawable_rgba(9, 2, 1));
        assert!(!is_drawable_rgba(4, usize::MAX, 2));
    }
}
