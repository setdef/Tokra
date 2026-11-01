# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: ProgressBarStatus adapted from tauri-runtime/src/lib.rs

module Tokra
  # What a taskbar or Dock progress bar says about the work it tracks.
  #
  # A download or an export shows its progress where a person looks
  # while the app is in the background. Give one of these to
  # ProgressBarState and Window#set_progress_bar shows it.
  #
  # These five are the only statuses, as in Tauri's enum, so
  # ProgressBarStatus.new is private.
  #
  # Mirrors Tauri's <tt>ProgressBarStatus</tt> (tauri-runtime
  # src/lib.rs:51-65).
  #
  # === Example
  #
  #   Tokra::ProgressBarState.new(status: Tokra::ProgressBarStatus::Normal, progress: 40)
  class ProgressBarStatus < Data.define(:name)
    extend ClosedEnum

    ##
    # Hides the progress bar.
    None = new(name: "None")
    # Normal progress.
    Normal = new(name: "Normal")
    # Work of unknown length. Shown as Normal on Linux and macOS.
    Indeterminate = new(name: "Indeterminate")
    # Paused. Shown as Normal on Linux.
    Paused = new(name: "Paused")
    # Failed. Shown as Normal on Linux.
    Error = new(name: "Error")

    close
  end
end

# SPDX-SnippetEnd
