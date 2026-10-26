# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Commands adapted from tauri-plugin-dialog
#                      src/commands.rs; simplified from tauri-plugin-fs
#                      src/file_path.rs

module Tokra
  module Plugins
    module Dialog
      # The plugin's IPC commands: open, save, message, ask, and confirm.
      #
      # Each reads its arguments the way Tauri deserializes them, rejecting
      # a bad one with Tauri's message, and then runs on a thread of its
      # own, as Tauri runs its +async+ commands on a worker: it builds the
      # dialog, waits for the user with a +blocking_+ method, and settles
      # the invoke. The invoke rejects with the message of anything that
      # goes wrong, so it always settles.
      #
      # These are the functions of Tauri's private +commands+ module
      # (commands.rs). Plugin#extend_api calls them.
      #
      # === Deviations
      #
      # * No parent window: Tokra's windows cannot name their native handle
      #   yet (plan 023, decision 3).
      # * Tauri adds each picked path to the fs plugin's scope and the asset
      #   protocol's scope (commands.rs:156-215, 247-257). Tokra has neither
      #   yet, so a picked path widens nothing.
      module Commands
        # A filter as the frontend sends it (commands.rs:28-34).
        DialogFilter = Data.define(:name, :extensions)

        # The open command's options (commands.rs:36-71).
        OpenDialogOptions = Data.define(:title, :filters, :multiple, :directory, :default_path, :recursive,
          :can_create_directories, :picker_mode, :file_access_mode)

        # The save command's options (commands.rs:73-87).
        SaveDialogOptions = Data.define(:title, :filters, :default_path, :can_create_directories)

        # Opens a file or folder dialog and settles +invoke+ with the path,
        # the paths, or +nil+ (commands.rs:122-219).
        #
        # === Example
        #
        #   Commands.open(invoke, handle.dialog)
        def self.open(invoke, dialog)
          options = arguments(invoke.payload, "open").open_options
          spawn(invoke) { open_dialog(dialog, options) }
        end

        # Opens a save dialog and settles +invoke+ with the path or +nil+
        # (commands.rs:221-260).
        #
        # === Example
        #
        #   Commands.save(invoke, handle.dialog)
        def self.save(invoke, dialog)
          options = arguments(invoke.payload, "save").save_options
          spawn(invoke) { save_dialog(dialog, options) }
        end

        # Shows a message dialog and settles +invoke+ with the button
        # pressed, as MessageDialogResult serializes it (commands.rs:290-307).
        #
        # === Example
        #
        #   Commands.message(invoke, handle.dialog)
        def self.message(invoke, dialog)
          args = arguments(invoke.payload, "message")
          title = args.optional_string("title")
          message = args.string("message")
          kind = args.kind("kind")
          ok_button_label = args.optional_string("okButtonLabel")
          buttons = message_buttons(args.buttons("buttons"), ok_button_label)
          spawn(invoke) do
            message_dialog(dialog, title, message, kind, buttons).blocking_show_with_result.to_s
          end
        end

        # Shows a Yes and No dialog and settles +invoke+ with whether the
        # user said yes (commands.rs:309-338).
        #
        # === Example
        #
        #   Commands.ask(invoke, handle.dialog)
        def self.ask(invoke, dialog)
          args = arguments(invoke.payload, "ask")
          title = args.optional_string("title")
          message = args.string("message")
          kind = args.kind("kind")
          buttons = ask_buttons(args.optional_string("yesButtonLabel"), args.optional_string("noButtonLabel"))
          spawn(invoke) { message_dialog(dialog, title, message, kind, buttons).blocking_show }
        end

        # Shows an Ok and Cancel dialog and settles +invoke+ with whether
        # the user said Ok (commands.rs:340-369).
        #
        # === Example
        #
        #   Commands.confirm(invoke, handle.dialog)
        def self.confirm(invoke, dialog)
          args = arguments(invoke.payload, "confirm")
          title = args.optional_string("title")
          message = args.string("message")
          kind = args.kind("kind")
          buttons = confirm_buttons(args.optional_string("okButtonLabel"), args.optional_string("cancelButtonLabel"))
          spawn(invoke) { message_dialog(dialog, title, message, kind, buttons).blocking_show }
        end

        # The message command's buttons: the ones given, else a custom Ok
        # label, else Ok (commands.rs:300-304).
        #
        # === Example
        #
        #   Commands.message_buttons(nil, "Fine")  #=> MessageDialogButtons::OkCustom.new(ok: "Fine")
        def self.message_buttons(buttons, ok_button_label)
          return buttons if buttons
          return MessageDialogButtons::OkCustom.new(ok: ok_button_label) if ok_button_label

          MessageDialogButtons::Ok
        end

        # The ask command's buttons: custom when either label is given,
        # with "Yes" and "No" filling in, else YesNo (commands.rs:325-334).
        #
        # === Example
        #
        #   Commands.ask_buttons("Sure", nil)  #=> MessageDialogButtons::OkCancelCustom.new(ok: "Sure", cancel: "No")
        def self.ask_buttons(yes_button_label, no_button_label)
          if yes_button_label
            MessageDialogButtons::OkCancelCustom.new(ok: yes_button_label, cancel: no_button_label || "No")
          elsif no_button_label
            MessageDialogButtons::OkCancelCustom.new(ok: "Yes", cancel: no_button_label)
          else
            MessageDialogButtons::YesNo
          end
        end

        # The confirm command's buttons: custom when either label is given,
        # with "Ok" and "Cancel" filling in, else OkCancel
        # (commands.rs:356-365).
        #
        # === Example
        #
        #   Commands.confirm_buttons(nil, "Stop")  #=> MessageDialogButtons::OkCancelCustom.new(ok: "Ok", cancel: "Stop")
        def self.confirm_buttons(ok_button_label, cancel_button_label)
          if ok_button_label
            MessageDialogButtons::OkCancelCustom.new(ok: ok_button_label, cancel: cancel_button_label || "Cancel")
          elsif cancel_button_label
            MessageDialogButtons::OkCancelCustom.new(ok: "Ok", cancel: cancel_button_label)
          else
            MessageDialogButtons::OkCancel
          end
        end

        # Points +builder+ at +default_path+ (commands.rs:100-120).
        #
        # The path is first normalized the way Rust's
        # <tt>Path::components</tt> collects it, which also fixes the
        # separators on Windows. An existing file, or a path that does not
        # exist, splits into the starting folder and file name; a path with
        # no file name, or an existing folder, is the starting folder.
        # Returns the builder.
        #
        # === Example
        #
        #   Commands.set_default_path(handle.dialog.file, "~/notes/todo.txt")
        def self.set_default_path(builder, default_path)
          root, parts = components(default_path)
          path = join(root, parts)
          return builder.set_directory(path) unless File.file?(path) || !File.exist?(path)

          file_name = parts.last unless [nil, ".", ".."].include?(parts.last)
          return builder.set_directory(path) if parts.empty? || file_name.nil?

          parent_parts = parts[0...-1] || []
          builder.set_directory(join(root, parent_parts)) unless root.empty? && parent_parts.empty?
          builder.set_file_name(file_name)
        end

        # +path+ with a <tt>\\?\</tt> prefix dropped where Windows allows
        # it, as <tt>FilePath::simplified</tt> does with dunce
        # (tauri-plugin-fs file_path.rs:61-69, dunce src/lib.rs:53-60).
        # Everywhere but Windows, +path+ unchanged.
        #
        # === Example
        #
        #   Commands.simplified("\\\\?\\C:\\Users\\me")  #=> "C:\\Users\\me" on Windows
        def self.simplified(path)
          return path unless path && Gem.win_platform? && Dunce.safe_to_strip_unc?(path)

          path.byteslice(4..) || path
        end

        # The reader for one command's arguments.
        private_class_method def self.arguments(payload, command)
          Arguments.new(payload, command)
        end

        # Runs +work+ on a new thread and settles +invoke+ with its value,
        # or rejects with the message of what it raised. Returns +true+.
        private_class_method def self.spawn(invoke, &work)
          Thread.new do
            invoke.resolve(work.call)
          rescue => e
            invoke.reject(e.message)
          end
          true
        end

        # The open command's dialog, after Tauri's order of options
        # (commands.rs:128-217).
        private_class_method def self.open_dialog(dialog, options)
          builder = dialog.file
          title = options.title
          default_path = options.default_path
          can_create_directories = options.can_create_directories
          picker_mode = options.picker_mode
          file_access_mode = options.file_access_mode
          builder.set_title(title) if title
          set_default_path(builder, default_path) if default_path
          builder.set_can_create_directories(can_create_directories) unless can_create_directories.nil?
          builder.set_picker_mode(picker_mode) if picker_mode
          options.filters.each { |filter| builder.add_filter(filter.name, filter.extensions) }
          builder.set_file_access_mode(file_access_mode) if file_access_mode

          if options.directory
            options.multiple ? simplify_all(builder.blocking_pick_folders) : simplified(builder.blocking_pick_folder)
          elsif options.multiple
            simplify_all(builder.blocking_pick_files)
          else
            simplified(builder.blocking_pick_file)
          end
        end

        # The save command's dialog (commands.rs:228-259).
        private_class_method def self.save_dialog(dialog, options)
          builder = dialog.file
          title = options.title
          default_path = options.default_path
          can_create_directories = options.can_create_directories
          builder.set_title(title) if title
          set_default_path(builder, default_path) if default_path
          builder.set_can_create_directories(can_create_directories) unless can_create_directories.nil?
          options.filters.each { |filter| builder.add_filter(filter.name, filter.extensions) }
          simplified(builder.blocking_save_file)
        end

        # The builder every message command shares (commands.rs:262-288).
        private_class_method def self.message_dialog(dialog, title, message, kind, buttons)
          builder = dialog.message(message).buttons(buttons)
          builder.title(title) if title
          builder.kind(kind) if kind
          builder
        end

        # Each of +paths+ simplified, or +nil+ (commands.rs:170-171, 203).
        private_class_method def self.simplify_all(paths)
          paths&.map { |path| simplified(path) }
        end

        # The root (a Windows prefix and separator, or "/") and the other
        # components of +path+, as Rust's Path::components yields them:
        # repeated and trailing separators go, and so does "." after the
        # start.
        private_class_method def self.components(path)
          windows = Gem.win_platform?
          separator = windows ? %r{[\\/]+} : %r{/+}
          prefix = windows ? path[/\A(?:\\\\\?\\[^\\]+|\\\\[^\\]+\\[^\\]+|[A-Za-z]:)/].to_s : ""
          rest = path[(prefix.length)..] || ""
          root = prefix + (rest.match?(/\A#{separator}/o) ? File::SEPARATOR : "")
          root = root.tr("/", "\\") if windows
          parts = rest.split(separator).reject(&:empty?)
          parts = parts.each_with_index.reject { |part, index| part == "." && !(index.zero? && root.empty?) }.map(&:first)
          [root, parts]
        end

        # The path for +root+ and +parts+, joined with the platform's
        # separator.
        private_class_method def self.join(root, parts)
          root + parts.join(Gem.win_platform? ? "\\" : "/")
        end
      end
    end
  end
end

# SPDX-SnippetEnd
