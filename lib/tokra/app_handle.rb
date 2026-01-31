# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AppHandle structure adapted from tauri/crates/tauri/src/app.rs

module Tokra
  # Handle to the running application, safe to pass between Ractors.
  #
  # Provides access to application state and control methods.
  # Includes the Manager module for shared interface.
  class AppHandle
    include Manager

    # Creates a new AppHandle with the given AppManager.
    #
    # This is called internally by App and should not be called directly.
    def initialize(manager, state_manager: nil) # :nodoc:
      @manager = manager
      @state_manager = state_manager
    end

    # Returns self since this is already an app handle.
    def app_handle
      self
    end

    # Retrieves managed state by class.
    #
    # Raises +KeyError+ if not found, +Error+ if no StateManager.
    def state(klass)
      mgr = @state_manager
      raise Error, "No StateManager available" unless mgr

      mgr.get(klass)
    end

    # Retrieves managed state by class, or +nil+ if not found.
    def try_state(klass)
      @state_manager&.try_get(klass)
    end

    # Returns the application configuration.
    def config
      @manager.config
    end

    # Returns all managed webviews.
    def webviews
      @manager.webviews
    end

    # Returns the path resolver for app directories.
    #
    # Provides cross-platform access to app-specific directories like
    # log directories, config directories, etc.
    def path
      @path ||= Path::Resolver.new(config)
    end

    # Emits an event to all webviews.
    #
    # Mirrors Tauri's AppHandle#emit which broadcasts to all webviews.
    def emit(event_name, payload)
      js = Tokra::Native.emit_js_script(event_name, payload.to_json)
      webviews.each_value { |wv| wv.eval(js) }
    end

    # Requests application exit with optional exit code.
    #
    # Currently calls Kernel.exit directly.
    # Will signal native event loop when wired up.
    def exit(code = 0)
      Kernel.exit(code)
    end
  end
end

# SPDX-SnippetEnd
