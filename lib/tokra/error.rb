# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # Base error class for all Tokra errors.
  #
  # Error subclasses are nested under this class to mirror Tauri's
  # <tt>tauri::Error</tt> enum structure.
  #
  # Example:
  #   begin
  #     table.get(999)
  #   rescue Tokra::Error::BadResourceId => e
  #     puts "Invalid rid: #{e.rid}"
  #   end
  #
  class Error < StandardError
    # Raised when image bytes cannot be decoded.
    #
    # Mirrors <tt>tauri::Error::Image(ImageError)</tt>; the message keeps
    # Tauri's "failed to process image" prefix.
    class Image < Error
    end

    # SPDX-SnippetBegin
    # SPDX-License-Identifier: Apache-2.0 OR MIT
    # SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
    # SPDX-SnippetComment: Io, Runtime, PluginInitialization, and InvalidArgs and their
    # messages from tauri/src/error.rs and tauri-runtime/src/lib.rs

    # Raised when a file cannot be read.
    #
    # An image loaded from a path can fail before any decoding starts: the
    # file is missing, is a directory, or its name holds a NUL byte no
    # operating system accepts. The frontend gets the I/O error's own words,
    # with no prefix, so its message reads as the cause.
    #
    # Mirrors <tt>tauri::Error::Io(std::io::Error)</tt>, displayed as the
    # io::Error alone (error.rs:53-54), in Rust's words: the OS's text for
    # the error code, then <tt>(os error N)</tt>. Image.from_path raises it.
    #
    # === Example
    #
    #   Tokra::Image.from_path("missing.png")
    #   # raises Tokra::Error::Io: No such file or directory (os error 2)
    class Io < Error
    end

    # Raised when a call cannot reach the main thread, or its answer never
    # comes back.
    #
    # Window and webview calls made from another thread travel to the main
    # thread through the event loop. Once the loop has ended, a call cannot
    # get there, and a call already waiting for an answer will never get
    # one. Rescue this error in a background thread that may outlive the
    # loop.
    #
    # Mirrors <tt>tauri::Error::Runtime</tt>, whose message prefixes the
    # runtime error's own (error.rs:35-36), wrapping
    # <tt>FailedToSendMessage</tt> and <tt>FailedToReceiveMessage</tt>
    # (tauri-runtime lib.rs:131-136).
    #
    # === Example
    #
    #   Thread.new do
    #     window.title
    #   rescue Tokra::Error::Runtime => e
    #     e.message  #=> "runtime error: failed to send message to the webview"
    #   end
    class Runtime < Error
      # The message could not be sent to the main thread.
      FAILED_TO_SEND_MESSAGE = "failed to send message to the webview"

      # The main thread never answered.
      FAILED_TO_RECEIVE_MESSAGE = "failed to receive message from webview"

      # Creates a runtime error from the runtime's own +message+.
      def initialize(message)
        super("runtime error: #{message}")
      end
    end

    # Raised when a plugin's setup fails.
    #
    # A plugin may need something from the system before it can work: a
    # hotkey manager, a connection, a file. When it cannot get one, the app
    # should hear which plugin failed and why, not a bare error from deep
    # inside it.
    #
    # A plugin raises this from its constructor, which is its setup, with
    # its name and the reason. Mirrors
    # <tt>tauri::Error::PluginInitialization</tt> (error.rs:64-66), which
    # Tauri builds from the plugin's name and its setup error
    # (plugin.rs:1009).
    #
    # === Example
    #
    #   raise Tokra::Error::PluginInitialization.new("global-shortcut", e.message)
    #   # message: "failed to initialize plugin `global-shortcut`: ..."
    class PluginInitialization < Error
      # The name of the plugin that failed.
      attr_reader :plugin

      # Creates the error for +plugin+, a plugin name, and +message+, the
      # reason its setup failed.
      def initialize(plugin, message)
        @plugin = plugin
        super("failed to initialize plugin `#{plugin}`: #{message}")
      end
    end

    # Raised when a command's argument is missing or of the wrong kind.
    #
    # The frontend calls a command with a payload, and each argument the
    # command takes is read from one key of it. When the key is missing,
    # or holds the wrong kind of value, the invoke rejects, and the
    # frontend should hear which argument of which command was wrong and
    # why, in Tauri's words.
    #
    # Tokra::Ipc::CommandItem raises this when an argument does not read.
    # A plugin's extend_api rescues it and rejects the invoke with its
    # message. It is not an ArgumentError, so a bug's ArgumentError is not
    # mistaken for the frontend's mistake. Mirrors
    # <tt>tauri::Error::InvalidArgs</tt> (error.rs:58-60), which Tauri
    # builds from the command's name, the argument's key, and serde_json's
    # error (ipc/command.rs:63-69).
    #
    # === Example
    #
    #   raise Tokra::Error::InvalidArgs.new("register", "shortcuts", "invalid type: null, expected a sequence")
    #   # message: "invalid args `shortcuts` for command `register`: invalid type: null, expected a sequence"
    class InvalidArgs < Error
      # The name of the command whose argument did not read.
      attr_reader :command

      # The argument's key in the payload.
      attr_reader :key

      # Creates the error for argument +key+ of +command+, with +reason+,
      # what serde_json said went wrong.
      def initialize(command, key, reason)
        @command = command
        @key = key
        super("invalid args `#{key}` for command `#{command}`: #{reason}")
      end
    end

    # SPDX-SnippetEnd

    # Raised when a resource ID is not found in a ResourceTable.
    #
    # Mirrors <tt>tauri::Error::BadResourceId(rid)</tt>.
    class BadResourceId < Error
      # The resource ID that was not found.
      attr_reader :rid

      # Creates a new BadResourceId error.
      #
      # +rid+:: the resource ID that was not found
      def initialize(rid)
        @rid = rid
        super("The resource id #{rid} is invalid.")
      end
    end
  end
end
