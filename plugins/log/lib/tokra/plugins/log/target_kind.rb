# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: TargetKind structure adapted from tauri-plugin-log lib.rs TargetKind enum

module Tokra
  module Plugins
    module Log
      # TargetKind determines the destination for log output.
      #
      # Mirrors Tauri's TargetKind enum. Use with Target.new(kind).
      #
      # == Kinds
      #
      # - +LogDir+: OS-specific log directory (~/Library/Logs on macOS)
      # - +Webview+: WebView console (for JS integration)
      # - +Stdout+: Standard output IO
      # - +Stderr+: Standard error IO
      # - +Folder+: Custom folder path
      #
      module TargetKind
        # Log to OS-specific application log directory.
        #
        # On macOS: ~/Library/Logs/{identifier}/
        # On Linux: ~/.local/share/{identifier}/logs/
        # On Windows: %LOCALAPPDATA%/{identifier}/logs/
        #
        # +file_name+: Optional log file name (defaults to app name).
        LogDir = Data.define(:file_name) do
          def initialize(file_name: nil)
            super
          end
        end
      end
    end
  end
end

# SPDX-SnippetEnd
