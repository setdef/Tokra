// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: The window id to label table adapted from tauri-runtime-wry/src/lib.rs window_id_map

//! The label of each window tao knows, by tao's window id (plan 052,
//! decision 2).
//!
//! tao names the window an event is for by its `WindowId`, which means
//! nothing to Ruby. Tauri's runtime keeps a `window_id_map` from tao's id
//! to its own, inserts each window as it builds it, and resolves every
//! window event through it, dropping an id it does not know
//! (tauri-runtime-wry `src/lib.rs:4126-4150`, `:4459`). Tokra keeps the
//! label instead, since Ruby finds a window by label: `RbWindow::new`
//! inserts it, and the event loop reads it as it queues each window event
//! and forgets it when it queues `Destroyed`.
//!
//! The table holds plain `String`s, never a Ruby value, and lives on the
//! main thread, the one thread that builds windows and runs the loop.

use std::cell::RefCell;
use std::collections::HashMap;
use std::hash::Hash;

use tao::window::WindowId;

/// Labels by window id. Generic over the id so its tests need no window:
/// tao makes a `WindowId` only for a real window, or through an `unsafe`
/// dummy.
#[derive(Debug)]
pub struct Labels<K> {
    labels: HashMap<K, String>,
}

impl<K: Hash + Eq> Labels<K> {
    /// An empty table.
    #[must_use]
    pub fn new() -> Self {
        Self {
            labels: HashMap::new(),
        }
    }

    /// Records `label` for `id`, replacing any label it had.
    pub fn insert(&mut self, id: K, label: String) {
        self.labels.insert(id, label);
    }

    /// A copy of the label of `id`, or `None` for an id it does not know.
    #[must_use]
    pub fn get(&self, id: &K) -> Option<String> {
        self.labels.get(id).cloned()
    }

    /// Forgets `id`, answering the label it had.
    pub fn remove(&mut self, id: &K) -> Option<String> {
        self.labels.remove(id)
    }
}

impl<K: Hash + Eq> Default for Labels<K> {
    fn default() -> Self {
        Self::new()
    }
}

thread_local! {
    /// The main thread's table. Only the main thread builds a tao window
    /// (tao refuses elsewhere on macOS and Linux) or runs the loop.
    static WINDOWS: RefCell<Labels<WindowId>> = RefCell::new(Labels::new());
}

/// Records `label` for the window tao just built as `id`.
pub fn insert(id: WindowId, label: String) {
    WINDOWS.with_borrow_mut(|labels| labels.insert(id, label));
}

/// `query` with the main thread's table, for the loop to read a window
/// event's label and forget a destroyed window's.
pub fn with<R>(query: impl FnOnce(&mut Labels<WindowId>) -> R) -> R {
    WINDOWS.with_borrow_mut(query)
}

// SPDX-SnippetEnd

/// Why a label cannot cross into the native layer: wry copies a webview's
/// id into a C string with `unwrap` on macOS (wry 0.54.1
/// `src/wkwebview/mod.rs:274-277`), so a NUL would panic inside webview
/// creation, a fatal error Ruby cannot rescue. The window table takes the
/// same rule, so one label is valid for both.
///
/// # Errors
///
/// Answers the message for `ArgumentError` when `label` holds a NUL.
pub fn refuse_nul(label: &str) -> Result<(), &'static str> {
    if label.contains('\0') {
        Err("label contains null byte")
    } else {
        Ok(())
    }
}

/// `label`, or the `ArgumentError` [`refuse_nul`] gives for it.
///
/// # Errors
///
/// Returns `ArgumentError` when `label` holds a NUL.
pub fn checked(ruby: &magnus::Ruby, label: String) -> Result<String, magnus::Error> {
    refuse_nul(&label)
        .map(|()| label)
        .map_err(|message| magnus::Error::new(ruby.exception_arg_error(), message))
}

#[cfg(test)]
mod tests {
    use super::{refuse_nul, Labels};

    #[test]
    fn a_recorded_label_answers_as_a_copy() {
        let mut labels = Labels::new();
        labels.insert(7, "second".to_string());
        assert_eq!(labels.get(&7), Some("second".to_string()));
        assert_eq!(
            labels.get(&7),
            Some("second".to_string()),
            "get must not take the label out"
        );
    }

    #[test]
    fn an_unknown_id_has_no_label() {
        let mut labels = Labels::new();
        labels.insert(7, "main".to_string());
        assert_eq!(labels.get(&8), None);
    }

    #[test]
    fn a_removed_id_is_forgotten() {
        let mut labels = Labels::new();
        labels.insert(7, "main".to_string());
        assert_eq!(labels.remove(&7), Some("main".to_string()));
        assert_eq!(labels.get(&7), None);
    }

    #[test]
    fn a_reused_id_takes_the_new_label() {
        let mut labels = Labels::new();
        labels.insert(7, "first".to_string());
        labels.insert(7, "second".to_string());
        assert_eq!(labels.get(&7), Some("second".to_string()));
    }

    #[test]
    fn a_label_with_nul_is_refused() {
        assert_eq!(refuse_nul("ma\0in"), Err("label contains null byte"));
        assert_eq!(refuse_nul("main"), Ok(()));
        assert_eq!(refuse_nul(""), Ok(()), "Tauri's empty label passes");
    }
}
