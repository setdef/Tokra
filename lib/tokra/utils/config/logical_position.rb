# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: LogicalPosition adapted from tauri-utils src/config.rs:519-530
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # A point in logical pixels, as a config writes one.
      #
      # A window's <tt>trafficLightPosition</tt> places macOS's three
      # window buttons. The config gives it as an object with +x+ and +y+,
      # which this class holds. It is the config's own struct, apart from
      # Tokra::LogicalPosition, as Tauri keeps its config type apart from
      # its dpi type.
      #
      # Mirrors Tauri's <tt>tauri_utils::config::LogicalPosition</tt>
      # (config.rs:519-530).
      #
      # === Example
      #
      #   window = Tokra.generate_context.config.app.windows.first
      #   window.traffic_light_position  #=> #<data Tokra::Utils::Config::LogicalPosition x=12.0, y=16.0>
      class LogicalPosition < Data.define(:x, :y)
        FIELDS = [
          Field.required(:x, "x", -> (raw) { Ipc::Serde.f64(raw) }),
          Field.required(:y, "y", -> (raw) { Ipc::Serde.f64(raw) }),
        ].freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "LogicalPosition", FIELDS)) # steep:ignore UnresolvedOverloading
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
