# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: SafePathBuf adapted from tauri/crates/tauri/src/path/mod.rs

module Tokra
  module Path
    # A path that cannot climb out of the directory it is joined to.
    #
    # A command that takes a file name from the page, and joins it to one
    # of the app's directories, trusts the page not to send
    # <tt>../../.ssh/id_rsa</tt>. A path with a <tt>..</tt> component can
    # reach any file the user can.
    #
    # SafePathBuf refuses such a path when it is made, so code that holds
    # one knows it has no <tt>..</tt> in it. A name that merely contains
    # dots, such as <tt>a..b</tt>, is fine. The path keeps its text, and
    # works wherever Ruby takes a path, since it answers +to_path+.
    #
    # Use it for a command argument the page sends, with
    # SafePathBuf.deserialize, or wrap any path before you join it.
    #
    # Mirrors Tauri's <tt>tauri::path::SafePathBuf</tt>
    # (path/mod.rs:29-84). Its <tt>..</tt> components are the platform's:
    # on Windows <tt>..\\a</tt> climbs too.
    #
    # === Examples
    #
    #   Tokra::Path::SafePathBuf.new("../secret.txt")
    #   # raises ArgumentError: cannot traverse directory, rewrite the path without the use of `../`
    #
    #   safe = Tokra::Path::SafePathBuf.new("notes/today.md")
    #   File.read(app.path.app_data_dir.join(safe.display))
    class SafePathBuf < Data.define(:path)
      # Tauri's message for a path that climbs.
      MESSAGE = "cannot traverse directory, rewrite the path without the use of `../`"

      # Checks +path+, a String or anything with +to_path+ such as a
      # Pathname. Raises ArgumentError with Tauri's message when a
      # component of it is <tt>..</tt>, as SafePathBuf::new returns that
      # message as its error (mod.rs:44-52).
      def initialize(path:) # steep:ignore MethodParameterMismatch
        text = ::File.path(path)
        raise ArgumentError, MESSAGE if SafePathBuf.traverses?(text, Std.for(Utils::Platform::Target.current))

        super(path: text) # steep:ignore UnexpectedKeywordArgument
      end

      # :attr_reader: path
      # The path, a String.

      # Whether +path+ has a <tt>..</tt> component by +std+'s rules.
      def self.traverses?(path, std) # :nodoc:
        std.components(path).any? { |component| component.kind == :parent_dir }
      end

      # The path from a command argument: a string, as serde reads a
      # PathBuf, then checked (mod.rs:76-84). Raises
      # Ipc::CommandItem::Mismatch with serde's words, or Tauri's message.
      def self.deserialize(value) # :nodoc:
        raise Ipc::CommandItem::Mismatch.invalid_type(value, "path string") unless value.is_a?(String)

        new(value)
      rescue ArgumentError => e
        raise Ipc::CommandItem::Mismatch, e.message
      end

      # The path as text, for printing. Mirrors SafePathBuf::display.
      #
      # === Example
      #
      #   Tokra::Path::SafePathBuf.new("a/b").display  #=> "a/b"
      def display
        path
      end

      # The path, so File.open and its kin take a SafePathBuf, as Rust's
      # take it through <tt>AsRef<Path></tt>.
      #
      # === Example
      #
      #   File.exist?(Tokra::Path::SafePathBuf.new("a.txt"))
      def to_path
        path
      end

      # The path, a String.
      #
      # === Example
      #
      #   Tokra::Path::SafePathBuf.new("a/b").to_s  #=> "a/b"
      def to_s
        path
      end
    end
  end
end

# SPDX-SnippetEnd
