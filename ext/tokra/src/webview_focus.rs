// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

// SPDX-SnippetBegin
// SPDX-License-Identifier: Apache-2.0 OR MIT
// SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
// SPDX-SnippetComment: Ported from tauri-runtime-wry/src/lib.rs create_webview (Windows focus)

//! A window's focus on Windows, from its webview (plan 047, decision 10).
//!
//! On Windows the webview takes the keyboard focus from its window, so
//! tao reports the window losing focus whenever the page gains it.
//! Tauri's runtime drops tao's `Focused` there for a window without child
//! webviews and takes `WebView2`'s `GotFocus` and `LostFocus` instead
//! (tauri-runtime-wry `src/lib.rs:521-549`, `5070-5128`). This is that
//! code for Tokra's one webview: Tauri keeps the label of the focused
//! webview, and with one webview whether one is focused is all it can
//! learn, so a flag stands in for the label. A lost focus always reports,
//! as Tauri's does when the focused webview is this one.

#![cfg(windows)]

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use tao::event_loop::EventLoopProxy;
use webview2_com::FocusChangedEventHandler;
use wry::{WebView, WebViewExtWindows};

use crate::user_event::UserEvent;

/// Sends `UserEvent::Focused` for the webview's `GotFocus`, unless it
/// already has focus, and for each `LostFocus`.
///
/// # Errors
///
/// Returns `WebView2`'s error if it refuses a handler.
pub fn attach(webview: &WebView, proxy: &EventLoopProxy<UserEvent>) -> windows::core::Result<()> {
    let controller = webview.controller();
    let focused = Arc::new(AtomicBool::new(false));
    let mut token = 0;

    let got = {
        let focused = Arc::clone(&focused);
        let proxy = proxy.clone();
        FocusChangedEventHandler::create(Box::new(move |_, _| {
            if !focused.swap(true, Ordering::AcqRel) {
                let _ = proxy.send_event(UserEvent::Focused(true));
            }
            Ok(())
        }))
    };
    // SAFETY: `controller` is the live ICoreWebView2Controller wry built
    // the webview with (wry 0.54.1 `src/lib.rs:2266-2269`),
    // called on the thread that created it; `got` is a COM handler object
    // the controller holds a reference to, and `token` outlives the call,
    // as tauri-runtime-wry passes them (`src/lib.rs:5079-5097`).
    #[allow(unsafe_code)]
    unsafe {
        controller.add_GotFocus(&got, &raw mut token)?;
    }

    let lost = {
        let proxy = proxy.clone();
        FocusChangedEventHandler::create(Box::new(move |_, _| {
            focused.store(false, Ordering::Release);
            let _ = proxy.send_event(UserEvent::Focused(false));
            Ok(())
        }))
    };
    // SAFETY: as for `add_GotFocus` above (`src/lib.rs:5099-5128`).
    #[allow(unsafe_code)]
    unsafe {
        controller.add_LostFocus(&lost, &raw mut token)?;
    }
    Ok(())
}

// SPDX-SnippetEnd
