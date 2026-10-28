// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! `Tokra::Native::Icon`: tao's window icon, built on any thread (plan 041,
//! decision 4).
//!
//! Tauri converts an `Image` into tao's `Icon` before it sends the window
//! a message (tauri-runtime-wry `src/lib.rs:490-499`, `2278-2286`), so a
//! bad image fails the caller. tao's `Icon` is `Send` on every platform
//! (its macOS and Linux icons hold bytes; its Windows icon declares
//! `unsafe impl Send`, tao 0.34.5 `platform_impl/windows/icon.rs:70`), so
//! it can be built here and handed to the main thread.

use magnus::{function, prelude::*, Error, RString, Ruby};
use tao::window::Icon;

/// tao's window icon, ready for `Native::Window#set_window_icon`.
#[magnus::wrap(class = "Tokra::Native::Icon", free_immediately, size)]
pub struct RbIcon(Icon);

impl RbIcon {
    /// The tao icon, for the window that takes it.
    pub(crate) fn icon(&self) -> Icon {
        self.0.clone()
    }

    /// tao's `Icon::from_rgba` for `rgba`, `width` pixels wide and
    /// `height` high.
    ///
    /// # Errors
    ///
    /// Returns a `RuntimeError` with tao's `BadIcon` text when the bytes
    /// do not make a `width` by `height` RGBA image (on Linux, the text of
    /// [`bad_icon`], which checks first), or when Windows fails to make the
    /// icon.
    fn from_rgba(rgba: RString, width: u32, height: u32) -> Result<Self, Error> {
        let rgba = rgba.to_bytes().to_vec();
        #[cfg(any(
            target_os = "linux",
            target_os = "dragonfly",
            target_os = "freebsd",
            target_os = "netbsd",
            target_os = "openbsd"
        ))]
        if let Some(message) = bad_icon(&rgba, width, height) {
            return Err(Error::new(crate::runtime_error(), message));
        }
        Icon::from_rgba(rgba, width, height)
            .map(Self)
            .map_err(|e| Error::new(crate::runtime_error(), e.to_string()))
    }
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0
// SPDX-SnippetCopyrightText: 2014-2021 The winit contributors
// SPDX-SnippetCopyrightText: 2021-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The RGBA checks and their texts adapted from tao 0.34.5 src/icon.rs

/// Why tao would refuse `rgba` as a `width` by `height` icon, in its own
/// words, or `None` when it would take it.
///
/// On Linux tao checks nothing (`platform_impl/linux/icon.rs:37-48`), and
/// GTK's `Pixbuf::from_mut_slice` then panics on the main thread for a
/// buffer shorter than the image (gdk-pixbuf 0.18.5 `src/pixbuf.rs:24-60`),
/// which would end Ruby's VM. So on Linux this makes the checks tao's
/// `RgbaIcon::from_rgba` makes on macOS and Windows (`src/icon.rs:103-136`),
/// in the same order, with `BadIcon`'s texts (`src/icon.rs:42-79`). tao's
/// `BadIcon` variants are `#[non_exhaustive]`, so only tao can build one,
/// and this answers its text instead.
#[cfg(any(
    target_os = "linux",
    target_os = "dragonfly",
    target_os = "freebsd",
    target_os = "netbsd",
    target_os = "openbsd",
    test
))]
fn bad_icon(rgba: &[u8], width: u32, height: u32) -> Option<String> {
    // tao's `PIXEL_SIZE`: four bytes, one each for red, green, blue, alpha.
    const PIXEL_SIZE: usize = 4;

    if width == 0 || height == 0 {
        return Some(format!(
            "The specified dimensions ({width:?}x{height:?}) must be greater than zero."
        ));
    }
    if !rgba.len().is_multiple_of(PIXEL_SIZE) {
        let byte_count = rgba.len();
        return Some(format!(
            "The length of the `rgba` argument ({byte_count:?}) isn't divisible by 4, making it impossible to interpret as 32bpp RGBA pixels."
        ));
    }
    let Some(width_x_height) = (width as usize).checked_mul(height as usize) else {
        return Some(format!(
            "The specified dimensions multiplication has overflowed ({width:?}x{height:?})."
        ));
    };
    let pixel_count = rgba.len() / PIXEL_SIZE;
    (pixel_count != width_x_height).then(|| {
        format!(
            "The specified dimensions ({width:?}x{height:?}) don't match the number of pixels supplied by the `rgba` argument ({pixel_count:?}). For those dimensions, the expected pixel count is {width_x_height:?}."
        )
    })
}

// SPDX-SnippetEnd

/// Define `Tokra::Native::Icon`.
///
/// # Errors
///
/// Returns an error if class definition fails.
pub fn define_class(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    let class = native.define_class("Icon", ruby.class_object())?;
    class.define_singleton_method("from_rgba", function!(RbIcon::from_rgba, 3))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::bad_icon;

    /// Each answer is tao's own text for the same bytes, which only macOS
    /// and Windows tao would give.
    #[test]
    fn bad_icon_refuses_what_tao_refuses_in_its_words() {
        assert_eq!(bad_icon(&[0; 16], 2, 2), None);
        assert_eq!(
            bad_icon(&[], 0, 2).as_deref(),
            Some("The specified dimensions (0x2) must be greater than zero.")
        );
        assert_eq!(
            bad_icon(&[0; 5], 1, 1).as_deref(),
            Some("The length of the `rgba` argument (5) isn't divisible by 4, making it impossible to interpret as 32bpp RGBA pixels.")
        );
        assert_eq!(
            bad_icon(&[0; 12], 2, 2).as_deref(),
            Some("The specified dimensions (2x2) don't match the number of pixels supplied by the `rgba` argument (3). For those dimensions, the expected pixel count is 4.")
        );
    }

    /// tao's own check gives the same texts on this platform.
    #[cfg(not(any(
        target_os = "linux",
        target_os = "dragonfly",
        target_os = "freebsd",
        target_os = "netbsd",
        target_os = "openbsd"
    )))]
    #[test]
    fn bad_icon_matches_taos_own_check() {
        for (rgba, width, height) in [
            (vec![0; 16], 2, 2),
            (vec![], 0, 2),
            (vec![0; 5], 1, 1),
            (vec![0; 12], 2, 2),
        ] {
            let tao = tao::window::Icon::from_rgba(rgba.clone(), width, height)
                .err()
                .map(|e| e.to_string());
            assert_eq!(bad_icon(&rgba, width, height), tao);
        }
    }
}
