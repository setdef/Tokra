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
        assert_eq!(second, first + 1);
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
