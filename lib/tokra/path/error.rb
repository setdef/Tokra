# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: the path errors and their messages from tauri/crates/tauri/src/error.rs

module Tokra
  class Error < StandardError
    # Raised when a path ends in a root or a prefix, or is empty, so it
    # has no parent directory.
    #
    # The page's +dirname+ rejects with this message for <tt>/</tt> or
    # an empty path.
    #
    # Mirrors <tt>tauri::Error::NoParent</tt>, "path does not have a
    # parent" (error.rs:116-118).
    #
    # === Example
    #
    #   Tokra::Path::Plugin.dirname(Tokra::Path::Std::UNIX, "/")
    #   # raises Tokra::Error::NoParent: path does not have a parent
    class NoParent < Error
      # Creates the error with Tauri's message.
      def initialize(message = "path does not have a parent")
        super
      end
    end

    # Raised when a path's file name has no extension, or the path has no
    # file name.
    #
    # The page's +extname+ rejects with this message for
    # <tt>.bashrc</tt>, <tt>a/b</tt>, or <tt>a/..</tt>.
    #
    # Mirrors <tt>tauri::Error::NoExtension</tt>, "path does not have an
    # extension" (error.rs:119-121).
    #
    # === Example
    #
    #   Tokra::Path::Plugin.extname(Tokra::Path::Std::UNIX, "a/b")
    #   # raises Tokra::Error::NoExtension: path does not have an extension
    class NoExtension < Error
      # Creates the error with Tauri's message.
      def initialize(message = "path does not have an extension")
        super
      end
    end

    # Raised when a path ends in no file name, such as <tt>/</tt> or
    # <tt>a/..</tt>.
    #
    # The page's +basename+ rejects with this message.
    #
    # Mirrors <tt>tauri::Error::NoBasename</tt>, "path does not have a
    # basename" (error.rs:122-124).
    #
    # === Example
    #
    #   Tokra::Path::Plugin.basename(Tokra::Path::Std::UNIX, "/", nil)
    #   # raises Tokra::Error::NoBasename: path does not have a basename
    class NoBasename < Error
      # Creates the error with Tauri's message.
      def initialize(message = "path does not have a basename")
        super
      end
    end

    # Raised when the process cannot read its current directory, as when
    # the directory was deleted under it.
    #
    # The page's +resolve+ starts from the current directory, and rejects
    # with this message when it cannot. The message ends in the I/O
    # error's own words, as Rust displays them.
    #
    # Mirrors <tt>tauri::Error::CurrentDir</tt>, "failed to read current
    # dir: {0}" (error.rs:125-127).
    #
    # === Example
    #
    #   Tokra::Error::CurrentDir.new("No such file or directory (os error 2)").message
    #   #=> "failed to read current dir: No such file or directory (os error 2)"
    class CurrentDir < Error
      # Creates the error for +io_error+, the I/O error's message.
      def initialize(io_error)
        super("failed to read current dir: #{io_error}")
      end
    end

    # Raised when the operating system has no directory of the kind asked
    # for.
    #
    # The dirs crate answers nothing for a directory a platform lacks:
    # macOS has no runtime or template directory, Windows no font
    # directory, and a Linux system without <tt>XDG_RUNTIME_DIR</tt> no
    # runtime directory. Each PathResolver method raises this then, as do
    # the page's directory functions.
    #
    # Mirrors <tt>tauri::Error::UnknownPath</tt>, "unknown path"
    # (error.rs:128-131).
    #
    # === Example
    #
    #   app.path.runtime_dir   # on macOS
    #   # raises Tokra::Error::UnknownPath: unknown path
    class UnknownPath < Error
      # Creates the error with Tauri's message.
      def initialize(message = "unknown path")
        super
      end
    end
  end
end

# SPDX-SnippetEnd
