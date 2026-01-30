# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Approved Clippy allow exceptions.
# Each entry must explain WHY the exception is unavoidable.
# Review carefully before adding new entries.

allow "ext/tokra/src/lib.rs", line: 7, reason: <<~END
  Magnus FFI requires owned types at the Ruby-Rust boundary. Ruby strings must be
  converted to owned Rust Strings when crossing the FFI, as borrowed references
  cannot safely outlive the Ruby GC cycle. This is a fundamental constraint of
  the magnus crate's type marshaling, not a code smell to be fixed.
END

allow "ext/tokra/src/lib.rs", lines: [77, 189, 249], lint: "unsafe_code", reason: <<~END
  Tauri Pattern: unsafe impl Send for RbEventLoop, RbWindow, RbWebView

  These types wrap platform-native GUI objects (tao::Window, wry::WebView) that
  are bound to the main OS thread. Magnus's TypedData trait requires Send, but
  these types are not inherently thread-safe.

  INVARIANT: All access to these types happens exclusively on the main thread
  via the tao event loop. Ruby code cannot access these objects from Worker
  Ractors - only through the Send-safe Proxy which marshals commands to the
  main thread.

  This pattern is identical to how Tauri implements this in tauri-runtime-wry:
  - `unsafe impl Send for WindowsStore {}` (lib.rs:433)
  - `unsafe impl Send for DispatcherMainThreadContext<T> {}` (lib.rs:451)
  - `unsafe impl Send for WindowBuilderWrapper {}` (lib.rs:809)

  The invariant is enforced by:
  1. The event loop callback runs only on the main thread
  2. Ractors can only hold the Proxy (which IS genuinely Send+Sync-safe)
  3. Integration tests verify invariants:
     test/integration/thread_safety_invariant_test.rb:23-38 (Proxy is Ractor-safe)
     test/integration/thread_safety_invariant_test.rb:44-55 (main thread instantiation)
     test/integration/thread_safety_invariant_test.rb:60-73 (main thread operations)
END

allow "ext/tokra/src/lib.rs", lines: [310], lint: "unsafe_code", reason: <<~END
  Magnus TypedData for RbProxy: unsafe impl TypedData for RbProxy

  This is SAFE because EventLoopProxy<T> is genuinely Send+Sync by design.
  We use this to enable the `frozen_shareable` flag which makes the Ruby
  object Ractor-shareable when frozen.

  Unlike the other unsafe impls (which are for main-thread-only types),
  this one is actually safe - tao explicitly designed EventLoopProxy for
  cross-thread communication. The unsafe is only required by Magnus's
  TypedData trait signature, not because the operation is unsafe.

  VERIFIED BY: test/integration/thread_safety_invariant_test.rb:23-38
  Tests that frozen Proxy becomes Ractor-shareable.
END
