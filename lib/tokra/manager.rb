# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Shared interface for AppHandle, Window, and Webview.
  #
  # Mirrors Tauri's Manager<R> trait, providing common functionality
  # like state management, configuration access, and window/webview lookup.
  #
  # Plugins can extend Manager to add functionality to all manager types:
  #
  #   module ClipboardExt
  #     def clipboard
  #       state(Clipboard)
  #     end
  #   end
  #
  #   Tokra::Manager.include(ClipboardExt)
  #
  # This enables `app.clipboard`, `window.clipboard`, `webview.clipboard`.
  module Manager
    # Returns the application handle.
    def app_handle
      raise NotImplementedError, "#{self.class} must implement #app_handle"
    end

    # Returns the application configuration.
    def config
      raise NotImplementedError, "#{self.class} must implement #config"
    end

    # Adds state to the state manager.
    #
    # @param state [Object] the state object to manage
    # @return [Boolean] true if added, false if already managed
    def manage(state)
      raise NotImplementedError, "#{self.class} must implement #manage"
    end

    # Retrieves managed state by class.
    #
    # @param klass [Class] the class to look up
    # @return [Object] the managed state instance
    # @raise [KeyError] if no state is managed for this class
    def state(klass)
      raise NotImplementedError, "#{self.class} must implement #state"
    end

    # Retrieves managed state by class, or nil if not found.
    #
    # @param klass [Class] the class to look up
    # @return [Object, nil] the managed state instance or nil
    def try_state(klass)
      raise NotImplementedError, "#{self.class} must implement #try_state"
    end

    # Fetches a window by label.
    #
    # @param label [String] the window label
    # @return [Window, nil] the window or nil
    def get_window(label)
      raise NotImplementedError, "#{self.class} must implement #get_window"
    end

    # Fetches a webview by label.
    #
    # @param label [String] the webview label
    # @return [Webview, nil] the webview or nil
    def get_webview(label)
      raise NotImplementedError, "#{self.class} must implement #get_webview"
    end

    # Returns all managed windows.
    #
    # @return [Hash{String => Window}] label to window mapping
    def windows
      raise NotImplementedError, "#{self.class} must implement #windows"
    end

    # Returns all managed webviews.
    #
    # @return [Hash{String => Webview}] label to webview mapping
    def webviews
      raise NotImplementedError, "#{self.class} must implement #webviews"
    end
  end
end
