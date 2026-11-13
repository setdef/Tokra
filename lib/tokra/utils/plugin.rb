# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: adapted from tauri/crates/tauri-utils/src/plugin.rs:9-91

module Tokra
  module Utils
    # The plugins' global API scripts: each plugin's JavaScript API as an
    # IIFE that puts it on <tt>window.__TAURI__</tt>.
    #
    # A page with no frontend bundler cannot import
    # <tt>@tauri-apps/plugin-dialog</tt>. Tauri's answer is the app config's
    # <tt>withGlobalTauri</tt>: every page runs Tauri's own API bundle and
    # each plugin's script, so the page calls
    # <tt>window.__TAURI__.dialog.open()</tt>. Something has to know which
    # plugins the app has and where their scripts are.
    #
    # A plugin gem names its script here when it is required, and
    # Tokra.generate_context reads every script named so far when the
    # config sets <tt>withGlobalTauri</tt>, Tauri's first. Require your
    # plugins before you call Tokra.generate_context, as an app does at the
    # top of its file.
    #
    # Use it to ship a global API script with a plugin of your own.
    #
    # Mirrors Tauri's <tt>tauri_utils::plugin</tt> (plugin.rs:9-91): where
    # Tauri collects the scripts of the crates an app links when it
    # compiles, Tokra collects those of the gems it requires (plan 064,
    # decision 7).
    #
    # === Example
    #
    #   # lib/my_plugin.rb, in the gem
    #   Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("my_plugin/api-iife.js", __dir__))
    module Plugin
      none = [] #: Array[String]
      @global_api_script_paths = none.freeze

      # Names +path+, a plugin's global API script, for the app to run in
      # each page when its config sets <tt>withGlobalTauri</tt>, and
      # returns +nil+. The path is kept canonicalized, once however often
      # it is named. A path that names no file raises Tokra::Error,
      # "failed to canonicalize global API script path: {error}", where
      # Tauri's build panics with that message.
      #
      # Mirrors <tt>define_global_api_script_path</tt> (plugin.rs:21-30),
      # which tauri-plugin's build Builder#global_api_script_path calls.
      #
      # === Example
      #
      #   Tokra::Utils::Plugin.define_global_api_script_path(File.expand_path("api-iife.js", __dir__))
      def self.define_global_api_script_path(path)
        canonical = begin
          File.realpath(path)
        rescue SystemCallError => e
          raise Error, "failed to canonicalize global API script path: #{io_error(e)}"
        end
        paths = @global_api_script_paths
        @global_api_script_paths = Ractor.make_shareable([*paths, canonical]) unless paths.include?(canonical)
        nil
      end

      # The scripts named so far, canonicalized, in the order they were
      # named: a frozen Array of Strings.
      #
      # === Example
      #
      #   Tokra::Utils::Plugin.global_api_script_paths  #=> ["/gems/tokra-dialog/lib/.../api-iife.js"]
      def self.global_api_script_paths
        @global_api_script_paths
      end

      # The text of Tauri's own API bundle, then of each script named so
      # far, in order: a frozen Array of Strings. A script that cannot be
      # read raises Tokra::Error, "failed to read plugin global API script
      # {path}: {error}", where Tauri's codegen panics.
      #
      # Mirrors <tt>read_global_api_scripts</tt> (plugin.rs:62-90), with
      # Tauri's bundle first, as <tt>save_global_api_scripts_paths</tt>
      # inserts it (plugin.rs:37-60).
      #
      # === Example
      #
      #   Tokra::Utils::Plugin.read_global_api_scripts.size  #=> 2, with one plugin's
      def self.read_global_api_scripts
        scripts = @global_api_script_paths.map do |path|
          File.read(path)
        rescue SystemCallError => e
          raise Error, "failed to read plugin global API script #{path}: #{io_error(e)}"
        end
        Ractor.make_shareable([Native.load_js_template("bundle.global.js"), *scripts])
      end

      # A Ruby SystemCallError as Rust displays an <tt>io::Error</tt> from
      # the operating system: <tt>"{description} (os error {code})"</tt>.
      def self.io_error(error) # :nodoc:
        # A nil message leaves the description alone, which Ruby allows
        # and core's RBS does not say.
        description = SystemCallError.new(nil, error.errno).message # steep:ignore ArgumentTypeMismatch
        "#{description} (os error #{error.errno})"
      end
      private_class_method :io_error
    end
  end
end

# SPDX-SnippetEnd
