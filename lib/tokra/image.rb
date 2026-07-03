# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Image structure adapted from tauri/crates/tauri/src/image/mod.rs

module Tokra
  # An RGBA image in row-major order from top to bottom.
  #
  # Stores raw pixel data as bytes. Each pixel is 4 bytes (RGBA).
  # Total bytes should equal <tt>width * height * 4</tt>.
  #
  # Mirrors Tauri's Image struct (image/mod.rs). This class includes the Resource
  # module for ResourceTable compatibility.
  #
  # Example:
  #   rgba = "\xFF\x00\x00\xFF".b  # 1x1 red pixel
  #   image = Tokra::Image.new(rgba: rgba, width: 1, height: 1)
  #   rid = table.add(image)
  #
  class Image < Data.define(:rgba, :width, :height)
    include Resource

    # Creates an Image by decoding PNG or ICO bytes.
    #
    # Icons and clipboard graphics usually arrive as encoded files, not
    # raw pixels. Decoding them by hand means porting a PNG decoder.
    #
    # This method decodes natively, using the same image crate as Tauri,
    # and returns an Image holding raw RGBA data. Only PNG and ICO are
    # supported, matching Tauri's Image::from_bytes (image/mod.rs).
    #
    # Raises Error::Image when the bytes cannot be decoded.
    #
    # === Example
    #
    #   image = Tokra::Image.from_bytes(File.binread("icon.png"))
    #   image.width  #=> 32
    def self.from_bytes(bytes)
      rgba, width, height = Native.image_from_bytes(bytes)
      new(rgba:, width:, height:)
    rescue RuntimeError => e
      raise Error::Image, e.message
    end

    # Creates an Image by decoding the PNG or ICO file at +path+.
    #
    # Matches Tauri's Image::from_path (image/mod.rs).
    #
    # Raises Error::Image when the file cannot be decoded, or a
    # SystemCallError when it cannot be read.
    #
    # === Example
    #
    #   image = Tokra::Image.from_path("assets/icon.ico")
    def self.from_path(path)
      from_bytes(File.binread(path))
    end
  end
end

# SPDX-SnippetEnd
