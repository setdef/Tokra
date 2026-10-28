// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! File reading bindings.
//!
//! Thin wrapper around `std::fs::read`, the call Tauri's `Image::from_path`
//! makes (`tauri/crates/tauri/src/image/mod.rs:97`). Tauri sends a failed
//! read as `std::io::Error`'s Display, which only std can produce: on
//! Windows it formats the raw Win32 error code, which Ruby has already
//! mapped to a POSIX errno by the time it raises. Ruby owns the
//! `Tokra::Error::Io` it becomes, per ADR 005.
//!
//! Ruby reads the file first, interruptibly, and calls this only when its
//! read failed, to learn std's text. The read runs with Ruby's global VM
//! lock released, so even a failing open on a slow network file system
//! stops only the calling Ruby thread, never the main thread and its
//! windows (ADR 001). It runs with no unblocking function: std retries a
//! call the OS interrupts (`EINTR`), so nothing Ruby could send would end
//! it early, and `Thread#raise`, `Thread#kill`, and Ctrl-C take effect once
//! it returns. Ruby documents that such a call "will not stop for
//! Control+C" (`thread.c:1677-1679` at Ruby v4.0.1).
//!
//! The retry loop is ferro-rfd's (Ferro `gems/rfd/ext/ferro_rfd/src/gvl.rs`,
//! after ferro-arboard's), whose author, Kerrick Long, licenses this copy
//! under Tokra's license. magnus does not wrap
//! `rb_thread_call_without_gvl2`, so this module calls rb-sys directly.

use magnus::{function, prelude::*, Error, RString, Ruby};
use std::ffi::c_void;
use std::io;
use std::panic::{self, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;

/// How many times [`drive`] lets Ruby skip the read for a pending
/// interrupt before reading with the GVL held.
const TRIES: usize = 3;

/// What a read ends in: the file's bytes or std's error, or the payload of
/// a panic.
type Outcome = std::thread::Result<io::Result<Vec<u8>>>;

/// One read, and the slot its outcome lands in.
struct Read {
    path: PathBuf,
    outcome: Option<Outcome>,
}

impl Read {
    const fn new(path: PathBuf) -> Self {
        Self {
            path,
            outcome: None,
        }
    }

    /// Reads the file, once, catching a panic as the outcome. It touches
    /// nothing of Ruby's.
    fn run(&mut self) {
        if self.outcome.is_none() {
            let path = &self.path;
            self.outcome = Some(panic::catch_unwind(AssertUnwindSafe(|| {
                std::fs::read(path)
            })));
        }
    }
}

/// The function Ruby runs without the GVL.
extern "C" fn run(data: *mut c_void) -> *mut c_void {
    // SAFETY: `data` is the `&mut Read` that `release_and_run` (or a test)
    // passed in, and it outlives this call: `rb_nogvl` calls `func`
    // synchronously on the calling thread and returns only after it does
    // (`thread.c:1594-1643` at Ruby v4.0.1), so nothing else holds the
    // reference meanwhile.
    #[allow(unsafe_code)]
    let read = unsafe { &mut *data.cast::<Read>() };
    read.run();
    ptr::null_mut()
}

/// Asks Ruby to read with the GVL released. Ruby skips the read when an
/// interrupt is pending; then `read` holds no outcome.
fn release_and_run(read: &mut Read) {
    // SAFETY: Ruby calls `run` with `data1` at most once, on this thread,
    // with the GVL released, and returns after it does (`thread.c:189-201`,
    // `:1594-1643`, `:1730-1735` at Ruby v4.0.1). `run` touches no Ruby
    // object, which the NOTE at `thread.c:1709-1715` requires, and never
    // unwinds, since it catches panics. A null unblocking function is
    // allowed: Ruby calls one only when it is non-null (`thread.c:367-369`).
    // The `2` variant never checks interrupts after the read
    // (`thread.c:1636-1638`), so no exception unwinds across this frame.
    // The caller holds the GVL, as magnus guarantees for any `&Ruby`.
    #[allow(unsafe_code)]
    unsafe {
        rb_sys::rb_thread_call_without_gvl2(
            Some(run),
            ptr::from_mut(read).cast::<c_void>(),
            None,
            ptr::null_mut(),
        );
    }
}

/// The retry loop, with Ruby's two calls passed in so tests can drive it.
///
/// Each try asks for the read to run unlocked. When it was skipped for a
/// pending interrupt, `check_ints` runs that interrupt; an `Err` from it
/// (the exception the interrupt raised) is returned and the file is never
/// read. After `TRIES` skips, the read runs with the GVL held.
fn drive<E>(
    read: &mut Read,
    mut try_unlocked: impl FnMut(&mut Read),
    mut check_ints: impl FnMut() -> Result<(), E>,
) -> Result<Outcome, E> {
    for _ in 0..TRIES {
        try_unlocked(read);
        if let Some(outcome) = read.outcome.take() {
            return Ok(outcome);
        }
        check_ints()?;
    }
    read.run();
    Ok(read
        .outcome
        .take()
        .unwrap_or_else(|| Err(Box::new("the read had already run"))))
}

/// Reads the whole file at `path`, as `std::fs::read` does, with the GVL
/// released.
///
/// # Errors
///
/// Returns `RuntimeError` holding the `std::io::Error`'s Display when the
/// file cannot be read, such as <tt>No such file or directory (os error
/// 2)</tt>, or the exception an interrupt raised before the read began.
/// On Windows, a path that is not valid in UTF-8 raises magnus's encoding
/// error first, since std encodes paths as UTF-16 there.
fn fs_read(ruby: &Ruby, path: RString) -> Result<RString, Error> {
    #[cfg(unix)]
    let path = path_buf(path);
    #[cfg(not(unix))]
    let path = path_buf(path)?;
    let mut read = Read::new(path);
    let outcome = drive(&mut read, release_and_run, || ruby.thread_check_ints())?;
    // A panic resumes here, with the GVL held, where magnus turns it into
    // a Ruby exception as it does for any panic in a bound function.
    let bytes = outcome
        .unwrap_or_else(|payload| panic::resume_unwind(payload))
        .map_err(|e| Error::new(crate::runtime_error(), e.to_string()))?;
    Ok(ruby.str_from_slice(&bytes))
}

/// The path's bytes as they are, NUL bytes included, so std reports them.
///
/// magnus's own `PathBuf` conversion goes through `rb_get_path`, which
/// raises `ArgumentError` for a NUL byte before std sees the path.
#[cfg(unix)]
fn path_buf(path: RString) -> PathBuf {
    use std::os::unix::ffi::OsStringExt;

    std::ffi::OsString::from_vec(path.to_bytes().to_vec()).into()
}

/// The path as UTF-8, which std encodes as UTF-16 for the OS.
#[cfg(not(unix))]
fn path_buf(path: RString) -> Result<PathBuf, Error> {
    Ok(path.to_string()?.into())
}

/// Define file-related module functions on the Native module.
///
/// # Errors
///
/// Returns an error if function definition fails.
pub fn define_functions(_ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    native.define_singleton_method("fs_read", function!(fs_read, 1))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{drive, run, Read, TRIES};
    use std::cell::Cell;
    use std::ffi::c_void;
    use std::path::PathBuf;
    use std::ptr;

    fn call_run(read: &mut Read) {
        run(ptr::from_mut(read).cast::<c_void>());
    }

    fn this_file() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src/fs.rs")
    }

    #[test]
    fn run_reads_the_file_once_unlocked_and_keeps_its_bytes() {
        let mut read = Read::new(this_file());
        call_run(&mut read);
        assert!(matches!(read.outcome, Some(Ok(Ok(ref bytes))) if bytes.starts_with(b"// SPDX")));
        read.path = PathBuf::from("missing");
        call_run(&mut read);
        assert!(
            matches!(read.outcome, Some(Ok(Ok(_)))),
            "a second run reads nothing"
        );
    }

    #[test]
    fn run_keeps_std_s_error() {
        let mut read = Read::new(PathBuf::from("a\0b"));
        call_run(&mut read);
        let message = match read.outcome {
            Some(Ok(Err(error))) => error.to_string(),
            _ => String::new(),
        };
        assert!(message.contains("NUL"), "{message}");
    }

    #[test]
    fn a_skipped_try_checks_interrupts_then_reads_unlocked() {
        let tries = Cell::new(0);
        let checks = Cell::new(0);
        let mut read = Read::new(this_file());
        let outcome = drive(
            &mut read,
            |read| {
                tries.set(tries.get() + 1);
                if tries.get() == 2 {
                    call_run(read);
                }
            },
            || -> Result<(), ()> {
                checks.set(checks.get() + 1);
                Ok(())
            },
        );
        assert!(matches!(outcome, Ok(Ok(Ok(_)))));
        assert_eq!((tries.get(), checks.get()), (2, 1));
    }

    #[test]
    fn after_every_try_is_skipped_the_read_runs_with_the_gvl_held() {
        let tries = Cell::new(0);
        let mut read = Read::new(this_file());
        let outcome = drive(
            &mut read,
            |_| tries.set(tries.get() + 1),
            || -> Result<(), ()> { Ok(()) },
        );
        assert!(matches!(outcome, Ok(Ok(Ok(_)))));
        assert_eq!(tries.get(), TRIES);
    }

    #[test]
    fn an_interrupt_that_raises_leaves_the_file_unread() {
        let mut read = Read::new(this_file());
        let outcome = drive(&mut read, |_| {}, || Err("Interrupt"));
        assert_eq!(outcome.err(), Some("Interrupt"));
        assert!(read.outcome.is_none());
    }
}
