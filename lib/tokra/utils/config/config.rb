# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Config, PackageVersion, and version_deserializer adapted
#   from tauri-utils src/config.rs:3133-3332 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # Your whole app config, as <tt>tokra.conf.json</tt> writes it.
      #
      # An app's identity, windows, security, build, bundle, and plugin
      # settings live in one file, so every part of the app reads them from
      # one place. Tokra.generate_context reads the file, merges the
      # platform's own file over it, and hands you this, frozen and
      # shareable with any Ractor.
      #
      # Every key is Tauri's (ADR 014 §4): <tt>identifier</tt> is
      # required, <tt>$schema</tt> reads as +schema+, and
      # <tt>plugins</tt> is a Hash of plugin name to that plugin's JSON,
      # with String keys, as Tauri's <tt>JsonValue</tt> holds it. Each
      # plugin reads its own slice (plan 054, decision 20).
      #
      # <tt>version</tt> is a semver string, or a path to a JSON file
      # whose <tt>version</tt> it reads, such as your
      # <tt>package.json</tt>, resolved against the config's directory.
      # Tauri resolves it against the working directory, which its
      # codegen moves to the config's directory for the call; Tokra passes
      # the directory instead, so no other thread sees the working
      # directory move. A file named like a version, such as
      # <tt>1.0.0</tt>, beside the config is read as JSON, as in Tauri.
      #
      # Mirrors Tauri's <tt>Config</tt> (config.rs:3198-3325).
      #
      # === Examples
      #
      #   config = Tokra.generate_context.config
      #   config.identifier          #=> "com.example.notes"
      #   config.product_name        #=> "Notes"
      #   config.plugins["log"]      #=> {"level" => "info"}
      #
      #   beta = config.with(identifier: "com.example.notes.beta")
      class Config < Data.define(
        :schema, :product_name, :main_binary_name, :version, :identifier, :app, :build, :bundle, :plugins
      )
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        private_constant :STRING

        # The fields in config.rs's order. +version+'s reader needs the
        # config's directory, so Config.deserialize gives it one.
        FIELDS = [
          Field.option(:schema, "$schema", STRING),
          Field.option(:product_name, "productName", STRING, aliases: %w[product-name]),
          Field.option(:main_binary_name, "mainBinaryName", STRING, aliases: %w[main-binary-name]),
          Field.defaulted(:version, "version", STRING, nil, option: true),
          Field.required(:identifier, "identifier", STRING),
          Field.defaulted(:app, "app", -> (raw) { AppConfig.deserialize(raw) }, AppConfig.new),
          Field.defaulted(:build, "build", -> (raw) { BuildConfig.deserialize(raw) }, BuildConfig.new),
          Field.defaulted(:bundle, "bundle", -> (raw) { BundleConfig.deserialize(raw) }, BundleConfig.new),
          Field.defaulted(:plugins, "plugins", -> (raw) { Utils::Config.map(raw) { |plugin| plugin } }, {}),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # What <tt>version</tt> takes, in serde's <tt>invalid type</tt>
        # error (config.rs:3143-3148).
        VERSION_EXPECTING = "a semver string or a path to a package.json file" # :nodoc:

        # The words of PackageVersion's custom errors (config.rs:3155-3183),
        # with the config's file named as Tokra names it (ADR 014 §3).
        NOT_SEMVER = "`tokra.conf.json > version` must be a semver string" # :nodoc:
        NOT_AN_OBJECT = "`tokra.conf.json > version` value is not a path to a JSON object" # :nodoc:
        NO_VERSION_FIELD = "JSON must contain a `version` field" # :nodoc:

        # A version semver 1.0.24's Version::from_str accepts
        # (semver src/parse.rs:16-73, 167-278): three numbers without
        # leading zeros, then an optional prerelease whose numeric
        # identifiers have none either, then optional build metadata.
        SEMVER = /
          \A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)
          (?:-(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?
          (?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z
        /x # :nodoc:

        U64_MAX = (2 ** 64) - 1 # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct, with
        # <tt>version</tt> read against +config_parent+, the config's
        # directory. The result is deep-frozen and Ractor-shareable.
        # Raises Ipc::CommandItem::Mismatch with serde's words.
        def self.deserialize(value, config_parent) # :nodoc:
          version = -> (raw) { package_version(raw, config_parent) }
          fields = FIELDS.map { |field| (field.key == "version") ? field.with(reader: version) : field }
          Ractor.make_shareable(new(**Utils::Config.read_struct(value, "Config", fields))) # steep:ignore InsufficientKeywordArguments
        end

        # PackageVersion's visitor (config.rs:3137-3189): a string that
        # names an existing file is read as JSON for its +version+; any
        # other string is the version itself. Either is checked as semver.
        def self.package_version(value, config_parent) # :nodoc:
          raise Ipc::CommandItem::Mismatch.invalid_type(value, VERSION_EXPECTING) unless value.is_a?(String)

          # Rust's Path::new("").exists() is false; Ruby's absolute path of
          # "" is the directory itself.
          path = File.absolute_path(value, config_parent) unless value.empty?
          return semver(value) unless path && File.exist?(path)

          package_json = version_json(path)
          raise Ipc::CommandItem::Mismatch, NOT_AN_OBJECT unless package_json.is_a?(Hash)
          raise Ipc::CommandItem::Mismatch, NO_VERSION_FIELD unless package_json.key?("version")

          version = package_json["version"]
          raise Ipc::CommandItem::Mismatch, "`#{value} > version` must be a string" unless version.is_a?(String)

          semver(version)
        end
        private_class_method :package_version

        # The JSON at +path+, or PackageVersion's error for a file that
        # cannot be read or parsed.
        def self.version_json(path) # :nodoc:
          Ipc::Json.parse(Parse.read_to_string(path))
        rescue Parse::ConfigError::Io => e
          raise Ipc::CommandItem::Mismatch, "failed to read version JSON file: #{e.error}"
        rescue Ipc::Json::Error => e
          raise Ipc::CommandItem::Mismatch, "failed to read version JSON file: #{e.message}"
        end
        private_class_method :version_json

        # +version+ as Tauri keeps it, the parsed version written back,
        # which is the same text; or NOT_SEMVER.
        def self.semver(version) # :nodoc:
          match = SEMVER.match(version)
          raise Ipc::CommandItem::Mismatch, NOT_SEMVER unless match && match.captures.first(3).all? { |part| part.to_i <= U64_MAX }

          version
        end
        private_class_method :semver

        # Takes the members as keywords: +identifier+, which Tauri
        # requires, and any of the rest, each one left out taking serde's
        # default (Rust's derived Default also fills +identifier+, with
        # an empty string).
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
