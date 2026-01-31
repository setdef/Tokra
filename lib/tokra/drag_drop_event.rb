# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: DragDropEvent adapted from tauri-runtime/src/window.rs

module Tokra
  # The drag and drop event payload.
  #
  # Maps to Tauri's +DragDropEvent+ enum.
  module DragDropEvent
    # A drag operation has entered the webview.
    #
    # +paths+: Array of Pathnames being dragged.
    # +position+: PhysicalPosition of the mouse cursor.
    class Enter < Data.define(:paths, :position)
    end

    # A drag operation is moving over the webview.
    #
    # +position+: PhysicalPosition of the mouse cursor.
    class Over < Data.define(:position)
    end

    # The file(s) have been dropped onto the webview.
    #
    # +paths+: Array of Pathnames being dropped.
    # +position+: PhysicalPosition of the mouse cursor.
    class Drop < Data.define(:paths, :position)
    end

    # The drag operation has been cancelled or left the window.
    class Leave < Data.define
    end
  end
end

# SPDX-SnippetEnd
