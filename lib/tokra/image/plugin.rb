# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: Image plugin adapted from tauri/crates/tauri/src/image/plugin.rs;
#                      the argument messages are serde's as serde_json produces them

module Tokra
  class Image
    # Core plugin handling image lifecycle IPC commands.
    #
    # Frontend code cannot hold Ruby objects, and images are too large
    # to shuttle through JSON on every call. Tauri's JavaScript Image
    # class solves this with resource IDs, and it expects the
    # <tt>plugin:image|*</tt> commands to exist.
    #
    # This plugin answers those commands: it stores images in the
    # calling webview's ResourceTable and serves queries by rid. Tokra
    # registers it automatically, so the Image class from
    # <tt>@tauri-apps/api</tt> works without setup.
    #
    # Matches Tauri's image/plugin.rs.
    class Plugin < Tokra::Plugin
      # Returns the plugin identifier.
      def name
        "image"
      end

      # Handles IPC commands for image resource management.
      #
      # Receives the bare command name: the IPC dispatcher strips the
      # <tt>plugin:image|</tt> prefix before routing, exactly as Tauri rewrites
      # +invoke.message.command+ in webview/mod.rs.
      #
      # Returns +true+ if the command was handled, +false+ otherwise.
      #
      # Command errors reject the invoke rather than raise, mirroring
      # Tauri's Result-to-InvokeError propagation in the command layer, as
      # does an argument that does not read (Error::InvalidArgs). Anything
      # else is a bug, and reaches the router.
      def extend_api(invoke)
        case invoke.command
        when "new"        then handle_new(invoke)
        when "rgba"       then handle_rgba(invoke)
        when "size"       then handle_size(invoke)
        when "from_bytes" then handle_from_bytes(invoke)
        when "from_path"  then handle_from_path(invoke)
        else false
        end
      rescue Error::BadResourceId, Error::Image, Error::InvalidArgs, Error::Io => e
        invoke.reject(e.message)
        true
      end

      # Creates a new Image from RGBA byte array and stores it.
      #
      # Matches Tauri image/plugin.rs:12-22.
      private def handle_new(invoke)
        rgba = bytes_arg(invoke, "rgba")
        width = u32_arg(invoke, "width")
        height = u32_arg(invoke, "height")
        image = Image.new(rgba:, width:, height:)
        rid = invoke.webview.resources_table.add(image)
        invoke.resolve(rid)
        true
      end

      # Returns RGBA bytes of a stored image as an Array of integers.
      #
      # Matches Tauri image/plugin.rs:57-62.
      private def handle_rgba(invoke)
        image = image_arg(invoke)
        invoke.resolve(image.rgba.bytes)
        true
      end

      # Returns the dimensions of a stored image as a Hash.
      #
      # Matches Tauri image/plugin.rs:70-78 (Size struct serialization).
      private def handle_size(invoke)
        image = image_arg(invoke)
        invoke.resolve({ "width" => image.width, "height" => image.height })
        true
      end

      # Decodes PNG or ICO bytes into a stored Image.
      #
      # Matches Tauri's from_bytes command (image/plugin.rs). Tauri gates
      # it behind Cargo features; Ruby has no build flags, so Tokra
      # supports it unconditionally.
      private def handle_from_bytes(invoke)
        bytes = bytes_arg(invoke, "bytes")
        rid = invoke.webview.resources_table.add(Image.from_bytes(bytes))
        invoke.resolve(rid)
        true
      end

      # Decodes the PNG or ICO file at the given path into a stored Image.
      #
      # Matches Tauri's from_path command (image/plugin.rs).
      private def handle_from_path(invoke)
        path = path_arg(invoke, "path")
        rid = invoke.webview.resources_table.add(Image.from_path(path))
        invoke.resolve(rid)
        true
      end

      # Fetches the Image referenced by the +rid+ argument.
      #
      # Raises Error::BadResourceId when the rid is unknown or the stored
      # resource is not an Image, mirroring Tauri's ResourceTable::get,
      # which downcasts to the requested type or fails.
      private def image_arg(invoke)
        rid = u32_arg(invoke, "rid")
        image = invoke.webview.resources_table.get(rid)
        raise Error::BadResourceId, rid unless image.is_a?(Image)

        image
      end

      # The argument at +key+ as a Rust <tt>Vec<u8></tt>, packed into a
      # binary String.
      private def bytes_arg(invoke, key)
        argument(invoke, key).deserialize do |value|
          raise Ipc::CommandItem::Mismatch.invalid_type(value, "a sequence") unless value.is_a?(Array)

          value.map { |byte| Ipc::CommandItem.integer(byte, "u8") }.pack("C*")
        end
      end

      # The argument at +key+ as a Rust +u32+ (a dimension, or a
      # ResourceId).
      private def u32_arg(invoke, key)
        argument(invoke, key).u32
      end

      # The argument at +key+ as a Rust +PathBuf+: any string, which serde's
      # PathBuf visitor expects as a <tt>path string</tt>.
      private def path_arg(invoke, key)
        argument(invoke, key).deserialize do |value|
          value.is_a?(String) ? value : raise(Ipc::CommandItem::Mismatch.invalid_type(value, "path string"))
        end
      end

      private def argument(invoke, key)
        Ipc::CommandItem.new(name: invoke.command, key:, payload: invoke.body)
      end
    end
  end
end

# SPDX-SnippetEnd
