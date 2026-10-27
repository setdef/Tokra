# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Approved Clippy allow exceptions.
# Each entry must explain WHY the exception is unavoidable.
# Review carefully before adding new entries.

allow "ext/tokra/src/window.rs", line: 106, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWindow::set_title
  receives a Ruby string that must be converted to an owned Rust String because
  Magnus's TryConvert trait only implements String, not &str.

  UNFIXABLE: magnus/src/try_convert.rs:209 shows `impl TryConvert for String`
  with no corresponding impl for &str. The conversion copies Ruby string data
  into an owned Rust String because borrowed references cannot safely outlive
  the Ruby GC cycle.
END

allow "ext/tokra/src/webview.rs", line: 185, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWebView::new
  receives a URL from Ruby that must be converted to an owned Rust String.

  UNFIXABLE: magnus/src/try_convert.rs:209 only implements TryConvert for String.
  There is no &str implementation because Ruby string memory is GC-managed and
  cannot be safely borrowed across the FFI boundary.
END

allow "ext/tokra/src/webview.rs", line: 340, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. RbWebView::eval
  receives JavaScript code from Ruby that must be converted to an owned String.

  UNFIXABLE: Same constraint as above - magnus/src/try_convert.rs:209 only
  provides TryConvert for owned String types.
END

allow "ext/tokra/src/thread_bound.rs", line: 125, reason: <<~END
  ThreadBound<T> exists to make a value that is not Send safe to hold in a
  Send type: magnus wraps only Send types (magnus/src/typed_data.rs:411-413),
  and tao's EventLoop and wry's WebView are not Send. The lint flags exactly
  that: a Send impl over a field of unbounded T.

  UNFIXABLE: bounding T by Send would defeat the type, which holds non-Send
  values by design. The SAFETY comment on the impl gives the argument: on
  any thread but the owner, get returns None and Drop forgets the value, so
  no other thread reaches T or runs its destructor. Rust tests in
  thread_bound.rs drive both halves with real threads. This replaces the
  two former exceptions for unsafe impl Send on RbEventLoop and RbWebView,
  whose invariant nothing enforced (Plan 019, Plan 020).
END

allow "ext/tokra/src/proxy.rs", lines: [116, 117], reason: <<~END
  Proxy#respond method clippy allows for FFI boundary and readability.

  Line 116: #[allow(clippy::needless_pass_by_value)]
  Magnus FFI requires owned types at the Ruby-Rust boundary. The `headers`
  parameter is received from Ruby as an owned value (the body arrives as an
  RString and is copied out as bytes). Changing to references
  would require an intermediate allocation anyway since TryConvert produces owned
  Strings.

  Line 117: #[allow(clippy::option_if_let_else)]
  Using `match` is more readable than `map_or_else` when the branches have
  significantly different complexity. The `Some` branch builds an HTTP response
  while `None` returns a simple error.
END
