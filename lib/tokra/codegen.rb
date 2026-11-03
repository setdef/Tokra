# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: adapted from tauri-codegen src/lib.rs:32-99 and
#   src/context.rs:33-45, 135-491 at vendor/tauri 9f0306fbc
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
    # on: the directory's <tt>tokra.conf.json</tt>, with the platform's
    # file merged over it, checked against the schema. A relative +path+
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
    # its package information, and its pattern.
    #
    # The package information is the config's <tt>productName</tt> and
    # <tt>version</tt>. What Tauri takes from <tt>Cargo.toml</tt> comes
    # from the entry script here (Tokra::Utils::PackageInfo).
    #
    # Mirrors Tauri's <tt>context_codegen</tt> (tauri-codegen
    # src/context.rs:135-491), as far as plan 054's first phase goes: the
    # assets, icons, and capabilities arrive with their plans.
    #
    # === Example
    #
    #   context = Tokra::Codegen.context_codegen(data)
    #   context.package_info.version  #=> "1.0.0"
    def self.context_codegen(data)
      config = data.config
      script = Tokra.script_name
      package_info = Utils::PackageInfo.new(name: config.product_name || script, version: config.version || "0.0.0",
        authors: "", description: "", crate_name: script)
      # Brownfield, and isolation too until an isolation plan builds it
      # (context.rs:354-359; plan 054, decision 21).
      context = Context.new(config:, package_info:, pattern: Pattern::Brownfield.new)
      context.dev = data.dev
      context
    end
  end
end

#--
# SPDX-SnippetEnd
#++
