# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: TitleBarStyle adapted from tauri-utils/src/lib.rs

module Tokra
  # How a macOS window draws its title bar.
  #
  # An app with its own toolbar often wants the window's content to run
  # up under the traffic lights, as Finder and Safari do. Pass one of
  # these to Window#set_title_bar_style. Other platforms ignore it.
  #
  # These three are the only styles, as in Tauri's enum, so
  # TitleBarStyle.new is private.
  #
  # Mirrors Tauri's <tt>TitleBarStyle</tt> (tauri-utils src/lib.rs:159-178).
  #
  # === Example
  #
  #   window.set_title_bar_style(Tokra::TitleBarStyle::Overlay)
  class TitleBarStyle < Data.define(:name)
    extend ClosedEnum

    ##
    # A normal title bar.
    Visible = new(name: "Visible")
    # A transparent title bar, so the window's background color shows
    # instead. Use it when no HTML belongs under the title bar; it avoids
    # Overlay's caveats.
    Transparent = new(name: "Transparent")
    # A transparent title bar over the window's content. Its height
    # differs between macOS versions, so the controls and title may not
    # sit where you expect. Give the page a drag region to move the
    # window, and know that a window out of focus cannot be dragged. The
    # title's color follows the system's theme.
    Overlay = new(name: "Overlay")

    close
  end
end

# SPDX-SnippetEnd
