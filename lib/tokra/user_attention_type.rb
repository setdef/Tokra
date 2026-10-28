# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: UserAttentionType adapted from tauri-runtime/src/lib.rs

module Tokra
  # How urgently Window#request_user_attention asks for attention.
  #
  # These two are the only kinds, as in Tauri's enum, so
  # UserAttentionType.new is private.
  #
  # Mirrors Tauri's <tt>tauri::UserAttentionType</tt> (tauri-runtime
  # src/lib.rs:80-85), as tao describes each kind (tao 0.34.5
  # src/window.rs:1521-1533).
  #
  # === Example
  #
  #   window.request_user_attention(Tokra::UserAttentionType::Informational)
  class UserAttentionType < Data.define(:name)
    ##
    # On macOS, bounces the Dock icon until the app is in focus; on
    # Windows, flashes both the window and the taskbar button until the
    # app is in focus.
    Critical = new(name: "Critical")
    # On macOS, bounces the Dock icon once; on Windows, flashes the
    # taskbar button until the app is in focus.
    Informational = new(name: "Informational")

    private_class_method :new
  end
end

# SPDX-SnippetEnd
