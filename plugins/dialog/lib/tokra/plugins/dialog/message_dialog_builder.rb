# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: MessageDialogBuilder adapted from tauri-plugin-dialog
#                      src/lib.rs:214-369 and its AsyncMessageDialog
#                      conversion from src/desktop.rs:126-140

module Tokra
  module Plugins
    module Dialog
      # Builds a message dialog: a message, ask, or confirm dialog.
      #
      # An app tells the user things and asks them things: a job finished,
      # a file could not be saved, a change cannot be undone. The system's
      # own dialog is the one they recognize.
      #
      # Get one from Dialog#message, set its title, kind, and buttons, and
      # show it. #show answers whether the user pressed Ok or Yes;
      # #show_with_result answers which button they pressed.
      #
      # === Threads
      #
      # #show and #show_with_result return at once and call your block
      # later, on another thread. Use them anywhere, including the main
      # thread. #blocking_show and #blocking_show_with_result wait for the
      # user; do not call them on the main thread, where they freeze the app
      # (on macOS, forever).
      #
      # #show and the others read the builder's settings when you call them,
      # as Tauri's consume the builder then: changing the builder afterwards
      # leaves a dialog already shown as it was.
      #
      # === Parent window
      #
      # Tauri's commands show their dialog over the calling window. Tokra's
      # windows cannot name their native handle yet, so the plugin's
      # commands pass none. On macOS a message dialog without a parent is a
      # system alert of its own rather than a sheet on the window; on
      # Windows and X11 the window still takes input behind it. #parent
      # takes a parent you can name yourself.
      #
      # Mirrors Tauri's <tt>MessageDialogBuilder</tt> (lib.rs:214-369).
      #
      # === Examples
      #
      #   handle.dialog.message("Tauri is Awesome!").show { |_ok| puts "dialog closed" }
      #
      #   handle.dialog.message("Are you sure?")
      #     .buttons(MessageDialogButtons::OkCancelCustom.new(ok: "Yes", cancel: "No"))
      #     .show { |yes| puts "user said #{yes ? 'yes' : 'no'}" }
      #
      #   Thread.new do
      #     yes = handle.dialog.message("Are you sure?").buttons(MessageDialogButtons::YesNo).blocking_show
      #   end
      class MessageDialogBuilder
        # The Dialog that made this builder.
        attr_reader :dialog

        # Creates a builder for a dialog titled +title+ that shows
        # +message+, with the Info kind and an Ok button (lib.rs:243-254).
        #
        # [dialog] the Dialog it starts through.
        # [title] the dialog's title.
        # [message] the text it shows.
        def initialize(dialog, title, message)
          @dialog = dialog
          @title = title
          @message = message
          @kind = MessageDialogKind.default
          @buttons = MessageDialogButtons.default
          @parent = nil
        end

        # Sets the dialog's title. Returns the builder.
        #
        # === Example
        #
        #   handle.dialog.message("Saved").title("Export")
        def title(title)
          @title = title
          self
        end

        # Sets the parent window: any object whose +window_handle+ and
        # +display_handle+ return ferro-rfd handle values. Kept only when
        # both answer, as Tauri keeps a parent only when it has both handles
        # (lib.rs:287-302). Returns the builder.
        #
        # === Example
        #
        #   Parent = Data.define(:window_handle, :display_handle)
        #   builder.parent(Parent.new(Ferro::Rfd::Win32WindowHandle.new(hwnd: hwnd, hinstance: nil),
        #     Ferro::Rfd::WindowsDisplayHandle.new))
        def parent(parent)
          window_handle = parent.window_handle
          display_handle = parent.display_handle
          @parent = Desktop::WindowHandle.new(window_handle:, display_handle:) if window_handle && display_handle
          self
        end

        # Sets the buttons, a MessageDialogButtons. Returns the builder.
        #
        # === Example
        #
        #   builder.buttons(MessageDialogButtons::YesNoCancel)
        def buttons(buttons)
          @buttons = buttons
          self
        end

        # Sets the kind, a MessageDialogKind. Depending on the system, it
        # shows a matching icon that tells the user whether the message is
        # an error, a warning, or information. Returns the builder.
        #
        # === Example
        #
        #   builder.kind(MessageDialogKind::Error)
        def kind(kind)
          @kind = kind
          self
        end

        # Shows the dialog and returns at once. The block gets +true+ when
        # the user pressed Ok or Yes, or the custom label in the Ok or Yes
        # place (lib.rs:319-341).
        #
        # === Example
        #
        #   builder.show { |ok| delete_all if ok }
        def show(&block)
          buttons = @buttons
          Desktop.show_message_dialog(self, buttons) { |result| block.call(self.class.__send__(:success?, result, buttons)) }
          nil
        end

        # Shows the dialog and returns at once. The block gets the
        # MessageDialogResult for the button pressed (lib.rs:343-348).
        #
        # === Example
        #
        #   builder.show_with_result { |result| puts result }
        def show_with_result(&)
          Desktop.show_message_dialog(self, @buttons, &)
          nil
        end

        # Shows the dialog and waits for the user. Returns +true+ when they
        # pressed Ok or Yes (lib.rs:350-358). Raises what rfd raised.
        #
        # This blocks, so do not call it on the main thread.
        #
        # === Example
        #
        #   Thread.new { save if builder.blocking_show }
        def blocking_show
          buttons = @buttons
          Desktop.blocking do |respond|
            Desktop.show_message_dialog(self, buttons, respond) do |result|
              respond.call(self.class.__send__(:success?, result, buttons))
            end
          end
        end

        # Shows the dialog and waits for the user. Returns the
        # MessageDialogResult for the button pressed (lib.rs:360-368).
        # Raises what rfd raised.
        #
        # This blocks, so do not call it on the main thread.
        #
        # === Example
        #
        #   Thread.new { puts builder.blocking_show_with_result }
        def blocking_show_with_result
          Desktop.blocking { |respond| Desktop.show_message_dialog(self, @buttons, respond, &respond) }
        end

        # The ferro-rfd dialog this builder describes (desktop.rs:126-140).
        #
        # === Example
        #
        #   builder.to_async_message_dialog.show
        def to_async_message_dialog
          dialog = Ferro::Rfd::AsyncMessageDialog.new
            .set_title(@title)
            .set_description(@message)
            .set_level(@kind.to_message_level)
            .set_buttons(@buttons.to_message_buttons)
          parent = @parent
          dialog.set_parent(parent) if parent
          dialog
        end

        # Whether +result+ counts as Ok for a dialog with +buttons+: Ok and
        # Yes do, and so does a custom label equal to the Ok or Yes label,
        # or to "Ok" when the buttons have none (lib.rs:323-337).
        private_class_method def self.success?(result, buttons)
          ok_label = case buttons
          when MessageDialogButtons::OkCustom, MessageDialogButtons::OkCancelCustom then buttons.ok
          when MessageDialogButtons::YesNoCancelCustom then buttons.yes
          end
          case result
          when MessageDialogResult::Ok, MessageDialogResult::Yes then true
          when MessageDialogResult::Custom then result.label == (ok_label || MessageDialogResult::Ok.name)
          else false
          end
        end
      end
    end
  end
end

# SPDX-SnippetEnd
