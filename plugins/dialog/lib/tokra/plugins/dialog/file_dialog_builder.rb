# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: FileDialogBuilder adapted from tauri-plugin-dialog
#                      src/lib.rs:370-770 and its AsyncFileDialog conversion
#                      from src/desktop.rs:82-108

module Tokra
  module Plugins
    module Dialog
      # Builds a dialog that picks files or folders, or a place to save one.
      #
      # Opening a document, importing a folder of photos, and choosing where
      # to save an export all start with the system's file dialog: it knows
      # the user's folders, favorites, and recent places.
      #
      # Get one from Dialog#file, set its title, starting folder, file name,
      # and filters, and call one of its terminal methods. Each answers with
      # path Strings, or +nil+ when the user cancels.
      #
      # === Threads
      #
      # #pick_file, #pick_files, #pick_folder, #pick_folders, and #save_file
      # return at once and call your block later, on another thread. Use
      # them anywhere, including the main thread. The +blocking_+ methods
      # wait for the user; do not call them on the main thread, where they
      # freeze the app (on macOS, forever).
      #
      # A terminal method reads the builder's settings when you call it, as
      # Tauri's consumes the builder then: changing the builder afterwards
      # leaves a dialog already started as it was.
      #
      # === Paths
      #
      # Tauri answers with <tt>FilePath</tt> from its fs plugin, which on a
      # desktop is always a path. Tokra has no fs plugin yet, so the answers
      # are path Strings.
      #
      # Mirrors Tauri's <tt>FileDialogBuilder</tt> (lib.rs:370-770).
      #
      # === Examples
      #
      #   handle.dialog.file.pick_file do |path|
      #     # path is nil if the user closed the dialog
      #   end
      #
      #   handle.dialog.file.add_filter("Image", ["png", "jpeg"]).pick_files { |paths| p paths }
      #
      #   Thread.new do
      #     folder = handle.dialog.file.set_title("Import").blocking_pick_folder
      #   end
      class FileDialogBuilder
        # A file type filter: a name and the extensions it shows
        # (lib.rs:370-374).
        Filter = Data.define(:name, :extensions)

        # The Dialog that made this builder.
        attr_reader :dialog

        # Creates a builder with no options set (lib.rs:409-423).
        #
        # [dialog] the Dialog it starts through.
        def initialize(dialog)
          @dialog = dialog
          @filters = [] #: Array[Filter]
          @starting_directory = nil
          @file_name = nil
          @title = nil
          @can_create_directories = nil
          @picker_mode = nil
          @file_access_mode = nil
          @parent = nil
        end

        # Adds a filter named +name+ that shows files with +extensions+,
        # given without the dot. Returns the builder.
        #
        # === Example
        #
        #   builder.add_filter("Image", ["png", "jpeg"])
        def add_filter(name, extensions)
          @filters << Filter.new(name:, extensions: extensions.map(&:to_s))
          self
        end

        # Sets the folder the dialog starts in. Returns the builder.
        #
        # === Example
        #
        #   builder.set_directory(Dir.home)
        def set_directory(directory)
          @starting_directory = directory.to_s
          self
        end

        # Sets the file name the dialog starts with. Returns the builder.
        #
        # === Example
        #
        #   builder.set_file_name("report.pdf")
        def set_file_name(file_name)
          @file_name = file_name
          self
        end

        # Sets the parent window: a Tokra::Window, or any object whose
        # +window_handle+ and +display_handle+ return Tokra::RawWindowHandle
        # or ferro-rfd handle values. Kept only when both answer, as Tauri
        # keeps a parent only when it has both handles (lib.rs:460-478).
        # Returns the builder.
        #
        # A parent keeps the dialog in front of its window on Windows; on
        # macOS the dialog slides out of that window as a sheet; on X11
        # rfd names the window to the desktop portal. On Wayland the
        # dialog has no parent: ferro-rfd binds no handle rfd follows as a
        # pointer (ADR 013). Keep the window open until the dialog closes.
        #
        # === Example
        #
        #   handle.dialog.file.set_parent(window).pick_file { |path| p path }
        def set_parent(parent)
          handle = Desktop::WindowHandle.of(parent)
          @parent = handle if handle
          self
        end

        # Sets the dialog's title. Returns the builder.
        #
        # === Example
        #
        #   builder.set_title("Open a project")
        def set_title(title)
          @title = title
          self
        end

        # Sets whether the user may create folders in the dialog. Enabled
        # by default. macOS only. Returns the builder.
        #
        # === Example
        #
        #   builder.set_can_create_directories(false)
        def set_can_create_directories(can)
          @can_create_directories = can
          self
        end

        # Sets the PickerMode, for mobile platforms with separate file and
        # media pickers. Desktops ignore it (lib.rs:493-500). Returns the
        # builder.
        #
        # === Example
        #
        #   builder.set_picker_mode(PickerMode::Image)
        def set_picker_mode(mode)
          @picker_mode = mode
          self
        end

        # Sets the FileAccessMode, used only on iOS. Desktops ignore it
        # (lib.rs:502-508). Returns the builder.
        #
        # === Example
        #
        #   builder.set_file_access_mode(FileAccessMode::Scoped)
        def set_file_access_mode(mode)
          @file_access_mode = mode
          self
        end

        # Shows the dialog to pick one file and returns at once. The block
        # gets the path, or +nil+ if the user closed the dialog
        # (lib.rs:510-532).
        #
        # === Example
        #
        #   builder.pick_file { |path| open_document(path) if path }
        def pick_file(&)
          Desktop.pick_file(self, &)
          nil
        end

        # Shows the dialog to pick several files and returns at once. The
        # block gets the paths, or +nil+ if the user closed the dialog
        # (lib.rs:534-580).
        #
        # === Example
        #
        #   builder.pick_files { |paths| Array(paths).each { |path| import(path) } }
        def pick_files(&)
          Desktop.pick_files(self, &)
          nil
        end

        # Shows the dialog to pick one folder and returns at once. The block
        # gets the path, or +nil+ if the user closed the dialog
        # (lib.rs:582-605).
        #
        # === Example
        #
        #   builder.pick_folder { |folder| p folder }
        def pick_folder(&)
          Desktop.pick_folder(self, &)
          nil
        end

        # Shows the dialog to pick several folders and returns at once. The
        # block gets the paths, or +nil+ if the user closed the dialog
        # (lib.rs:607-630).
        #
        # === Example
        #
        #   builder.pick_folders { |folders| p folders }
        def pick_folders(&)
          Desktop.pick_folders(self, &)
          nil
        end

        # Shows the dialog to save a file and returns at once. The block
        # gets the path, or +nil+ if the user closed the dialog
        # (lib.rs:632-654).
        #
        # === Example
        #
        #   builder.save_file { |path| File.write(path, report) if path }
        def save_file(&)
          Desktop.save_file(self, &)
          nil
        end

        # Shows the dialog to pick one file and waits. Returns the path, or
        # +nil+ if the user closed the dialog (lib.rs:659-679). Raises what
        # rfd raised.
        #
        # This blocks, so do not call it on the main thread.
        #
        # === Example
        #
        #   Thread.new { path = builder.blocking_pick_file }
        def blocking_pick_file
          Desktop.blocking { |respond| Desktop.pick_file(self, respond, &respond) }
        end

        # Shows the dialog to pick several files and waits. Returns the
        # paths, or +nil+ if the user closed the dialog (lib.rs:681-701).
        #
        # This blocks, so do not call it on the main thread.
        #
        # === Example
        #
        #   Thread.new { paths = builder.blocking_pick_files }
        def blocking_pick_files
          Desktop.blocking { |respond| Desktop.pick_files(self, respond, &respond) }
        end

        # Shows the dialog to pick one folder and waits. Returns the path,
        # or +nil+ if the user closed the dialog (lib.rs:703-724).
        #
        # This blocks, so do not call it on the main thread.
        #
        # === Example
        #
        #   Thread.new { folder = builder.blocking_pick_folder }
        def blocking_pick_folder
          Desktop.blocking { |respond| Desktop.pick_folder(self, respond, &respond) }
        end

        # Shows the dialog to pick several folders and waits. Returns the
        # paths, or +nil+ if the user closed the dialog (lib.rs:726-747).
        #
        # This blocks, so do not call it on the main thread.
        #
        # === Example
        #
        #   Thread.new { folders = builder.blocking_pick_folders }
        def blocking_pick_folders
          Desktop.blocking { |respond| Desktop.pick_folders(self, respond, &respond) }
        end

        # Shows the dialog to save a file and waits. Returns the path, or
        # +nil+ if the user closed the dialog (lib.rs:749-769).
        #
        # This blocks, so do not call it on the main thread.
        #
        # === Example
        #
        #   Thread.new { path = builder.blocking_save_file }
        def blocking_save_file
          Desktop.blocking { |respond| Desktop.save_file(self, respond, &respond) }
        end

        # The ferro-rfd dialog this builder describes. The user may create
        # folders unless told otherwise (desktop.rs:82-108).
        #
        # === Example
        #
        #   builder.to_async_file_dialog.pick_file
        def to_async_file_dialog
          dialog = Ferro::Rfd::AsyncFileDialog.new
          title = @title
          starting_directory = @starting_directory
          file_name = @file_name
          parent = @parent
          dialog.set_title(title) if title
          dialog.set_directory(starting_directory) if starting_directory
          dialog.set_file_name(file_name) if file_name
          @filters.each { |filter| dialog.add_filter(filter.name, filter.extensions) }
          dialog.set_parent(parent) if parent
          dialog.set_can_create_directories(@can_create_directories.nil? || @can_create_directories)
        end
      end
    end
  end
end

# SPDX-SnippetEnd
