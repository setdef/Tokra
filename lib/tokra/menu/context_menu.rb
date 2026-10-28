# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: ContextMenu adapted from tauri/crates/tauri/src/menu/mod.rs,
#                      menu/menu.rs, and menu/submenu.rs

module Tokra
  module Menu
    # A Menu or a Submenu shown as a context menu: the menu that opens
    # where you right-click.
    #
    # An app that handles the page's +contextmenu+ event, or a button that
    # opens a menu, calls #popup to show the menu at the pointer, or
    # #popup_at to show it at a position in the window. Window#popup_menu
    # and Window#popup_menu_at do the same from the window's side. A click
    # on one of its items reaches the app's and the window's
    # +on_menu_event+ listeners, as a click in the menu bar does.
    #
    # The menu stays open until you choose an item or dismiss it, and the
    # call returns then. Meanwhile the main thread runs the menu, so the
    # app's events and the blocks sent to the main thread wait for it to
    # close, as they do in Tauri; other Ruby threads keep running (plan
    # 042, decision 15).
    #
    # Mirrors Tauri's ContextMenu trait (menu/mod.rs:730-757), which Menu
    # and Submenu implement (menu/menu.rs:23-80, menu/submenu.rs:16-73).
    # Only those two include it, as only they implement Tauri's sealed
    # trait.
    #
    # === Example
    #
    #   menu = Tokra::Menu::Menu.with_items(app, [
    #     Tokra::Menu::MenuItem.with_id(app, "copy-link", "Copy Link", true, nil),
    #   ])
    #   menu.popup(window)
    #   menu.popup_at(window, Tokra::LogicalPosition.new(x: 40, y: 60))
    module ContextMenu
      # Shows this menu as a context menu on +window+, a Window, at the
      # pointer, and returns +nil+ once it closes.
      #
      # It does nothing when +window+ has closed. From another thread the
      # call goes to the main thread and waits there for the menu to
      # close. On Linux a menu holding an item whose accelerator GTK has
      # no key for, a numpad or volume key, raises Error::Menu with muda's
      # words before it shows, where Tauri panics (plan 042, decision 18).
      #
      # Mirrors Tauri's ContextMenu::popup (menu/menu.rs:29-31).
      def popup(window)
        popup_inner(window, nil)
      end

      # Shows this menu as a context menu on +window+ with its top-left
      # corner at +position+, a LogicalPosition or a PhysicalPosition
      # relative to the window's top-left corner, and returns +nil+ once it
      # closes. Runs as #popup does; any other position raises TypeError.
      #
      # Mirrors Tauri's ContextMenu::popup_at (menu/menu.rs:33-39).
      def popup_at(window, position)
        popup_inner(window, position)
      end

      if Native::Menu.method_defined?(:hpopupmenu)
        # The Win32 +HMENU+ handle muda shows this menu with as a context
        # menu, as an Integer. It stays valid as long as this menu does.
        # Windows only.
        #
        # Mirrors Tauri's ContextMenu::hpopupmenu (menu/mod.rs:736-743,
        # menu/menu.rs:24-27).
        def hpopupmenu
          menu = native #: Native::Menu | Native::Submenu
          Tokra::Menu.run_main_thread(app_handle) { menu.hpopupmenu }
        end
      end

      # Tauri's ContextMenuBase::popup_inner (menu/menu.rs:42-80): the
      # position converts on the calling thread, and the menu shows on the
      # main thread.
      private def popup_inner(window, position)
        unless window.is_a?(Window)
          raise TypeError, "wrong argument type #{window.class} (expected Tokra::Window)"
        end

        dimensions = position && Dpi.position_dimensions(position)
        native_window = window.native
        menu = native #: Native::Menu | Native::Submenu
        Tokra::Menu.run_main_thread(app_handle) { native_window.popup_menu(menu, dimensions) }
        nil
      end
    end
  end
end

# SPDX-SnippetEnd
