# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetCopyrightText: The Rust Project Developers (std's NUL path messages)
# SPDX-SnippetComment: Image structure adapted from tauri/crates/tauri/src/image/mod.rs;
#                      JsImage's message is serde's for an untagged enum

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

    # Rust's io::Error for a path with a NUL byte: Unix hands paths to the
    # OS as C strings (std sys/helpers/small_c_string.rs:13-14), and
    # Windows as wide strings (std sys/pal/windows/mod.rs:99-104).
    NUL_IN_PATH = if Gem.win_platform?
      "strings passed to WinAPI cannot contain NULs"
    else
      "file name contained an unexpected NUL byte"
    end

    # Creates an Image by decoding the PNG or ICO file at +path+.
    #
    # Matches Tauri's Image::from_path (image/mod.rs).
    #
    # Raises Error::Image when the file cannot be decoded, or Error::Io
    # when it cannot be read, with the reason Ruby gives. A path holding a
    # NUL byte is a file Rust's std::fs::read cannot open either, and
    # raises Error::Io with Rust's words, where Ruby's File.binread would
    # raise ArgumentError.
    #
    # === Example
    #
    #   image = Tokra::Image.from_path("assets/icon.ico")
    def self.from_path(path)
      raise Error::Io, NUL_IN_PATH if path.include?("\0")

      from_bytes(read(path))
    end

    # The file at +path+, or Error::Io with Ruby's reason.
    private_class_method def self.read(path)
      File.binread(path)
    rescue SystemCallError => e
      raise Error::Io, e.message
    end
  end

  # An image argument from frontend JavaScript.
  #
  # Frontend code refers to an image four ways: a file path, encoded
  # bytes, a resource ID from a prior <tt>Image.new</tt> call, or an
  # inline RGBA hash. A command that takes an image reads all four, and
  # rejects anything else in serde's words. Reading the
  # argument and resolving it fail differently: a value of the wrong
  # shape is the frontend's bad argument, while a resource ID that names
  # nothing, or bytes that do not decode, is the command's error.
  #
  # deserialize reads the payload value as Tauri's untagged JsImage enum
  # deserializes (image/mod.rs:158-189), raising
  # Ipc::CommandItem::Mismatch, so CommandItem#deserialize reports it as
  # the argument's Error::InvalidArgs. into_img then resolves it as
  # Tauri's <tt>JsImage::into_img</tt> does (image/mod.rs:191-230),
  # raising Tauri's errors. Like Tauri's non-exhaustive variants, a
  # JsImage cannot be built any other way.
  #
  # === Example
  #
  #   js_image = Tokra::Ipc::CommandItem.new(name: "write_image", key: "image", payload: invoke.body)
  #     .deserialize { |value| Tokra::JsImage.deserialize(value) }
  #   image = js_image.into_img(invoke.webview.resources_table)
  #
  class JsImage
    # The message for a payload that fits none of the four shapes: serde's
    # error for Tauri's untagged JsImage enum.
    MISMATCH = "data did not match any variant of untagged enum JsImage"

    # The largest u32, the type of Tauri's ResourceId and image dimensions.
    U32_MAX = (2 ** 32) - 1

    private_class_method :new

    # Reads +value+, a JSON value, as one of Tauri's four variants, tried
    # in serde's order:
    #
    # [String]  +Path+, a file path.
    # [Array]   +Bytes+, when every element is an integer from 0 to 255.
    # [Integer] +Resource+, an ID from 0 to 4294967295.
    # [Hash]    +Rgba+, from its <tt>"rgba"</tt> bytes and its
    #           <tt>"width"</tt> and <tt>"height"</tt> u32s. Only a map:
    #           serde_derive gives an untagged enum's struct variant no
    #           sequence form (serde_derive 1.0.228 de/struct_.rs:70-73),
    #           so <tt>[rgba, width, height]</tt> is not an image.
    #
    # A value that fits no variant raises Ipc::CommandItem::Mismatch with
    # serde's message, <tt>data did not match any variant of untagged enum
    # JsImage</tt>.
    #
    # === Example
    #
    #   Tokra::JsImage.deserialize({ "rgba" => [0, 0, 0, 0], "width" => 1, "height" => 1 })
    def self.deserialize(value)
      variant = case value
      when String then value
      when Array then bytes(value)
      when Integer then u32(value)
      when Hash then rgba(value)
      end
      variant ? new(variant) : raise(Ipc::CommandItem::Mismatch, MISMATCH)
    end

    # The Rgba variant from a hash, or +nil+ when it does not read.
    private_class_method def self.rgba(hash)
      rgba = hash["rgba"]
      pixels = bytes(rgba)&.pack("C*") if rgba.is_a?(Array)
      width = u32(hash["width"])
      height = u32(hash["height"])
      Image.new(rgba: pixels, width:, height:) if pixels && width && height
    end

    # A JSON array as a Vec<u8>, or +nil+ unless every element is a u8, so
    # 256 cannot wrap to 0 and 1.5 cannot truncate to 1 when it is packed.
    private_class_method def self.bytes(array)
      array.map do |byte|
        return nil unless byte.is_a?(Integer) && byte.between?(0, 255)

        byte
      end
    end

    # +value+ if it is a u32, or +nil+.
    private_class_method def self.u32(value)
      value if value.is_a?(Integer) && value.between?(0, U32_MAX)
    end

    # Holds one variant: a String (Path, any string, as a PathBuf takes
    # it), an Array of u8 (Bytes), an Integer (Resource), or an Image
    # (Rgba).
    def initialize(variant)
      @variant = variant
    end

    # Resolves the image.
    #
    # A resource ID is fetched from +resources_table+, raising
    # Error::BadResourceId when it names nothing or a resource that is not
    # an Image. A path is read and decoded with Image.from_path, and bytes
    # with Image.from_bytes, raising Error::Image when they do not decode
    # (and Error::Io when the file cannot be read). An RGBA image
    # is returned as it is.
    #
    # Matches Tauri's JsImage#into_img (image/mod.rs:191-230). Pass the
    # webview's resources_table so resource IDs resolve against the same
    # table that stored them.
    #
    # === Example
    #
    #   table = Tokra::ResourceTable.new
    #   rid = table.add(Tokra::Image.new(rgba: "\0\0\0\0".b, width: 1, height: 1))
    #   Tokra::JsImage.deserialize(rid).into_img(table)  #=> the stored Image
    def into_img(resources_table)
      variant = @variant
      case variant
      when Integer then image_resource(variant, resources_table)
      when String then Image.from_path(variant)
      when Array then Image.from_bytes(variant.pack("C*"))
      else variant
      end
    end

    private def image_resource(rid, resources_table)
      resource = resources_table.get(rid)
      raise Error::BadResourceId, rid unless resource.is_a?(Image)

      resource
    end
  end
end

# SPDX-SnippetEnd
