# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AboutMetadata and its builder adapted from tauri/crates/tauri/src/menu/mod.rs

module Tokra
  module Menu
    # What the About item shows: the app's name, version, authors, and the
    # like.
    #
    # Each field is +nil+ unless set. On macOS the About panel shows what
    # it gets and fills in the rest from the app bundle; on Windows and
    # Linux the About dialog shows only what it gets. +icon+ is a
    # Tokra::Image.
    #
    # Mirrors Tauri's AboutMetadata (menu/mod.rs:169-224), and its
    # conversion to muda's (menu/mod.rs:330-353).
    #
    # === Example
    #
    #   metadata = Tokra::Menu::AboutMetadata.new(name: "Notes", version: "1.2.0")
    #   Tokra::Menu::PredefinedMenuItem.about(app, nil, metadata)
    class AboutMetadata < Data.define(:name, :version, :short_version, :authors, :comments, :copyright,
      :license, :website, :website_label, :credits, :icon)
      # Metadata with the given fields, the rest +nil+, as Tauri's
      # <tt>Default</tt> leaves them.
      def initialize(name: nil, version: nil, short_version: nil, authors: nil, comments: nil, copyright: nil,
        license: nil, website: nil, website_label: nil, credits: nil, icon: nil
      )
        super
      end

      # The Hash Native::PredefinedMenuItem.new takes, with the icon as
      # <tt>[rgba, width, height]</tt>.
      def to_native # :nodoc:
        to_h.merge(icon: icon && [icon.rgba, icon.width, icon.height])
      end
    end

    # Builds AboutMetadata one field at a time.
    #
    # Mirrors Tauri's AboutMetadataBuilder (menu/mod.rs:228-328). Each
    # method takes the value or +nil+, as Tauri's take an Option, and
    # returns the builder.
    #
    # === Example
    #
    #   Tokra::Menu::AboutMetadataBuilder.new.name("Notes").version("1.2.0").build
    class AboutMetadataBuilder
      # A builder with every field +nil+.
      def initialize
        @fields = {} #: Hash[Symbol, String | Array[String] | Image | nil]
      end

      # Sets the app's name.
      def name(name)
        set(:name, name)
      end

      # Sets the app's version.
      def version(version)
        set(:version, version)
      end

      # Sets the short version, such as "1.0". macOS shows it in its About
      # panel beside the version.
      def short_version(short_version)
        set(:short_version, short_version)
      end

      # Sets the authors, an Array of String. macOS does not show them.
      def authors(authors)
        set(:authors, authors)
      end

      # Sets a line about the app. macOS does not show it.
      def comments(comments)
        set(:comments, comments)
      end

      # Sets the copyright notice.
      def copyright(copyright)
        set(:copyright, copyright)
      end

      # Sets the license. macOS does not show it.
      def license(license)
        set(:license, license)
      end

      # Sets the app's website. macOS does not show it.
      def website(website)
        set(:website, website)
      end

      # Sets the text for the website link. macOS does not show it.
      def website_label(website_label)
        set(:website_label, website_label)
      end

      # Sets the credits. Only macOS shows them.
      def credits(credits)
        set(:credits, credits)
      end

      # Sets the icon, a Tokra::Image.
      def icon(icon)
        set(:icon, icon)
      end

      # The AboutMetadata with the fields set so far.
      def build
        AboutMetadata.new(**@fields)
      end

      private def set(field, value)
        @fields[field] = value
        self
      end
    end
  end
end

# SPDX-SnippetEnd
