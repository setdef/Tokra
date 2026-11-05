# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Context adapted from tauri src/lib.rs:349-527 at vendor/tauri 9f0306fbc
#++

module Tokra
  # Everything your app is built from: its config, its default window
  # icon, its package information, and its pattern.
  #
  # A Tauri app compiles its config into the binary: a macro reads
  # <tt>tauri.conf.json</tt> and hands the builder a context holding it.
  # A Ruby app has no compile step, so Tokra.generate_context reads
  # <tt>tokra.conf.json</tt> when your app starts and answers this (ADR
  # 014 §2).
  #
  # Change what the context holds before you build the app with
  # #config= and #package_info=. Its values are frozen, so build a changed
  # copy with <tt>Data#with</tt>: Tauri's <tt>config_mut</tt> and
  # <tt>package_info_mut</tt> lend the value to change in place, which
  # Ruby has no way to express (ADR 014 §8).
  #
  # Change the icon each window without one of its own takes with
  # #set_default_window_icon.
  #
  # The tray icon, the assets, and the capabilities Tauri's context
  # carries join with the plans that port them (plan 054's inventory).
  #
  # Mirrors Tauri's <tt>tauri::Context</tt> (lib.rs:349-527).
  #
  # === Examples
  #
  #   context = Tokra.generate_context
  #   context.config.identifier  #=> "com.example.notes"
  #
  #   context.config = context.config.with(identifier: "com.example.notes.beta")
  #   context.package_info = context.package_info.with(version: "2.0.0-beta.1")
  class Context
    # The app's config, a Tokra::Utils::Config::Config.
    attr_reader :config

    # The app's name, version, and authors, a Tokra::Utils::PackageInfo.
    attr_reader :package_info

    # The pattern the app's pages invoke through, such as
    # Tokra::Pattern::Brownfield.
    attr_reader :pattern

    # The icon a window takes when its builder gives it none, a
    # Tokra::Image, or +nil+ for none. Tokra.generate_context decodes it
    # from <tt>icons/icon.png</tt> beside the config, or the first PNG the
    # config's <tt>bundle.icon</tt> lists (on Windows, an ICO first).
    #
    # Mirrors Tauri's <tt>Context::default_window_icon</tt> (lib.rs:433-437).
    #
    # === Example
    #
    #   context.default_window_icon.width  #=> 32
    attr_reader :default_window_icon

    # The app's icon file as it is, which Tokra sets on macOS's Dock while
    # the app runs in development, or +nil+. Tauri's is internal too
    # (lib.rs:362).
    attr_reader :app_icon # :nodoc:

    # Whether the app runs in development, Tauri's <tt>ContextData.dev</tt>.
    # Nothing reads it before plan 054a-5, which settles its default
    # (decision 10, question 1); until then it is +true+.
    attr_reader :dev # :nodoc:

    # Builds a context, as Tauri's <tt>Context::new</tt> does
    # (lib.rs:490-517). Tokra.generate_context builds one for you.
    #
    # [config] the app's Tokra::Utils::Config::Config.
    # [default_window_icon] the Tokra::Image a window without an icon
    #                       takes, or +nil+.
    # [app_icon] an image file's bytes, a String, that the app sets on
    #            macOS's Dock in development, or +nil+.
    # [package_info] the app's Tokra::Utils::PackageInfo.
    # [pattern] the app's pattern, such as <tt>Tokra::Pattern::Brownfield.new</tt>.
    #
    # Each has to be its type; anything else raises TypeError.
    #
    # === Example
    #
    #   config = Tokra::Utils::Config::Config.new(identifier: "com.example.app")
    #   info = Tokra::Utils::PackageInfo.new(name: "app", version: "0.0.0", authors: "", description: "",
    #     crate_name: "app")
    #   Tokra::Context.new(config:, default_window_icon: nil, app_icon: nil, package_info: info,
    #     pattern: Tokra::Pattern::Brownfield.new)
    def initialize(config:, default_window_icon:, app_icon:, package_info:, pattern:)
      self.config = config
      set_default_window_icon(default_window_icon)
      unless app_icon.nil? || app_icon.is_a?(String)
        raise TypeError, "wrong argument type #{app_icon.class} (expected String)"
      end

      @app_icon = app_icon
      self.package_info = package_info
      raise TypeError, "wrong argument type #{pattern.class} (expected Tokra::Pattern)" unless pattern.is_a?(Pattern::Brownfield)

      @pattern = pattern
      @dev = true
    end

    # Makes +icon+, a Tokra::Image or +nil+, the icon a window takes when
    # its builder gives it none. Answers +nil+. Anything else raises
    # TypeError.
    #
    # Mirrors Tauri's <tt>Context::set_default_window_icon</tt>
    # (lib.rs:439-443).
    #
    # === Example
    #
    #   context.set_default_window_icon(Tokra::Image.from_path("icons/beta.png"))
    def set_default_window_icon(icon)
      raise TypeError, "wrong argument type #{icon.class} (expected Tokra::Image)" unless icon.nil? || icon.is_a?(Image)

      @default_window_icon = icon
      nil
    end

    # Replaces the config with +config+, a Tokra::Utils::Config::Config,
    # deep-frozen so any Ractor may read it. Answers +config+.
    #
    # Mirrors Tauri's <tt>Context::config_mut</tt> (lib.rs:418-421).
    #
    # === Example
    #
    #   context.config = context.config.with(product_name: "Notes Beta")
    def config=(config)
      unless config.is_a?(Utils::Config::Config)
        raise TypeError, "wrong argument type #{config.class} (expected Tokra::Utils::Config::Config)"
      end

      @config = Ractor.make_shareable(config)
    end

    # Replaces the package information with +package_info+, a
    # Tokra::Utils::PackageInfo, deep-frozen. Answers +package_info+.
    #
    # Mirrors Tauri's <tt>Context::package_info_mut</tt> (lib.rs:456-459).
    #
    # === Example
    #
    #   context.package_info = context.package_info.with(version: "1.0.1")
    def package_info=(package_info)
      unless package_info.is_a?(Utils::PackageInfo)
        raise TypeError, "wrong argument type #{package_info.class} (expected Tokra::Utils::PackageInfo)"
      end

      @package_info = Ractor.make_shareable(package_info)
    end

    # Sets whether the app runs in development (#dev).
    attr_writer :dev # :nodoc:
  end
end

#--
# SPDX-SnippetEnd
#++
