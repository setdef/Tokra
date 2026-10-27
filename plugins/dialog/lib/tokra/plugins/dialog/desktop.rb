# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Dialog, WindowHandle, and the dialog functions adapted
#                      from tauri-plugin-dialog src/desktop.rs; DialogExt and
#                      blocking_fn! from src/lib.rs

module Tokra
  module Plugins
    module Dialog
      # The dialogs an app shares through managed state.
      #
      # Commands, menu handlers, and setup code all open dialogs, and each
      # needs the app handle to start one on the main thread, where the
      # system runs them.
      #
      # The plugin manages one Dialog at registration, so every manager
      # reaches it as +dialog+. Ask it for a builder: #message for a
      # message, ask, or confirm dialog, #file for an open or save dialog.
      #
      # Mirrors Tauri's desktop <tt>Dialog</tt> (desktop.rs:18-39) and its
      # builder constructors (lib.rs:90-182).
      #
      # === Examples
      #
      #   handle.dialog.message("Saved").show { |_ok| puts "closed" }
      #   handle.dialog.file.add_filter("Text", ["txt"]).pick_file { |path| puts path.inspect }
      class Dialog
        # The app handle the dialogs start through.
        attr_reader :app_handle

        # Creates the dialogs for +app_handle+. The plugin does this once
        # and manages the result (desktop.rs:18-23).
        #
        # [app_handle] the Tokra::AppHandle dialogs start through.
        def initialize(app_handle)
          @app_handle = app_handle
        end

        # A builder for a message dialog showing +message+, titled with the
        # app's product name (lib.rs:170-176).
        #
        # *Deviation*: Tauri titles it with the package name, which falls
        # back to the crate's name. Tokra has no package name yet, so an app
        # without a product name gets an empty title.
        #
        # === Example
        #
        #   handle.dialog.message("Are you sure?").buttons(MessageDialogButtons::YesNo).show { |yes| p yes }
        def message(message)
          MessageDialogBuilder.new(self, @app_handle.config.product_name || "", message)
        end

        # A builder for a dialog that picks files or folders, or a place to
        # save one (lib.rs:178-181).
        #
        # === Example
        #
        #   handle.dialog.file.set_title("Export").save_file { |path| export(path) if path }
        def file
          FileDialogBuilder.new(self)
        end
      end

      # Gives every manager a +dialog+ method.
      #
      # When included into Tokra::Manager, an app handle, window, or webview
      # reaches the managed Dialog directly:
      #
      #   handle.dialog.message("Hello").show { |_| }
      #
      # Mirrors Tauri's <tt>DialogExt</tt> blanket implementation
      # (lib.rs:79-88).
      module DialogExt
        # The Dialog in managed state.
        #
        # === Example
        #
        #   window.dialog.file.pick_folder { |folder| p folder }
        def dialog
          state(Dialog)
        end
      end

      # How a dialog runs: started on the main thread, awaited on another.
      #
      # AppKit runs dialogs on the main thread, and on macOS a sheet
      # finishes only while that thread keeps running its event loop. Tokra
      # runs that loop holding the GVL (ADR 012), so nothing may wait for
      # the user there.
      #
      # Each function sends the start to the main thread with
      # +run_on_main_thread+, which runs it at once when already there. On
      # the main thread, rfd's async dialog opens (on macOS as a sheet) and
      # returns a Ferro::Rfd::Future; a new thread waits on the future,
      # without the GVL, and calls the callback with the answer. These are
      # the functions of Tauri's private +desktop+ module (desktop.rs).
      #
      # Each takes +failed+, a callable for a Failure, or +nil+. With one,
      # an exception from rfd reaches it; without one it ends the waiting
      # thread, as a panic ends Tauri's. A start the event loop can no
      # longer take is dropped, as Tauri's <tt>let _ =</tt> drops it, and
      # reported to +failed+.
      module Desktop
        # An exception carried from the thread that waited on rfd to the
        # caller blocked on the answer.
        Failure = Data.define(:error)

        # A parent window's raw handles, taken when the parent was set
        # (desktop.rs:51-80), as the ferro-rfd values its +set_parent+
        # reads back.
        #
        # A Tokra::Window answers with Tokra::RawWindowHandle values, and
        # ferro-rfd takes only its own, so each kind ferro-rfd binds is
        # copied into ferro-rfd's: a Win32 window on Windows, an Xlib one
        # on X11. ferro-rfd binds no AppKit or Wayland handle, since rfd
        # follows those as pointers and an Integer from Ruby could point
        # anywhere (ADR 013), so a parent that names one is no parent.
        class WindowHandle < Data.define(:window_handle, :display_handle)
          ##
          # :attr_reader: window_handle
          # The parent's ferro-rfd window handle.

          ##
          # :attr_reader: display_handle
          # The parent's ferro-rfd display handle.

          # The handles of +parent+, an object that answers +window_handle+
          # and +display_handle+, such as a Tokra::Window; or +nil+ when
          # either answers +nil+ or raises
          # Tokra::RawWindowHandle::HandleError, as Tauri keeps a parent only
          # when both handles are <tt>Ok</tt> (lib.rs:287-302, 460-478), or
          # when ferro-rfd cannot take the kind.
          #
          # === Example
          #
          #   Desktop::WindowHandle.of(window)  #=> a WindowHandle on Windows and X11, nil on macOS
          def self.of(parent)
            window_handle = rfd_window_handle(parent.window_handle)
            display_handle = rfd_display_handle(parent.display_handle)
            new(window_handle:, display_handle:) if window_handle && display_handle
          rescue Tokra::RawWindowHandle::HandleError
            nil
          end

          # ferro-rfd's value for +handle+: a copy of a Tokra handle it
          # binds, +nil+ for one it does not, and its own values as they
          # are.
          private_class_method def self.rfd_window_handle(handle)
            case handle
            when Tokra::RawWindowHandle::Win32WindowHandle
              Ferro::Rfd::Win32WindowHandle.new(hwnd: handle.hwnd, hinstance: handle.hinstance)
            when Tokra::RawWindowHandle::XlibWindowHandle
              Ferro::Rfd::XlibWindowHandle.new(window: handle.window, visual_id: handle.visual_id)
            when Tokra::RawWindowHandle::AppKitWindowHandle, Tokra::RawWindowHandle::WaylandWindowHandle then nil
            else handle
            end
          end

          # ferro-rfd's value for the display +handle+, as for a window.
          private_class_method def self.rfd_display_handle(handle)
            case handle
            when Tokra::RawWindowHandle::WindowsDisplayHandle then Ferro::Rfd::WindowsDisplayHandle.new
            when Tokra::RawWindowHandle::XlibDisplayHandle
              Ferro::Rfd::XlibDisplayHandle.new(display: handle.display, screen: handle.screen)
            when Tokra::RawWindowHandle::AppKitDisplayHandle, Tokra::RawWindowHandle::WaylandDisplayHandle then nil
            else handle
            end
          end
        end

        # Picks one file; the callback gets its path or +nil+
        # (desktop.rs:142-152).
        #
        # === Example
        #
        #   Desktop.pick_file(builder, nil) { |path| p path }
        def self.pick_file(builder, failed = nil, &callback)
          rfd = builder.to_async_file_dialog
          start(builder.dialog, failed, -> { rfd.pick_file }) do |handle|
            callback.call(handle&.path)
          end
        end

        # Picks several files; the callback gets their paths or +nil+
        # (desktop.rs:154-170).
        #
        # === Example
        #
        #   Desktop.pick_files(builder, nil) { |paths| p paths }
        def self.pick_files(builder, failed = nil, &callback)
          rfd = builder.to_async_file_dialog
          start(builder.dialog, failed, -> { rfd.pick_files }) do |handles|
            callback.call(handles&.map(&:path))
          end
        end

        # Picks one folder; the callback gets its path or +nil+
        # (desktop.rs:172-182).
        #
        # === Example
        #
        #   Desktop.pick_folder(builder, nil) { |path| p path }
        def self.pick_folder(builder, failed = nil, &callback)
          rfd = builder.to_async_file_dialog
          start(builder.dialog, failed, -> { rfd.pick_folder }) do |handle|
            callback.call(handle&.path)
          end
        end

        # Picks several folders; the callback gets their paths or +nil+
        # (desktop.rs:184-200).
        #
        # === Example
        #
        #   Desktop.pick_folders(builder, nil) { |paths| p paths }
        def self.pick_folders(builder, failed = nil, &callback)
          rfd = builder.to_async_file_dialog
          start(builder.dialog, failed, -> { rfd.pick_folders }) do |handles|
            callback.call(handles&.map(&:path))
          end
        end

        # Asks where to save a file; the callback gets the path or +nil+
        # (desktop.rs:202-212).
        #
        # === Example
        #
        #   Desktop.save_file(builder, nil) { |path| p path }
        def self.save_file(builder, failed = nil, &callback)
          rfd = builder.to_async_file_dialog
          start(builder.dialog, failed, -> { rfd.save_file }) do |handle|
            callback.call(handle&.path)
          end
        end

        # Shows a message dialog with +buttons+; the callback gets the
        # MessageDialogResult (desktop.rs:214-257).
        #
        # === Example
        #
        #   Desktop.show_message_dialog(builder, MessageDialogButtons::Ok) { |result| p result }
        def self.show_message_dialog(builder, buttons, failed = nil, &callback)
          rfd = builder.to_async_message_dialog
          start(builder.dialog, failed, -> { rfd.show }) do |result|
            callback.call(message_dialog_result(result, buttons))
          end
        end

        # The MessageDialogResult for rfd's +result+ from a dialog with
        # +buttons+.
        #
        # rfd answers some dialogs with custom labels with a standard
        # result: on Linux, and on Windows without common-controls-v6 (as
        # ferro-rfd builds it). Tauri maps those back to the label of the
        # button pressed (desktop.rs:227-253), so a dialog with custom
        # buttons always answers with one of its labels.
        #
        # === Example
        #
        #   Desktop.message_dialog_result(Ferro::Rfd::MessageDialogResult::Ok,
        #     MessageDialogButtons::OkCustom.new(ok: "Fine"))  #=> MessageDialogResult::Custom.new(label: "Fine")
        def self.message_dialog_result(result, buttons)
          rfd = Ferro::Rfd::MessageDialogResult
          label = case buttons
          when MessageDialogButtons::OkCustom then buttons.ok if result == rfd::Ok
          when MessageDialogButtons::OkCancelCustom
            { rfd::Ok => buttons.ok, rfd::Cancel => buttons.cancel }[result]
          when MessageDialogButtons::YesNoCancelCustom
            { rfd::Yes => buttons.yes, rfd::No => buttons.no, rfd::Cancel => buttons.cancel }[result]
          end
          label ? MessageDialogResult::Custom.new(label:) : MessageDialogResult.from_rfd(result)
        end

        # Waits for the answer a function gives its callback, and returns
        # it, raising the Failure's error instead. Yields the callable that
        # takes the answer, to pass as both callback and +failed+.
        #
        # Mirrors the <tt>blocking_fn!</tt> macro (lib.rs:68-77), whose
        # caller panics when the answer never comes; here it raises.
        #
        # === Example
        #
        #   path = Desktop.blocking { |respond| Desktop.pick_file(builder, respond, &respond) }
        def self.blocking
          queue = Thread::Queue.new
          yield -> (response) { queue << response }
          response = queue.pop
          raise response.error if response.is_a?(Failure)

          response
        end

        # Sends +open+ to the main thread and a thread to wait on the
        # future it returns, which hands the value to +deliver+.
        #
        # With +failed+, a caller waits for the answer, so the start goes
        # as a RuntimeContext getter: whatever +open+ raises, and a loop
        # that ends before or while the start waits for it, reach +failed+
        # instead of leaving the caller waiting forever. Without it, the
        # start goes as +run_on_main_thread+ and a dropped start is ignored,
        # as Tauri ignores it.
        private_class_method def self.start(dialog, failed, open, &deliver)
          begin_dialog = lambda do
            future = open.call
            Thread.new { await(future, failed, &deliver) }
            nil
          end
          if failed
            begin
              dialog.app_handle.runtime_context.getter(&begin_dialog)
            rescue => e
              failed.call(Failure.new(error: e))
            end
          else
            dialog.app_handle.run_on_main_thread(&begin_dialog)
          end
          nil
        rescue Tokra::Error::Runtime
          nil
        end

        # Waits on +future+ off the main thread, where Future#value releases
        # the GVL, and delivers its value.
        private_class_method def self.await(future, failed)
          value = future.value
        rescue => e
          raise unless failed

          failed.call(Failure.new(error: e))
        else
          yield value
        end
      end
    end
  end
end

# SPDX-SnippetEnd
