# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Submenu adapted from tauri/crates/tauri/src/menu/submenu.rs

module Tokra
  module Menu
    # A titled group of items inside a Menu or another Submenu: File,
    # Edit, Window.
    #
    # Mirrors Tauri's Submenu (menu/submenu.rs). Its icons and its
    # context-menu methods are not ported yet (plan 042, phases 2 and 3).
    #
    # === Example
    #
    #   edit = Tokra::Menu::Submenu.with_items(app, "Edit", true, [
    #     Tokra::Menu::PredefinedMenuItem.copy(app, nil),
    #     Tokra::Menu::PredefinedMenuItem.paste(app, nil),
    #   ])
    class Submenu
      include IsMenuItem
      include MenuTree

      class << self
        # A new, empty submenu titled +text+, enabled or not, with an id
        # muda makes up.
        def new(manager, text, enabled)
          submenu = Tokra::Menu.natives(manager).submenu
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) { from_native(handle, submenu.new(text, enabled)) }
        end

        # A new, empty submenu with the id +id+, a String or a MenuId.
        def with_id(manager, id, text, enabled)
          submenu = Tokra::Menu.natives(manager).submenu
          value = MenuId.from(id).value
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) { from_native(handle, submenu.with_id(value, text, enabled)) }
        end

        # A new submenu holding +items+.
        def with_items(manager, text, enabled, items)
          new(manager, text, enabled).tap { |submenu| submenu.append_items(items) }
        end

        # A new submenu with the id +id+, holding +items+.
        def with_id_and_items(manager, id, text, enabled, items)
          with_id(manager, id, text, enabled).tap { |submenu| submenu.append_items(items) }
        end

        # The Submenu that wraps +native+, for +app_handle+.
        def from_native(app_handle, native) # :nodoc:
          submenu = allocate
          submenu.__send__(:initialize_wrapper, app_handle, native, MenuId.new(value: native.id))
          submenu
        end
      end

      # The submenu's title.
      def text
        native = @native #: Native::Submenu
        run_item_main_thread { native.text }
      end

      # Sets the submenu's title and returns +nil+.
      def set_text(text)
        native = @native #: Native::Submenu
        run_item_main_thread { native.set_text(text) }
        nil
      end

      # Whether the submenu can be opened.
      def is_enabled
        native = @native #: Native::Submenu
        run_item_main_thread { native.is_enabled }
      end

      # Lets the submenu be opened, or not, and returns +nil+.
      def set_enabled(enabled)
        native = @native #: Native::Submenu
        run_item_main_thread { native.set_enabled(enabled) }
        nil
      end

      if Native.respond_to?(:set_windows_menu_for_nsapp)
        # Makes this submenu NSApp's Window menu, where macOS lists the
        # app's open windows, and returns +nil+. macOS only.
        #
        # Mirrors Tauri's Submenu::set_as_windows_menu_for_nsapp
        # (menu/submenu.rs:400-405).
        def set_as_windows_menu_for_nsapp
          native = @native #: Native::Submenu
          app = Tokra::Menu.natives(@app_handle).app
          run_item_main_thread { app.set_windows_menu_for_nsapp(native) }
          nil
        end

        # Makes this submenu NSApp's Help menu, where macOS adds its help
        # search, and returns +nil+. macOS only.
        #
        # Mirrors Tauri's Submenu::set_as_help_menu_for_nsapp
        # (menu/submenu.rs:414-419).
        def set_as_help_menu_for_nsapp
          native = @native #: Native::Submenu
          app = Tokra::Menu.natives(@app_handle).app
          run_item_main_thread { app.set_help_menu_for_nsapp(native) }
          nil
        end
      end
    end
  end
end

# SPDX-SnippetEnd
