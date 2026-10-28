# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: PredefinedMenuItem adapted from tauri/crates/tauri/src/menu/predefined.rs

module Tokra
  module Menu
    # A menu item the platform already knows how to do: Copy, Paste, Quit,
    # Minimize, a separator.
    #
    # The platform runs it, so clicking one sends no MenuEvent. Each
    # constructor takes the title to show in place of the platform's, or
    # +nil+. Not every platform has every item: on Windows and Linux some
    # do nothing. On Linux the Copy, Cut, Paste, and Select All items work
    # under X11 through libxdo (plan 042, decision 2).
    #
    # Mirrors Tauri's PredefinedMenuItem (menu/predefined.rs).
    #
    # === Example
    #
    #   Tokra::Menu::PredefinedMenuItem.quit(app, "Quit Notes")
    class PredefinedMenuItem
      include IsMenuItem

      class << self
        # A line between items.
        def separator(manager)
          build(manager, "separator", nil)
        end

        # Copies the selection.
        def copy(manager, text)
          build(manager, "copy", text)
        end

        # Cuts the selection.
        def cut(manager, text)
          build(manager, "cut", text)
        end

        # Pastes.
        def paste(manager, text)
          build(manager, "paste", text)
        end

        # Selects everything.
        def select_all(manager, text)
          build(manager, "select_all", text)
        end

        # Undoes. macOS only.
        def undo(manager, text)
          build(manager, "undo", text)
        end

        # Redoes. macOS only.
        def redo(manager, text)
          build(manager, "redo", text)
        end

        # Minimizes the focused window.
        def minimize(manager, text)
          build(manager, "minimize", text)
        end

        # Maximizes the focused window.
        def maximize(manager, text)
          build(manager, "maximize", text)
        end

        # Makes the focused window full screen. macOS only.
        def fullscreen(manager, text)
          build(manager, "fullscreen", text)
        end

        # Hides the app.
        def hide(manager, text)
          build(manager, "hide", text)
        end

        # Hides every other app.
        def hide_others(manager, text)
          build(manager, "hide_others", text)
        end

        # Shows every app. macOS and Linux.
        def show_all(manager, text)
          build(manager, "show_all", text)
        end

        # Closes the focused window.
        def close_window(manager, text)
          build(manager, "close_window", text)
        end

        # Quits the app.
        def quit(manager, text)
          build(manager, "quit", text)
        end

        # Shows the About panel with +metadata+, an AboutMetadata or +nil+.
        # Raises Error::BadMenuIcon for an icon muda refuses.
        def about(manager, text, metadata)
          build(manager, "about", text, metadata&.to_native)
        end

        # The Services submenu. macOS only.
        def services(manager, text)
          build(manager, "services", text)
        end

        # The PredefinedMenuItem that wraps +native+, for +app_handle+.
        def from_native(app_handle, native) # :nodoc:
          item = allocate
          item.__send__(:initialize_wrapper, app_handle, native, MenuId.new(value: native.id))
          item
        end

        private def build(manager, kind, text, about = nil)
          item = Tokra::Menu.natives(manager).predefined_menu_item
          handle = manager.app_handle
          handle.runtime_context.run_main_thread do
            from_native(handle, item.new(kind, text, about))
          rescue RuntimeError => e
            raise unless e.instance_of?(RuntimeError)

            raise Error::BadMenuIcon, e.message
          end
        end
      end

      # The item's title.
      def text
        native = @native #: Native::PredefinedMenuItem
        run_item_main_thread { native.text }
      end

      # Sets the item's title and returns +nil+.
      def set_text(text)
        native = @native #: Native::PredefinedMenuItem
        run_item_main_thread { native.set_text(text) }
        nil
      end
    end
  end
end

# SPDX-SnippetEnd
