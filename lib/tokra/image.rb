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

  # Intermediate image payload from frontend JavaScript.
  #
  # Frontend code refers to an image four ways: a resource ID from a
  # prior <tt>Image.new</tt> call, encoded bytes, a file path, or an
  # inline RGBA hash. Every IPC command that accepts an image must
  # resolve all four.
  #
  # This class wraps the raw payload value and resolves it with
  # into_img. Mirrors Tauri's JsImage enum (image/mod.rs:169-229), the
  # server side of the frontend transformImage API.
  #
  # === Example
  #
  #   js_image = Tokra::JsImage.new(invoke.payload["image"])
  #   image = js_image.into_img(invoke.webview.resources_table)
  #
  class JsImage
    # Wraps a raw payload value (Integer, Array, String, or Hash).
    def initialize(value)
      @value = value
    end

    # Resolves the payload to an Image.
    #
    # [Integer] fetched from +resources_table+; the resource must be an
    #           Image.
    # [Array]   decoded with Image.from_bytes.
    # [String]  decoded with Image.from_path.
    # [Hash]    built from its <tt>"rgba"</tt>, <tt>"width"</tt>, and
    #           <tt>"height"</tt> keys.
    #
    # Raises Error::BadResourceId when a resource ID is unknown or does
    # not hold an Image, Error::Image when bytes cannot be decoded, and
    # ArgumentError for any other value.
    #
    # Matches Tauri's JsImage#into_img (image/mod.rs:191-229). Pass the
    # webview's resources_table so resource IDs resolve against the same
    # table that stored them.
    #
    # === Example
    #
    #   table = Tokra::ResourceTable.new
    #   rid = table.add(Tokra::Image.new(rgba: "\0\0\0\0".b, width: 1, height: 1))
    #   Tokra::JsImage.new(rid).into_img(table)  #=> the stored Image
    def into_img(resources_table)
      value = @value
      case value
      when Integer then image_resource(value, resources_table)
      when Array then Image.from_bytes(pack_bytes(value))
      when String then Image.from_path(value)
      when Hash then rgba_image(value)
      else
        raise ArgumentError,
          "invalid args: image must be a resource ID, byte array, file path, or RGBA hash"
      end
    end

    private def image_resource(rid, resources_table)
      resource = resources_table.get(rid)
      raise Error::BadResourceId, rid unless resource.is_a?(Image)

      resource
    end

    # Builds an Image from an inline RGBA hash.
    private def rgba_image(hash)
      rgba = hash["rgba"]
      width = hash["width"]
      height = hash["height"]
      unless rgba.is_a?(Array) && width.is_a?(Integer) && height.is_a?(Integer)
        raise ArgumentError,
          "invalid args: image hash must have an rgba array, an integer width, and an integer height"
      end

      Image.new(rgba: pack_bytes(rgba), width:, height:)
    end

    # Packs a JSON byte array into a binary string.
    private def pack_bytes(array)
      array.pack("C*")
    rescue TypeError
      raise ArgumentError, "invalid args: image bytes must be integers"
    end
  end
end

# SPDX-SnippetEnd
