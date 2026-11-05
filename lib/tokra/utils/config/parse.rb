# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Utils
    module Config
      #--
      # SPDX-SnippetBegin
      # SPDX-License-Identifier: Apache-2.0 OR MIT
      # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
      # SPDX-SnippetComment: adapted from tauri-utils src/config/parse.rs at
      #   vendor/tauri 9f0306fbc, with the config-json5 feature and without
      #   config-toml, with the brand renamed (ADR 014 §3)
      #++

      # Reads config files from disk into JSON values.
      #
      # An app's config is a main file with an optional file per platform
      # beside it: <tt>tokra.conf.json</tt>, and <tt>tokra.macos.conf.json</tt>
      # read over it on macOS, each of which may be written as JSON5
      # instead, <tt>tokra.conf.json5</tt>. Reading them takes several
      # steps: finding the file, reading it as UTF-8, parsing it, and
      # merging the platform's file over it. Each step fails in its own
      # words.
      #
      # This module takes those steps as Tauri's <tt>config::parse</tt>
      # takes them, with its errors, ConfigError. Tokra.generate_context
      # calls it; call it yourself to read a config without building a
      # context.
      #
      # Tokra reads JSON and JSON5, as Tauri does with its
      # <tt>config-json5</tt> feature, which ADR 014 §7 builds in. A
      # <tt>tokra.conf.json</tt> is read as JSON5 first, so one with
      # comments or trailing commas reads too, and serde_json's error is
      # the one reported when neither reads it (parse.rs:288-300). TOML
      # waits on plan 054's question 2: a lone <tt>Tokra.toml</tt> raises
      # ConfigError::DisabledFormat, as Tauri without its
      # <tt>config-toml</tt> feature does.
      #
      # Mirrors Tauri's <tt>tauri_utils::config::parse</tt>
      # (tauri-utils src/config/parse.rs).
      #
      # === Examples
      #
      #   target = Tokra::Utils::Platform::Target.current
      #   value, paths = Tokra::Utils::Config::Parse.read_from(target, __dir__)
      #   value["identifier"]  #=> "com.example.app"
      #   paths                #=> ["/app/tokra.conf.json", "/app/tokra.macos.conf.json"]
      #
      #   Tokra::Utils::Config::Parse.does_supported_file_name_exist(target, "/app/tokra.conf.json")  #=> true
      module Parse
        # Every extension a config file may have, enabled or not.
        EXTENSIONS_SUPPORTED = %w[json json5 toml].freeze

        # A config file's format.
        #
        # Each format has its own file names: <tt>tokra.conf.json</tt>,
        # <tt>tokra.conf.json5</tt>, and <tt>Tokra.toml</tt>, and each
        # platform's beside them. These three are the formats, so
        # ConfigFormat.new is private.
        #
        # Mirrors Tauri's <tt>ConfigFormat</tt> (parse.rs:30-76).
        #
        # === Example
        #
        #   Tokra::Utils::Config::Parse::ConfigFormat::Json.into_file_name  #=> "tokra.conf.json"
        class ConfigFormat < Data.define(:name)
          extend ClosedEnum

          ##
          # <tt>tokra.conf.json</tt>.
          Json = new(name: "Json")
          # <tt>tokra.conf.json5</tt>.
          Json5 = new(name: "Json5")
          # <tt>Tokra.toml</tt>.
          Toml = new(name: "Toml")

          # Each platform's word in its file name (parse.rs:51-75).
          PLATFORMS = { "MacOS" => "macos", "Windows" => "windows", "Linux" => "linux" }.freeze # :nodoc:

          # The format's file name.
          #
          # === Example
          #
          #   Tokra::Utils::Config::Parse::ConfigFormat::Toml.into_file_name  #=> "Tokra.toml"
          def into_file_name
            case name
            when "Json" then "tokra.conf.json"
            when "Json5" then "tokra.conf.json5"
            else "Tokra.toml"
            end
          end

          # The format's file name for +target+, a Platform::Target.
          def into_platform_file_name(target) # :nodoc:
            platform = PLATFORMS.fetch(target.name)
            case name
            when "Json" then "tokra.#{platform}.conf.json"
            when "Json5" then "tokra.#{platform}.conf.json5"
            else "Tokra.#{platform}.toml"
            end
          end

          close
        end

        # Every format a config file may have, enabled or not.
        SUPPORTED_FORMATS = [ConfigFormat::Json, ConfigFormat::Json5, ConfigFormat::Toml].freeze

        # The formats Tokra reads: JSON, and JSON5 (ADR 014 §7). TOML
        # waits on plan 054's question 2.
        ENABLED_FORMATS = [ConfigFormat::Json, ConfigFormat::Json5].freeze

        # Raised when a config file cannot be read.
        #
        # Reading a config fails in one of five ways, and each names the
        # file and the reason in Tauri's words. Rescue ConfigError for any
        # of them, or a subclass for one.
        #
        # Mirrors Tauri's <tt>ConfigError</tt> (parse.rs:78-137), with
        # "Tauri config file" renamed "Tokra config file" (plan 054,
        # decision 7).
        #
        # === Example
        #
        #   begin
        #     Tokra.generate_context
        #   rescue Tokra::Utils::Config::Parse::ConfigError => e
        #     warn e.message  # unable to read Tokra config file at /app/tokra.conf.json because entity not found
        #   end
        class ConfigError < Tokra::Error
          # The file is valid neither as JSON5 nor as JSON.
          #
          # A <tt>tokra.conf.json</tt> is read as JSON5 first, and only when
          # that fails as JSON, so this error carries serde_json's words
          # and position, not json5's.
          #
          # === Example
          #
          #   e.message  #=> "unable to parse JSON Tokra config file at /app/tokra.conf.json because expected value at line 4 column 1"
          class FormatJson < ConfigError
            # The file's path.
            attr_reader :path

            # The parse error, a Tokra::Ipc::Json::Error with serde_json's
            # words and position.
            attr_reader :error

            # [path] the file's path.
            # [error] the Tokra::Ipc::Json::Error.
            def initialize(path, error)
              @path = path
              @error = error
              super("unable to parse JSON Tokra config file at #{Parse.display(path)} because #{error.message}")
            end
          end

          # The file is not valid JSON5.
          #
          # A <tt>tokra.conf.json5</tt> that json5 rejects raises this,
          # with json5's words: pest's report of a syntax error, which
          # spans lines, or the deserializer's reason, such as
          # <tt>error parsing hex</tt>. A <tt>tokra.conf.json</tt> that
          # json5 rejects raises FormatJson instead, with serde_json's.
          #
          # === Example
          #
          #   e.message
          #   #=> "unable to parse JSON5 Tokra config file at /app/tokra.conf.json5 because error parsing hex"
          class FormatJson5 < ConfigError
            # The file's path.
            attr_reader :path

            # The parse error, a Tokra::Json5::Error.
            attr_reader :error

            # [path] the file's path.
            # [error] the Tokra::Json5::Error.
            def initialize(path, error)
              @path = path
              @error = error
              super("unable to parse JSON5 Tokra config file at #{Parse.display(path)} because #{error.message}")
            end
          end

          # The file's extension is not one a config file has.
          #
          # === Example
          #
          #   e.message  #=> "unsupported format encountered yaml"
          class UnsupportedFormat < ConfigError
            # The extension, without its dot.
            attr_reader :extension

            # [extension] the extension, without its dot.
            def initialize(extension)
              @extension = extension
              super("unsupported format encountered #{extension}")
            end
          end

          # The file is in a format Tokra does not read yet: TOML, until
          # plan 054's question 2 is answered.
          #
          # The message names Tauri's Cargo feature for the format, as
          # Tauri's does.
          #
          # === Example
          #
          #   e.message  #=> "supported (but disabled) format encountered .toml - try enabling `config-toml` "
          class DisabledFormat < ConfigError
            # The extension, with its dot.
            attr_reader :extension

            # The Cargo feature Tauri reads the format with.
            attr_reader :feature

            # [extension] the extension, with its dot.
            # [feature] the Cargo feature's name.
            def initialize(extension, feature)
              @extension = extension
              @feature = feature
              super("supported (but disabled) format encountered #{extension} - try enabling `#{feature}` ")
            end
          end

          # The file could not be read.
          #
          # +error+ reads as Rust's <tt>io::Error</tt> displays one: an
          # operating system error as its description and number, such as
          # <tt>Is a directory (os error 21)</tt>; a missing config as
          # <tt>entity not found</tt>; a file that is not UTF-8 as
          # <tt>stream did not contain valid UTF-8</tt>.
          #
          # *Deviation*: on Windows Rust prints the system's own message,
          # such as "The system cannot find the file specified.", where
          # Ruby gives errno's words.
          #
          # === Example
          #
          #   e.message  #=> "unable to read Tokra config file at /app/tokra.conf.json because entity not found"
          class Io < ConfigError
            # The file's path.
            attr_reader :path

            # The reason, as Rust displays it.
            attr_reader :error

            # [path] the file's path.
            # [error] the reason, a String.
            def initialize(path, error)
              @path = path
              @error = error
              super("unable to read Tokra config file at #{Parse.display(path)} because #{error}")
            end
          end
        end

        # Rust's display of <tt>ErrorKind::NotFound</tt>, the error do_parse
        # raises when no file exists (parse.rs:327-333).
        NOT_FOUND = "entity not found" # :nodoc:

        # Rust's <tt>io::Error::INVALID_UTF8</tt>, which read_to_string
        # raises for a file that is not UTF-8.
        INVALID_UTF8 = "stream did not contain valid UTF-8" # :nodoc:

        # Reads the config in the directory +root_dir+ for +target+, a
        # Platform::Target: <tt>tokra.conf.json</tt> or
        # <tt>tokra.conf.json5</tt>, one of which has to exist, with the
        # platform's file merged over it when there is one, as
        # JSON Merge Patch merges (RFC 7396): an object key by key, +null+
        # deleting a key, and anything else, an array too, replacing.
        # Answers the merged value and the paths read. Raises ConfigError.
        #
        # Every object in the value has its keys in byte order, as
        # serde_json's map keeps them, so a key the platform's file adds
        # reads where Tauri reads it.
        #
        # Mirrors Tauri's <tt>read_from</tt> (parse.rs:166-188).
        #
        # === Example
        #
        #   value, paths = Tokra::Utils::Config::Parse.read_from(Tokra::Utils::Platform::Target::MacOS, "/app")
        def self.read_from(target, root_dir)
          config, config_file_path = parse_value(target, File.join(root_dir, ConfigFormat::Json.into_file_name))
          config_paths = [config_file_path]
          platform = read_platform(target, root_dir)
          if platform
            platform_config, path = platform
            config_paths << path
            config = merge(config, platform_config)
          end
          [config, config_paths]
        end

        # Reads the file for +target+ in +root_dir+, such as
        # <tt>tokra.macos.conf.json</tt> or <tt>tokra.macos.conf.json5</tt>,
        # when one of an enabled format exists, answering its value and
        # path; +nil+ when none does.
        # Raises ConfigError.
        #
        # Mirrors Tauri's <tt>read_platform</tt> (parse.rs:190-204).
        #
        # === Example
        #
        #   Tokra::Utils::Config::Parse.read_platform(Tokra::Utils::Platform::Target::Linux, "/app")  #=> nil
        def self.read_platform(target, root_dir)
          platform_config_path = File.join(root_dir, ConfigFormat::Json.into_platform_file_name(target))
          return nil unless does_supported_file_name_exist(target, platform_config_path)

          parse_value(target, platform_config_path)
        end

        # Whether a config file of an enabled format exists beside +path+:
        # under the platform's names when +path+ names the platform's file
        # for +target+, and under the main names otherwise.
        #
        # Mirrors Tauri's <tt>does_supported_file_name_exist</tt>
        # (parse.rs:206-225).
        #
        # === Example
        #
        #   Tokra::Utils::Config::Parse.does_supported_file_name_exist(Tokra::Utils::Platform::Target::MacOS,
        #     "/app/tokra.macos.conf.json")  #=> false
        def self.does_supported_file_name_exist(target, path)
          path = path.to_s
          source_file_name = File.basename(path)
          lookup_platform_config = ENABLED_FORMATS.any? do |format|
            source_file_name == format.into_platform_file_name(target)
          end
          ENABLED_FORMATS.any? do |format|
            name = lookup_platform_config ? format.into_platform_file_name(target) : format.into_file_name
            File.exist?(File.join(File.dirname(path), name))
          end
        end

        # Reads the config file at +path+ into its JSON value, answering
        # the value and the path read. A file there is read as JSON5 first
        # and as JSON when that fails, with serde_json's error when both
        # do. When no file is there, a <tt>.json5</tt> beside it under the
        # same kind of name stands in, and then a <tt>.toml</tt>, which
        # raises ConfigError::DisabledFormat, since TOML is not enabled.
        # Raises ConfigError.
        #
        # Mirrors Tauri's <tt>parse_value</tt> and <tt>do_parse</tt>
        # (parse.rs:227-335).
        #
        # === Example
        #
        #   value, path = Tokra::Utils::Config::Parse.parse_value(Tokra::Utils::Platform::Target::MacOS,
        #     "/app/tokra.conf.json")
        def self.parse_value(target, path)
          path = path.to_s
          file_name = File.basename(path)
          lookup_platform_config = ENABLED_FORMATS.any? { |format| file_name == format.into_platform_file_name(target) }
          json5 = sibling(path, ConfigFormat::Json5, target, lookup_platform_config)
          toml = sibling(path, ConfigFormat::Toml, target, lookup_platform_config)
          path_ext = File.extname(file_name).delete_prefix(".")

          if File.exist?(path)
            raw = read_to_string(path)
            # Valid JSON5 reads, whatever the extension; a .json that is
            # not keeps serde_json's error (parse.rs:288-300).
            json = begin
              Tokra::Json5.from_str(raw)
            rescue Tokra::Json5::Error
              do_parse_json(raw, path)
            end
            [json, path]
          elsif File.exist?(json5)
            [do_parse_json5(read_to_string(json5), json5), json5]
          elsif File.exist?(toml)
            raise ConfigError::DisabledFormat.new(".toml", "config-toml")
          elsif !EXTENSIONS_SUPPORTED.include?(path_ext)
            raise ConfigError::UnsupportedFormat, path_ext
          else
            raise ConfigError::Io.new(path, NOT_FOUND)
          end
        end

        # +path+'s sibling in +format+: its platform name or its main name.
        def self.sibling(path, format, target, platform) # :nodoc:
          File.join(File.dirname(path), platform ? format.into_platform_file_name(target) : format.into_file_name)
        end
        private_class_method :sibling

        # +raw+, a config file's text, as JSON, or ConfigError::FormatJson
        # with serde_json's words and position (parse.rs:351-356).
        def self.do_parse_json(raw, path) # :nodoc:
          Ipc::Json.parse(raw)
        rescue Ipc::Json::Error => e
          raise ConfigError::FormatJson.new(path, e)
        end
        private_class_method :do_parse_json

        # +raw+, a config file's text, as JSON5, or ConfigError::FormatJson5
        # with json5's words (parse.rs:376-382).
        def self.do_parse_json5(raw, path) # :nodoc:
          Tokra::Json5.from_str(raw)
        rescue Tokra::Json5::Error => e
          raise ConfigError::FormatJson5.new(path, e)
        end
        private_class_method :do_parse_json5

        # The file at +path+ as a UTF-8 String, as Rust's
        # <tt>fs::read_to_string</tt> reads it, or ConfigError::Io
        # (parse.rs:390-398).
        def self.read_to_string(path) # :nodoc:
          text = File.binread(path).force_encoding(Encoding::UTF_8)
          raise ConfigError::Io.new(path, INVALID_UTF8) unless text.valid_encoding?

          text
        rescue SystemCallError => e
          raise ConfigError::Io.new(path, io_error(e))
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

        # +path+ as Rust displays a path, with the platform's separator,
        # so a message reads <tt>C:\app\tokra.conf.json</tt> on Windows.
        # Every separator turns: where Rust joins a relative argument, such
        # as <tt>src/tokra.conf.json</tt>, to a directory, it keeps the
        # argument's own <tt>/</tt> and prints mixed separators
        # (<tt>C:\app\src/tokra.conf.json</tt>).
        def self.display(path) # :nodoc:
          separator = File::ALT_SEPARATOR
          separator ? path.to_s.tr("/", separator) : path.to_s
        end

        #--
        # SPDX-SnippetEnd
        # SPDX-SnippetBegin
        # SPDX-License-Identifier: MIT OR Apache-2.0
        # SPDX-SnippetCopyrightText: Ivan Dubrov (json-patch)
        # SPDX-SnippetComment: merge adapted from json-patch 3.0.1 src/lib.rs:661-678
        #++

        # +patch+ merged over +doc+, JSON values both, as JSON Merge Patch
        # merges (RFC 7396). Answers a new value. Each object it builds has
        # its keys in byte order, as serde_json's BTreeMap keeps them, so
        # serde reads them in Tauri's order (plan 054, decision 4).
        def self.merge(doc, patch) # :nodoc:
          return patch unless patch.is_a?(Hash)

          map = doc.is_a?(Hash) ? doc.dup : {} #: Hash[String, json_value]
          patch.each do |key, value|
            if value.nil?
              map.delete(key)
            else
              map[key] = merge(map[key], value)
            end
          end
          map.sort.to_h
        end

        #--
        # SPDX-SnippetEnd
        #++
      end
    end
  end
end
