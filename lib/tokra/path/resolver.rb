# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PathResolver structure adapted from tauri/crates/tauri/src/path/desktop.rs

module Tokra
  # Path resolution utilities for cross-platform directory access.
  #
  # Wraps the Rust +dirs+ crate via thin Magnus bindings per ADR 005.
  module Path
    # Resolves application-specific paths in a cross-platform manner.
    #
    # Combines raw directory functions from the Rust +dirs+ crate with
    # platform-specific path logic in Ruby per ADR 005.
    class Resolver
      # Creates a new Resolver with the given configuration.
      #
      # +config+ must include +:identifier+ (the bundle identifier).
      # +platform:+ can be injected for testing (defaults to RUBY_PLATFORM).
      # +native:+ can be injected for testing (defaults to Tokra::Native).
      def initialize(config, platform: RUBY_PLATFORM, native: Native)
        @identifier = config.fetch(:identifier)
        @platform = platform
        @native = native
      end

      # Returns the path to the suggested directory for your app's log files.
      #
      # ## Platform-specific
      #
      # - **Linux:** +~/.local/share/{identifier}/logs+
      # - **macOS:** +~/Library/Logs/{identifier}+
      # - **Windows:** +%LOCALAPPDATA%/{identifier}/logs+
      def app_log_dir
        base = if macos?
          Pathname.new(@native.home_dir).join("Library", "Logs")
        else
          Pathname.new(@native.data_local_dir).join("logs")
        end
        base.join(@identifier)
      end

      private def macos?
        @platform.include?("darwin")
      end
    end
  end
end

# SPDX-SnippetEnd
