// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Ruby event classes for the event loop callback.
//!
//! These are simple data classes that are created by the event loop and
//! passed to the Ruby callback. They carry event data from native code
//! to Ruby land.

use magnus::{function, method, prelude::*, Error, Ruby};

// =============================================================================
// IpcEvent
// =============================================================================

/// Simple Ruby class for IPC events.
#[magnus::wrap(class = "Tokra::Native::IpcEvent", free_immediately, size)]
pub struct RbIpcEvent {
    message: String,
}

impl RbIpcEvent {
    /// Create a new IPC event.
    #[must_use]
    pub const fn new(message: String) -> Self {
        Self { message }
    }

    /// Get the message content.
    #[must_use]
    pub fn message(&self) -> String {
        self.message.clone()
    }
}

// =============================================================================
// WakeUpEvent
// =============================================================================

/// Simple Ruby class for wake-up events.
#[magnus::wrap(class = "Tokra::Native::WakeUpEvent", free_immediately, size)]
pub struct RbWakeUpEvent {
    payload: String,
}

impl RbWakeUpEvent {
    /// Create a new wake-up event.
    #[must_use]
    pub const fn new(payload: String) -> Self {
        Self { payload }
    }

    /// Get the payload content.
    #[must_use]
    pub fn payload(&self) -> String {
        self.payload.clone()
    }
}

// =============================================================================
// WindowCloseEvent
// =============================================================================

/// Simple Ruby class for window close events.
#[magnus::wrap(class = "Tokra::Native::WindowCloseEvent", free_immediately, size)]
pub struct RbWindowCloseEvent;

impl RbWindowCloseEvent {
    /// Create a new window close event.
    #[must_use]
    pub const fn new() -> Self {
        Self
    }
}

impl Default for RbWindowCloseEvent {
    fn default() -> Self {
        Self::new()
    }
}

// =============================================================================
// HttpRequestEvent
// =============================================================================

/// Ruby class for HTTP request events (from `tokra://` custom protocol).
/// Includes `request_id` for correlating async responses.
#[magnus::wrap(class = "Tokra::Native::HttpRequestEvent", free_immediately, size)]
pub struct RbHttpRequestEvent {
    request_id: u64,
    method: String,
    uri: String,
    headers: Vec<(String, String)>,
    body: String,
}

impl RbHttpRequestEvent {
    /// Create a new HTTP request event.
    #[must_use]
    pub const fn new(
        request_id: u64,
        method: String,
        uri: String,
        headers: Vec<(String, String)>,
        body: String,
    ) -> Self {
        Self {
            request_id,
            method,
            uri,
            headers,
            body,
        }
    }

    /// Get the request ID.
    #[must_use]
    pub const fn request_id(&self) -> u64 {
        self.request_id
    }

    /// Get the HTTP method.
    #[must_use]
    pub fn method(&self) -> String {
        self.method.clone()
    }

    /// Get the request URI.
    #[must_use]
    pub fn uri(&self) -> String {
        self.uri.clone()
    }

    /// Get the request headers as array of [name, value] pairs.
    /// Magnus automatically converts Vec<(String, String)> to Ruby Array of Arrays.
    #[must_use]
    pub fn headers(&self) -> Vec<(String, String)> {
        self.headers.clone()
    }

    /// Get the request body.
    #[must_use]
    pub fn body(&self) -> String {
        self.body.clone()
    }
}

// =============================================================================
// PageLoadEvent
// =============================================================================

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2020-2023 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: PageLoadEvent pattern adapted from tauri/webview/mod.rs on_page_load

/// Ruby class for page load events (started/finished).
/// Matches Tauri's `on_page_load` API.
#[magnus::wrap(class = "Tokra::Native::PageLoadEvent", free_immediately, size)]
pub struct RbPageLoadEvent {
    event: String, // "started" or "finished"
    url: String,
}

impl RbPageLoadEvent {
    /// Create a new page load event.
    #[must_use]
    pub const fn new(event: String, url: String) -> Self {
        Self { event, url }
    }

    /// Returns "started" or "finished"
    #[must_use]
    pub fn event(&self) -> String {
        self.event.clone()
    }

    /// Get the page URL.
    #[must_use]
    pub fn url(&self) -> String {
        self.url.clone()
    }

    /// Returns true if this is a "started" event
    #[must_use]
    pub fn started(&self) -> bool {
        self.event == "started"
    }

    /// Returns true if this is a "finished" event
    #[must_use]
    pub fn finished(&self) -> bool {
        self.event == "finished"
    }
}

// SPDX-SnippetEnd

// =============================================================================
// Module Initialization
// =============================================================================

/// Define all event classes on the given Ruby module.
///
/// # Errors
///
/// Returns an error if class or method definition fails.
pub fn define_classes(ruby: &Ruby, native: magnus::RModule) -> Result<(), Error> {
    // IpcEvent
    let ipc_event_class = native.define_class("IpcEvent", ruby.class_object())?;
    ipc_event_class.define_singleton_method("new", function!(RbIpcEvent::new, 1))?;
    ipc_event_class.define_method("message", method!(RbIpcEvent::message, 0))?;

    // WakeUpEvent
    let wake_up_event_class = native.define_class("WakeUpEvent", ruby.class_object())?;
    wake_up_event_class.define_singleton_method("new", function!(RbWakeUpEvent::new, 1))?;
    wake_up_event_class.define_method("payload", method!(RbWakeUpEvent::payload, 0))?;

    // WindowCloseEvent
    let window_close_event_class = native.define_class("WindowCloseEvent", ruby.class_object())?;
    window_close_event_class
        .define_singleton_method("new", function!(RbWindowCloseEvent::new, 0))?;

    // HttpRequestEvent
    let http_request_event_class = native.define_class("HttpRequestEvent", ruby.class_object())?;
    http_request_event_class
        .define_singleton_method("new", function!(RbHttpRequestEvent::new, 5))?;
    http_request_event_class
        .define_method("request_id", method!(RbHttpRequestEvent::request_id, 0))?;
    http_request_event_class.define_method("method", method!(RbHttpRequestEvent::method, 0))?;
    http_request_event_class.define_method("uri", method!(RbHttpRequestEvent::uri, 0))?;
    http_request_event_class.define_method("headers", method!(RbHttpRequestEvent::headers, 0))?;
    http_request_event_class.define_method("body", method!(RbHttpRequestEvent::body, 0))?;

    // PageLoadEvent
    let page_load_event_class = native.define_class("PageLoadEvent", ruby.class_object())?;
    page_load_event_class.define_singleton_method("new", function!(RbPageLoadEvent::new, 2))?;
    page_load_event_class.define_method("event", method!(RbPageLoadEvent::event, 0))?;
    page_load_event_class.define_method("url", method!(RbPageLoadEvent::url, 0))?;
    page_load_event_class.define_method("started?", method!(RbPageLoadEvent::started, 0))?;
    page_load_event_class.define_method("finished?", method!(RbPageLoadEvent::finished, 0))?;

    Ok(())
}

// =============================================================================
// Unit Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // -------------------------------------------------------------------------
    // RbIpcEvent tests
    // -------------------------------------------------------------------------

    #[test]
    fn test_ipc_event_stores_message() {
        let event = RbIpcEvent::new("hello".to_string());
        assert_eq!(event.message(), "hello");
    }

    #[test]
    fn test_ipc_event_preserves_unicode() {
        let event = RbIpcEvent::new("日本語 🎉".to_string());
        assert_eq!(event.message(), "日本語 🎉");
    }

    #[test]
    fn test_ipc_event_empty_string() {
        let event = RbIpcEvent::new("".to_string());
        assert!(event.message().is_empty());
    }

    // -------------------------------------------------------------------------
    // RbWakeUpEvent tests
    // -------------------------------------------------------------------------

    #[test]
    fn test_wake_up_event_stores_payload() {
        let event = RbWakeUpEvent::new("worker_result".to_string());
        assert_eq!(event.payload(), "worker_result");
    }

    #[test]
    fn test_wake_up_event_empty_payload() {
        let event = RbWakeUpEvent::new("".to_string());
        assert!(event.payload().is_empty());
    }

    // -------------------------------------------------------------------------
    // RbWindowCloseEvent tests
    // -------------------------------------------------------------------------

    #[test]
    fn test_window_close_event_can_be_created() {
        let _event = RbWindowCloseEvent::new();
        // Unit struct - just verify it can be constructed
    }

    #[test]
    fn test_window_close_event_default_impl() {
        let event = RbWindowCloseEvent::default();
        // Verify Default impl works (produces same as new())
        let _ = event;
    }

    // -------------------------------------------------------------------------
    // RbHttpRequestEvent tests
    // -------------------------------------------------------------------------

    #[test]
    fn test_http_request_event_stores_all_fields() {
        let headers = vec![
            ("cookie".to_string(), "session=abc123".to_string()),
            ("accept".to_string(), "text/html".to_string()),
        ];
        let event = RbHttpRequestEvent::new(
            42,
            "POST".to_string(),
            "tokra://localhost/api".to_string(),
            headers,
            r#"{"key":"value"}"#.to_string(),
        );

        assert_eq!(event.request_id(), 42);
        assert_eq!(event.method(), "POST");
        assert_eq!(event.uri(), "tokra://localhost/api");
        assert_eq!(event.headers().len(), 2);
        assert_eq!(event.headers()[0].0, "cookie");
        assert_eq!(event.body(), r#"{"key":"value"}"#);
    }

    #[test]
    fn test_http_request_event_request_id_zero() {
        let event = RbHttpRequestEvent::new(
            0,
            "GET".to_string(),
            "/".to_string(),
            vec![],
            "".to_string(),
        );
        assert_eq!(event.request_id(), 0);
    }

    #[test]
    fn test_http_request_event_request_id_max() {
        let event = RbHttpRequestEvent::new(
            u64::MAX,
            "GET".to_string(),
            "/".to_string(),
            vec![],
            "".to_string(),
        );
        assert_eq!(event.request_id(), u64::MAX);
    }

    #[test]
    fn test_http_request_event_empty_body() {
        let event = RbHttpRequestEvent::new(
            1,
            "GET".to_string(),
            "/index.html".to_string(),
            vec![],
            "".to_string(),
        );
        assert!(event.body().is_empty());
        assert!(event.headers().is_empty());
    }

    // -------------------------------------------------------------------------
    // RbPageLoadEvent tests - CRITICAL for mutation testing
    // -------------------------------------------------------------------------

    #[test]
    fn test_page_load_event_stores_fields() {
        let event = RbPageLoadEvent::new("started".to_string(), "https://example.com/".to_string());
        assert_eq!(event.event(), "started");
        assert_eq!(event.url(), "https://example.com/");
    }

    #[test]
    fn test_page_load_started_returns_true_for_started() {
        let event = RbPageLoadEvent::new("started".to_string(), "https://example.com/".to_string());
        assert!(event.started());
    }

    #[test]
    fn test_page_load_started_returns_false_for_finished() {
        let event =
            RbPageLoadEvent::new("finished".to_string(), "https://example.com/".to_string());
        assert!(!event.started());
    }

    #[test]
    fn test_page_load_finished_returns_true_for_finished() {
        let event =
            RbPageLoadEvent::new("finished".to_string(), "https://example.com/".to_string());
        assert!(event.finished());
    }

    #[test]
    fn test_page_load_finished_returns_false_for_started() {
        let event = RbPageLoadEvent::new("started".to_string(), "https://example.com/".to_string());
        assert!(!event.finished());
    }

    // These tests catch mutations that swap "started" <-> "finished"
    #[test]
    fn test_page_load_predicates_are_mutually_exclusive_for_started() {
        let event = RbPageLoadEvent::new("started".to_string(), "https://example.com/".to_string());
        assert!(event.started() && !event.finished());
    }

    #[test]
    fn test_page_load_predicates_are_mutually_exclusive_for_finished() {
        let event =
            RbPageLoadEvent::new("finished".to_string(), "https://example.com/".to_string());
        assert!(!event.started() && event.finished());
    }

    // This test catches mutations that return a constant
    #[test]
    fn test_page_load_predicates_both_false_for_unknown() {
        let event = RbPageLoadEvent::new("loading".to_string(), "https://example.com/".to_string());
        assert!(!event.started());
        assert!(!event.finished());
    }
}
