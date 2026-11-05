// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! The config's icons, decoded as Tauri's codegen decodes them.
//!
//! Tauri's tauri-codegen reads the window icon and the tray icon from the
//! app's config while the app compiles, and decodes each to RGBA with png
//! 0.17.16 or ico 0.5.0, the versions its lock pins (`CachedIcon`,
//! `crates/tauri-codegen/src/image.rs:50-99` at vendor/tauri `9f0306fbc`).
//! Tokra reads its config when the app starts, so `Tokra::Codegen::CachedIcon`
//! calls these two functions then (plan 054, decision 19). `Tokra::Image`'s
//! decoder, the image crate, cannot stand in: it picks an ICO's richest
//! entry, not its first, and converts any PNG to RGBA, where codegen
//! refuses one that is not RGBA.
//!
//! Ruby reads the file and hands over its bytes and the path to name in a
//! message. Each function copies the bytes out of Ruby's string, decodes
//! them holding no Ruby value, and builds the Ruby string it answers only
//! after decoding. Where codegen panics, these raise `RuntimeError` with
//! the panic's message (plan 054, decision 8); a panic inside a decoder is
//! caught and raised the same way. An allocation a file's claims make
//! impossible would abort the process, which `catch_unwind` cannot catch,
//! so none is made: PNG's output buffer is reserved fallibly, and an ICO
//! whose claims run past its bytes is refused before ico allocates for
//! them, with the message ico's failed read would give.
//! The GVL stays held: an icon is a few kilobytes read once at start, as
//! `Image.from_bytes` decodes one.

use magnus::{function, prelude::*, Error, RString, Ruby};
use std::io::Cursor;
use std::panic::{self, AssertUnwindSafe};

/// Decoded RGBA bytes, with the width and height they hold.
type Decoded = (Vec<u8>, u32, u32);

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: adapted from tauri-codegen src/image.rs:50-99 at vendor/tauri 9f0306fbc

/// Decodes PNG bytes as codegen's `CachedIcon::new_png` does
/// (`image.rs:74-99`): png's `Decoder` with no transformations, refused
/// unless its output is RGBA, then each row while `next_row` gives one.
///
/// The loop is codegen's `while let Ok(Some(row))`: an error ends it
/// silently and keeps the rows read so far. So a truncated image answers
/// fewer bytes than its size needs, and an interlaced one answers its
/// Adam7 passes one after another, since png 0.17.16's `next_row` yields
/// each pass's rows, not the image's (plan 054, phase 3).
///
/// # Errors
///
/// "failed to read icon {path}: {e}" when png cannot read the header, and
/// "icon {path} is not RGBA" when the image is another color type.
fn decode_png(path: &str, buf: &[u8]) -> Result<Decoded, String> {
    let decoder = png::Decoder::new(Cursor::new(buf));
    let mut reader = decoder
        .read_info()
        .map_err(|e| format!("failed to read icon {path}: {e}"))?;

    if reader.output_color_type().0 != png::ColorType::Rgba {
        return Err(format!("icon {path} is not RGBA"));
    }

    let mut rgba = with_capacity(reader.output_buffer_size())?;
    while let Ok(Some(row)) = reader.next_row() {
        rgba.extend(row.data());
    }

    Ok((rgba, reader.info().width, reader.info().height))
}

/// Decodes ICO bytes as codegen's `CachedIcon::new_ico` does
/// (`image.rs:50-72`): the directory's first entry, whatever the others
/// hold, with the entry's width and height.
///
/// # Errors
///
/// "failed to parse icon {path}: {e}" when ico cannot read the directory,
/// "failed to decode icon {path}: {e}" when it cannot decode the entry,
/// and, for a directory with no entries, the message of the panic
/// codegen's `entries()[0]` raises. An ICO whose claims run past its bytes
/// answers, before ico reads it, what ico's failed read would (see
/// [`overrun`]).
fn decode_ico(path: &str, buf: &[u8]) -> Result<Decoded, String> {
    match overrun(buf) {
        Some(Overrun::Directory) => {
            return Err(format!("failed to parse icon {path}: {FAILED_TO_FILL}"))
        }
        Some(Overrun::FirstEntry) => {
            return Err(format!("failed to decode icon {path}: {FAILED_TO_FILL}"))
        }
        None => {}
    }
    let icon_dir = ico::IconDir::read(Cursor::new(buf))
        .map_err(|e| format!("failed to parse icon {path}: {e}"))?;

    let entries = icon_dir.entries();
    // Codegen indexes `entries()[0]`, which panics with Rust's slice
    // message on an empty directory (plan 054, decision 8).
    let Some(entry) = entries.first() else {
        return Err(format!(
            "index out of bounds: the len is {} but the index is 0",
            entries.len()
        ));
    };
    let rgba = entry
        .decode()
        .map_err(|e| format!("failed to decode icon {path}: {e}"))?
        .rgba_data()
        .to_vec();

    Ok((rgba, entry.width(), entry.height()))
}

// SPDX-SnippetEnd

/// The `Display` of the error `Read::read_exact` returns when its reader
/// ends first, as ico's reads all do.
const FAILED_TO_FILL: &str = "failed to fill whole buffer";

/// The bytes a PNG starts with, by which ico tells a PNG entry from a BMP
/// one (`icondir.rs:226-230` in ico 0.5.0).
const PNG_SIGNATURE: &[u8] = b"\x89PNG\r\n\x1a\n";

/// Where an ICO's claims run past its bytes.
#[derive(Debug, PartialEq, Eq)]
enum Overrun {
    /// An entry's span, its offset plus its size, ends past the file.
    Directory,
    /// The first entry is a BMP with fewer bytes than its header's rows,
    /// color table, and mask need.
    FirstEntry,
}

// SPDX-SnippetBegin
// SPDX-License-Identifier: MIT
// SPDX-SnippetCopyrightText: 2018 Matthew D. Steele
// SPDX-SnippetComment: the checks of ico 0.5.0 src/icondir.rs:52-120 and
//   src/image.rs:242-449, restated to find a short read before it happens

/// Whether ico 0.5.0 would fail a read of `buf` after allocating for what
/// it claims, and where; `None` when ico answers otherwise, or allocates
/// no more than `buf` holds.
///
/// `IconDir::read` makes `vec![0; data_size]` for each entry before
/// `read_exact` fills it (`icondir.rs:115-120`), up to 4 GiB a claim, and
/// `read_bmp` makes `vec![u8::MAX; width * height * 4]` for the first
/// entry before reading its rows (`image.rs:321-325`), up to 16 GiB,
/// written, not lazily zeroed. Where the allocator refuses, Rust aborts.
/// So this walks the same checks in the same order, and wherever one
/// would fail first, it leaves the answer to ico, which allocates nothing
/// large before that failure. Only where every check passes and the bytes
/// still fall short does it answer: the error ico's read would give, with
/// nothing allocated. A PNG entry is left to ico, since png 0.17.16's
/// default limit of 64 MiB bounds its buffer.
///
/// It counts in `u64`. Where ico's `u32` sums overflow, a width times
/// bits a pixel past `u32::MAX` (`image.rs:326`), ico has already
/// allocated at least 512 MiB; this answers the short read there.
fn overrun(buf: &[u8]) -> Option<Overrun> {
    // ICONDIR: reserved 0, then an icon (1) or a cursor (2), then the count
    // (icondir.rs:52-68).
    if le_u16(buf, 0)? != 0 || !matches!(le_u16(buf, 2)?, 1 | 2) {
        return None;
    }
    let len = buf.len() as u64;
    let mut first = None;
    let mut past_the_end = false;
    for index in 0..usize::from(le_u16(buf, 4)?) {
        // Each ICONDIRENTRY's reserved byte is 0 (icondir.rs:71-86).
        let entry = 6 + 16 * index;
        if *buf.get(entry + 3)? != 0 {
            return None;
        }
        let size = le_u32(buf, entry + 8)?;
        let offset = le_u32(buf, entry + 12)?;
        first.get_or_insert((offset, size));
        // read_exact of no bytes succeeds wherever the seek put it.
        past_the_end |= size > 0 && u64::from(offset) + u64::from(size) > len;
    }
    if past_the_end {
        return Some(Overrun::Directory);
    }
    let (offset, size) = first?;
    let data = buf
        .get(usize::try_from(offset).ok()?..)?
        .get(..usize::try_from(size).ok()?)?;
    if data.starts_with(PNG_SIGNATURE) {
        return None;
    }
    (bmp_needs(data)? > data.len() as u64).then_some(Overrun::FirstEntry)
}

/// The bytes ico's `read_bmp` reads from `data` once it has allocated the
/// image (`image.rs:284-449`): the 40-byte header, the color table, each
/// row padded to four bytes, and, below 32 bits a pixel, each row of the
/// one-bit mask padded the same; `None` where it fails before allocating.
fn bmp_needs(data: &[u8]) -> Option<u64> {
    // BITMAPINFOHEADER (image.rs:242-294): its size is 40, the width is at
    // least 1, the height is doubled and at least 1 when halved.
    if le_u32(data, 0)? != 40 || data.len() < 40 {
        return None;
    }
    let width = u32::try_from(le_i32(data, 4)?)
        .ok()
        .filter(|width| *width >= 1)?;
    let doubled = le_i32(data, 8)?;
    if doubled % 2 != 0 {
        return None;
    }
    let height = u32::try_from(doubled / 2)
        .ok()
        .filter(|height| *height >= 1)?;
    // Supported depths and their color tables (bmpdepth.rs:14-46).
    let bits = le_u16(data, 14)?;
    let colors: u64 = match bits {
        1 => 2,
        4 => 16,
        8 => 256,
        16 | 24 | 32 => 0,
        _ => return None,
    };
    let table = 40 + 4 * colors;
    // The color table is read before the image is allocated (image.rs:309-316),
    // and width times height must fit a u32 (:321-324).
    if (data.len() as u64) < table || width.checked_mul(height).is_none() {
        return None;
    }
    let (width, height) = (u64::from(width), u64::from(height));
    let row = (width * u64::from(bits)).div_ceil(8).div_ceil(4) * 4;
    let mask = if bits == 32 {
        0
    } else {
        width.div_ceil(8).div_ceil(4) * 4
    };
    Some(table + height * (row + mask))
}

// SPDX-SnippetEnd

/// The little-endian `u16` at `at` in `buf`, if `buf` holds it.
fn le_u16(buf: &[u8], at: usize) -> Option<u16> {
    Some(u16::from_le_bytes(buf.get(at..at + 2)?.try_into().ok()?))
}

/// The little-endian `u32` at `at` in `buf`, if `buf` holds it.
fn le_u32(buf: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_le_bytes(buf.get(at..at + 4)?.try_into().ok()?))
}

/// The little-endian `i32` at `at` in `buf`, if `buf` holds it.
fn le_i32(buf: &[u8], at: usize) -> Option<i32> {
    Some(i32::from_le_bytes(buf.get(at..at + 4)?.try_into().ok()?))
}

/// An empty buffer for `capacity` bytes, as `Vec::with_capacity` makes
/// one, but answering the message Rust gives where that call would end
/// the process: "capacity overflow", its panic past `isize::MAX`, and
/// "memory allocation of {n} bytes failed", its abort when the allocator
/// refuses.
fn with_capacity(capacity: usize) -> Result<Vec<u8>, String> {
    if isize::try_from(capacity).is_err() {
        return Err("capacity overflow".to_owned());
    }
    let mut buffer = Vec::new();
    buffer
        .try_reserve_exact(capacity)
        .map_err(|_| format!("memory allocation of {capacity} bytes failed"))?;
    Ok(buffer)
}

/// Runs `decode` on a copy of `bytes`, and answers the RGBA string, width,
/// and height, or raises `RuntimeError` with its message or the message of
/// a panic inside it.
fn decoded(
    ruby: &Ruby,
    path: &str,
    bytes: RString,
    decode: fn(&str, &[u8]) -> Result<Decoded, String>,
) -> Result<(RString, u32, u32), Error> {
    let buf = bytes.to_bytes();
    let outcome = panic::catch_unwind(AssertUnwindSafe(|| decode(path, &buf)));
    let result = outcome.unwrap_or_else(|panic| Err(panic_message(&*panic)));
    let (rgba, width, height) =
        result.map_err(|message| Error::new(ruby.exception_runtime_error(), message))?;
    Ok((ruby.str_from_slice(&rgba), width, height))
}

/// The message a caught panic carries.
fn panic_message(panic: &(dyn std::any::Any + Send)) -> String {
    panic
        .downcast_ref::<&str>()
        .map(|message| (*message).to_owned())
        .or_else(|| panic.downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "the icon decoder panicked".to_owned())
}

/// `Native.cached_icon_png(path, bytes)`: see [`decode_png`].
fn cached_icon_png(
    ruby: &Ruby,
    path: RString,
    bytes: RString,
) -> Result<(RString, u32, u32), Error> {
    decoded(ruby, &path.to_string()?, bytes, decode_png)
}

/// `Native.cached_icon_ico(path, bytes)`: see [`decode_ico`].
fn cached_icon_ico(
    ruby: &Ruby,
    path: RString,
    bytes: RString,
) -> Result<(RString, u32, u32), Error> {
    decoded(ruby, &path.to_string()?, bytes, decode_ico)
}

/// Defines `Native.cached_icon_png` and `Native.cached_icon_ico`.
///
/// # Errors
///
/// Returns an error if function definition fails.
pub fn define_functions(_ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    native.define_singleton_method("cached_icon_png", function!(cached_icon_png, 2))?;
    native.define_singleton_method("cached_icon_ico", function!(cached_icon_ico, 2))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::alloc::{GlobalAlloc, Layout, System};
    use std::cell::Cell;

    /// The system allocator, noting the largest block each thread asks for,
    /// so a test sees whether ico allocated for a claim.
    struct Recording;

    thread_local! {
        static LARGEST: Cell<usize> = const { Cell::new(0) };
    }

    fn note(size: usize) {
        // A const-initialized Cell has no destructor, so this neither
        // allocates nor fails while the thread lives.
        let _ = LARGEST.try_with(|largest| largest.set(largest.get().max(size)));
    }

    // SAFETY: each method passes its arguments to `System`'s, whose
    // contract (std::alloc::GlobalAlloc) is the one the caller upholds
    // here; noting a size touches only a thread-local `Cell<usize>` and
    // never allocates or unwinds.
    #[allow(unsafe_code)]
    unsafe impl GlobalAlloc for Recording {
        unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
            note(layout.size());
            // SAFETY: the caller upholds `alloc`'s contract, which is System's.
            unsafe { System.alloc(layout) }
        }

        unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
            note(layout.size());
            // SAFETY: the caller upholds `alloc_zeroed`'s contract, which is System's.
            unsafe { System.alloc_zeroed(layout) }
        }

        unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
            note(new_size);
            // SAFETY: `ptr` came from System through this allocator with
            // `layout`, and the caller upholds `realloc`'s contract.
            unsafe { System.realloc(ptr, layout, new_size) }
        }

        unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
            // SAFETY: `ptr` came from System through this allocator with
            // `layout`, as `dealloc`'s caller guarantees.
            unsafe { System.dealloc(ptr, layout) }
        }
    }

    #[global_allocator]
    static RECORDING: Recording = Recording;

    /// `decode_ico` on `buf`, with the largest block it asked for.
    fn decode_ico_recording(buf: &[u8]) -> (Result<Decoded, String>, usize) {
        LARGEST.with(|largest| largest.set(0));
        let result = decode_ico("x.ico", buf);
        (result, LARGEST.with(Cell::get))
    }

    /// An ICO of one entry at offset 22 holding `data`, its size given as
    /// `claimed`.
    fn ico(data: &[u8], claimed: u32) -> Vec<u8> {
        let mut ico = vec![0, 0, 1, 0, 1, 0, 2, 2, 2, 0, 1, 0, 1, 0];
        ico.extend(claimed.to_le_bytes());
        ico.extend(22u32.to_le_bytes());
        ico.extend(data);
        ico
    }

    /// A one-bit BMP, `width` by `height` as its header claims, with a
    /// color table and two four-byte rows of pixels and two of mask: the
    /// bytes a 2x2 image needs.
    fn bmp(width: i32, height: i32) -> Vec<u8> {
        let mut bmp = 40u32.to_le_bytes().to_vec();
        bmp.extend(width.to_le_bytes());
        bmp.extend((height * 2).to_le_bytes());
        bmp.extend([1, 0, 1, 0]);
        bmp.extend([0; 24]);
        bmp.extend([0, 0, 0, 0, 0x10, 0x80, 0xf0, 0]);
        bmp.extend([0x80, 0, 0, 0, 0x40, 0, 0, 0, 0, 0, 0, 0, 0x80, 0, 0, 0]);
        bmp
    }

    #[test]
    fn a_bmp_that_fills_its_claim_decodes() {
        let data = bmp(2, 2);
        let (result, _) = decode_ico_recording(&ico(&data, 64));
        let (rgba, width, height) = result.unwrap();
        assert_eq!((rgba.len(), width, height), (16, 2, 2));
    }

    // ico would make vec![0; 1 MiB] for the claim before its read fails.
    #[test]
    fn an_entry_past_the_end_is_refused_before_ico_allocates_for_it() {
        let (result, largest) = decode_ico_recording(&ico(&bmp(2, 2), 1 << 20));
        assert_eq!(
            result.unwrap_err(),
            "failed to parse icon x.ico: failed to fill whole buffer"
        );
        assert!(largest < 1 << 16, "allocated {largest} bytes");
    }

    // ico would make vec![u8::MAX; 512 * 512 * 4], 1 MiB, before its read
    // of the rows fails.
    #[test]
    fn a_bmp_short_of_its_rows_is_refused_before_ico_allocates_for_them() {
        let data = bmp(512, 512);
        let claimed = u32::try_from(data.len()).unwrap();
        let (result, largest) = decode_ico_recording(&ico(&data, claimed));
        assert_eq!(
            result.unwrap_err(),
            "failed to decode icon x.ico: failed to fill whole buffer"
        );
        assert!(largest < 1 << 16, "allocated {largest} bytes");
    }

    // read_exact of no bytes succeeds past the end, so ico goes on to
    // decode the empty entry, and its header read fails there.
    #[test]
    fn an_empty_entry_past_the_end_is_left_to_ico() {
        let mut empty = ico(&[], 0);
        empty[18..22].copy_from_slice(&1000u32.to_le_bytes());
        assert_eq!(overrun(&empty), None);
        assert_eq!(
            decode_ico("x.ico", &empty).unwrap_err(),
            "failed to decode icon x.ico: failed to fill whole buffer"
        );
    }

    #[test]
    fn a_bmp_one_byte_short_of_its_mask_is_refused() {
        let data = bmp(2, 2);
        assert_eq!(overrun(&ico(&data[..63], 63)), Some(Overrun::FirstEntry));
        assert_eq!(overrun(&ico(&data, 64)), None);
    }

    #[test]
    fn an_impossible_capacity_is_refused_with_rusts_messages() {
        assert_eq!(with_capacity(usize::MAX).unwrap_err(), "capacity overflow");
        assert!(with_capacity(16).unwrap().capacity() >= 16);
    }

    #[test]
    fn an_empty_icon_directory_gives_the_slice_panic_message() {
        let empty = [0u8, 0, 1, 0, 0, 0];
        assert_eq!(
            decode_ico("x.ico", &empty).unwrap_err(),
            "index out of bounds: the len is 0 but the index is 0"
        );
    }
}
