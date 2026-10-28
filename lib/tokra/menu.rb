# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: 2022-2022 Tauri Programme within The Commons Conservancy (muda)
# SPDX-SnippetComment: The menu module adapted from tauri/crates/tauri/src/menu/mod.rs
#                      and menu/menu.rs, and MenuId from muda 0.17.1 src/menu_id.rs

module Tokra
  # Menus: the menu bar, its submenus, and their items.
  #
  # A desktop app keeps its commands in a menu bar: the one at the top of
  # the screen on macOS, and one inside each window on Windows and Linux.
  # This module builds those menus from Ruby. Build a Menu of Submenu
  # objects holding MenuItem, CheckMenuItem, and PredefinedMenuItem
  # objects, give it to AppHandle#set_menu or Window#set_menu, and hear
  # each click in AppHandle#on_menu_event or Window#on_menu_event. Every
  # menu and item answers on the main thread; from another thread a call
  # travels there and waits for the answer.
  #
  # Mirrors Tauri's <tt>tauri::menu</tt> module (menu/mod.rs), which wraps
  # the muda crate. Icons and context menus are not ported yet (plan 042).
  #
  # === Example
  #
  #   Tokra::Builder.default
  #     .menu { |app| Tokra::Menu::MenuBuilder.new(app).text("open", "Open").quit.build }
  #     .on_menu_event(Ractor.shareable_proc { |_app, event| puts event.id })
  module Menu
    # The id of the Window submenu in Menu.default. On macOS the app makes
    # it NSApp's Window menu (menu/menu.rs:19).
    WINDOW_SUBMENU_ID = "__tauri_window_menu__"

    # The id of the Help submenu in Menu.default. On macOS the app makes it
    # NSApp's Help menu (menu/menu.rs:21).
    HELP_SUBMENU_ID = "__tauri_help_menu__"

    # The id of a menu or item.
    #
    # Each click names the item it came from by this id, so an app tells
    # its items apart by the id it gave each one, or the one muda made up.
    # An id equals another with the same text, and equals that text as a
    # String.
    #
    # Mirrors muda's <tt>MenuId(String)</tt> (menu_id.rs). Rust's tuple
    # struct needs a member name in Ruby's Data, so the text is +value+.
    #
    # === Example
    #
    #   Tokra::Menu::MenuId.new("save") == "save"  #=> true
    class MenuId < Data.define(:value)
      # The id for +id+: itself if it is a MenuId, else a MenuId of its
      # text, as muda's <tt>From<T: ToString></tt> makes one.
      #
      # === Example
      #
      #   Tokra::Menu::MenuId.from(:save).value  #=> "save"
      def self.from(id)
        id.is_a?(MenuId) ? id : new(value: id.to_s)
      end

      # Whether +other+ is this id, or its text (muda's
      # <tt>PartialEq<&str></tt> and <tt>PartialEq<String></tt>).
      #
      # === Example
      #
      #   event.id == "save"
      def ==(other)
        other.is_a?(String) ? value == other : super
      end

      # The id's text, as muda's <tt>AsRef<str></tt> gives it.
      def to_s
        value
      end

      # The id as JSON: its text alone, as serde serializes the newtype
      # struct.
      def to_json(*)
        value.to_json(*)
      end
    end

    # A click on a menu item.
    #
    # Mirrors Tauri's <tt>MenuEvent { id }</tt> (menu/mod.rs:44-61).
    #
    # === Example
    #
    #   app.on_menu_event { |_app, event| quit if event.id == "quit" }
    class MenuEvent < Data.define(:id)
      # The event as a JSON object holding its id, as Tauri serializes it.
      def to_json(*) # :nodoc:
        { "id" => id }.to_json(*)
      end
    end

    # The native classes and app functions one app's menus are built with
    # (plan 042, decision 1).
    class Natives < Data.define(:app, :menu, :submenu, :menu_item, :check_menu_item, :predefined_menu_item) # :nodoc:
      # The menu classes of +native+, Native or a test's stand-in.
      def self.from(native)
        app = native #: singleton(Native)
        new(app:, menu: native.const_get(:Menu), submenu: native.const_get(:Submenu),
          menu_item: native.const_get(:MenuItem), check_menu_item: native.const_get(:CheckMenuItem),
          predefined_menu_item: native.const_get(:PredefinedMenuItem))
      end

      # Whether menus belong to the app, as on macOS, where Tauri's
      # <tt>cfg(target_os = "macos")</tt> branches go.
      def nsapp?
        app.respond_to?(:init_menu_for_nsapp)
      end
    end

    # What every menu and item is: its id, its app, and its native muda
    # value, which only the main thread touches.
    #
    # Mirrors the wrapper types Tauri's <tt>gen_wrappers!</tt> defines
    # (menu/mod.rs:63-165). Ruby frees the native value; one freed on
    # another thread goes to the main thread to be dropped, as Tauri's
    # Drop does.
    module Wrapper
      include Resource

      # The menu's or item's id.
      attr_reader :id

      # The app this menu or item belongs to.
      attr_reader :app_handle

      # The native muda value. Use it only on the main thread.
      attr_reader :native # :nodoc:

      # Whether +other+ is this menu or item: the same kind with the same
      # id, as muda tells a menu's children apart.
      def ==(other)
        other.instance_of?(self.class) && other.id == id
      end
      alias eql? ==

      # A hash of the kind and id, so equal items are one Hash key.
      def hash
        [self.class, id].hash
      end

      # The kind and the id, which is all that tells menus apart.
      def inspect
        "#<#{self.class} id=#{id.value.inspect}>"
      end

      private def initialize_wrapper(app_handle, native, id)
        @app_handle = app_handle
        @native = native
        @id = id
      end

      # Runs +call+ on the main thread and answers its result, as Tauri's
      # run_item_main_thread! does. A muda error, a RuntimeError from the
      # native layer, raises Error::Menu.
      private def run_item_main_thread(&call)
        Tokra::Menu.run_main_thread(@app_handle, &call)
      end
    end

    # What a menu item is, as Tauri's IsMenuItem trait says: an item with
    # an id that a Menu or Submenu holds.
    #
    # Tauri's MenuItemKind enum wraps one item type per variant; in Ruby
    # the item is its own variant, so #kind answers the item itself and
    # MenuItemKind's <tt>as_*</tt> methods are Ruby's +is_a?+
    # (plan 042, decision 4).
    module IsMenuItem
      include Wrapper

      # The item, as Tauri's IsMenuItem#kind answers its MenuItemKind.
      def kind
        self
      end
    end

    class << self
      # Runs +call+ on the main thread of +manager+'s app and answers its
      # result, raising Error::Menu with muda's text for a RuntimeError
      # the native layer raises.
      def run_main_thread(manager, &call) # :nodoc:
        manager.app_handle.runtime_context.run_main_thread do
          call.call
        rescue RuntimeError => e
          # The native layer raises muda's errors as plain RuntimeErrors;
          # a subclass, such as FrozenError, is a bug and stays itself.
          raise unless e.instance_of?(RuntimeError)

          raise Error::Menu, e.message
        end
      end

      # The native menu classes of +manager+'s app.
      def natives(manager) # :nodoc:
        manager.app_handle.runtime_context.menu_natives
      end

      # The item that wraps the native item +native+, for +app_handle+:
      # Tauri's MenuItemKind::from_muda (menu/mod.rs:576-606), by the
      # app's own native classes.
      def wrap_item(app_handle, native) # :nodoc:
        natives = app_handle.runtime_context.menu_natives
        case native
        when natives.menu_item
          item = native #: Native::MenuItem
          MenuItem.from_native(app_handle, item)
        when natives.submenu
          submenu = native #: Native::Submenu
          Submenu.from_native(app_handle, submenu)
        when natives.predefined_menu_item
          predefined = native #: Native::PredefinedMenuItem
          PredefinedMenuItem.from_native(app_handle, predefined)
        when natives.check_menu_item
          check = native #: Native::CheckMenuItem
          CheckMenuItem.from_native(app_handle, check)
        else raise TypeError, "wrong argument type #{native.class} (expected a native menu item)"
        end
      end

      # The native item for +item+, raising TypeError for anything that is
      # no menu item, as Rust's <tt>&dyn IsMenuItem</tt> bound would not
      # compile.
      def native_item(item) # :nodoc:
        case item
        when IsMenuItem then item.native
        else raise TypeError, "wrong argument type #{item.class} (expected Tokra::Menu::IsMenuItem)"
        end
      end
    end
  end
end

# SPDX-SnippetEnd

require_relative "menu/about_metadata"
require_relative "menu/menu_tree"
require_relative "menu/menu"
require_relative "menu/submenu"
require_relative "menu/menu_item"
require_relative "menu/check_menu_item"
require_relative "menu/predefined_menu_item"
require_relative "menu/builders"
require_relative "menu/plugin"
