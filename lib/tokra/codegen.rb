# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "codegen/cached_icon"

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: adapted from tauri-codegen src/lib.rs:32-99 and
#   src/context.rs:33-45, 135-507 at vendor/tauri 9f0306fbc
#++

module Tokra
  # Turns a config file into the Context your app is built from.
  #
  # Tauri's tauri-codegen crate reads the config while the app compiles
  # and writes the code that builds its context. Ruby has no compile
  # step, so this module does the same work when your app starts, and
  # answers the context itself (ADR 014 §2). Tokra.generate_context calls
  # it, as Tauri's macro calls codegen.
  #
  # Mirrors Tauri's tauri-codegen crate: <tt>get_config</tt>,
  # <tt>ContextData</tt>, and <tt>context_codegen</tt>.
  #
  # === Example
  #
  #   config, parent = Tokra::Codegen.get_config("/app/tokra.conf.json")
  #   data = Tokra::Codegen::ContextData.new(dev: true, config:, config_parent: parent)
  #   context = Tokra::Codegen.context_codegen(data)
  module Codegen
    # Raised when a config file's JSON does not fit the schema.
    #
    # The file parses, but a key is unknown, a value has the wrong type,
    # or a required key is missing. The message is serde's, without a
    # line or column, since Tauri checks the parsed value, not the text.
    #
    # Codegen's other errors have no cause in Tokra: a file that cannot be
    # read raises Tokra::Utils::Config::Parse::ConfigError itself, as
    # Tauri's transparent variant shows it, and no working directory moves
    # and no environment variable is read (plan 054, decision 8).
    #
    # Mirrors Tauri's <tt>CodegenConfigError</tt> (tauri-codegen
    # src/lib.rs:32-51).
    #
    # === Example
    #
    #   begin
    #     Tokra.generate_context
    #   rescue Tokra::Codegen::CodegenConfigError::Json => e
    #     warn e.message  # missing field `identifier`
    #   end
    class CodegenConfigError < Tokra::Error
      # The config does not fit the schema; the message is serde's.
      class Json < CodegenConfigError
      end
    end

    # What Codegen.context_codegen builds a context from.
    #
    # [dev] whether the app runs in development, which Tauri reads from
    #       its <tt>custom-protocol</tt> feature (plan 054, decision 10).
    # [config] the Tokra::Utils::Config::Config.
    # [config_parent] the config file's directory.
    #
    # Tauri's <tt>root</tt>, <tt>capabilities</tt>, <tt>assets</tt>, and
    # <tt>test</tt> have no Ruby meaning yet: Ruby has no crate paths, and
    # the rest arrive with the plans that port what they feed.
    #
    # Mirrors Tauri's <tt>ContextData</tt> (tauri-codegen
    # src/context.rs:33-45).
    #
    # === Example
    #
    #   Tokra::Codegen::ContextData.new(dev: true, config:, config_parent: "/app")
    class ContextData < Data.define(:dev, :config, :config_parent)
    end

    # Reads the config beside +path+ for the platform this process runs
    # on: the directory's <tt>tokra.conf.json</tt> (or
    # <tt>tokra.conf.json5</tt>), with the platform's file merged over it,
    # checked against the schema. A relative +path+
    # joins the working directory. Answers the Tokra::Utils::Config::Config
    # and the directory it came from.
    #
    # Raises Tokra::Utils::Config::Parse::ConfigError when the files
    # cannot be read, and CodegenConfigError::Json when they do not fit
    # the schema.
    #
    # Tauri merges its <tt>TAURI_CONFIG</tt> variable over the files too;
    # that is the CLI's, and Tokra reads no environment variable (ADR 014
    # §6). Tauri moves the working directory to the config's while it
    # reads <tt>version</tt>; Tokra hands the reader the directory instead.
    #
    # Mirrors Tauri's <tt>get_config</tt> (tauri-codegen src/lib.rs:53-99).
    #
    # === Example
    #
    #   config, parent = Tokra::Codegen.get_config("/app/tokra.conf.json")
    #   parent  #=> "/app"
    def self.get_config(path)
      path = path.to_s
      path = File.join(Dir.pwd, path) unless File.absolute_path?(path)
      parent = File.dirname(path)
      raw, = Utils::Config::Parse.read_from(Utils::Platform::Target.current, parent)
      [config_from(raw, parent), parent]
    end

    # +raw+, the merged JSON, read as the schema reads it, or
    # CodegenConfigError::Json with serde's words.
    def self.config_from(raw, parent) # :nodoc:
      Utils::Config::Config.deserialize(raw, parent)
    rescue Ipc::CommandItem::Mismatch => e
      raise CodegenConfigError::Json, e.message
    end
    private_class_method :config_from

    # Builds the Context +data+, a ContextData, describes: its config,
    # its default window icon, its app icon, its tray icon, its package
    # information, and its pattern.
    #
    # The default window icon is the first <tt>.png</tt> the config's
    # <tt>bundle.icon</tt> lists, else <tt>icons/icon.png</tt>, beside the
    # config, decoded by CachedIcon; on Windows, the first <tt>.ico</tt>,
    # else <tt>icons/icon.ico</tt>, when that file exists. So a config
    # directory without the icon fails here, as a Tauri app without one
    # fails to compile. The app icon, set on macOS's Dock in development,
    # is the first <tt>.icns</tt> or <tt>.png</tt> as it is. The tray
    # icon, when the config has an <tt>app.trayIcon</tt>, is its
    # <tt>iconPath</tt> beside the config, a <tt>.png</tt> or an
    # <tt>.ico</tt>, decoded by CachedIcon.
    #
    # The package information is the config's <tt>productName</tt> and
    # <tt>version</tt>. What Tauri takes from <tt>Cargo.toml</tt> comes
    # from the entry script here (Tokra::Utils::PackageInfo).
    #
    # Raises RuntimeError with codegen's message when an icon cannot be
    # read or decoded, and EmbeddedAssetsError::InvalidImageExtension when
    # one is neither PNG nor ICO (CachedIcon).
    #
    # Mirrors Tauri's <tt>context_codegen</tt> (tauri-codegen
    # src/context.rs:135-491), as far as plan 054 has come: the assets and
    # the capabilities arrive with their plans.
    #
    # === Example
    #
    #   context = Tokra::Codegen.context_codegen(data)
    #   context.package_info.version  #=> "1.0.0"
    #   context.default_window_icon.width  #=> 32
    def self.context_codegen(data)
      config = data.config
      target = Utils::Platform::Target.current
      default_window_icon = default_window_icon(config, data.config_parent, target)
      app_icon = app_icon(config, data.config_parent, target, data.dev)
      tray_icon = tray_icon(config, data.config_parent)
      script = Tokra.script_name
      package_info = Utils::PackageInfo.new(name: config.product_name || script, version: config.version || "0.0.0",
        authors: "", description: "", crate_name: script)
      # Brownfield, and isolation too until an isolation plan builds it
      # (context.rs:354-359; plan 054, decision 21).
      context = Context.new(config:, default_window_icon:, app_icon:, package_info:, pattern: Pattern::Brownfield.new)
      context.set_tray_icon(tray_icon) if tray_icon
      context.dev = data.dev
      context
    end

    # The icon of the config's <tt>app.trayIcon</tt>, decoded by CachedIcon
    # from its <tt>iconPath</tt> joined to the config's directory, or +nil+
    # when the config has no tray (context.rs:291-300). Every Tokra target
    # is a desktop one, so the target check Tauri makes always passes.
    def self.tray_icon(config, config_parent) # :nodoc:
      tray = config.app.tray_icon
      return nil unless tray

      CachedIcon.new(join(config_parent, tray.icon_path.to_s)).value #: Image
    end

    # The default window icon for +target+, a Tokra::Image decoded from
    # the file #find_icon finds beside the config (context.rs:213-246).
    def self.default_window_icon(config, config_parent, target) # :nodoc:
      if target == Utils::Platform::Target::Windows
        icon_path = find_icon(config, config_parent, "icons/icon.ico") { |i| i.end_with?(".ico") }
        if File.exist?(icon_path)
          return CachedIcon.new(icon_path).value #: Image
        end
      end
      CachedIcon.new(find_icon(config, config_parent, "icons/icon.png") { |i| i.end_with?(".png") }).value #: Image
    end

    # The app icon's raw bytes on macOS in development, and +nil+
    # otherwise: the first <tt>.icns</tt>, else the first <tt>.png</tt>
    # (context.rs:248-268).
    def self.app_icon(config, config_parent, target, dev) # :nodoc:
      return nil unless target == Utils::Platform::Target::MacOS && dev

      icon_path = find_icon(config, config_parent, "icons/icon.png") { |i| i.end_with?(".icns") }
      icon_path = find_icon(config, config_parent, "icons/icon.png") { |i| i.end_with?(".png") } unless File.exist?(icon_path)
      CachedIcon.new_raw(icon_path).value #: String
    end

    # The first of the config's <tt>bundle.icon</tt> entries the block
    # accepts, else +default+, joined to +config_parent+ as Rust's
    # <tt>Path::join</tt> joins it: an absolute entry stands alone, and
    # the separator is the platform's, so the path reads in a message as
    # Tauri's does (context.rs:493-507).
    #
    # On Windows, as <tt>PathBuf::push</tt> there does, an entry with a
    # prefix, such as <tt>C:a.png</tt>, stands alone too, and one with a
    # root but no prefix, such as <tt>\icons\a.png</tt>, keeps only the
    # parent's drive or share. On Unix a <tt>\\</tt> is no separator, so
    # such an entry joins like any relative one.
    private_class_method def self.find_icon(config, config_parent, default, &predicate)
      join(config_parent, config.bundle.icon.find(&predicate) || default)
    end

    # +path+ joined to +config_parent+ as Rust's <tt>Path::join</tt> joins
    # it: an absolute +path+ stands alone, and the separator is the
    # platform's, so the path reads in a message as Tauri's does. #find_icon
    # explains Windows' prefixes and roots.
    private_class_method def self.join(config_parent, icon_path)
      return icon_path if File.absolute_path?(icon_path)

      parent = Utils::Config::Parse.display(config_parent)
      separator = File::ALT_SEPARATOR
      if separator
        return icon_path if icon_path.match?(/\A[A-Za-z]:/)
        # The parent's prefix: a drive, or a UNC server and share.
        return "#{parent[%r{\A(?:[A-Za-z]:|[\\/]{2}[^\\/]+[\\/][^\\/]+)}]}#{icon_path}" if icon_path.start_with?("/", "\\")
      end
      separator ||= File::SEPARATOR
      parent.end_with?(File::SEPARATOR, separator) ? "#{parent}#{icon_path}" : "#{parent}#{separator}#{icon_path}"
    end
  end
end

#--
# SPDX-SnippetEnd
#++
