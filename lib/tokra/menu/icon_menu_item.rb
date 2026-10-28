# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: IconMenuItem adapted from tauri/crates/tauri/src/menu/icon.rs

module Tokra
  module Menu
    # A menu item with an image beside its title: Lock, Share, Trash.
    #
    # It runs a command as a MenuItem does, and shows either an image the
    # app gives it, a Tokra::Image, or one of macOS's own, a NativeIcon.
    # Windows and Linux show no native icon. An image whose bytes do not
    # make its size raises Error::BadMenuIcon before anything is made.
    #
    # Mirrors Tauri's IconMenuItem (menu/icon.rs).
    #
    # === Example
    #
    #   icon = Tokra::Image.from_path("icons/lock.png")
    #   lock = Tokra::Menu::IconMenuItem.with_id(app, "lock", "Lock", true, icon, "CmdOrCtrl+L")
    class IconMenuItem
      include IsMenuItem

      class << self
        # A new item titled +text+, enabled or not, showing +icon+ (a
        # Tokra::Image, or +nil+), with an id muda makes up.
        def new(manager, text, enabled, icon, accelerator)
          item = Tokra::Menu.natives(manager).icon_menu_item
          native_icon = Tokra::Menu.menu_icon(manager, icon)
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) do
            from_native(handle, item.new(text, enabled, native_icon, accelerator))
          end
        end

        # A new item with the id +id+, a String or a MenuId.
        def with_id(manager, id, text, enabled, icon, accelerator)
          item = Tokra::Menu.natives(manager).icon_menu_item
          value = MenuId.from(id).value
          native_icon = Tokra::Menu.menu_icon(manager, icon)
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) do
            from_native(handle, item.with_id(value, text, enabled, native_icon, accelerator))
          end
        end

        # A new item showing +native_icon+, a NativeIcon or +nil+. Windows
        # and Linux show no icon.
        def with_native_icon(manager, text, enabled, native_icon, accelerator)
          item = Tokra::Menu.natives(manager).icon_menu_item
          name = native_icon&.name
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) do
            from_native(handle, item.with_native_icon(text, enabled, name, accelerator))
          end
        end

        # A new item with the id +id+, showing +native_icon+.
        def with_id_and_native_icon(manager, id, text, enabled, native_icon, accelerator)
          item = Tokra::Menu.natives(manager).icon_menu_item
          value = MenuId.from(id).value
          name = native_icon&.name
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) do
            from_native(handle, item.with_id_and_native_icon(value, text, enabled, name, accelerator))
          end
        end

        # The IconMenuItem that wraps +native+, for +app_handle+.
        def from_native(app_handle, native) # :nodoc:
          item = allocate
          item.__send__(:initialize_wrapper, app_handle, native, MenuId.new(value: native.id))
          item
        end
      end

      # The item's title.
      def text
        native = @native #: Native::IconMenuItem
        run_item_main_thread { native.text }
      end

      # Sets the item's title and returns +nil+.
      def set_text(text)
        native = @native #: Native::IconMenuItem
        run_item_main_thread { native.set_text(text) }
        nil
      end

      # Whether the item can be clicked.
      def is_enabled
        native = @native #: Native::IconMenuItem
        run_item_main_thread { native.is_enabled }
      end

      # Lets the item be clicked, or not, and returns +nil+.
      def set_enabled(enabled)
        native = @native #: Native::IconMenuItem
        run_item_main_thread { native.set_enabled(enabled) }
        nil
      end

      # Sets the item's shortcut, or takes it away with +nil+, and returns
      # +nil+. One muda cannot read takes it away too, as in Tauri.
      def set_accelerator(accelerator)
        native = @native #: Native::IconMenuItem
        run_item_main_thread { native.set_accelerator(accelerator) }
        nil
      end

      # Shows +icon+, a Tokra::Image, in place of the item's icon, or no
      # icon with +nil+, and returns +nil+. Raises Error::BadMenuIcon for
      # an image muda refuses.
      def set_icon(icon)
        native = @native #: Native::IconMenuItem
        native_icon = Tokra::Menu.menu_icon(@app_handle, icon)
        run_item_main_thread { native.set_icon(native_icon) }
        nil
      end

      # Shows +native_icon+, a NativeIcon, in place of the item's icon, or
      # no icon with +nil+, and returns +nil+. It does nothing on Windows
      # and Linux, as in Tauri.
      def set_native_icon(native_icon)
        return nil unless Tokra::Menu.natives(@app_handle).nsapp?

        native = @native #: Native::IconMenuItem
        name = native_icon&.name
        run_item_main_thread { native.set_native_icon(name) }
        nil
      end
    end
  end
end

# SPDX-SnippetEnd
