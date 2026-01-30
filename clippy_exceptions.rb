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
