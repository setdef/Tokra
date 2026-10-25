// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! User events for cross-thread/Ractor communication.
//!
//! This module defines the `UserEvent` enum that carries messages between
//! different parts of the Tokra runtime: from `WebView` to Ruby, from Ractors
//! to the main thread, and from Ruby back to pending protocol requests.

use std::fmt;

use crate::thread_bound::ThreadBound;

/// A platform object on its way to the main thread to be dropped there.
///
/// A garbage collection on another thread frees `Tokra::Native::WebView` or
/// `Tokra::Native::Window` there; its `Drop` sends the tao or wry value home
/// in this wrapper (`webview.rs`, `window.rs`). The `ThreadBound` makes
/// dropping it anywhere sound: on the main thread the value drops, anywhere
/// else it leaks.
pub enum Released {
    WebView(ThreadBound<wry::WebView>),
    Window(ThreadBound<tao::window::Window>),
}

impl fmt::Debug for Released {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::WebView(_) => "Released(WebView)",
            Self::Window(_) => "Released(Window)",
        })
    }
}

/// A pending custom-protocol request's answer, on its way to the main
/// thread: a response, or `None` to drop the request unanswered.
///
/// On macOS, `WebKit` answers a scheme task on the main run loop and makes any
/// other thread wait for it (`-[WKURLSchemeTaskImpl didReceiveResponse:]`
/// calls `WTF::callOnMainRunLoopAndWait`). A Ruby thread waiting there holds
/// the GVL that the main thread needs to run its loop, so neither moves.
/// `Proxy#respond` on another thread sends the answer here instead, and the
/// loop answers on the main thread, where `WebKit` runs it inline.
pub struct Answer {
    pub responder: wry::RequestAsyncResponder,
    pub response: Option<wry::http::Response<Vec<u8>>>,
}

impl Answer {
    /// Respond, or drop the request when there is no response.
    pub fn deliver(self) {
        if let Some(response) = self.response {
            self.responder.respond(response);
        }
    }
}

impl fmt::Debug for Answer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Answer")
            .field(
                "response",
                &self.response.as_ref().map(wry::http::Response::status),
            )
            .finish_non_exhaustive()
    }
}

/// Custom event type for cross-thread/Ractor communication.
///
/// This is the payload type for `tao::EventLoopProxy<UserEvent>`. It is not
/// `Clone`: a released webview cannot be copied, and tao never clones a user
/// event (only `Event::clone` asks for it, and Tokra never calls that).
#[derive(Debug)]
pub enum UserEvent {
    /// IPC message received from `WebView` JavaScript.
    ///
    /// `url` is the sending frame's URL, which wry passes as the request URI
    /// and Tauri uses as the invoke origin (`ipc/protocol.rs` `InvokeRequest`).
    IpcMessage { url: String, body: String },

    /// HTTP request received from `WebView` (via custom protocol)
    /// Contains: (`request_id`, method, uri, headers, body)
    /// The `request_id` is used to correlate with the async response
    HttpRequest {
        request_id: u64,
        method: String,
        uri: String,
        headers: Vec<(String, String)>,
        /// The exact request body bytes; binary uploads must survive intact.
        body: Vec<u8>,
    },

    /// Page load event (Started or Finished)
    /// Matches Tauri's `on_page_load` API
    PageLoad {
        event: String, // "started" or "finished"
        url: String,
    },

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: DragDrop event structure adapted from tauri-runtime/window.rs DragDropEvent enum
    /// Drag-drop event from webview
    /// Matches Tauri's `DragDropEvent` variants: Enter, Over, Drop, Leave
    DragDrop {
        event: String, // "enter", "over", "drop", "leave"
        paths: Vec<String>,
        x: i32,
        y: i32,
    },

    // SPDX-SnippetEnd
    /// Wake-up signal from a Ractor (via Proxy)
    WakeUp(String),

    /// Exit signal (from ctrlc handler)
    Exit,

    // SPDX-SnippetBegin
    // SPDX-License-Identifier: Apache-2.0 OR MIT
    // SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    // SPDX-SnippetComment: Task message adapted from tauri-runtime-wry/src/lib.rs Message::Task
    /// A Ruby thread queued a task for the main thread (`Proxy#send_task`).
    ///
    /// Tauri's `Message::Task` carries the closure (tauri-runtime-wry
    /// `src/lib.rs:1482-1483`); Tokra's task is a Ruby block, which stays in
    /// `Tokra::RuntimeContext`'s queue, so the event only wakes the loop to
    /// run the oldest one.
    Task,

    // SPDX-SnippetEnd
    /// Another Ruby thread is waiting for the GVL, which the loop holds.
    /// Sent by the READY thread-event hook (`gvl_handoff.rs`); the loop
    /// answers with `Thread.pass`.
    Yield,

    /// A window or webview to drop on the main thread.
    Release(Released),

    /// A custom-protocol answer from another thread, for the main thread
    /// to deliver.
    Respond(Answer),
}

// =============================================================================
// Unit Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_event_ipc_message_stores_string() {
        let event = UserEvent::IpcMessage {
            url: "tokra://localhost/".to_string(),
            body: "hello from JS".to_string(),
        };
        match event {
            UserEvent::IpcMessage { body: msg, .. } => assert_eq!(msg, "hello from JS"),
            _ => panic!("Expected IpcMessage variant"),
        }
    }

    #[test]
    fn test_user_event_ipc_message_preserves_unicode() {
        let event = UserEvent::IpcMessage {
            url: "tokra://localhost/".to_string(),
            body: "こんにちは 🎌".to_string(),
        };
        match event {
            UserEvent::IpcMessage { body: msg, .. } => assert_eq!(msg, "こんにちは 🎌"),
            _ => panic!("Expected IpcMessage variant"),
        }
    }

    #[test]
    fn test_user_event_http_request_stores_all_fields() {
        let headers = vec![
            ("cookie".to_string(), "session=abc123".to_string()),
            ("content-type".to_string(), "application/json".to_string()),
        ];
        let event = UserEvent::HttpRequest {
            request_id: 42,
            method: "POST".to_string(),
            uri: "tokra://localhost/api".to_string(),
            headers,
            body: br#"{"key":"value"}"#.to_vec(),
        };

        match event {
            UserEvent::HttpRequest {
                request_id,
                method,
                uri,
                headers: h,
                body,
            } => {
                assert_eq!(request_id, 42);
                assert_eq!(method, "POST");
                assert_eq!(uri, "tokra://localhost/api");
                assert_eq!(h.len(), 2);
                assert_eq!(h[0].0, "cookie");
                assert_eq!(h[0].1, "session=abc123");
                assert_eq!(body, br#"{"key":"value"}"#);
            }
            _ => panic!("Expected HttpRequest variant"),
        }
    }

    #[test]
    fn test_user_event_page_load_started() {
        let event = UserEvent::PageLoad {
            event: "started".to_string(),
            url: "https://example.com/".to_string(),
        };

        match event {
            UserEvent::PageLoad { event, url } => {
                assert_eq!(event, "started");
                assert_eq!(url, "https://example.com/");
            }
            _ => panic!("Expected PageLoad variant"),
        }
    }

    #[test]
    fn test_user_event_page_load_finished() {
        let event = UserEvent::PageLoad {
            event: "finished".to_string(),
            url: "https://example.com/page".to_string(),
        };

        match event {
            UserEvent::PageLoad { event, url } => {
                assert_eq!(event, "finished");
                assert_eq!(url, "https://example.com/page");
            }
            _ => panic!("Expected PageLoad variant"),
        }
    }

    #[test]
    fn test_user_event_wake_up_stores_payload() {
        let event = UserEvent::WakeUp("worker response".to_string());
        match event {
            UserEvent::WakeUp(payload) => assert_eq!(payload, "worker response"),
            _ => panic!("Expected WakeUp variant"),
        }
    }

    #[test]
    fn test_user_event_exit_variant_exists() {
        let event = UserEvent::Exit;
        assert!(matches!(event, UserEvent::Exit));
    }

    #[test]
    fn test_user_event_debug_format_ipc() {
        let event = UserEvent::IpcMessage {
            url: "tokra://localhost/".to_string(),
            body: "debug test".to_string(),
        };
        let debug_str = format!("{event:?}");
        assert!(debug_str.contains("IpcMessage"));
        assert!(debug_str.contains("debug test"));
    }

    #[test]
    fn test_user_event_task_and_yield_carry_nothing() {
        assert!(matches!(UserEvent::Task, UserEvent::Task));
        assert_eq!(format!("{:?}", UserEvent::Yield), "Yield");
    }

    #[test]
    fn test_user_event_debug_format_exit() {
        let event = UserEvent::Exit;
        let debug_str = format!("{event:?}");
        assert!(debug_str.contains("Exit"));
    }

    #[test]
    fn test_http_request_id_can_be_zero() {
        let event = UserEvent::HttpRequest {
            request_id: 0,
            method: "GET".to_string(),
            uri: "tokra://test".to_string(),
            headers: vec![],
            body: vec![],
        };

        match event {
            UserEvent::HttpRequest { request_id, .. } => assert_eq!(request_id, 0),
            _ => panic!("Expected HttpRequest"),
        }
    }

    #[test]
    fn test_http_request_id_can_be_max_u64() {
        let event = UserEvent::HttpRequest {
            request_id: u64::MAX,
            method: "GET".to_string(),
            uri: "tokra://test".to_string(),
            headers: vec![],
            body: vec![],
        };

        match event {
            UserEvent::HttpRequest { request_id, .. } => assert_eq!(request_id, u64::MAX),
            _ => panic!("Expected HttpRequest"),
        }
    }

    #[test]
    fn test_empty_strings_are_preserved() {
        let event = UserEvent::IpcMessage {
            url: "tokra://localhost/".to_string(),
            body: String::new(),
        };
        match event {
            UserEvent::IpcMessage { body: msg, .. } => assert_eq!(msg, ""),
            _ => panic!("Expected IpcMessage"),
        }
    }
}
