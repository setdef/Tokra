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
    # The message for a payload that fits none of the four shapes: serde's
    # error for Tauri's untagged JsImage enum.
    MISMATCH = "data did not match any variant of untagged enum JsImage"

    # The largest u32, the type of Tauri's ResourceId and image dimensions.
    U32_MAX = (2 ** 32) - 1

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
    # [Array of three] <tt>[rgba, width, height]</tt>, the sequence form
    #           serde's derived struct visitor also accepts for Tauri's
    #           Rgba variant, when the array is not a byte array.
    #
    # Each shape is checked the way Tauri deserializes it: bytes are
    # integers from 0 to 255, and resource IDs, widths, and heights are
    # integers from 0 to 4294967295. A value that fits no shape raises
    # ArgumentError with serde's message,
    # <tt>data did not match any variant of untagged enum JsImage</tt>.
    # An unknown resource ID, or one that does not hold an Image, raises
    # Error::BadResourceId; bytes that cannot be decoded raise Error::Image.
    #
    # Matches Tauri's JsImage enum and JsImage#into_img
    # (image/mod.rs:166-229). Pass the webview's resources_table so
    # resource IDs resolve against the same table that stored them.
    #
    # === Example
    #
    #   table = Tokra::ResourceTable.new
    #   rid = table.add(Tokra::Image.new(rgba: "\0\0\0\0".b, width: 1, height: 1))
    #   Tokra::JsImage.new(rid).into_img(table)  #=> the stored Image
    def into_img(resources_table)
      value = @value
      case value
      when Integer then image_resource(u32(value), resources_table)
      when Array then array_image(value)
      when String then Image.from_path(value)
      when Hash then rgba_image(value)
      else raise ArgumentError, MISMATCH
      end
    end

    private def image_resource(rid, resources_table)
      resource = resources_table.get(rid)
      raise Error::BadResourceId, rid unless resource.is_a?(Image)

      resource
    end

    # An array is Tauri's Bytes variant when every element is a u8, and
    # otherwise its Rgba variant in sequence form: serde's untagged enum
    # tries Bytes first, then the struct visitor, which reads exactly
    # three elements in field order (rgba, width, height).
    private def array_image(array)
      return Image.from_bytes(pack_bytes(array)) unless array.size == 3 && array.first.is_a?(Array)

      rgba, width, height = array
      rgba_image({ "rgba" => rgba, "width" => width, "height" => height })
    end

    # Builds an Image from an inline RGBA hash.
    private def rgba_image(hash)
      rgba = hash["rgba"]
      raise ArgumentError, MISMATCH unless rgba.is_a?(Array)

      Image.new(rgba: pack_bytes(rgba), width: u32(hash["width"]), height: u32(hash["height"]))
    end

    # Packs a JSON byte array into a binary string, accepting only u8
    # values, so 256 cannot wrap to 0 and 1.5 cannot truncate to 1.
    private def pack_bytes(array)
      raise ArgumentError, MISMATCH unless array.all? { |byte| byte.is_a?(Integer) && byte.between?(0, 255) }

      array.pack("C*")
    end

    # Returns +value+ if it is a u32.
    private def u32(value)
      raise ArgumentError, MISMATCH unless value.is_a?(Integer) && value.between?(0, U32_MAX)

      value
    end
  end
end

# SPDX-SnippetEnd
