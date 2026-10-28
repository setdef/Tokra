# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: The menu builders adapted from tauri/crates/tauri/src/menu/builders/menu.rs,
#                      builders/normal.rs, builders/check.rs, and builders/icon.rs

module Tokra
  module Menu
    # The item methods MenuBuilder and SubmenuBuilder share.
    #
    # Each makes its item at once, as Tauri's do, and keeps it, or the
    # Tokra::Error making it raised, for #build, which adds the items in
    # order and raises the first error it meets. Each returns the builder.
    #
    # Mirrors Tauri's <tt>shared_menu_builder!</tt> (builders/menu.rs).
    module SharedMenuBuilder
      # Sets the id of the menu being built, a String or a MenuId.
      def id(id)
        @id = MenuId.from(id)
        self
      end

      # Adds +item+, a menu item made elsewhere.
      def item(item)
        Tokra::Menu.native_item(item)
        @items << item
        self
      end

      # Adds each of +items+.
      def items(items)
        items.each { |item| item(item) }
        self
      end

      # Adds an enabled MenuItem with the id +id+ and the title +text+.
      def text(id, text)
        add { MenuItem.with_id(@manager, id, text, true, nil) }
      end

      # Adds an enabled CheckMenuItem with the id +id+ and the title
      # +text+, checked, as Tauri's builder makes it.
      def check(id, text)
        add { CheckMenuItem.with_id(@manager, id, text, true, true, nil) }
      end

      # Adds an enabled IconMenuItem with the id +id+ and the title +text+,
      # showing +icon+, a Tokra::Image.
      def icon(id, text, icon)
        add { IconMenuItem.with_id(@manager, id, text, true, icon, nil) }
      end

      # Adds an enabled IconMenuItem with the id +id+ and the title +text+,
      # showing +icon+, a NativeIcon. Windows and Linux show no icon.
      def native_icon(id, text, icon)
        add { IconMenuItem.with_id_and_native_icon(@manager, id, text, true, icon, nil) }
      end

      # Adds a separator.
      def separator
        add { PredefinedMenuItem.separator(@manager) }
      end

      # Adds Copy.
      def copy
        add { PredefinedMenuItem.copy(@manager, nil) }
      end

      # Adds Copy titled +text+.
      def copy_with_text(text)
        add { PredefinedMenuItem.copy(@manager, text) }
      end

      # Adds Cut.
      def cut
        add { PredefinedMenuItem.cut(@manager, nil) }
      end

      # Adds Cut titled +text+.
      def cut_with_text(text)
        add { PredefinedMenuItem.cut(@manager, text) }
      end

      # Adds Paste.
      def paste
        add { PredefinedMenuItem.paste(@manager, nil) }
      end

      # Adds Paste titled +text+.
      def paste_with_text(text)
        add { PredefinedMenuItem.paste(@manager, text) }
      end

      # Adds Select All.
      def select_all
        add { PredefinedMenuItem.select_all(@manager, nil) }
      end

      # Adds Select All titled +text+.
      def select_all_with_text(text)
        add { PredefinedMenuItem.select_all(@manager, text) }
      end

      # Adds Undo.
      def undo
        add { PredefinedMenuItem.undo(@manager, nil) }
      end

      # Adds Undo titled +text+.
      def undo_with_text(text)
        add { PredefinedMenuItem.undo(@manager, text) }
      end

      # Adds Redo.
      def redo
        add { PredefinedMenuItem.redo(@manager, nil) }
      end

      # Adds Redo titled +text+.
      def redo_with_text(text)
        add { PredefinedMenuItem.redo(@manager, text) }
      end

      # Adds Minimize.
      def minimize
        add { PredefinedMenuItem.minimize(@manager, nil) }
      end

      # Adds Minimize titled +text+.
      def minimize_with_text(text)
        add { PredefinedMenuItem.minimize(@manager, text) }
      end

      # Adds Maximize.
      def maximize
        add { PredefinedMenuItem.maximize(@manager, nil) }
      end

      # Adds Maximize titled +text+.
      def maximize_with_text(text)
        add { PredefinedMenuItem.maximize(@manager, text) }
      end

      # Adds Enter Full Screen.
      def fullscreen
        add { PredefinedMenuItem.fullscreen(@manager, nil) }
      end

      # Adds Enter Full Screen titled +text+.
      def fullscreen_with_text(text)
        add { PredefinedMenuItem.fullscreen(@manager, text) }
      end

      # Adds Hide.
      def hide
        add { PredefinedMenuItem.hide(@manager, nil) }
      end

      # Adds Hide titled +text+.
      def hide_with_text(text)
        add { PredefinedMenuItem.hide(@manager, text) }
      end

      # Adds Hide Others.
      def hide_others
        add { PredefinedMenuItem.hide_others(@manager, nil) }
      end

      # Adds Hide Others titled +text+.
      def hide_others_with_text(text)
        add { PredefinedMenuItem.hide_others(@manager, text) }
      end

      # Adds Show All.
      def show_all
        add { PredefinedMenuItem.show_all(@manager, nil) }
      end

      # Adds Show All titled +text+.
      def show_all_with_text(text)
        add { PredefinedMenuItem.show_all(@manager, text) }
      end

      # Adds Close Window.
      def close_window
        add { PredefinedMenuItem.close_window(@manager, nil) }
      end

      # Adds Close Window titled +text+.
      def close_window_with_text(text)
        add { PredefinedMenuItem.close_window(@manager, text) }
      end

      # Adds Quit.
      def quit
        add { PredefinedMenuItem.quit(@manager, nil) }
      end

      # Adds Quit titled +text+.
      def quit_with_text(text)
        add { PredefinedMenuItem.quit(@manager, text) }
      end

      # Adds About, showing +metadata+ (an AboutMetadata, or +nil+).
      def about(metadata)
        add { PredefinedMenuItem.about(@manager, nil, metadata) }
      end

      # Adds About titled +text+, showing +metadata+.
      def about_with_text(text, metadata)
        add { PredefinedMenuItem.about(@manager, text, metadata) }
      end

      # Adds Services.
      def services
        add { PredefinedMenuItem.services(@manager, nil) }
      end

      # Adds Services titled +text+.
      def services_with_text(text)
        add { PredefinedMenuItem.services(@manager, text) }
      end

      # The built menu with the items added, raising the first error kept.
      private def append_built(menu)
        @items.each do |item|
          raise item if item.is_a?(Exception)

          menu.append(item)
        end
        menu
      end

      # Keeps the item the block makes, or the Tokra::Error it raises, as
      # Tauri keeps a crate::Result.
      private def add
        @items << begin
          yield
        rescue Error => e
          e
        end
        self
      end
    end

    # Builds a Menu.
    #
    # Mirrors Tauri's MenuBuilder (builders/menu.rs).
    #
    # === Example
    #
    #   Tokra::Menu::MenuBuilder.new(app).item(file).item(edit).build
    class MenuBuilder
      include SharedMenuBuilder

      # A builder for a menu belonging to +manager+, an App, AppHandle,
      # Window, or Webview.
      def initialize(manager)
        @manager = manager
        @id = nil #: MenuId?
        @items = [] #: Array[IsMenuItem | Error]
      end

      # A builder for a menu with the id +id+.
      def self.with_id(manager, id)
        builder = new(manager)
        builder.id(id)
        builder
      end

      # The Menu, with the items added in order. Raises the first error
      # an item's making kept.
      def build
        id = @id
        append_built(id ? Menu.with_id(@manager, id) : Menu.new(@manager))
      end
    end

    # Builds a Submenu, enabled unless #enabled says otherwise.
    #
    # Mirrors Tauri's SubmenuBuilder (builders/menu.rs).
    #
    # === Example
    #
    #   Tokra::Menu::SubmenuBuilder.new(app, "Edit").undo.redo.separator.copy.paste.build
    class SubmenuBuilder
      include SharedMenuBuilder

      # A builder for a submenu titled +text+, belonging to +manager+.
      def initialize(manager, text)
        @manager = manager
        @text = text
        @enabled = true
        @id = nil #: MenuId?
        @items = [] #: Array[IsMenuItem | Error]
        @icon = nil #: Image?
        @native_icon = nil #: NativeIcon?
      end

      # A builder for a submenu with the id +id+.
      def self.with_id(manager, id, text)
        builder = new(manager, text)
        builder.id(id)
        builder
      end

      # Sets whether the submenu can be opened.
      def enabled(enabled)
        @enabled = enabled
        self
      end

      # Sets the icon the submenu shows, a Tokra::Image, and drops any
      # #submenu_native_icon.
      def submenu_icon(icon)
        @icon = icon
        @native_icon = nil
        self
      end

      # Sets the icon the submenu shows, a NativeIcon, and drops any
      # #submenu_icon. Windows and Linux show no icon.
      def submenu_native_icon(icon)
        @native_icon = icon
        @icon = nil
        self
      end

      # The Submenu, with the items added in order.
      def build
        append_built(build_submenu)
      end

      private def build_submenu
        id = @id
        icon = @icon
        native_icon = @native_icon
        if id
          if icon then Submenu.with_id_and_icon(@manager, id, @text, @enabled, icon)
          elsif native_icon then Submenu.with_id_and_native_icon(@manager, id, @text, @enabled, native_icon)
          else Submenu.with_id(@manager, id, @text, @enabled)
          end
        elsif icon then Submenu.new_with_icon(@manager, @text, @enabled, icon)
        elsif native_icon then Submenu.new_with_native_icon(@manager, @text, @enabled, native_icon)
        else Submenu.new(@manager, @text, @enabled)
        end
      end
    end

    # Builds a MenuItem: enabled, with no accelerator, unless told
    # otherwise.
    #
    # Mirrors Tauri's MenuItemBuilder (builders/normal.rs).
    #
    # === Example
    #
    #   Tokra::Menu::MenuItemBuilder.with_id("save", "Save").accelerator("CmdOrCtrl+S").build(app)
    class MenuItemBuilder
      # A builder for an item titled +text+.
      def initialize(text)
        @text = text
        @id = nil #: MenuId?
        @enabled = true
        @accelerator = nil #: String?
      end

      # A builder for an item with the id +id+.
      def self.with_id(id, text)
        new(text).id(id)
      end

      # Sets the item's id, a String or a MenuId.
      def id(id)
        @id = MenuId.from(id)
        self
      end

      # Sets whether the item can be clicked.
      def enabled(enabled)
        @enabled = enabled
        self
      end

      # Sets the item's shortcut, such as <tt>"CmdOrCtrl+S"</tt>.
      def accelerator(accelerator)
        @accelerator = accelerator
        self
      end

      # The MenuItem, belonging to +manager+.
      def build(manager)
        id = @id
        if id
          MenuItem.with_id(manager, id, @text, @enabled, @accelerator)
        else
          MenuItem.new(manager, @text, @enabled, @accelerator)
        end
      end
    end

    # Builds a CheckMenuItem: enabled, checked, with no accelerator,
    # unless told otherwise. Tauri's builder starts it checked.
    #
    # Mirrors Tauri's CheckMenuItemBuilder (builders/check.rs).
    #
    # === Example
    #
    #   Tokra::Menu::CheckMenuItemBuilder.with_id("wrap", "Word Wrap").checked(false).build(app)
    class CheckMenuItemBuilder
      # A builder for an item titled +text+.
      def initialize(text)
        @text = text
        @id = nil #: MenuId?
        @enabled = true
        @checked = true
        @accelerator = nil #: String?
      end

      # A builder for an item with the id +id+.
      def self.with_id(id, text)
        new(text).id(id)
      end

      # Sets the item's id, a String or a MenuId.
      def id(id)
        @id = MenuId.from(id)
        self
      end

      # Sets whether the item can be clicked.
      def enabled(enabled)
        @enabled = enabled
        self
      end

      # Sets whether the item shows its check mark.
      def checked(checked)
        @checked = checked
        self
      end

      # Sets the item's shortcut, such as <tt>"CmdOrCtrl+W"</tt>.
      def accelerator(accelerator)
        @accelerator = accelerator
        self
      end

      # The CheckMenuItem, belonging to +manager+.
      def build(manager)
        id = @id
        if id
          CheckMenuItem.with_id(manager, id, @text, @enabled, @checked, @accelerator)
        else
          CheckMenuItem.new(manager, @text, @enabled, @checked, @accelerator)
        end
      end
    end

    # Builds an IconMenuItem: enabled, with no icon and no accelerator,
    # unless told otherwise. #icon and #native_icon each drop the other.
    #
    # Mirrors Tauri's IconMenuItemBuilder (builders/icon.rs).
    #
    # === Example
    #
    #   Tokra::Menu::IconMenuItemBuilder.with_id("lock", "Lock").native_icon(Tokra::Menu::NativeIcon::LockLocked).build(app)
    class IconMenuItemBuilder
      # A builder for an item titled +text+.
      def initialize(text)
        @text = text
        @id = nil #: MenuId?
        @enabled = true
        @icon = nil #: Image?
        @native_icon = nil #: NativeIcon?
        @accelerator = nil #: String?
      end

      # A builder for an item with the id +id+.
      def self.with_id(id, text)
        new(text).id(id)
      end

      # Sets the item's id, a String or a MenuId.
      def id(id)
        @id = MenuId.from(id)
        self
      end

      # Sets whether the item can be clicked.
      def enabled(enabled)
        @enabled = enabled
        self
      end

      # Sets the item's shortcut, such as <tt>"CmdOrCtrl+L"</tt>.
      def accelerator(accelerator)
        @accelerator = accelerator
        self
      end

      # Sets the item's icon, a Tokra::Image, and drops any #native_icon.
      def icon(icon)
        @icon = icon
        @native_icon = nil
        self
      end

      # Sets the item's icon, a NativeIcon, and drops any #icon. Windows
      # and Linux show no icon.
      def native_icon(icon)
        @native_icon = icon
        @icon = nil
        self
      end

      # The IconMenuItem, belonging to +manager+: with its image if it has
      # one, else with its native icon or none, as Tauri's build chooses.
      def build(manager)
        id = @id
        if @icon
          if id
            IconMenuItem.with_id(manager, id, @text, @enabled, @icon, @accelerator)
          else
            IconMenuItem.new(manager, @text, @enabled, @icon, @accelerator)
          end
        elsif id
          IconMenuItem.with_id_and_native_icon(manager, id, @text, @enabled, @native_icon, @accelerator)
        else
          IconMenuItem.with_native_icon(manager, @text, @enabled, @native_icon, @accelerator)
        end
      end
    end
  end
end

# SPDX-SnippetEnd
