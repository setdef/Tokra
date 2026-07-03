// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Image decoding bindings.
//!
//! Thin wrapper around the `image` crate — the same crate Tauri uses for
//! its `image-png` and `image-ico` features. Rust decodes bytes to raw
//! RGBA; Ruby owns the Image value object and all resource management
//! per ADR 005.

use magnus::{function, prelude::*, Error, RString, Ruby};

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Decoding adapted from Image::from_bytes in tauri/crates/tauri/src/image/mod.rs

/// Decodes PNG or ICO bytes into raw RGBA pixel data.
///
/// Returns `(rgba, width, height)` where `rgba` is a binary Ruby String
/// in row-major order from top to bottom.
///
/// # Errors
///
/// Returns `RuntimeError` when the bytes cannot be decoded. The message
/// matches `tauri::Error::Image`: `failed to process image: ...`.
fn image_from_bytes(ruby: &Ruby, bytes: RString) -> Result<(RString, u32, u32), Error> {
    use image::GenericImageView;

    let data = bytes.to_bytes();
    let img = image::load_from_memory(&data).map_err(|e| {
        Error::new(
            crate::runtime_error(),
            format!("failed to process image: {e}"),
        )
    })?;
    let pixels = img
        .pixels()
        .flat_map(|(_, _, pixel)| pixel.0)
        .collect::<Vec<_>>();
    Ok((ruby.str_from_slice(&pixels), img.width(), img.height()))
}

// SPDX-SnippetEnd

/// Define image-related module functions on the Native module.
///
/// # Errors
///
/// Returns an error if function definition fails.
pub fn define_functions(_ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    native.define_singleton_method("image_from_bytes", function!(image_from_bytes, 1))?;
    Ok(())
}
