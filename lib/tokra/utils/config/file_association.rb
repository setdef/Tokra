# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: BundleTypeRole, HandlerRank, AssociationExt, FileAssociation,
#   and ExportedFileAssociation adapted from tauri-utils src/config.rs:1076-1203
#   at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # What your app does with a file type it opens, on macOS.
      #
      # A bundle's Info.plist tells macOS whether the app edits files of a
      # type, only views them, or neither. It is
      # <tt>CFBundleTypeRole</tt>, and the config writes it by its Rust
      # name.
      #
      # These five are the only roles, so BundleTypeRole.new is private.
      #
      # Mirrors Tauri's <tt>BundleTypeRole</tt> (config.rs:1076-1104).
      #
      # === Example
      #
      #   # "role": "Viewer"
      #   association.role  #=> Tokra::Utils::Config::BundleTypeRole::Viewer
      class BundleTypeRole < Data.define(:name)
        extend ClosedEnum

        ##
        # Files can be read and edited. The default.
        Editor = new(name: "Editor")
        # Files can be read.
        Viewer = new(name: "Viewer")
        # <tt>CFBundleTypeRole.Shell</tt>.
        Shell = new(name: "Shell")
        # <tt>CFBundleTypeRole.QLGenerator</tt>, a Quick Look generator.
        QLGenerator = new(name: "QLGenerator")
        # <tt>CFBundleTypeRole.None</tt>.
        None = new(name: "None")

        # Reads +value+, a JSON value, as serde reads the enum: a unit
        # variant by its Rust name.
        def self.deserialize(value) # :nodoc:
          const_get(Ipc::Serde.unit_variant(value, %w[Editor Viewer Shell QLGenerator None]), false)
        end

        # Its name, as Tauri's Display writes it (config.rs:1094-1104).
        def to_s
          name
        end

        close
      end

      # Where your app ranks among the apps that open a file type, on macOS.
      #
      # It is <tt>LSHandlerRank</tt>, written by its Rust name.
      #
      # These four are the only ranks, so HandlerRank.new is private.
      #
      # Mirrors Tauri's <tt>HandlerRank</tt> (config.rs:1106-1133).
      class HandlerRank < Data.define(:name)
        extend ClosedEnum

        ##
        # One app among those that open the type. The default.
        Default = new(name: "Default")
        # The app that creates files of the type.
        Owner = new(name: "Owner")
        # A secondary viewer of the type.
        Alternate = new(name: "Alternate")
        # Never chosen to open the type, though it takes dropped files.
        None = new(name: "None")

        # Reads +value+, a JSON value, as serde reads the enum: a unit
        # variant by its Rust name.
        def self.deserialize(value) # :nodoc:
          const_get(Ipc::Serde.unit_variant(value, %w[Default Owner Alternate None]), false)
        end

        # Its name, as Tauri's Display writes it (config.rs:1123-1133).
        def to_s
          name
        end

        close
      end

      # A file extension in a FileAssociation, without its leading dot.
      #
      # Tauri wraps the String in a newtype, which Ruby has no use for, so
      # an extension is a String and this module only reads one.
      #
      # Mirrors Tauri's <tt>AssociationExt</tt> (config.rs:1135-1156).
      module AssociationExt
        # Reads +value+, a JSON value, as Tauri's own Deserialize reads it:
        # a string, with one leading <tt>.</tt> removed.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.string(value).delete_prefix(".")
        end
      end

      # A custom file type your app defines, on macOS.
      #
      # An exported type gives macOS a type identifier and the types it
      # conforms to, a <tt>UTExportedTypeDeclarations</tt> entry.
      #
      # Mirrors Tauri's <tt>ExportedFileAssociation</tt>
      # (config.rs:1191-1203).
      class ExportedFileAssociation < Data.define(:identifier, :conforms_to)
        FIELDS = [
          Field.required(:identifier, "identifier", -> (raw) { Ipc::Serde.string(raw) }),
          Field.option(:conforms_to, "conformsTo", -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } },
            aliases: %w[conforms-to]),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "ExportedFileAssociation", FIELDS)) # steep:ignore InsufficientKeywordArguments
        end

        # Takes the identifier, and the types it conforms to or +nil+.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end

      # A file type your app opens.
      #
      # The bundler writes each association into the platform's own
      # records: Info.plist on macOS, the registry on Windows, a desktop
      # file's MIME types on Linux. Tokra has no bundler yet (TODO 002), so
      # it reads the associations and registers nothing.
      #
      # Mirrors Tauri's <tt>FileAssociation</tt> (config.rs:1158-1189).
      #
      # === Example
      #
      #   # "fileAssociations": [{ "ext": [".md"], "mimeType": "text/markdown" }]
      #   bundle.file_associations.first.ext  #=> ["md"]
      class FileAssociation < Data.define(
        :ext, :content_types, :name, :description, :role, :mime_type, :rank, :exported_type
      )
        STRING = -> (raw) { Ipc::Serde.string(raw) } # :nodoc:
        private_constant :STRING

        FIELDS = [
          Field.required(:ext, "ext", -> (raw) { Utils::Config.sequence(raw) { |item| AssociationExt.deserialize(item) } }),
          Field.option(:content_types, "contentTypes", -> (raw) { Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) } },
            aliases: %w[content-types]),
          Field.option(:name, "name", STRING),
          Field.option(:description, "description", STRING),
          Field.defaulted(:role, "role", -> (raw) { BundleTypeRole.deserialize(raw) }, BundleTypeRole::Editor),
          Field.option(:mime_type, "mimeType", STRING, aliases: %w[mime-type]),
          Field.defaulted(:rank, "rank", -> (raw) { HandlerRank.deserialize(raw) }, HandlerRank::Default),
          Field.option(:exported_type, "exportedType", -> (raw) { ExportedFileAssociation.deserialize(raw) }),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "FileAssociation", FIELDS)) # steep:ignore InsufficientKeywordArguments
        end

        # Takes the extensions, and any of the other members as keywords;
        # each one left out takes Tauri's default.
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
