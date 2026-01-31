# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WebviewEvent adapted from tauri-runtime/src/window.rs

module Tokra
  # Events from a webview.
  #
  # Mirrors Tauri's +WebviewEvent+ enum.
  module WebviewEvent
    # An event associated with drag and drop.
    #
    # Wraps a +DragDropEvent+ variant.
    class DragDrop < Data.define(:event)
    end
  end
end

# SPDX-SnippetEnd
