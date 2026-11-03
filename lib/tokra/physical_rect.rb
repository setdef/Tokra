# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PhysicalRect adapted from tauri-runtime/src/dpi.rs

module Tokra
  # A rectangle in physical pixels: its top-left +position+, a
  # PhysicalPosition, and its +size+, a PhysicalSize.
  #
  # Monitor#work_area answers one.
  #
  # Mirrors Tauri's <tt>PhysicalRect<P, S></tt> (tauri-runtime
  # src/dpi.rs:26-33).
  #
  # === Example
  #
  #   rect = monitor.work_area
  #   rect.size.width  #=> 2880
  class PhysicalRect < Data.define(:position, :size)
    # The rectangle as JSON, as serde writes Tauri's derived Serialize:
    # <tt>{"position": {"x", "y"}, "size": {"width", "height"}}</tt>
    # (tauri-runtime src/dpi.rs:26-33).
    #
    # === Example
    #
    #   monitor.work_area.to_json  #=> "{\"position\":{\"x\":0,\"y\":25},\"size\":{...}}"
    def to_json(state = nil)
      json = as_json
      state ? json.to_json(state) : json.to_json
    end

    # The rectangle as a JSON value, as #to_json writes it.
    def as_json # :nodoc:
      { "position" => position.as_json, "size" => size.as_json }
    end
  end
end

# SPDX-SnippetEnd
