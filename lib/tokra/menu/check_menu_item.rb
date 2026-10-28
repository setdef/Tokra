# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: CheckMenuItem adapted from tauri/crates/tauri/src/menu/check.rs

module Tokra
  module Menu
    # A menu item with a check mark: Show Toolbar, Word Wrap.
    #
    # A click flips the check mark and sends a MenuEvent, as a MenuItem
    # does.
    #
    # Mirrors Tauri's CheckMenuItem (menu/check.rs).
    #
    # === Example
    #
    #   wrap = Tokra::Menu::CheckMenuItem.with_id(app, "wrap", "Word Wrap", true, false, nil)
    class CheckMenuItem
      include IsMenuItem

      class << self
        # A new item titled +text+, enabled or not, checked or not, with
        # an id muda makes up.
        def new(manager, text, enabled, checked, accelerator)
          item = Tokra::Menu.natives(manager).check_menu_item
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) { from_native(handle, item.new(text, enabled, checked, accelerator)) }
        end

        # A new item with the id +id+, a String or a MenuId.
        def with_id(manager, id, text, enabled, checked, accelerator)
          item = Tokra::Menu.natives(manager).check_menu_item
          value = MenuId.from(id).value
          handle = manager.app_handle
          Tokra::Menu.run_main_thread(handle) { from_native(handle, item.with_id(value, text, enabled, checked, accelerator)) }
        end

        # The CheckMenuItem that wraps +native+, for +app_handle+.
        def from_native(app_handle, native) # :nodoc:
          item = allocate
          item.__send__(:initialize_wrapper, app_handle, native, MenuId.new(value: native.id))
          item
        end
      end

      # The item's title.
      def text
        native = @native #: Native::CheckMenuItem
        run_item_main_thread { native.text }
      end

      # Sets the item's title and returns +nil+.
      def set_text(text)
        native = @native #: Native::CheckMenuItem
        run_item_main_thread { native.set_text(text) }
        nil
      end

      # Whether the item can be clicked.
      def is_enabled
        native = @native #: Native::CheckMenuItem
        run_item_main_thread { native.is_enabled }
      end

      # Lets the item be clicked, or not, and returns +nil+.
      def set_enabled(enabled)
        native = @native #: Native::CheckMenuItem
        run_item_main_thread { native.set_enabled(enabled) }
        nil
      end

      # Sets the item's shortcut, or takes it away with +nil+, and returns
      # +nil+.
      def set_accelerator(accelerator)
        native = @native #: Native::CheckMenuItem
        run_item_main_thread { native.set_accelerator(accelerator) }
        nil
      end

      # Whether the item shows its check mark.
      def is_checked
        native = @native #: Native::CheckMenuItem
        run_item_main_thread { native.is_checked }
      end

      # Shows the check mark, or hides it, and returns +nil+.
      def set_checked(checked)
        native = @native #: Native::CheckMenuItem
        run_item_main_thread { native.set_checked(checked) }
        nil
      end
    end
  end
end

# SPDX-SnippetEnd
