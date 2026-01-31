# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Base class for Tokra plugins.
  #
  # Mirrors Tauri's Plugin trait, providing lifecycle hooks for desktop
  # application integration.
  #
  # == Implementing a Plugin
  #
  # Subclass this and override the lifecycle methods:
  #
  #   class MyPlugin < Tokra::Plugin
  #     def name
  #       "my_plugin"
  #     end
  #
  #     def initialize(app, config = {})
  #       # Setup logic
  #     end
  #
  #     def on_event(event)
  #       # Handle run loop events
  #     end
  #   end
  #
  class Plugin
    # Returns the unique plugin identifier.
    def name
      raise NotImplementedError
    end

    # Initializes the plugin with app handle and configuration.
    def initialize(app, config = {})
      raise NotImplementedError
    end

    # Called on each run loop event.
    def on_event(event)
      raise NotImplementedError
    end
  end
end
