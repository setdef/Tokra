# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Monitor adapted from tauri/src/window/mod.rs and tauri-runtime/src/monitor.rs

module Tokra
  # A display attached to the computer, as it was when you asked.
  #
  # Window#current_monitor, Window#primary_monitor,
  # Window#monitor_from_point, and Window#available_monitors answer
  # Monitors. Use one to place a window: Monitor#work_area is the part of
  # the screen a window may use, without the menu bar, the Dock, or the
  # taskbar. A Monitor is a copy; it does not follow later changes.
  #
  # +name+:: a name a person can read, or +nil+ if the monitor is gone.
  # +size+:: the monitor's resolution, a PhysicalSize.
  # +position+:: the top-left corner within the desktop that spans every
  #              monitor, a PhysicalPosition.
  # +work_area+:: a PhysicalRect.
  # +scale_factor+:: the number of physical pixels in a logical one.
  #
  # Mirrors Tauri's Monitor (window/mod.rs:57-106, tauri-runtime
  # src/monitor.rs:8-21), which the runtime copies from tao's
  # MonitorHandle (tauri-runtime-wry lib.rs:596-608).
  #
  # === Example
  #
  #   monitor = window.current_monitor
  #   monitor.name          #=> "Built-in Retina Display"
  #   monitor.scale_factor  #=> 2.0
  class Monitor < Data.define(:name, :size, :position, :work_area, :scale_factor)
  end
end

# SPDX-SnippetEnd
