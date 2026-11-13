# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Commands adapted from tauri-plugin-process src/commands.rs

module Tokra
  module Plugins
    module Process
      # The plugin's IPC commands: exit and restart.
      #
      # Each takes what Tauri's command takes and returns +nil+, as the
      # Rust function returns <tt>()</tt>, so the page's promise resolves
      # with +null+. Plugin#extend_api reads the arguments and calls them.
      #
      # These are the functions of Tauri's private +commands+ module
      # (commands.rs).
      module Commands
        # Asks the app to exit with +code+, an Integer in the range of a
        # Rust +i32+, through AppHandle#exit (commands.rs:7-10). The
        # handlers of RunEvent::ExitRequested may still prevent it.
        #
        # === Example
        #
        #   Tokra::Plugins::Process::Commands.exit(handle, 0)
        def self.exit(app, code)
          app.exit(code)
          nil
        end

        # Asks the app to restart through AppHandle#request_restart
        # (commands.rs:12-15). No handler can prevent it.
        #
        # === Example
        #
        #   Tokra::Plugins::Process::Commands.restart(handle)
        def self.restart(app)
          app.request_restart
          nil
        end
      end
    end
  end
end

# SPDX-SnippetEnd
