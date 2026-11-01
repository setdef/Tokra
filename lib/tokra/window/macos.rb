# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# Tauri compiles Window::set_badge_label only for macOS
# (window/mod.rs:2140-2149), so it exists only where the native window
# has it (ADR 011; plan 045, decision 5).
return unless Tokra::Native::Window.method_defined?(:set_badge_label)

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Window::set_badge_label adapted from tauri/crates/tauri/src/window/mod.rs

module Tokra
  class Window
    # Shows +label+, a String, as a badge on the app's Dock icon, and
    # returns +nil+. +nil+ takes the badge away. Runs as #center does;
    # anything else raises TypeError on the calling thread.
    #
    # The Dock icon is the app's, so the badge is too, whichever window
    # sets it. Defined only on macOS, as in Tauri.
    #
    # Mirrors Tauri's Window::set_badge_label (window/mod.rs:2140-2149;
    # tauri-runtime-wry lib.rs:3500-3503).
    #
    # === Example
    #
    #   window.set_badge_label("New")
    def set_badge_label(label)
      native = @native
      expect(label, String) if label
      text = label&.dup
      dispatch { native.set_badge_label(text) }
    end
  end
end

# SPDX-SnippetEnd
