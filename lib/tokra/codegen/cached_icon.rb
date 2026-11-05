# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: adapted from tauri-codegen src/image.rs:13-118 and
#   src/embedded_assets.rs:50-51 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Codegen
    # Raised when codegen cannot embed something the config names.
    #
    # Mirrors Tauri's <tt>EmbeddedAssetsError</tt> (tauri-codegen
    # src/embedded_assets.rs:24-64), as far as Tokra reads what it covers:
    # the icons so far, and the frontend's assets with the plan that ports
    # them.
    #
    # === Example
    #
    #   begin
    #     Tokra.generate_context
    #   rescue Tokra::Codegen::EmbeddedAssetsError::InvalidImageExtension => e
    #     warn e.message  # invalid extension `jpg` used for image /app/icons/icon.jpg, must be `ico` or `png`
    #   end
    class EmbeddedAssetsError < Tokra::Error
      # An icon whose name ends in neither <tt>.png</tt> nor <tt>.ico</tt>,
      # the two formats codegen decodes.
      #
      # Mirrors Tauri's <tt>EmbeddedAssetsError::InvalidImageExtension</tt>
      # (embedded_assets.rs:50-51).
      class InvalidImageExtension < EmbeddedAssetsError
        # The extension, without its dot; empty when the name has none.
        attr_reader :extension

        # The icon's path.
        attr_reader :path

        # Builds the error for +extension+ on the icon at +path+.
        def initialize(extension, path)
          @extension = extension
          @path = path
          super("invalid extension `#{extension}` used for image #{path}, must be `ico` or `png`")
        end
      end
    end

    # An icon the config names, read and decoded when your app starts, as
    # Tauri's codegen embeds one when the app compiles.
    #
    # A Tauri app's window icon, its macOS development icon, and its tray
    # icon come from files beside its config. Codegen decodes a PNG or an
    # ICO to RGBA, or keeps a file's raw bytes, and writes code that holds
    # the result. A Ruby app has no compile step, so this class does the
    # same work when Tokra.generate_context runs (ADR 014 §2) and #value
    # answers what that code would hold: a Tokra::Image, or the raw bytes.
    #
    # It decodes through png 0.17.16 and ico 0.5.0, the decoders codegen
    # uses, in Tokra's extension (plan 054, decision 19), not through
    # Image.from_bytes, which picks an ICO's richest entry rather than its
    # first and converts any PNG to RGBA. So a PNG must be RGBA; a 16-bit
    # one keeps eight bytes a pixel. As codegen's row loop does, a PNG that
    # ends early keeps the rows read before the error, and an interlaced
    # one keeps its Adam7 passes one after another, as png's rows give them
    # (plan 054, phase 3).
    #
    # Codegen panics where an icon cannot be read or decoded; that raises
    # RuntimeError here, with the panic's message (plan 054, decision 8).
    #
    # Mirrors Tauri's <tt>CachedIcon</tt> (tauri-codegen src/image.rs:22-118).
    #
    # === Example
    #
    #   icon = Tokra::Codegen::CachedIcon.new("/app/icons/icon.png")
    #   icon.value  #=> #<data Tokra::Image rgba="...", width=32, height=32>
    class CachedIcon
      # How an icon is held: its raw bytes, or RGBA pixels of a size.
      #
      # Mirrors Tauri's <tt>IconFormat</tt> (image.rs:13-20).
      module IconFormat # :nodoc:
        # The file, completely unmodified.
        class Raw < Data.define
        end

        # RGBA pixels, +width+ by +height+.
        class Image < Data.define(:width, :height)
        end
      end

      # The bytes codegen caches: RGBA pixels, or the file as it is.
      attr_reader :cache

      # An IconFormat: IconFormat::Raw or IconFormat::Image.
      attr_reader :format # :nodoc:

      # Reads and decodes the icon at +icon+ by its extension: a
      # <tt>.png</tt> as #new_png does, an <tt>.ico</tt> as #new_ico does.
      #
      # Raises EmbeddedAssetsError::InvalidImageExtension for any other
      # extension, and RuntimeError where the file cannot be read or
      # decoded.
      #
      # Mirrors Tauri's <tt>CachedIcon::new</tt> (image.rs:28-38).
      #
      # === Example
      #
      #   Tokra::Codegen::CachedIcon.new("/app/icons/icon.ico").value.width  #=> 256
      def self.new(icon)
        case extension(icon)
        when "png" then new_png(icon)
        when "ico" then new_ico(icon)
        else raise EmbeddedAssetsError::InvalidImageExtension.new(extension(icon).to_s, icon)
        end
      end

      # Reads the file at +icon+ and keeps its bytes as they are, as codegen
      # keeps the macOS app icon.
      #
      # Raises RuntimeError "failed to open icon {path}: {e}" when the file
      # cannot be read, +e+ in Rust's words, such as "No such file or
      # directory (os error 2)".
      #
      # Mirrors Tauri's <tt>CachedIcon::new_raw</tt> (image.rs:40-48).
      #
      # === Example
      #
      #   Tokra::Codegen::CachedIcon.new_raw("/app/icons/icon.icns").value  #=> "icns..."
      def self.new_raw(icon)
        cached(read(icon), IconFormat::Raw.new)
      end

      # Reads the ICO file at +icon+ and decodes its first entry to RGBA,
      # whatever the other entries hold.
      #
      # Raises RuntimeError "failed to open icon {path}: {e}" when the file
      # cannot be read, "failed to parse icon {path}: {e}" when it is no
      # ICO, "failed to decode icon {path}: {e}" when its first entry cannot
      # be decoded, and "index out of bounds: the len is 0 but the index is
      # 0" when it has no entries, the message of codegen's panic there
      # (plan 054, decision 8).
      #
      # Mirrors Tauri's <tt>CachedIcon::new_ico</tt> (image.rs:50-72).
      #
      # === Example
      #
      #   Tokra::Codegen::CachedIcon.new_ico("/app/icons/icon.ico")
      def self.new_ico(icon)
        rgba, width, height = Native.cached_icon_ico(icon, read(icon))
        cached(rgba, IconFormat::Image.new(width:, height:))
      end

      # Reads the PNG file at +icon+ and decodes it, untransformed, to its
      # rows of pixels.
      #
      # Raises RuntimeError "failed to open icon {path}: {e}" when the file
      # cannot be read, "failed to read icon {path}: {e}" when png cannot
      # read its header, and "icon {path} is not RGBA" when its pixels are
      # another color type.
      #
      # Mirrors Tauri's <tt>CachedIcon::new_png</tt> (image.rs:74-99).
      #
      # === Example
      #
      #   Tokra::Codegen::CachedIcon.new_png("/app/icons/icon.png")
      def self.new_png(icon)
        rgba, width, height = Native.cached_icon_png(icon, read(icon))
        cached(rgba, IconFormat::Image.new(width:, height:))
      end

      # A CachedIcon holding +cache+ in +format+.
      private_class_method def self.cached(cache, format)
        icon = allocate
        icon.__send__(:initialize, cache, format)
        icon
      end

      # The bytes of the file at +path+, read as Tauri's CachedIcon::open reads them
      # (image.rs:101-103): Ruby reads it, interruptibly, and only when
      # that fails does Rust's std::fs::read try, for its words.
      private_class_method def self.read(path)
        File.binread(path)
      rescue SystemCallError, ArgumentError # ArgumentError: a NUL byte
        begin
          Native.fs_read(path)
        rescue RuntimeError => e
          raise "failed to open icon #{path}: #{e.message}"
        end
      end

      # The extension of +path+'s last component as Rust's
      # <tt>Path::extension</tt> finds it: the text after the last dot,
      # unless the name has no dot, starts with its only one, or is "..".
      private_class_method def self.extension(path)
        name = File.basename(path)
        dot = name.rindex(".")
        return nil if name == ".." || dot.nil? || dot.zero?

        name[(dot + 1)..]
      end

      def initialize(cache, format) # :nodoc:
        @cache = cache.b.freeze
        @format = format
      end

      # What the code Tauri's codegen writes for this icon holds: a
      # Tokra::Image of the RGBA pixels for a decoded icon, or the raw
      # bytes, a frozen binary String.
      #
      # Mirrors Tauri's <tt>ToTokens for CachedIcon</tt> (image.rs:106-118),
      # which writes <tt>Image::new(bytes, width, height)</tt> or the bytes.
      #
      # === Example
      #
      #   Tokra::Codegen::CachedIcon.new("/app/icons/icon.png").value.height  #=> 32
      def value
        format = @format
        case format
        when IconFormat::Image then Tokra::Image.new(rgba: @cache, width: format.width, height: format.height)
        else @cache
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
