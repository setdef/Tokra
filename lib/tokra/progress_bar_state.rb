# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: ProgressBarState adapted from tauri/src/window/mod.rs

module Tokra
  # A progress bar's status and how far along it is.
  #
  # Window#set_progress_bar takes one. Each field left +nil+ leaves that
  # part of the bar as it was: a +progress+ alone moves the bar, and a
  # +status+ alone shows or hides it. +progress+ runs from 0 to 100, and
  # anything higher shows as 100.
  #
  # Mirrors Tauri's <tt>tauri::window::ProgressBarState</tt>
  # (window/mod.rs:2209-2221). Tauri reads a missing field as +None+, so
  # each defaults to +nil+ here. A status that is not a
  # ProgressBarStatus, or a progress that is not an Integer, raises
  # TypeError, and a negative progress raises RangeError, where Rust would
  # not compile.
  #
  # === Example
  #
  #   window.set_progress_bar(Tokra::ProgressBarState.new(status: Tokra::ProgressBarStatus::Normal, progress: 40))
  class ProgressBarState < Data.define(:status, :progress)
    # Creates the state, raising TypeError or RangeError as the class
    # says.
    # A Data class validating in initialize: its RBS declares self.new, as
    # AGENTS.md asks, and Steep cannot see that self.new reaches this.
    def initialize(status: nil, progress: nil) # steep:ignore MethodParameterMismatch
      unless status.nil? || status.is_a?(ProgressBarStatus)
        raise TypeError, "wrong argument type #{status.class} (expected Tokra::ProgressBarStatus or nil)"
      end
      unless progress.nil?
        raise TypeError, "wrong argument type #{progress.class} (expected Integer)" unless progress.is_a?(Integer)
        raise RangeError, "integer #{progress} out of range of u64" unless progress.between?(0, (2 ** 64) - 1)
      end
      super
    end
  end
end

# SPDX-SnippetEnd
