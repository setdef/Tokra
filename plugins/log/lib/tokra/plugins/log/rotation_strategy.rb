# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Plugins
    module Log
      # Controls how many rotated log files to keep (Tauri API parity).
      #
      # Maps to Ruby Logger's shift_age parameter.
      #
      # == Usage
      #
      #   Target.new(TargetKind::LogDir.new)
      #     .rotation_strategy(RotationStrategy::KeepAll.new)
      #
      module RotationStrategy
        # Keep all rotated log files with date suffix.
        #
        # Maps to shift_age: 'daily' (never deletes old files).
        class KeepAll < Data.define
          ##
          # Returns Ruby Logger shift_age value.
          def to_shift_age = "daily"
        end

        # Keep only the current log file.
        #
        # Maps to shift_age: 1 (discards old file on rotation).
        class KeepOne < Data.define
          ##
          # Returns Ruby Logger shift_age value.
          def to_shift_age = 1
        end

        # Keep N most recent log files.
        #
        # Maps to shift_age: count.
        class KeepSome < Data.define(:count)
          ##
          # Returns Ruby Logger shift_age value.
          def to_shift_age = count
        end
      end
    end
  end
end
