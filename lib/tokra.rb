# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tokra/version"
require "erb"
require "json"
require "securerandom"
require "ferro/url"
require_relative "tokra/error"
require_relative "tokra/closed_enum"
require_relative "tokra/raw_window_handle"
require_relative "tokra/resource"
require_relative "tokra/image"
require_relative "tokra/native"
require_relative "tokra/native/events"
require_relative "tokra/exit_request_api"
require_relative "tokra/close_request_api"
require_relative "tokra/run_event"
require_relative "tokra/window_event"
require_relative "tokra/page_load_payload"
require_relative "tokra/env"
require_relative "tokra/process"
require_relative "tokra/manager"
require_relative "tokra/event_target"
require_relative "tokra/event"
require_relative "tokra/event/listeners"
require_relative "tokra/listener"
require_relative "tokra/emitter"
require_relative "tokra/app_manager"
require_relative "tokra/runtime_context"
require_relative "tokra/app_handle"
require_relative "tokra/app"
require_relative "tokra/uri_scheme_context"
require_relative "tokra/uri_scheme_responder"
require_relative "tokra/response"
require_relative "tokra/z85"
require_relative "tokra/ipc/invoke_body"
require_relative "tokra/ipc/invoke"
require_relative "tokra/ipc/request"
require_relative "tokra/ipc/response"
require_relative "tokra/ipc/invoke_error"
require_relative "tokra/ipc/format_callback"
require_relative "tokra/ipc/unexpected"
require_relative "tokra/ipc/json"
require_relative "tokra/json5"
require_relative "tokra/ipc/command_item"
require_relative "tokra/ipc/serde"
require_relative "tokra/builder"
require_relative "tokra/plugin"
require_relative "tokra/ipc/channel"
require_relative "tokra/plugin_api"
require_relative "tokra/permission_state"
require_relative "tokra/state_manager"
require_relative "tokra/resource_table"
require_relative "tokra/event/plugin"
require_relative "tokra/resources/plugin"
require_relative "tokra/image/plugin"
require_relative "tokra/window"
require_relative "tokra/window_manager"
require_relative "tokra/cookie"
require_relative "tokra/webview"
require_relative "tokra/webview_url"
require_relative "tokra/webview_manager"
require_relative "tokra/webview_window"
require_relative "tokra/background_throttling_policy"
require_relative "tokra/scroll_bar_style"
require_relative "tokra/webview_builder"
require_relative "tokra/window_builder"
require_relative "tokra/webview_window_builder"
require_relative "tokra/window_builder/macos"
require_relative "tokra/window_builder/windows"
require_relative "tokra/window_builder/linux"
require_relative "tokra/window_builder/transparent"
require_relative "tokra/webview_builder/macos"
require_relative "tokra/path/resolver"
require_relative "tokra/dpi"
require_relative "tokra/physical_position"
require_relative "tokra/logical_position"
require_relative "tokra/physical_size"
require_relative "tokra/logical_size"
require_relative "tokra/physical_rect"
require_relative "tokra/logical_unit"
require_relative "tokra/physical_unit"
require_relative "tokra/window_size_constraints"
require_relative "tokra/color"
require_relative "tokra/monitor"
require_relative "tokra/theme"
require_relative "tokra/cursor_icon"
require_relative "tokra/user_attention_type"
require_relative "tokra/resize_direction"
require_relative "tokra/effect"
require_relative "tokra/effect_state"
require_relative "tokra/window_effects_config"
require_relative "tokra/effects_builder"
require_relative "tokra/progress_bar_status"
require_relative "tokra/progress_bar_state"
require_relative "tokra/title_bar_style"
require_relative "tokra/drag_drop_event"
require_relative "tokra/webview_event"
require_relative "tokra/utils"
require_relative "tokra/pattern"
require_relative "tokra/context"
require_relative "tokra/codegen"
# On Windows the extension imports WebView2Loader.dll, which its build
# installs beside it (ext/tokra/extconf.rb), and Windows does not look for an
# extension's DLLs in the extension's own directory. RubyInstaller limits the
# search to the directories it sets up and those added with
# add_dll_directory (AddDllDirectory; rubyinstaller2
# lib/ruby_installer/build/dll_directory.rb), so the directory is added
# there, or to PATH for a Ruby without RubyInstaller.
if RUBY_PLATFORM.match?(/mingw|mswin/)
  native_dir = File.expand_path("tokra", __dir__.to_s)
  if Object.const_defined?("RubyInstaller::Runtime")
    Object.const_get("RubyInstaller::Runtime").__send__(:add_dll_directory, native_dir)
  else
    ENV["PATH"] = "#{native_dir}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH', '')}"
  end
end
require_relative "tokra/tokra"
# The menu classes ask the extension which platform calls it defines.
require_relative "tokra/menu"
require_relative "tokra/menu_manager"
require_relative "tokra/rect"
require_relative "tokra/tray"
require_relative "tokra/tray_manager"
require_relative "tokra/activation_policy"
require_relative "tokra/window/macos"
require_relative "tokra/window/windows"
require_relative "tokra/rack/handler"

# Tokra is a port of Tauri to Ruby.
module Tokra
  # Generates the per-app IPC invoke key: 16 random bytes, Z85-encoded.
  #
  # The key is templated into the injected initialization scripts and
  # verified on every IPC message, so only frames the app initialized
  # can invoke commands. Mirrors Tauri's generate_invoke_key (lib.rs).
  def self.generate_invoke_key
    Z85.encode(SecureRandom.random_bytes(16))
  end

  # Your app's package information, Tokra::Utils::PackageInfo, at the
  # root where Tauri re-exports it (lib.rs:217-237).
  PackageInfo = Utils::PackageInfo

  # Your app's config, Tokra::Utils::Config::Config, at the root where
  # Tauri re-exports it (lib.rs:217-237).
  Config = Utils::Config::Config

  #--
  # SPDX-SnippetBegin
  # SPDX-License-Identifier: Apache-2.0 OR MIT
  # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
  # SPDX-SnippetComment: generate_context adapted from tauri-macros src/lib.rs:76-87
  #   and src/context.rs:24-169 at vendor/tauri 9f0306fbc
  #++

  # Reads your app's config and answers the Context to build your app
  # from.
  #
  # A Tauri app's <tt>main</tt> hands the builder
  # <tt>tauri::generate_context!()</tt>, a macro that reads
  # <tt>tauri.conf.json</tt> when the app compiles. A Ruby app has no
  # compile step, so this method reads <tt>tokra.conf.json</tt> when you
  # call it, with the same rules and the same errors, raised before any
  # window exists (ADR 014 §2).
  #
  # The file may be JSON5 instead, as <tt>tokra.conf.json5</tt> or as a
  # <tt>tokra.conf.json</tt> with comments or trailing commas, as Tauri
  # reads it with its <tt>config-json5</tt> feature (ADR 014 §7).
  #
  # With no +path+ it reads <tt>tokra.conf.json</tt> in the entry
  # script's directory, the one Ruby was started with, taken when
  # <tt>tokra</tt> loads, so a later <tt>Dir.chdir</tt> does not move it,
  # and a symlinked launcher resolves to the script it points at (ADR 014
  # §5). With +path+, a String or Pathname, a relative path joins that
  # directory and an absolute one is taken as given; a path where no
  # config file exists raises ArgumentError, "no file at path {path}
  # exists, expected tokra config file". Once the path is found only its
  # directory counts: the directory's <tt>tokra.conf.json</tt> (or
  # <tt>tokra.conf.json5</tt>) is read, with the platform's file merged
  # over it (Tokra::Codegen.get_config).
  #
  # Raises Tokra::Utils::Config::Parse::ConfigError when the files
  # cannot be read, and Tokra::Codegen::CodegenConfigError::Json when
  # they do not fit Tauri's schema. Reads no environment variable: Tauri's
  # <tt>TAURI_CONFIG</tt> belongs to its CLI (ADR 014 §6).
  #
  # Mirrors Tauri's <tt>generate_context!</tt> (tauri-macros
  # src/lib.rs:76-87, src/context.rs:24-169). Its <tt>capabilities</tt>,
  # <tt>assets</tt>, and <tt>test</tt> arguments arrive with the plans
  # that port what they feed.
  #
  # === Examples
  #
  #   context = Tokra.generate_context
  #   context.config.identifier  #=> "com.example.notes"
  #
  #   context = Tokra.generate_context("src-tokra/tokra.conf.json")
  def self.generate_context(path = nil)
    config_file = if path.nil?
      File.join(anchor, Utils::Config::Parse::ConfigFormat::Json.into_file_name)
    else
      given_config_file(path.to_s)
    end
    config, config_parent = Codegen.get_config(config_file)
    # Tauri's dev is !cfg!(feature = "custom-protocol") (tauri-macros
    # context.rs:155). Plan 054's question 1 settles how a Tokra app
    # sets it; until 054a-5, which reads it, it is true.
    Codegen.context_codegen(Codegen::ContextData.new(dev: true, config:, config_parent:))
  end

  # +path+ joined to the anchor when relative, checked for a config file
  # as the macro checks the path it is given (context.rs:36-56).
  def self.given_config_file(path) # :nodoc:
    path = File.join(anchor, path) unless File.absolute_path?(path)
    return path if Utils::Config::Parse.does_supported_file_name_exist(Utils::Platform::Target.current, path)

    raise ArgumentError, "no file at path #{Utils::Config::Parse.display(path)} exists, expected tokra config file"
  end
  private_class_method :given_config_file

  #--
  # SPDX-SnippetEnd
  #++

  # The entry script's directory, which a config path is relative to,
  # as Tauri's is to CARGO_MANIFEST_DIR (ADR 014 §5).
  def self.anchor # :nodoc:
    @anchor
  end

  # The entry script's name without its extension, which stands in for
  # Cargo's package name (Utils::PackageInfo), taken with the anchor so a
  # later change to $PROGRAM_NAME does not rename the app.
  def self.script_name # :nodoc:
    @script_name
  end

  # Records the anchor from +program+: the real directory of the script
  # it names, or the working directory when it names no file, as for
  # <tt>ruby -e</tt> or IRB; and the script's name. Runs once when tokra
  # loads; a test that sets $PROGRAM_NAME runs it again.
  def self.record_anchor(program = $PROGRAM_NAME) # :nodoc:
    @script_name = File.basename(program, ".*").freeze
    @anchor = (File.file?(program) ? File.dirname(File.realpath(program)) : Dir.pwd).freeze
  end

  record_anchor
end
