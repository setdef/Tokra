# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WixLanguageConfig, WixLanguage, WixConfig, NsisCompression,
#   NSISInstallerMode, NsisConfig, WebviewInstallMode, CustomSignCommandConfig, and
#   WindowsConfig adapted from tauri-utils src/config.rs:699-1074 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The settings of one WiX installer language.
      #
      # Mirrors Tauri's <tt>WixLanguageConfig</tt> (config.rs:699-709).
      class WixLanguageConfig < Data.define(:locale_path)
        FIELDS = [
          Field.option(:locale_path, "localePath", -> (raw) { Ipc::Serde.string(raw) }, aliases: %w[locale-path]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "WixLanguageConfig", FIELDS))
        end

        # Takes the path to a <tt>.wxl</tt> locale file, or leaves it
        # +nil+.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end

      # The languages the MSI installer is built in.
      #
      # Mirrors Tauri's untagged <tt>WixLanguage</tt> (config.rs:711-728).
      #
      # === Examples
      #
      #   # no "language"
      #   wix.language.language  #=> "en-US"
      #
      #   # "language": { "fr-FR": { "localePath": "fr.wxl" } }
      #   wix.language.languages["fr-FR"].locale_path  #=> "fr.wxl"
      module WixLanguage
        # One language.
        class One < Data.define(:language)
        end

        # Several languages.
        class List < Data.define(:languages)
        end

        # Each language with its own settings, a WixLanguageConfig.
        class Localized < Data.define(:languages)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "WixLanguage", [
            -> (raw) { One.new(language: Ipc::Serde.string(raw)) },
            -> (raw) { List.new(languages: Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) }) },
            -> (raw) { Localized.new(languages: Utils::Config.map(raw) { |item| WixLanguageConfig.deserialize(item) }) },
          ])
        end
      end

      # How the bundler builds the MSI installer with WiX.
      #
      # Tokra has no bundler yet (TODO 002), so it reads these settings
      # and builds nothing.
      #
      # +upgrade_code+ is the GUID Tauri reads with the uuid crate, as a
      # String in uuid's own form: hyphenated and lowercase, whichever of
      # its four forms the config wrote.
      #
      # Mirrors Tauri's <tt>WixConfig</tt> (config.rs:730-798).
      class WixConfig < Data.define(
        :version, :upgrade_code, :language, :template, :fragment_paths, :component_group_refs, :component_refs,
        :feature_group_refs, :feature_refs, :merge_refs, :enable_elevated_update_task, :banner_path,
        :dialog_image_path, :fips_compliant
      )
        STRINGS = -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } } # :nodoc:
        PATH = -> (raw) { Utils::Config.path(raw) } # :nodoc:
        BOOL = -> (raw) { Ipc::Serde.boolean(raw) } # :nodoc:
        private_constant :STRINGS, :PATH, :BOOL

        FIELDS = [
          Field.option(:version, "version", -> (raw) { Ipc::Serde.string(raw) }),
          Field.option(:upgrade_code, "upgradeCode", -> (raw) { Utils::Config.uuid(raw) }, aliases: %w[upgrade-code]),
          Field.defaulted(:language, "language", -> (raw) { WixLanguage.deserialize(raw) }, WixLanguage::One.new(language: "en-US")),
          Field.option(:template, "template", PATH),
          Field.defaulted(:fragment_paths, "fragmentPaths", -> (raw) { Utils::Config.sequence(raw) { |item| Utils::Config.path(item) } },
            [], aliases: %w[fragment-paths]),
          Field.defaulted(:component_group_refs, "componentGroupRefs", STRINGS, [], aliases: %w[component-group-refs]),
          Field.defaulted(:component_refs, "componentRefs", STRINGS, [], aliases: %w[component-refs]),
          Field.defaulted(:feature_group_refs, "featureGroupRefs", STRINGS, [], aliases: %w[feature-group-refs]),
          Field.defaulted(:feature_refs, "featureRefs", STRINGS, [], aliases: %w[feature-refs]),
          Field.defaulted(:merge_refs, "mergeRefs", STRINGS, [], aliases: %w[merge-refs]),
          Field.defaulted(:enable_elevated_update_task, "enableElevatedUpdateTask", BOOL, false,
            aliases: %w[enable-elevated-update-task]),
          Field.option(:banner_path, "bannerPath", PATH, aliases: %w[banner-path]),
          Field.option(:dialog_image_path, "dialogImagePath", PATH, aliases: %w[dialog-image-path]),
          Field.defaulted(:fips_compliant, "fipsCompliant", BOOL, false, aliases: %w[fips-compliant]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "WixConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end

      # How the NSIS installer compresses the app.
      #
      # These four are the only methods, so NsisCompression.new is private.
      #
      # Mirrors Tauri's <tt>NsisCompression</tt> (config.rs:800-816).
      class NsisCompression < Data.define(:name)
        extend ClosedEnum

        ##
        # Deflate: quick, with about 300 KB of memory.
        Zlib = new(name: "Zlib")
        # Better ratios than Zlib, a bit slower, with about 4 MB of memory.
        Bzip2 = new(name: "Bzip2")
        # The best ratios and fast decompression. The default.
        Lzma = new(name: "Lzma")
        # No compression.
        None = new(name: "None")

        # Reads +value+, a JSON value, as serde reads the enum: a unit
        # variant renamed camelCase.
        def self.deserialize(value) # :nodoc:
          variant = Ipc::Serde.unit_variant(value, %w[zlib bzip2 lzma none])
          const_get(variant.capitalize, false)
        end

        close
      end

      # Whom the NSIS installer installs the app for.
      #
      # These three are the only modes, so NSISInstallerMode.new is
      # private.
      #
      # Mirrors Tauri's <tt>NSISInstallerMode</tt> (config.rs:818-842).
      class NSISInstallerMode < Data.define(:name)
        extend ClosedEnum

        ##
        # The current user, in a directory that needs no Administrator
        # access, with its records under <tt>HKCU</tt>. The default.
        CurrentUser = new(name: "CurrentUser")
        # Every user, in <tt>Program Files</tt>, which needs Administrator
        # access, with its records under <tt>HKLM</tt>.
        PerMachine = new(name: "PerMachine")
        # Either, chosen when the app is installed; needs Administrator
        # access either way.
        Both = new(name: "Both")

        # Reads +value+, a JSON value, as serde reads the enum: a unit
        # variant renamed camelCase.
        def self.deserialize(value) # :nodoc:
          variant = Ipc::Serde.unit_variant(value, %w[currentUser perMachine both])
          const_get(variant.sub(/\A./, &:upcase), false)
        end

        close
      end

      # How the bundler builds the NSIS installer.
      #
      # Tokra has no bundler yet (TODO 002), so it reads these settings
      # and builds nothing.
      #
      # Mirrors Tauri's <tt>NsisConfig</tt> (config.rs:843-934).
      class NsisConfig < Data.define(
        :template, :header_image, :sidebar_image, :installer_icon, :install_mode, :languages,
        :custom_language_files, :display_language_selector, :compression, :start_menu_folder, :installer_hooks,
        :minimum_webview2_version
      )
        PATH = -> (raw) { Utils::Config.path(raw) } # :nodoc:
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        private_constant :PATH, :STRING

        FIELDS = [
          Field.option(:template, "template", PATH),
          Field.option(:header_image, "headerImage", PATH, aliases: %w[header-image]),
          Field.option(:sidebar_image, "sidebarImage", PATH, aliases: %w[sidebar-image]),
          Field.option(:installer_icon, "installerIcon", PATH, aliases: %w[install-icon]),
          Field.defaulted(:install_mode, "installMode", -> (raw) { NSISInstallerMode.deserialize(raw) },
            NSISInstallerMode::CurrentUser, aliases: %w[install-mode]),
          Field.option(:languages, "languages", -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } }),
          Field.option(:custom_language_files, "customLanguageFiles",
            -> (raw) { Utils::Config.map(raw) { |item| Utils::Config.path(item) } }),
          Field.defaulted(:display_language_selector, "displayLanguageSelector", -> (raw) { Ipc::Serde.boolean(raw) }, false,
            aliases: %w[display-language-selector]),
          Field.defaulted(:compression, "compression", -> (raw) { NsisCompression.deserialize(raw) }, NsisCompression::Lzma),
          Field.option(:start_menu_folder, "startMenuFolder", STRING, aliases: %w[start-menu-folder]),
          Field.option(:installer_hooks, "installerHooks", PATH, aliases: %w[installer-hooks]),
          Field.option(:minimum_webview2_version, "minimumWebview2Version", STRING, aliases: %w[minimum-webview2-version]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "NsisConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end

      # How the installer gets the WebView2 runtime the app needs.
      #
      # On Windows a Tauri app renders with WebView2, which the installer
      # can leave alone, download, or carry inside it. +FixedRuntime+ also
      # tells the running app to load a fixed WebView2 beside its
      # executable (app.rs:2167-2185). Tokra has no bundler yet, and an app
      # run from source has Ruby's executable, so it reads the mode and
      # acts on none of them (plan 054's inventory).
      #
      # Mirrors Tauri's internally tagged <tt>WebviewInstallMode</tt>
      # (config.rs:936-985).
      #
      # === Example
      #
      #   # "webviewInstallMode": { "type": "embedBootstrapper" }
      #   windows.webview_install_mode.silent  #=> true
      module WebviewInstallMode
        # Leave WebView2 out of the installer.
        class Skip < Data.define
        end

        # Download the bootstrapper and run it, silently unless +silent+ is
        # +false+. The default.
        class DownloadBootstrapper < Data.define(:silent)
        end

        # Carry the bootstrapper, about 1.8 MB, and run it.
        class EmbedBootstrapper < Data.define(:silent)
        end

        # Carry the whole offline installer, about 127 MB, and run it.
        class OfflineInstaller < Data.define(:silent)
        end

        # Carry a fixed WebView2, extracted to +path+, and use it at run
        # time.
        class FixedRuntime < Data.define(:path)
        end

        SILENT = [Field.defaulted(:silent, "silent", -> (raw) { Ipc::Serde.boolean(raw) }, true)].freeze # :nodoc:
        PATH = [Field.required(:path, "path", -> (raw) { Utils::Config.path(raw) })].freeze # :nodoc:
        VARIANTS = %w[skip downloadBootstrapper embedBootstrapper offlineInstaller fixedRuntime].freeze # :nodoc:
        private_constant :SILENT, :PATH, :VARIANTS

        # Reads +value+, a JSON value, as serde reads the enum: tagged by
        # its <tt>type</tt> key, each variant renamed camelCase.
        def self.deserialize(value) # :nodoc:
          variant, rest = Ipc::Serde.internally_tagged(value, "type", "WebviewInstallMode", VARIANTS)
          case variant
          when "skip"
            Utils::Config.read_unit_variant(rest)
            Skip.new
          when "fixedRuntime"
            path = Utils::Config.read_variant(rest, "WebviewInstallMode::FixedRuntime", PATH)[:path] #: Pathname
            FixedRuntime.new(path:)
          else
            name = variant.sub(/\A./, &:upcase)
            const_get(name, false).new(**Utils::Config.read_variant(rest, "WebviewInstallMode::#{name}", SILENT))
          end
        end
      end

      # The command that signs the app's binaries, in place of
      # <tt>signtool.exe</tt>.
      #
      # Mirrors Tauri's untagged <tt>CustomSignCommandConfig</tt>
      # (config.rs:987-1013).
      #
      # === Examples
      #
      #   # "signCommand": "osslsigncode sign %1"
      #   windows.sign_command.command  #=> "osslsigncode sign %1"
      #
      #   # "signCommand": { "cmd": "osslsigncode", "args": ["sign", "%1"] }
      #   windows.sign_command.args  #=> ["sign", "%1"]
      module CustomSignCommandConfig
        # The command and its arguments in one string, split at spaces;
        # <tt>%1</tt> stands for the binary.
        class Command < Data.define(:command)
        end

        # The command and its arguments apart, so either may hold spaces;
        # <tt>%1</tt> in +args+ stands for the binary.
        class CommandWithOptions < Data.define(:cmd, :args)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "CustomSignCommandConfig", [
            -> (raw) { Command.new(command: Ipc::Serde.string(raw)) },
            lambda do |raw|
              fields = Ipc::Serde.untagged_struct_variant(raw, "CustomSignCommandConfig::CommandWithOptions", %w[cmd args],
                deny_unknown: true) do |field, item|
                (field == "args") ? Utils::Config.sequence(item) { |arg| Ipc::Serde.string(arg) } : Ipc::Serde.string(item)
              end
              cmd = fields["cmd"] #: String
              args = fields["args"] #: Array[String]
              CommandWithOptions.new(cmd:, args:)
            end,
          ])
        end
      end

      # How the bundler packages and signs the app for Windows.
      #
      # Tokra has no bundler yet (TODO 002), so it reads these settings
      # and acts on none.
      #
      # Mirrors Tauri's <tt>WindowsConfig</tt> (config.rs:1015-1074).
      #
      # === Example
      #
      #   bundle.windows.allow_downgrades  #=> true
      class WindowsConfig < Data.define(
        :digest_algorithm, :certificate_thumbprint, :timestamp_url, :tsp, :webview_install_mode, :allow_downgrades,
        :wix, :nsis, :sign_command
      )
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        private_constant :STRING

        FIELDS = [
          Field.option(:digest_algorithm, "digestAlgorithm", STRING, aliases: %w[digest-algorithm]),
          Field.option(:certificate_thumbprint, "certificateThumbprint", STRING, aliases: %w[certificate-thumbprint]),
          Field.option(:timestamp_url, "timestampUrl", STRING, aliases: %w[timestamp-url]),
          Field.defaulted(:tsp, "tsp", -> (raw) { Ipc::Serde.boolean(raw) }, false),
          Field.defaulted(:webview_install_mode, "webviewInstallMode", -> (raw) { WebviewInstallMode.deserialize(raw) },
            WebviewInstallMode::DownloadBootstrapper.new(silent: true), aliases: %w[webview-install-mode]),
          Field.defaulted(:allow_downgrades, "allowDowngrades", -> (raw) { Ipc::Serde.boolean(raw) }, true,
            aliases: %w[allow-downgrades]),
          Field.option(:wix, "wix", -> (raw) { WixConfig.deserialize(raw) }),
          Field.option(:nsis, "nsis", -> (raw) { NsisConfig.deserialize(raw) }),
          Field.option(:sign_command, "signCommand", -> (raw) { CustomSignCommandConfig.deserialize(raw) },
            aliases: %w[sign-command]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "WindowsConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out takes
        # Tauri's default.
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
