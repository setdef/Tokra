# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Rect adapted from tauri/crates/tauri-runtime/src/dpi.rs

module Tokra
  # A rectangle on the screen: where it starts and how big it is.
  #
  # A tray icon reports where it sits this way, so an app can open a
  # window beside it. The position is a PhysicalPosition or a
  # LogicalPosition, and the size a PhysicalSize or a LogicalSize, so the
  # rectangle says which kind of pixels it counts.
  #
  # Mirrors Tauri's <tt>Rect { position: Position, size: Size }</tt>
  # (tauri-runtime dpi.rs:8-15). dpi's Position and Size enums wrap one
  # struct per variant; in Ruby the struct is the variant (ADR 013,
  # decision 2).
  #
  # === Example
  #
  #   rect = tray.rect
  #   rect.position.x  #=> 1180
  class Rect < Data.define(:position, :size)
    # The rectangle as JSON, each part tagged with its kind, as serde writes
    # dpi's externally tagged enums:
    # <tt>{"position": {"Physical": {"x": 1, "y": 2}}, "size": {"Physical": {...}}}</tt>.
    def to_json(*)
      as_json.to_json(*)
    end

    # The rectangle as a JSON value, as #to_json writes it.
    def as_json # :nodoc:
      position = self.position
      size = self.size
      {
        "position" => { tag(position) => { "x" => position.x, "y" => position.y } },
        "size" => { tag(size) => { "width" => size.width, "height" => size.height } },
      }
    end

    # The name of +value+'s dpi variant.
    private def tag(value)
      (value.is_a?(PhysicalPosition) || value.is_a?(PhysicalSize)) ? "Physical" : "Logical"
    end
  end
end

# SPDX-SnippetEnd
