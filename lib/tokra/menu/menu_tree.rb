# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: The item methods Menu and Submenu share, adapted from
#                      tauri/crates/tauri/src/menu/menu.rs and menu/submenu.rs

module Tokra
  module Menu
    # The methods that change and read the items of a Menu or a Submenu.
    #
    # Tauri writes the same methods twice, on Menu (menu/menu.rs:272-393)
    # and on Submenu (menu/submenu.rs:277-370); they are the same in Ruby,
    # so both include this module. Each runs on the main thread, waiting
    # for it from another thread, and raises Error::Menu for what muda
    # refuses. An +item+ is a MenuItem, Submenu, PredefinedMenuItem, or
    # CheckMenuItem; anything else raises TypeError.
    module MenuTree
      # Adds +item+ at the end and returns +nil+.
      #
      # === Example
      #
      #   menu.append(Tokra::Menu::PredefinedMenuItem.quit(app, nil))
      def append(item)
        native = @native #: Native::Menu | Native::Submenu
        native_item = Tokra::Menu.native_item(item)
        run_item_main_thread { native.append(native_item) }
        nil
      end

      # Adds each of +items+ at the end, in order, and returns +nil+.
      # Stops at the first that fails.
      def append_items(items)
        items.each { |item| append(item) }
        nil
      end

      # Adds +item+ at the start and returns +nil+.
      def prepend(item)
        native = @native #: Native::Menu | Native::Submenu
        native_item = Tokra::Menu.native_item(item)
        run_item_main_thread { native.prepend(native_item) }
        nil
      end

      # Adds +items+ at the start, keeping their order, and returns +nil+.
      def prepend_items(items)
        insert_items(items, 0)
      end

      # Adds +item+ at +position+, counted from 0, and returns +nil+.
      # Raises IndexError past the end, where Rust panics.
      def insert(item, position)
        native = @native #: Native::Menu | Native::Submenu
        native_item = Tokra::Menu.native_item(item)
        run_item_main_thread { native.insert(native_item, position) }
        nil
      end

      # Adds +items+ from +position+ on, keeping their order, and returns
      # +nil+.
      def insert_items(items, position)
        items.each_with_index { |item, index| insert(item, position + index) }
        nil
      end

      # Takes +item+ out and returns +nil+. Raises Error::Menu when it is
      # not here.
      def remove(item)
        native = @native #: Native::Menu | Native::Submenu
        native_item = Tokra::Menu.native_item(item)
        run_item_main_thread { native.remove(native_item) }
        nil
      end

      # Takes out the item at +position+ and returns it, or +nil+ when
      # there is none.
      def remove_at(position)
        native = @native #: Native::Menu | Native::Submenu
        handle = @app_handle
        run_item_main_thread do
          removed = native.remove_at(position)
          removed && Tokra::Menu.wrap_item(handle, removed)
        end
      end

      # The item with the id +id+ (a String or a MenuId) among these items,
      # not inside their submenus, or +nil+.
      #
      # Tauri answers +None+ when it cannot read the items, too
      # (<tt>unwrap_or_default</tt>).
      #
      # === Example
      #
      #   menu.get(Tokra::Menu::WINDOW_SUBMENU_ID)&.text  #=> "Window"
      def get(id)
        list = begin
          items
        rescue Error
          [] #: Array[item]
        end
        list.find { |item| item.id == id }
      end

      # The items, in order: MenuItem, Submenu, PredefinedMenuItem, and
      # CheckMenuItem objects.
      def items
        native = @native #: Native::Menu | Native::Submenu
        handle = @app_handle
        run_item_main_thread { native.items.map { |item| Tokra::Menu.wrap_item(handle, item) } }
      end
    end
  end
end

# SPDX-SnippetEnd
