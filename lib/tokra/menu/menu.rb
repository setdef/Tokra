# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Menu adapted from tauri/crates/tauri/src/menu/menu.rs

require "rbconfig"

module Tokra
  module Menu
    # A menu bar: the app's, or a window's.
    #
    # A Menu holds Submenu objects, and on Windows and Linux MenuItem
    # objects too, which show in the bar itself; macOS shows only
    # submenus there. Give it to AppHandle#set_menu (or #set_as_app_menu)
    # for the whole app, or to Window#set_menu (or #set_as_window_menu) for
    # one window on Windows and Linux.
    #
    # A Menu is also a ContextMenu: #popup and #popup_at show it where you
    # right-click.
    #
    # Mirrors Tauri's Menu (menu/menu.rs).
    #
    # === Example
    #
    #   file = Tokra::Menu::Submenu.with_items(app, "File", true, [
    #     Tokra::Menu::MenuItem.with_id(app, "open", "Open", true, "CmdOrCtrl+O"),
    #   ])
    #   Tokra::Menu::Menu.with_items(app, [file]).set_as_app_menu
    class Menu
      include Wrapper
      include MenuTree
      include ContextMenu

      class << self
        # A new, empty menu with an id muda makes up.
        #
        # +manager+ is the App, AppHandle, Window, or Webview the menu
        # belongs to. Like every constructor here, it builds the native
        # menu on the main thread, and from another thread waits for it.
        def new(manager)
          menu = Tokra::Menu.natives(manager).menu
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) { from_native(handle, menu.new) }
        end

        # A new, empty menu with the id +id+, a String or a MenuId.
        def with_id(manager, id)
          menu = Tokra::Menu.natives(manager).menu
          text = MenuId.from(id).value
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) { from_native(handle, menu.with_id(text)) }
        end

        # A new menu holding +items+.
        def with_items(manager, items)
          new(manager).tap { |menu| menu.append_items(items) }
        end

        # A new menu with the id +id+, holding +items+.
        def with_id_and_items(manager, id, items)
          with_id(manager, id).tap { |menu| menu.append_items(items) }
        end

        # The menu Tauri gives an app that sets none, for the platform it
        # runs on.
        #
        # On macOS: the app's submenu (About, Services, Hide, Hide Others,
        # Quit), then File, Edit, View, Window, and Help. On Windows: File,
        # Edit, Window, and Help, with About under Help. On Linux the same
        # without File. The Window and Help submenus have the ids
        # WINDOW_SUBMENU_ID and HELP_SUBMENU_ID.
        #
        # The About item names the app by its config's product name, or
        # the program's file name without one, and gives the config's
        # version (plan 042, decision 6).
        #
        # Mirrors Tauri's Menu::default (menu/menu.rs:150-249).
        #
        # === Example
        #
        #   Tokra::Menu::Menu.default(app.handle).set_as_app_menu
        def default(app_handle)
          default_for(app_handle, Tokra::Menu.os)
        end

        # The Menu that wraps +native+, for +app_handle+.
        def from_native(app_handle, native) # :nodoc:
          menu = allocate
          menu.__send__(:initialize_wrapper, app_handle, native, MenuId.new(value: native.id))
          menu
        end

        # Menu.default for the platform +os+: :macos, :windows, or :linux.
        private def default_for(app_handle, os)
          config = app_handle.config
          name = config.product_name || File.basename($PROGRAM_NAME, ".*")
          about = AboutMetadata.new(name:, version: config.version)
          window_menu = Submenu.with_id_and_items(app_handle, WINDOW_SUBMENU_ID, "Window", true, [
            PredefinedMenuItem.minimize(app_handle, nil),
            PredefinedMenuItem.maximize(app_handle, nil),
            *((os == :macos) ? [PredefinedMenuItem.separator(app_handle)] : []),
            PredefinedMenuItem.close_window(app_handle, nil),
          ])
          help_menu = Submenu.with_id_and_items(app_handle, HELP_SUBMENU_ID, "Help", true,
            (os == :macos) ? [] : [PredefinedMenuItem.about(app_handle, nil, about)])
          with_items(app_handle, [
            *((os == :macos) ? [app_submenu(app_handle, name, about)] : []),
            *((os == :linux) ? [] : [file_submenu(app_handle, os)]),
            edit_submenu(app_handle),
            *((os == :macos) ? [Submenu.with_items(app_handle, "View", true, [PredefinedMenuItem.fullscreen(app_handle, nil)])] : []),
            window_menu,
            help_menu,
          ])
        end

        private def app_submenu(app_handle, name, about)
          Submenu.with_items(app_handle, name, true, [
            PredefinedMenuItem.about(app_handle, nil, about),
            PredefinedMenuItem.separator(app_handle),
            PredefinedMenuItem.services(app_handle, nil),
            PredefinedMenuItem.separator(app_handle),
            PredefinedMenuItem.hide(app_handle, nil),
            PredefinedMenuItem.hide_others(app_handle, nil),
            PredefinedMenuItem.separator(app_handle),
            PredefinedMenuItem.quit(app_handle, nil),
          ])
        end

        private def file_submenu(app_handle, os)
          Submenu.with_items(app_handle, "File", true, [
            PredefinedMenuItem.close_window(app_handle, nil),
            *((os == :macos) ? [] : [PredefinedMenuItem.quit(app_handle, nil)]),
          ])
        end

        private def edit_submenu(app_handle)
          Submenu.with_items(app_handle, "Edit", true, [
            PredefinedMenuItem.undo(app_handle, nil),
            PredefinedMenuItem.redo(app_handle, nil),
            PredefinedMenuItem.separator(app_handle),
            PredefinedMenuItem.cut(app_handle, nil),
            PredefinedMenuItem.copy(app_handle, nil),
            PredefinedMenuItem.paste(app_handle, nil),
            PredefinedMenuItem.select_all(app_handle, nil),
          ])
        end
      end

      # Makes this the app's menu and returns the menu it replaces, or
      # +nil+, as AppHandle#set_menu does.
      def set_as_app_menu
        @app_handle.set_menu(self)
      end

      # Makes this +window+'s menu and returns the menu it replaces, or
      # +nil+, as Window#set_menu does.
      def set_as_window_menu(window)
        window.set_menu(self)
      end
    end

    # The platform Tauri's <tt>cfg(target_os)</tt> names: :macos,
    # :windows, or :linux (the BSDs count as Linux, as Tauri's cfg lists
    # them together).
    def self.os # :nodoc:
      case RbConfig::CONFIG["host_os"]
      when /darwin/ then :macos
      when /mswin|mingw|cygwin/ then :windows
      else :linux
      end
    end
  end
end

# SPDX-SnippetEnd
