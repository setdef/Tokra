# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: TargetKind adapted from tauri-plugin-log src/lib.rs

module Tokra
  module Plugins
    module Log
      # Where a Target sends its lines.
      #
      # One log call can reach several places: the terminal while you
      # develop, a file a user can send you, the page's console. Each
      # Target names one of these kinds.
      #
      # Mirrors Tauri's +TargetKind+ enum (lib.rs:323-355).
      #
      # === Examples
      #
      #   Target.new(TargetKind::Stdout.new)
      #   Target.new(TargetKind::LogDir.new(file_name: "webview"))
      #   Target.new(TargetKind::Folder.new(path: "logs"))
      #   Target.new(TargetKind::Dispatch.new(Logger.new("audit.log")))
      module TargetKind
        # Prints lines to standard output (+$stdout+).
        class Stdout < Data.define; end

        # Prints lines to standard error (+$stderr+).
        class Stderr < Data.define; end

        # Writes lines to <tt><file_name>.log</tt> in the folder at +path+,
        # rotating it as the builder's RotationStrategy says.
        #
        # The plugin creates the folder before writing. +file_name+
        # defaults to the app's name.
        class Folder < Data.define(:path, :file_name)
          # :attr_reader: path
          # The folder, a String or Pathname.

          # :attr_reader: file_name
          # The log file's name without <tt>.log</tt>, or +nil+ for the
          # app's name.

          # Makes a Folder kind.
          #
          # [path] The folder, a String or Pathname.
          # [file_name] The file's name without <tt>.log</tt>, or +nil+.
          def initialize(path:, file_name: nil)
            super
          end
        end

        # Writes lines to the OS's log directory for the app, rotating the
        # file as the builder's RotationStrategy says.
        #
        # The plugin creates the directory before writing. +file_name+
        # defaults to the app's name. The directory is the app handle's
        # <tt>path.app_log_dir</tt>:
        #
        # - Linux: <tt>$XDG_DATA_HOME/{bundleIdentifier}/logs</tt> or
        #   <tt>$HOME/.local/share/{bundleIdentifier}/logs</tt>
        # - macOS: <tt>{homeDir}/Library/Logs/{bundleIdentifier}</tt>
        # - Windows: <tt>{FOLDERID_LocalAppData}/{bundleIdentifier}/logs</tt>
        class LogDir < Data.define(:file_name)
          # :attr_reader: file_name
          # The log file's name without <tt>.log</tt>, or +nil+ for the
          # app's name.

          # Makes a LogDir kind.
          #
          # [file_name] The file's name without <tt>.log</tt>, or +nil+.
          def initialize(file_name: nil)
            super
          end
        end

        # Forwards lines to the webview as <tt>log://log</tt> events.
        #
        # Each event's payload is <tt>{ message:, level: }</tt>: the
        # formatted line and its LogLevel number. The page hears them
        # through <tt>attachConsole</tt> or <tt>attachLogger</tt> from
        # <tt>@tauri-apps/plugin-log</tt>.
        class Webview < Data.define; end

        # Hands each line to a Logger of your own.
        #
        # Tauri's Dispatch chains any fern dispatch, so an app can build a
        # target the plugin does not offer. A Ruby app reaches for a
        # Logger instead: the plugin calls <tt>logger.add(severity,
        # line, target)</tt>, with +:trace+ as Logger's DEBUG.
        class Dispatch < Data.define(:logger)
          # :attr_reader: logger
          # Any object with Logger's +add+.
        end
      end
    end
  end
end

# SPDX-SnippetEnd
