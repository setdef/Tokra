# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Target adapted from tauri-utils src/platform.rs:25-87
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    # The platforms an app runs on, as tauri-utils names them.
    #
    # Mirrors Tauri's <tt>tauri_utils::platform</tt> module, as far as its
    # desktop targets go.
    module Platform
      # The desktop platform an app runs on.
      #
      # A config can hold a platform's own file beside the main one,
      # <tt>tokra.macos.conf.json</tt> on macOS for example, and the loader
      # reads the one for the platform it runs on. Each platform needs a
      # name to look the file up by.
      #
      # These three are the targets. Tauri's Android and iOS are out of
      # Tokra's scope, so Target.new is private.
      #
      # Mirrors Tauri's <tt>Target</tt> (tauri-utils src/platform.rs:25-40).
      #
      # === Examples
      #
      #   Tokra::Utils::Platform::Target.current  #=> Tokra::Utils::Platform::Target::Linux
      #   Tokra::Utils::Config::Parse.read_from(Tokra::Utils::Platform::Target::Windows, __dir__)
      class Target < Data.define(:name)
        extend ClosedEnum

        ##
        # macOS.
        MacOS = new(name: "MacOS")
        # Windows.
        Windows = new(name: "Windows")
        # Linux, and any other desktop: Tauri's Target::current falls
        # through to it.
        Linux = new(name: "Linux")

        # The target this process runs on: MacOS on Darwin, Windows on
        # mingw and mswin, and Linux on anything else, the BSDs included,
        # since Tauri's Target::current falls through to Linux
        # (platform.rs:75-87).
        #
        # === Example
        #
        #   Tokra::Utils::Platform::Target.current  #=> Tokra::Utils::Platform::Target::MacOS
        def self.current
          for_ruby_platform(RUBY_PLATFORM)
        end

        # The target a Ruby platform string such as <tt>x86_64-freebsd14</tt>
        # names, by the rule of Target.current.
        def self.for_ruby_platform(platform) # :nodoc:
          case platform
          when /darwin/ then MacOS
          when /mingw|mswin/ then Windows
          else Linux
          end
        end

        close
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
