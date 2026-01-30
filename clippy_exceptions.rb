# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Approved Clippy allow exceptions.
# Each entry must explain WHY the exception is unavoidable.
# Review carefully before adding new entries.

allow "ext/tokra/src/window.rs", line: 61, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWindow::set_title
  receives a Ruby string that must be converted to an owned Rust String because
  Magnus's TryConvert trait only implements String, not &str.

  UNFIXABLE: magnus/src/try_convert.rs:209 shows `impl TryConvert for String`
  with no corresponding impl for &str. The conversion copies Ruby string data
  into an owned Rust String because borrowed references cannot safely outlive
  the Ruby GC cycle.
END

allow "ext/tokra/src/webview.rs", line: 51, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWebView::new
  receives a URL from Ruby that must be converted to an owned Rust String.

  UNFIXABLE: magnus/src/try_convert.rs:209 only implements TryConvert for String.
  There is no &str implementation because Ruby string memory is GC-managed and
  cannot be safely borrowed across the FFI boundary.
END

allow "ext/tokra/src/webview.rs", line: 172, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWebView::eval
  receives JavaScript code from Ruby that must be converted to an owned String.

  UNFIXABLE: Same constraint as above - magnus/src/try_convert.rs:209 only
  provides TryConvert for owned String types.
END

allow "ext/tokra/src/event_loop.rs", lines: [48, 49], reason: <<~END
  Tauri Pattern: unsafe impl Send for RbEventLoop

  RbEventLoop wraps tao::EventLoop which is bound to the main OS thread.

  UNFIXABLE: magnus/src/typed_data.rs:84 requires `DataTypeFunctions: Send`.
  tao::EventLoop is not Send (platform-bound). The only options are:
  1. unsafe impl Send with main-thread invariant (Tauri's approach)
  2. Don't wrap for Ruby (defeats purpose)
  3. Don't use Magnus (massive rewrite with raw C API)

  INVARIANT: RbEventLoop is only accessed from the main thread via event loop
  callback. This matches Tauri's `unsafe impl Send for DispatcherMainThreadContext<T>`.

  ENFORCED BY: test/integration/thread_safety_invariant_test.rb
END

allow "ext/tokra/src/window.rs", line: 30, reason: <<~END
  Tauri Pattern: unsafe impl Send for RbWindow

  RbWindow wraps tao::Window which is bound to the main OS thread.

  UNFIXABLE: magnus/src/typed_data.rs:84 requires `DataTypeFunctions: Send`.
  tao::Window is not Send. Same constraint as RbEventLoop.

  INVARIANT: RbWindow is only accessed within event loop callback on main thread.
  Matches Tauri's `unsafe impl Send for WindowsStore {}` in tauri-runtime-wry.

  ENFORCED BY: test/integration/thread_safety_invariant_test.rb
END

allow "ext/tokra/src/webview.rs", lines: [35, 36], reason: <<~END
  Tauri Pattern: unsafe impl Send for RbWebView

  RbWebView wraps wry::WebView which is bound to the main OS thread.

  UNFIXABLE: magnus/src/typed_data.rs:84 requires `DataTypeFunctions: Send`.
  wry::WebView is not Send. Same constraint as RbEventLoop and RbWindow.

  INVARIANT: RbWebView is only accessed within event loop callback on main thread.

  ENFORCED BY: test/integration/thread_safety_invariant_test.rb
END

allow "ext/tokra/src/proxy.rs", line: 103, reason: <<~END
  Magnus TypedData for RbProxy: unsafe impl TypedData for RbProxy

  Unlike the other unsafe impls, this IS actually safe. EventLoopProxy<T> is
  genuinely Send+Sync by tao's design - it's explicitly intended for cross-thread
  wakeups. The unsafe is only required by Magnus's TypedData trait signature.

  We use this to enable the frozen_shareable flag which makes the Ruby object
  Ractor-shareable when frozen. Ruby automatically freezes objects shared across
  Ractors.

  VERIFIED BY: test/integration/thread_safety_invariant_test.rb:23-38
  Tests that frozen Proxy becomes Ractor-shareable.
END
