# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: MenuItem adapted from tauri/crates/tauri/src/menu/normal.rs

module Tokra
  module Menu
    # A menu item that runs a command: Open, Save, Preferences.
    #
    # Clicking it sends a MenuEvent with its id to AppHandle#on_menu_event
    # and Window#on_menu_event. An +accelerator+ is a shortcut such as
    # <tt>"CmdOrCtrl+S"</tt>, or +nil+; one muda cannot read is dropped
    # without an error, as Tauri drops it.
    #
    # Mirrors Tauri's MenuItem (menu/normal.rs).
    #
    # === Example
    #
    #   save = Tokra::Menu::MenuItem.with_id(app, "save", "Save", true, "CmdOrCtrl+S")
    class MenuItem
      include IsMenuItem

      class << self
        # A new item titled +text+, enabled or not, with an id muda makes
        # up.
        def new(manager, text, enabled, accelerator)
          item = Tokra::Menu.natives(manager).menu_item
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) { from_native(handle, item.new(text, enabled, accelerator)) }
        end

        # A new item with the id +id+, a String or a MenuId.
        def with_id(manager, id, text, enabled, accelerator)
          item = Tokra::Menu.natives(manager).menu_item
          value = MenuId.from(id).value
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) { from_native(handle, item.with_id(value, text, enabled, accelerator)) }
        end

        # The MenuItem that wraps +native+, for +app_handle+.
        def from_native(app_handle, native) # :nodoc:
          item = allocate
          item.__send__(:initialize_wrapper, app_handle, native, MenuId.new(value: native.id))
          item
        end
      end

      # The item's title.
      def text
        native = @native #: Native::MenuItem
        run_item_main_thread { native.text }
      end

      # Sets the item's title and returns +nil+.
      def set_text(text)
        native = @native #: Native::MenuItem
        run_item_main_thread { native.set_text(text) }
        nil
      end

      # Whether the item can be clicked.
      def is_enabled
        native = @native #: Native::MenuItem
        run_item_main_thread { native.is_enabled }
      end

      # Lets the item be clicked, or not, and returns +nil+.
      def set_enabled(enabled)
        native = @native #: Native::MenuItem
        run_item_main_thread { native.set_enabled(enabled) }
        nil
      end

      # Sets the item's shortcut, or takes it away with +nil+, and returns
      # +nil+. One muda cannot read takes it away too, as in Tauri.
      def set_accelerator(accelerator)
        native = @native #: Native::MenuItem
        run_item_main_thread { native.set_accelerator(accelerator) }
        nil
      end
    end
  end
end

# SPDX-SnippetEnd
