# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Approved Clippy allow exceptions.
# Each entry must explain WHY the exception is unavoidable.
# Review carefully before adding new entries.

allow "ext/tokra/src/window.rs", line: 52, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWindow::set_title
  receives a Ruby string that must be converted to an owned Rust String because
  Magnus's TryConvert trait only implements String, not &str.

  UNFIXABLE: magnus/src/try_convert.rs:209 shows `impl TryConvert for String`
  with no corresponding impl for &str. The conversion copies Ruby string data
  into an owned Rust String because borrowed references cannot safely outlive
  the Ruby GC cycle.
END

allow "ext/tokra/src/webview.rs", line: 130, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWebView::new
  receives a URL from Ruby that must be converted to an owned Rust String.

  UNFIXABLE: magnus/src/try_convert.rs:209 only implements TryConvert for String.
  There is no &str implementation because Ruby string memory is GC-managed and
  cannot be safely borrowed across the FFI boundary.
END

allow "ext/tokra/src/webview.rs", line: 278, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWebView::eval
  receives JavaScript code from Ruby that must be converted to an owned String.

  UNFIXABLE: Same constraint as above - magnus/src/try_convert.rs:209 only
  provides TryConvert for owned String types.
END

allow "ext/tokra/src/event_loop.rs", lines: [58, 59], reason: <<~END
  Tauri Pattern: unsafe impl Send for RbEventLoop

  RbEventLoop wraps tao::EventLoop which is bound to the main OS thread.

  UNFIXABLE: magnus/src/typed_data.rs:84 requires `DataTypeFunctions: Send`.
  tao::EventLoop is not Send (platform-bound). The only options are:
  1. unsafe impl Send with main-thread invariant (Tauri's approach)
  2. Don't wrap for Ruby (defeats purpose)
  3. Don't use Magnus (massive rewrite with raw C API)

  INVARIANT: RbEventLoop is only used and dropped on the main thread. This
  matches Tauri's `unsafe impl Send for DispatcherMainThreadContext<T>`. The
  SAFETY comment in event_loop.rs says what upholds it and what does not
  (Plan 019).
END

allow "ext/tokra/src/webview.rs", lines: [114, 115], reason: <<~END
  Tauri Pattern: unsafe impl Send for RbWebView

  RbWebView wraps wry::WebView which is bound to the main OS thread.

  UNFIXABLE: magnus/src/typed_data.rs:84 requires `DataTypeFunctions: Send`.
  wry::WebView is not Send. Same constraint as RbEventLoop.

  INVARIANT: RbWebView is only used and dropped on the main thread. The
  SAFETY comment in webview.rs says what upholds it and what does not
  (Plan 019).
END

allow "ext/tokra/src/proxy.rs", lines: [93, 94], reason: <<~END
  Proxy#respond method clippy allows for FFI boundary and readability.

  Line 93: #[allow(clippy::needless_pass_by_value)]
  Magnus FFI requires owned types at the Ruby-Rust boundary. The `headers`
  parameter is received from Ruby as an owned value (the body arrives as an
  RString and is copied out as bytes). Changing to references
  would require an intermediate allocation anyway since TryConvert produces owned
  Strings.

  Line 94: #[allow(clippy::option_if_let_else)]
  Using `match` is more readable than `map_or_else` when the branches have
  significantly different complexity. The `Some` branch builds an HTTP response
  while `None` returns a simple error.
END
