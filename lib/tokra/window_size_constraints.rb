# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WindowSizeConstraints adapted from tauri-runtime/src/window.rs

module Tokra
  # The smallest and largest a window's client area may be, one side at a
  # time.
  #
  # Window#set_min_size and Window#set_max_size limit both sides at once.
  # A window that may grow only wider, or has a minimum height but no
  # minimum width, needs each limit on its own. Window#set_size_constraints
  # takes one of these: each limit is a LogicalUnit, a PhysicalUnit, or
  # +nil+ for none, and each is +nil+ unless given, as Tauri's Default
  # leaves it. Any other limit raises TypeError.
  #
  # Mirrors Tauri's <tt>WindowSizeConstraints</tt> (tauri-runtime
  # src/window.rs:208-228), whose limits are dpi's <tt>PixelUnit</tt>,
  # either kind of unit; Ruby has no conversion traits, so a limit takes
  # either kind itself (plan 041, decision 3).
  #
  # === Example
  #
  #   Tokra::WindowSizeConstraints.new(min_width: Tokra::LogicalUnit.new(400))
  class WindowSizeConstraints < Data.define(:min_width, :min_height, :max_width, :max_height)
    # Each limit's serde name, camelCase, in Tauri's order.
    FIELDS = %w[minWidth minHeight maxWidth maxHeight].freeze # :nodoc:

    # The constraints a command argument holds, as the derived Deserialize
    # reads them: a struct whose fields are renamed camelCase,
    # <tt>minWidth</tt> and so on, each an <tt>Option<PixelUnit></tt>
    # (Dpi.deserialize_pixel_unit), from a map whose other keys are
    # ignored or from a sequence (tauri-runtime src/window.rs:208-227).
    def self.deserialize(value) # :nodoc:
      fields = Ipc::Serde.struct_fields(value, "WindowSizeConstraints", FIELDS, optional: FIELDS) do |_, raw|
        Dpi.deserialize_pixel_unit(raw)
      end
      new(min_width: fields["minWidth"], min_height: fields["minHeight"], max_width: fields["maxWidth"],
        max_height: fields["maxHeight"])
    end

    # Creates the constraints, raising TypeError for a limit that is not a
    # LogicalUnit, a PhysicalUnit, or +nil+.
    # A Data class validating in initialize: its RBS declares self.new, as
    # AGENTS.md asks, and Steep cannot see that self.new reaches this.
    def initialize(min_width: nil, min_height: nil, max_width: nil, max_height: nil) # steep:ignore MethodParameterMismatch
      [min_width, min_height, max_width, max_height].each do |limit|
        next if limit.nil? || limit.is_a?(LogicalUnit) || limit.is_a?(PhysicalUnit)

        raise TypeError,
          "wrong argument type #{limit.class} (expected Tokra::LogicalUnit, Tokra::PhysicalUnit, or nil)"
      end
      super
    end
  end
end

# SPDX-SnippetEnd
