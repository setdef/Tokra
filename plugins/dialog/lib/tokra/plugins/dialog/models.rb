# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: MessageDialogKind, MessageDialogButtons, and
#                      MessageDialogResult adapted from
#                      tauri-plugin-dialog src/models.rs; PickerMode and
#                      FileAccessMode from src/lib.rs:47-61

module Tokra
  module Plugins
    module Dialog
      # The kind of a message, ask, or confirm dialog.
      #
      # A dialog that reports a failure should look different from one that
      # shares good news. Each system marks the difference with an icon,
      # and sometimes a sound.
      #
      # Pass one of the three kinds to MessageDialogBuilder#kind and the
      # system picks the matching icon. Info is the default.
      #
      # Mirrors Tauri's <tt>MessageDialogKind</tt> (models.rs:7-46), which
      # serializes as +info+, +warning+, or +error+.
      #
      # === Examples
      #
      #   handle.dialog.message("Disk almost full").kind(MessageDialogKind::Warning)
      #   MessageDialogKind::Error.to_s  #=> "error"
      class MessageDialogKind < Data.define(:name)
        ##
        # Information dialog.
        Info = new(name: "info")
        # Warning dialog.
        Warning = new(name: "warning")
        # Error dialog.
        Error = new(name: "error")

        # The default kind, Info (models.rs:11-13).
        #
        # === Example
        #
        #   MessageDialogKind.default  #=> MessageDialogKind::Info
        def self.default
          Info
        end

        # The kind as Tauri serializes it: +info+, +warning+, or +error+.
        #
        # === Example
        #
        #   MessageDialogKind::Warning.to_s  #=> "warning"
        def to_s
          name
        end

        # rfd's level for this kind (desktop.rs:41-49).
        #
        # === Example
        #
        #   MessageDialogKind::Warning.to_message_level  #=> Ferro::Rfd::MessageLevel::Warning
        def to_message_level
          Ferro::Rfd::MessageLevel.const_get(name.capitalize, false)
        end
      end

      # The buttons a message dialog shows.
      #
      # A dialog that only informs needs one button. A dialog that asks
      # needs two or three, and the words on them matter: "Save" and
      # "Discard" say more than "Ok" and "Cancel".
      #
      # The four constants show the system's own labels. The three custom
      # classes carry your labels. Ok is the default.
      #
      # Mirrors Tauri's <tt>MessageDialogButtons</tt> (models.rs:48-67).
      #
      # === Examples
      #
      #   builder.buttons(MessageDialogButtons::YesNo)
      #   builder.buttons(MessageDialogButtons::OkCancelCustom.new(ok: "Save", cancel: "Discard"))
      class MessageDialogButtons < Data.define(:name)
        ##
        # A single +Ok+ button with the system's text.
        Ok = new(name: "Ok")
        # +Ok+ and +Cancel+ buttons with the system's texts.
        OkCancel = new(name: "OkCancel")
        # +Yes+ and +No+ buttons with the system's texts.
        YesNo = new(name: "YesNo")
        # +Yes+, +No+, and +Cancel+ buttons with the system's texts.
        YesNoCancel = new(name: "YesNoCancel")

        # A single +Ok+ button with custom text.
        #
        # === Example
        #
        #   MessageDialogButtons::OkCustom.new(ok: "Got it")
        class OkCustom < Data.define(:ok)
          # rfd's buttons with the same label (desktop.rs:116).
          #
          # === Example
          #
          #   OkCustom.new(ok: "Fine").to_message_buttons  #=> Ferro::Rfd::MessageButtons::OkCustom.new("Fine")
          def to_message_buttons
            Ferro::Rfd::MessageButtons::OkCustom.new(ok)
          end
        end

        # +Ok+ and +Cancel+ buttons with custom texts.
        #
        # === Example
        #
        #   MessageDialogButtons::OkCancelCustom.new(ok: "Save", cancel: "Discard")
        class OkCancelCustom < Data.define(:ok, :cancel)
          # rfd's buttons with the same labels (desktop.rs:117).
          #
          # === Example
          #
          #   OkCancelCustom.new(ok: "Save", cancel: "Discard").to_message_buttons
          def to_message_buttons
            Ferro::Rfd::MessageButtons::OkCancelCustom.new(ok, cancel)
          end
        end

        # +Yes+, +No+, and +Cancel+ buttons with custom texts.
        #
        # === Example
        #
        #   MessageDialogButtons::YesNoCancelCustom.new(yes: "Show", no: "Open folder", cancel: "Cancel")
        class YesNoCancelCustom < Data.define(:yes, :no, :cancel)
          # rfd's buttons with the same labels (desktop.rs:119-121).
          #
          # === Example
          #
          #   YesNoCancelCustom.new(yes: "Y", no: "N", cancel: "C").to_message_buttons
          def to_message_buttons
            Ferro::Rfd::MessageButtons::YesNoCancelCustom.new(yes, no, cancel)
          end
        end

        # The default buttons, Ok (models.rs:52-54).
        #
        # === Example
        #
        #   MessageDialogButtons.default  #=> MessageDialogButtons::Ok
        def self.default
          Ok
        end

        # rfd's buttons with the system's labels (desktop.rs:110-124).
        #
        # === Example
        #
        #   MessageDialogButtons::YesNo.to_message_buttons  #=> Ferro::Rfd::MessageButtons::YesNo
        def to_message_buttons
          Ferro::Rfd::MessageButtons.const_get(name, false)
        end
      end

      # The button the user pressed in a message dialog.
      #
      # A dialog with standard buttons answers with one of the four
      # constants. A dialog with custom labels answers with a Custom
      # carrying the label the user pressed.
      #
      # Mirrors Tauri's <tt>MessageDialogResult</tt> (models.rs:69-104).
      # It serializes as the variant's name, or the custom label, which is
      # what the frontend's <tt>message()</tt> resolves.
      #
      # === Examples
      #
      #   handle.dialog.message("Saved").show_with_result { |result| puts result }  # prints "Ok"
      #   MessageDialogResult::Custom.new(label: "Discard").to_s  #=> "Discard"
      class MessageDialogResult < Data.define(:name)
        ##
        # The user pressed Yes.
        Yes = new(name: "Yes")
        # The user pressed No.
        No = new(name: "No")
        # The user pressed Ok.
        Ok = new(name: "Ok")
        # The user pressed Cancel or closed the dialog.
        Cancel = new(name: "Cancel")

        # The user pressed the button with this custom label.
        #
        # === Example
        #
        #   MessageDialogResult::Custom.new(label: "Save").to_s  #=> "Save"
        class Custom < Data.define(:label)
          # The label, as Tauri serializes the untagged variant.
          #
          # === Example
          #
          #   MessageDialogResult::Custom.new(label: "Save").to_s  #=> "Save"
          def to_s
            label
          end
        end

        # The default result, Cancel (models.rs:75-76).
        #
        # === Example
        #
        #   MessageDialogResult.default  #=> MessageDialogResult::Cancel
        def self.default
          Cancel
        end

        # The result for a button label: a standard name becomes its
        # constant, anything else a Custom (models.rs:94-104).
        #
        # === Example
        #
        #   MessageDialogResult.from("Yes")   #=> MessageDialogResult::Yes
        #   MessageDialogResult.from("Save")  #=> MessageDialogResult::Custom.new(label: "Save")
        def self.from(value)
          case value
          when "Yes" then Yes
          when "No" then No
          when "Ok" then Ok
          when "Cancel" then Cancel
          else Custom.new(label: value)
          end
        end

        # The result for rfd's +result+ (models.rs:81-92).
        #
        # === Example
        #
        #   MessageDialogResult.from_rfd(Ferro::Rfd::MessageDialogResult::Ok)  #=> MessageDialogResult::Ok
        def self.from_rfd(result)
          return Custom.new(label: result.custom) if result.is_a?(Ferro::Rfd::MessageDialogResult::Custom)

          const_get(result.to_s, false)
        end

        # The variant's name, as Tauri serializes it.
        #
        # === Example
        #
        #   MessageDialogResult::Ok.to_s  #=> "Ok"
        def to_s
          name
        end
      end

      # The picker a mobile file dialog shows.
      #
      # Phones keep photos and documents in different places, with a
      # picker for each. Desktops have one file dialog.
      #
      # Tokra runs on desktops, where FileDialogBuilder#set_picker_mode
      # keeps the mode and the dialog ignores it, as in Tauri.
      #
      # Mirrors Tauri's <tt>PickerMode</tt> (lib.rs:47-54).
      #
      # === Example
      #
      #   handle.dialog.file.set_picker_mode(PickerMode::Image)
      class PickerMode < Data.define(:name)
        ##
        # The document picker.
        Document = new(name: "document")
        # The media picker.
        Media = new(name: "media")
        # The image picker.
        Image = new(name: "image")
        # The video picker.
        Video = new(name: "video")
      end

      # How iOS hands a picked file to the app.
      #
      # iOS either copies a picked file into the app's sandbox or lends the
      # app the original under a security scope.
      #
      # Tokra runs on desktops, where FileDialogBuilder#set_file_access_mode
      # keeps the mode and the dialog ignores it, as in Tauri.
      #
      # Mirrors Tauri's <tt>FileAccessMode</tt> (lib.rs:56-61).
      #
      # === Example
      #
      #   handle.dialog.file.set_file_access_mode(FileAccessMode::Scoped)
      class FileAccessMode < Data.define(:name)
        ##
        # Copy the file into the app's sandbox.
        Copy = new(name: "copy")
        # Keep the file in place, with security-scoped access.
        Scoped = new(name: "scoped")
      end
    end
  end
end

# SPDX-SnippetEnd
