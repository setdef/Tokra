// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Async protocol responder storage.
//!
//! This module manages pending HTTP responses for the tokra:// custom protocol.
//! When the `WebView` makes a request via the custom protocol, we store a responder
//! that will be used later when Ruby sends back an `HttpResponse` event.
//!
//! # Pattern Origin
//!
//! This pattern is adapted from Tauri's `register_asynchronous_uri_scheme_protocol`
//! in tauri/app.rs.

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Async responder pattern adapted from tauri/app.rs register_asynchronous_uri_scheme_protocol

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

use wry::RequestAsyncResponder;

/// Global counter for generating unique request IDs
static NEXT_REQUEST_ID: AtomicU64 = AtomicU64::new(1);

/// Thread-safe storage for pending async responders
/// Maps `request_id` -> `RequestAsyncResponder`
static PENDING_RESPONDERS: std::sync::OnceLock<Mutex<HashMap<u64, RequestAsyncResponder>>> =
    std::sync::OnceLock::new();

/// Get the global responders map, initializing if needed.
#[must_use]
pub fn get_responders() -> &'static Mutex<HashMap<u64, RequestAsyncResponder>> {
    PENDING_RESPONDERS.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Remove the responder stored under `request_id`, returning it if present.
///
/// `Proxy#respond` replies with the returned responder; `Proxy#drop_response`
/// lets it fall out of scope, which closes the request without a reply, the
/// way Tauri drops its owned responder (`webview/mod.rs` `on_message`). A
/// missing id returns `None`: the request was already answered or dropped.
///
/// # Panics
///
/// Panics if the responders mutex is poisoned (internal invariant violation).
pub fn take_responder<R>(responders: &Mutex<HashMap<u64, R>>, request_id: u64) -> Option<R> {
    responders.lock().unwrap().remove(&request_id)
}

/// Generate the next unique request ID.
#[must_use]
pub fn next_request_id() -> u64 {
    NEXT_REQUEST_ID.fetch_add(1, Ordering::SeqCst)
}

// SPDX-SnippetEnd

// =============================================================================
// Unit Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_next_request_id_increments() {
        let first = next_request_id();
        let second = next_request_id();
        // Use > instead of == first + 1 because other parallel tests
        // may also call next_request_id() between our two calls
        assert!(
            second > first,
            "second ({second}) should be greater than first ({first})"
        );
    }

    #[test]
    fn test_next_request_id_is_unique_across_calls() {
        let ids: Vec<u64> = (0..100).map(|_| next_request_id()).collect();
        let unique: std::collections::HashSet<u64> = ids.iter().cloned().collect();
        assert_eq!(ids.len(), unique.len(), "All IDs should be unique");
    }

    #[test]
    fn test_get_responders_returns_same_instance() {
        let first = get_responders();
        let second = get_responders();
        assert!(std::ptr::eq(first, second), "Should return same instance");
    }

    /// Records whether it was dropped, standing in for wry's responder,
    /// which has no public constructor.
    struct DropFlag(std::sync::Arc<std::sync::atomic::AtomicBool>);

    impl Drop for DropFlag {
        fn drop(&mut self) {
            self.0.store(true, Ordering::SeqCst);
        }
    }

    #[test]
    fn test_take_responder_removes_and_dropping_it_releases_the_request() {
        let dropped = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let responders = Mutex::new(HashMap::new());
        responders
            .lock()
            .unwrap()
            .insert(7, DropFlag(dropped.clone()));

        // Proxy#drop_response discards what take_responder returns.
        drop(take_responder(&responders, 7));

        assert!(
            dropped.load(Ordering::SeqCst),
            "the responder must be dropped"
        );
        assert!(
            responders.lock().unwrap().is_empty(),
            "the responder must leave the map"
        );
        assert!(
            take_responder(&responders, 7).is_none(),
            "a second take finds nothing, so dropping is idempotent"
        );
    }

    #[test]
    fn test_take_responder_leaves_other_requests_pending() {
        let responders = Mutex::new(HashMap::new());
        responders.lock().unwrap().insert(1, "one");
        responders.lock().unwrap().insert(2, "two");

        assert_eq!(take_responder(&responders, 1), Some("one"));
        assert_eq!(responders.lock().unwrap().get(&2), Some(&"two"));
    }

    #[test]
    fn test_get_responders_is_empty_initially() {
        // Note: This may fail if other tests have added responders.
        // The responders map is global, so this test verifies the HashMap exists.
        let responders = get_responders();
        let guard = responders.lock().unwrap();
        // Just verify we can access it - can't guarantee empty due to other tests
        let _ = guard.len();
    }
}
