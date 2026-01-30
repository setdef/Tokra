// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

//! User events for cross-thread/Ractor communication.
//!
//! This module defines the `UserEvent` enum that carries messages between
//! different parts of the Tokra runtime: from `WebView` to Ruby, from Ractors
//! to the main thread, and from Ruby back to pending protocol requests.

/// Custom event type for cross-thread/Ractor communication.
///
/// This is the payload type for `tao::EventLoopProxy<UserEvent>`.
#[derive(Debug, Clone)]
pub enum UserEvent {
    /// IPC message received from `WebView` JavaScript
    IpcMessage(String),

    /// HTTP request received from `WebView` (via custom protocol)
    /// Contains: (`request_id`, method, uri, body)
    /// The `request_id` is used to correlate with the async response
    HttpRequest {
        request_id: u64,
        method: String,
        uri: String,
        body: String,
    },

    /// HTTP response from Ruby (for async protocol handling)
    /// Contains: (`request_id`, status, headers, body)
    HttpResponse {
        request_id: u64,
        status: u16,
        headers: Vec<(String, String)>,
        body: String,
    },

    /// Page load event (Started or Finished)
    /// Matches Tauri's `on_page_load` API
    PageLoad {
        event: String, // "started" or "finished"
        url: String,
    },

    /// Wake-up signal from a Ractor (via Proxy)
    WakeUp(String),

    /// Exit signal (from ctrlc handler)
    Exit,
}

// =============================================================================
// Unit Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_user_event_ipc_message_stores_string() {
        let event = UserEvent::IpcMessage("hello from JS".to_string());
        match event {
            UserEvent::IpcMessage(msg) => assert_eq!(msg, "hello from JS"),
            _ => panic!("Expected IpcMessage variant"),
        }
    }

    #[test]
    fn test_user_event_ipc_message_preserves_unicode() {
        let event = UserEvent::IpcMessage("こんにちは 🎌".to_string());
        match event {
            UserEvent::IpcMessage(msg) => assert_eq!(msg, "こんにちは 🎌"),
            _ => panic!("Expected IpcMessage variant"),
        }
    }

    #[test]
    fn test_user_event_http_request_stores_all_fields() {
        let event = UserEvent::HttpRequest {
            request_id: 42,
            method: "POST".to_string(),
            uri: "tokra://localhost/api".to_string(),
            body: r#"{"key":"value"}"#.to_string(),
        };

        match event {
            UserEvent::HttpRequest {
                request_id,
                method,
                uri,
                body,
            } => {
                assert_eq!(request_id, 42);
                assert_eq!(method, "POST");
                assert_eq!(uri, "tokra://localhost/api");
                assert_eq!(body, r#"{"key":"value"}"#);
            }
            _ => panic!("Expected HttpRequest variant"),
        }
    }

    #[test]
    fn test_user_event_http_response_stores_all_fields() {
        let headers = vec![
            ("content-type".to_string(), "text/html".to_string()),
            ("x-custom".to_string(), "value".to_string()),
        ];

        let event = UserEvent::HttpResponse {
            request_id: 99,
            status: 200,
            headers: headers.clone(),
            body: "<h1>Hello</h1>".to_string(),
        };

        match event {
            UserEvent::HttpResponse {
                request_id,
                status,
                headers: h,
                body,
            } => {
                assert_eq!(request_id, 99);
                assert_eq!(status, 200);
                assert_eq!(h.len(), 2);
                assert_eq!(h[0].0, "content-type");
                assert_eq!(h[0].1, "text/html");
                assert_eq!(body, "<h1>Hello</h1>");
            }
            _ => panic!("Expected HttpResponse variant"),
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
    fn test_user_event_clone_preserves_ipc_message() {
        let original = UserEvent::IpcMessage("test".to_string());
        let cloned = original.clone();

        match (original, cloned) {
            (UserEvent::IpcMessage(a), UserEvent::IpcMessage(b)) => {
                assert_eq!(a, b);
            }
            _ => panic!("Clone should preserve variant"),
        }
    }

    #[test]
    fn test_user_event_clone_preserves_http_request() {
        let original = UserEvent::HttpRequest {
            request_id: 123,
            method: "GET".to_string(),
            uri: "tokra://test".to_string(),
            body: "".to_string(),
        };
        let cloned = original.clone();

        match cloned {
            UserEvent::HttpRequest { request_id, .. } => {
                assert_eq!(request_id, 123);
            }
            _ => panic!("Clone should preserve variant"),
        }
    }

    #[test]
    fn test_user_event_debug_format_ipc() {
        let event = UserEvent::IpcMessage("debug test".to_string());
        let debug_str = format!("{:?}", event);
        assert!(debug_str.contains("IpcMessage"));
        assert!(debug_str.contains("debug test"));
    }

    #[test]
    fn test_user_event_debug_format_exit() {
        let event = UserEvent::Exit;
        let debug_str = format!("{:?}", event);
        assert!(debug_str.contains("Exit"));
    }

    #[test]
    fn test_http_request_id_can_be_zero() {
        let event = UserEvent::HttpRequest {
            request_id: 0,
            method: "GET".to_string(),
            uri: "tokra://test".to_string(),
            body: "".to_string(),
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
            body: "".to_string(),
        };

        match event {
            UserEvent::HttpRequest { request_id, .. } => assert_eq!(request_id, u64::MAX),
            _ => panic!("Expected HttpRequest"),
        }
    }

    #[test]
    fn test_http_response_status_boundary_low() {
        let event = UserEvent::HttpResponse {
            request_id: 1,
            status: 100,
            headers: vec![],
            body: "".to_string(),
        };

        match event {
            UserEvent::HttpResponse { status, .. } => assert_eq!(status, 100),
            _ => panic!("Expected HttpResponse"),
        }
    }

    #[test]
    fn test_http_response_status_boundary_high() {
        let event = UserEvent::HttpResponse {
            request_id: 1,
            status: 599,
            headers: vec![],
            body: "".to_string(),
        };

        match event {
            UserEvent::HttpResponse { status, .. } => assert_eq!(status, 599),
            _ => panic!("Expected HttpResponse"),
        }
    }

    #[test]
    fn test_empty_strings_are_preserved() {
        let event = UserEvent::IpcMessage("".to_string());
        match event {
            UserEvent::IpcMessage(msg) => assert!(msg.is_empty()),
            _ => panic!("Expected IpcMessage"),
        }
    }
}
