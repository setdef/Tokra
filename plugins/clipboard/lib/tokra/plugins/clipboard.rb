# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tokra"

# Load native extension
begin
  require "tokra_clipboard/tokra_clipboard"
rescue LoadError
  # Extension not compiled yet
end

module Tokra
  # Namespace for Tokra plugins.
  #
  # First-party plugins provide functionality like logging, clipboard access,
  # notifications, and other desktop integrations.
  module Plugins
    # Clipboard plugin for Tokra desktop applications.
    #
    # Provides read/write access to the system clipboard using the arboard crate.
    #
    # == Example
    #
    #   Tokra::Builder.new
    #     .plugin(Tokra::Plugins::Clipboard.new)
    #     .run
    #
    class Clipboard < Tokra::Plugin
      # Returns the unique plugin identifier.
      def name
        "clipboard"
      end

      # Initializes the clipboard plugin.
      #
      # +app+::    the application handle
      # +config+:: plugin configuration hash
      def initialize(app, config = {})
        raise NotImplementedError
      end

      # Reads text from the clipboard.
      #
      # Returns the clipboard text content, or +nil+ if empty.
      def read_text
        raise NotImplementedError
      end

      # Writes text to the clipboard.
      #
      # +text+:: the text string to write
      def write_text(text)
        raise NotImplementedError
      end

      # Clears the clipboard contents.
      def clear
        raise NotImplementedError
      end

      # Called on each run loop event.
      def on_event(event)
        raise NotImplementedError
      end
    end
  end
end
