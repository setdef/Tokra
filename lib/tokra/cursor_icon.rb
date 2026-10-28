# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: CursorIcon adapted from tauri-runtime/src/window.rs

module Tokra
  # How the mouse cursor looks over a window.
  #
  # Pass one to Window#set_cursor_icon. These 35 are the only icons,
  # as in Tauri's enum, so CursorIcon.new is private.
  #
  # Mirrors Tauri's <tt>tauri::CursorIcon</tt> (tauri-runtime
  # src/window.rs:100-159).
  #
  # === Example
  #
  #   window.set_cursor_icon(Tokra::CursorIcon::Wait)
  class CursorIcon < Data.define(:name)
    extend ClosedEnum

    ##
    # The platform-dependent default cursor.
    Default = new(name: "Default")
    # A simple crosshair.
    Crosshair = new(name: "Crosshair")
    # A hand (often used to indicate links in web browsers).
    Hand = new(name: "Hand")
    # An arrow.
    Arrow = new(name: "Arrow")
    # Indicates something is to be moved.
    Move = new(name: "Move")
    # Indicates text that may be selected or edited.
    Text = new(name: "Text")
    # Program busy indicator.
    Wait = new(name: "Wait")
    # Help indicator (often rendered as a "?").
    Help = new(name: "Help")
    # Progress indicator. Shows that processing is being done, but in
    # contrast with Wait the user may still interact with the program.
    # Often rendered as a spinning beach ball, or an arrow with a watch or
    # hourglass.
    Progress = new(name: "Progress")
    # Cursor showing that something cannot be done.
    NotAllowed = new(name: "NotAllowed")
    # Indicates a context menu is available.
    ContextMenu = new(name: "ContextMenu")
    # Indicates a cell or set of cells may be selected.
    Cell = new(name: "Cell")
    # Indicates vertical text that may be selected.
    VerticalText = new(name: "VerticalText")
    # Indicates an alias or shortcut is to be created.
    Alias = new(name: "Alias")
    # Indicates something is to be copied.
    Copy = new(name: "Copy")
    # Indicates the dragged item cannot be dropped here.
    NoDrop = new(name: "NoDrop")
    # Indicates something can be grabbed.
    Grab = new(name: "Grab")
    # Indicates something is grabbed.
    Grabbing = new(name: "Grabbing")
    # Indicates something can be scrolled in any direction.
    AllScroll = new(name: "AllScroll")
    # Indicates something can be zoomed in.
    ZoomIn = new(name: "ZoomIn")
    # Indicates something can be zoomed out.
    ZoomOut = new(name: "ZoomOut")
    # The right edge is to be moved. The resize cursors indicate that some
    # edge is to be moved; SeResize, for example, when the movement starts
    # from the south-east corner of the box.
    EResize = new(name: "EResize")
    # The top edge is to be moved.
    NResize = new(name: "NResize")
    # The top-right corner is to be moved.
    NeResize = new(name: "NeResize")
    # The top-left corner is to be moved.
    NwResize = new(name: "NwResize")
    # The bottom edge is to be moved.
    SResize = new(name: "SResize")
    # The bottom-right corner is to be moved.
    SeResize = new(name: "SeResize")
    # The bottom-left corner is to be moved.
    SwResize = new(name: "SwResize")
    # The left edge is to be moved.
    WResize = new(name: "WResize")
    # The left or right edge is to be moved.
    EwResize = new(name: "EwResize")
    # The top or bottom edge is to be moved.
    NsResize = new(name: "NsResize")
    # The top-right or bottom-left corner is to be moved.
    NeswResize = new(name: "NeswResize")
    # The top-left or bottom-right corner is to be moved.
    NwseResize = new(name: "NwseResize")
    # A column is to be resized.
    ColResize = new(name: "ColResize")
    # A row is to be resized.
    RowResize = new(name: "RowResize")

    close
  end
end

# SPDX-SnippetEnd
