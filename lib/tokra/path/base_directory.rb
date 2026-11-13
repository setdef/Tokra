# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: David Tolnay (serde_repr)
# SPDX-SnippetComment: BaseDirectory adapted from tauri/crates/tauri/src/path/mod.rs;
#                      its reading is serde_repr 0.1.19's derived Deserialize

module Tokra
  module Path
    # A directory a path is relative to.
    #
    # A file the app keeps belongs in a directory the platform names:
    # settings in the app's config directory, a database in its data
    # directory, a download in the user's Downloads. The page names one
    # by number when it calls <tt>@tauri-apps/api/path</tt>, and a string
    # path can start with one as a variable, such as
    # <tt>$APPDATA/db.sqlite</tt>.
    #
    # BaseDirectory names those directories. Pass one to
    # PathResolver#resolve with a relative path, and the resolver joins
    # the two. These 23 are Tauri's desktop variants, and the only ones,
    # so BaseDirectory.new is private.
    #
    # Each has +name+, the variant's name; +value+, the number the page
    # sends (Tauri's <tt>repr(u16)</tt>); and +variable+, the
    # <tt>$NAME</tt> PathResolver#parse reads.
    #
    # Mirrors Tauri's <tt>tauri::path::BaseDirectory</tt>
    # (path/mod.rs:86-247). For more about each directory, see the
    # PathResolver method it resolves to.
    #
    # === Examples
    #
    #   app.path.resolve("db.sqlite", Tokra::Path::BaseDirectory::AppData)
    #   Tokra::Path::BaseDirectory::AppData.variable          #=> "$APPDATA"
    #   Tokra::Path::BaseDirectory.from_variable("$HOME")     #=> Tokra::Path::BaseDirectory::Home
    class BaseDirectory < Data.define(:name, :value, :variable)
      extend ClosedEnum

      ##
      # The Audio directory. Resolves to PathResolver#audio_dir.
      Audio = new(name: "Audio", value: 1, variable: "$AUDIO")
      # The Cache directory. Resolves to PathResolver#cache_dir.
      Cache = new(name: "Cache", value: 2, variable: "$CACHE")
      # The Config directory. Resolves to PathResolver#config_dir.
      Config = new(name: "Config", value: 3, variable: "$CONFIG")
      # The Data directory. Resolves to PathResolver#data_dir.
      Data = new(name: "Data", value: 4, variable: "$DATA")
      # The LocalData directory. Resolves to PathResolver#local_data_dir.
      LocalData = new(name: "LocalData", value: 5, variable: "$LOCALDATA")
      # The Document directory. Resolves to PathResolver#document_dir.
      Document = new(name: "Document", value: 6, variable: "$DOCUMENT")
      # The Download directory. Resolves to PathResolver#download_dir.
      Download = new(name: "Download", value: 7, variable: "$DOWNLOAD")
      # The Picture directory. Resolves to PathResolver#picture_dir.
      Picture = new(name: "Picture", value: 8, variable: "$PICTURE")
      # The Public directory. Resolves to PathResolver#public_dir.
      Public = new(name: "Public", value: 9, variable: "$PUBLIC")
      # The Video directory. Resolves to PathResolver#video_dir.
      Video = new(name: "Video", value: 10, variable: "$VIDEO")
      # The Resource directory. Resolves to PathResolver#resource_dir.
      Resource = new(name: "Resource", value: 11, variable: "$RESOURCE")
      # A temporary directory. Resolves to PathResolver#temp_dir.
      Temp = new(name: "Temp", value: 12, variable: "$TEMP")
      # The default app config directory: Config, then the bundle
      # identifier.
      AppConfig = new(name: "AppConfig", value: 13, variable: "$APPCONFIG")
      # The default app data directory: Data, then the bundle identifier.
      AppData = new(name: "AppData", value: 14, variable: "$APPDATA")
      # The default app local data directory: LocalData, then the bundle
      # identifier.
      AppLocalData = new(name: "AppLocalData", value: 15, variable: "$APPLOCALDATA")
      # The default app cache directory: Cache, then the bundle identifier.
      AppCache = new(name: "AppCache", value: 16, variable: "$APPCACHE")
      # The default app log directory. Resolves to PathResolver#app_log_dir.
      AppLog = new(name: "AppLog", value: 17, variable: "$APPLOG")
      # The Desktop directory. Resolves to PathResolver#desktop_dir.
      Desktop = new(name: "Desktop", value: 18, variable: "$DESKTOP")
      # The Executable directory. Resolves to PathResolver#executable_dir.
      Executable = new(name: "Executable", value: 19, variable: "$EXE")
      # The Font directory. Resolves to PathResolver#font_dir.
      Font = new(name: "Font", value: 20, variable: "$FONT")
      # The Home directory. Resolves to PathResolver#home_dir.
      Home = new(name: "Home", value: 21, variable: "$HOME")
      # The Runtime directory. Resolves to PathResolver#runtime_dir.
      Runtime = new(name: "Runtime", value: 22, variable: "$RUNTIME")
      # The Template directory. Resolves to PathResolver#template_dir.
      Template = new(name: "Template", value: 23, variable: "$TEMPLATE")

      # :attr_reader: name
      # The variant's name, such as <tt>"AppData"</tt>.

      # :attr_reader: value
      # The number the page sends for this directory, such as +14+.

      # :attr_reader: variable
      # The variable that names this directory at the start of a string
      # path, such as <tt>"$APPDATA"</tt>. Mirrors BaseDirectory::variable
      # (mod.rs:173-207).

      # The directory +variable+ names, or +nil+ when it names none.
      # Mirrors BaseDirectory::from_variable (mod.rs:209-246).
      #
      # === Example
      #
      #   Tokra::Path::BaseDirectory.from_variable("$APPLOG")  #=> Tokra::Path::BaseDirectory::AppLog
      #   Tokra::Path::BaseDirectory.from_variable("$NOPE")    #=> nil
      def self.from_variable(variable)
        variants.find { |directory| directory.variable == variable }
      end

      # Every variant, in the order of their numbers.
      #
      # === Example
      #
      #   Tokra::Path::BaseDirectory.variants.first  #=> Tokra::Path::BaseDirectory::Audio
      def self.variants
        constants.map { |name| const_get(name) }.grep(self).sort_by(&:value)
      end

      # The directory a command argument names: serde reads a +u16+, and
      # serde_repr matches it to a variant (serde_repr 0.1.19 lib.rs,
      # derive_deserialize). Raises Ipc::CommandItem::Mismatch with
      # serde's words otherwise.
      def self.deserialize(value) # :nodoc:
        unless value.is_a?(Integer) && Ipc::Unexpected::JSON_INTEGERS.cover?(value)
          raise Ipc::CommandItem::Mismatch.invalid_type(value, "u16")
        end
        raise Ipc::CommandItem::Mismatch, "invalid value: integer `#{value}`, expected u16" unless U16.cover?(value)

        variants.find { |directory| directory.value == value } ||
          raise(Ipc::CommandItem::Mismatch,
            "invalid value: #{value}, expected one of: #{variants.map(&:value).join(', ')}")
      end

      # The range of a Rust u16.
      U16 = 0..65_535 # :nodoc:

      close
    end
  end
end

# SPDX-SnippetEnd
