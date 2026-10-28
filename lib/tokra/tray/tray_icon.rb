# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: TrayIcon adapted from tauri/crates/tauri/src/tray/mod.rs

module Tokra
  module Tray
    # An icon in the system tray.
    #
    # Build one with TrayIconBuilder; the app keeps it in its resources
    # table, so it stays in the tray until it is closed or the app ends,
    # whether or not the app keeps the object. AppHandle#tray_by_id finds
    # it again, and AppHandle#remove_tray_by_id takes it off the tray.
    # Every method runs on the main thread; from another thread it travels
    # there and waits for the answer.
    #
    # Mirrors Tauri's TrayIcon (tray/mod.rs:392-620). Tauri's icon
    # disappears when its last clone drops; this one disappears when it is
    # closed, and then each method does nothing (plan 043, decision 6).
    #
    # === Example
    #
    #   tray = app.tray_by_id("main")
    #   tray.set_tooltip("Syncing…")
    class TrayIcon
      include Resource

      # The tray's id, a TrayIconId.
      attr_reader :id

      # The app this tray belongs to.
      attr_reader :app_handle

      # The native tray. Use it only on the main thread.
      attr_reader :native # :nodoc:

      def initialize(id:, native:, app_handle:) # :nodoc:
        @id = id
        @native = native
        @app_handle = app_handle
      end

      # Puts the tray into the app's state: +on_menu_event+ joins the
      # app's menu listeners, +on_tray_icon_event+ becomes this tray's
      # listener, and the tray joins the resources table and the icons.
      # Answers its rid (tray/mod.rs:421-456).
      def register(on_menu_event, on_tray_icon_event) # :nodoc:
        @app_handle.menu_manager.on_menu_event(on_menu_event) if on_menu_event
        @app_handle.tray_manager.set_tray_listener(@id, on_tray_icon_event) if on_tray_icon_event
        rid = @app_handle.resources_table.add(self)
        @app_handle.tray_manager.insert(@id, rid)
        rid
      end

      # Calls the block with the AppHandle and each Menu::MenuEvent, a
      # click on any menu item, this tray's or not, and returns +nil+.
      #
      # Mirrors Tauri's TrayIcon::on_menu_event (tray/mod.rs:463-476).
      def on_menu_event(&handler)
        @app_handle.menu_manager.on_menu_event(handler)
      end

      # Calls the block with this tray and each of its TrayIconEvent
      # events, after the app's listeners heard it, and returns +nil+. A
      # second block replaces the first.
      #
      # Mirrors Tauri's TrayIcon::on_tray_icon_event (tray/mod.rs:478-491).
      #
      # === Example
      #
      #   tray.on_tray_icon_event { |tray, event| tray.set_visible(false) if event.is_a?(Tokra::Tray::TrayIconEvent::Click) }
      def on_tray_icon_event(&handler)
        @app_handle.tray_manager.set_tray_listener(@id, handler)
      end

      # Shows +icon+, a Tokra::Image, in the tray, or no icon for +nil+.
      # Raises Error::BadTrayIcon for an image whose bytes do not make its
      # size, and Error::Tray when the platform refuses it.
      #
      # On macOS a new icon is never a template, whatever
      # #set_icon_as_template said before, as in tray-icon.
      #
      # Mirrors Tauri's TrayIcon::set_icon (tray/mod.rs:498-505).
      def set_icon(icon)
        native_icon = icon && Tray.tray_icon(icon)
        run_item_main_thread { @native.set_icon(native_icon) }
        nil
      end

      # Shows +menu+, a Menu::Menu or Menu::Submenu, when the tray is
      # clicked, or no menu for +nil+.
      #
      # On Linux a menu, once set, stays: +nil+ changes nothing there.
      #
      # Mirrors Tauri's TrayIcon::set_menu (tray/mod.rs:507-516).
      def set_menu(menu)
        native_menu = menu && Tray.native_menu(menu)
        run_item_main_thread do
          Tray.refuse_unbuildable_menu(@app_handle, native_menu)
          @native.set_menu(native_menu)
        end
        nil
      end

      # Shows +tooltip+ when the pointer rests on the tray, or none for
      # +nil+. Linux shows no tooltip.
      #
      # Mirrors Tauri's TrayIcon::set_tooltip (tray/mod.rs:518-526).
      def set_tooltip(tooltip)
        run_item_main_thread { @native.set_tooltip(tooltip) }
        nil
      end

      # Shows +title+ beside the icon, or none for +nil+. On Linux the
      # title shows only with an icon; Windows shows no title.
      #
      # Mirrors Tauri's TrayIcon::set_title (tray/mod.rs:528-541).
      def set_title(title)
        run_item_main_thread { @native.set_title(title) }
        nil
      end

      # Shows the tray when +visible+, or hides it.
      #
      # Mirrors Tauri's TrayIcon::set_visible (tray/mod.rs:543-546).
      def set_visible(visible)
        run_item_main_thread { @native.set_visible(visible) }
        nil
      end

      # Writes the tray's icon into +path+ from now on, or into the default
      # directory for +nil+. Linux only, where the desktop reads the icon
      # from a file; elsewhere this does nothing.
      #
      # Mirrors Tauri's TrayIcon::set_temp_dir_path (tray/mod.rs:548-558).
      def set_temp_dir_path(path)
        return nil unless @native.respond_to?(:set_temp_dir_path)

        text = case path
        when String, nil then path
        else path.to_path
        end
        run_item_main_thread { @native.set_temp_dir_path(text) }
        nil
      end

      # Makes the icon a template, which macOS tints to suit the menu bar.
      # macOS only; elsewhere this does nothing.
      #
      # Mirrors Tauri's TrayIcon::set_icon_as_template (tray/mod.rs:560-567).
      def set_icon_as_template(is_template)
        return nil unless @native.respond_to?(:set_icon_as_template)

        run_item_main_thread { @native.set_icon_as_template(is_template) }
        nil
      end

      # Whether a left click opens the tray's menu, as it does unless told
      # otherwise. Linux does not support it; there this does nothing.
      #
      # Mirrors Tauri's TrayIcon::set_show_menu_on_left_click
      # (tray/mod.rs:569-581).
      def set_show_menu_on_left_click(enable)
        return nil unless @native.respond_to?(:set_show_menu_on_left_click)

        run_item_main_thread { @native.set_show_menu_on_left_click(enable) }
        nil
      end

      # Where the tray sits on the screen, a Tokra::Rect in physical
      # pixels, or +nil+: always on Linux, and once the tray is closed.
      #
      # Mirrors Tauri's TrayIcon::rect (tray/mod.rs:583-595).
      def rect
        values = run_item_main_thread { @native.rect }
        return nil unless values

        x, y, width, height = values
        Rect.new(position: PhysicalPosition.new(x:, y:), size: PhysicalSize.new(width:, height:))
      end

      # Forgets the tray and takes it off the system tray. Its methods do
      # nothing afterwards. The resources table calls this as it closes the
      # tray's rid.
      #
      # Mirrors Tauri's Resource::close for TrayIcon (tray/mod.rs:610-620),
      # with the drop that follows it (plan 043, decision 6).
      def close
        @app_handle.tray_manager.delete(@id)
        run_item_main_thread { @native.remove }
        nil
      end

      private def run_item_main_thread(&call)
        Tray.run_main_thread(@app_handle, &call)
      end
    end
  end
end

# SPDX-SnippetEnd
