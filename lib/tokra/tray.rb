# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: 2022-2022 Tauri Programme within The Commons Conservancy (tray-icon)
# SPDX-SnippetComment: The tray module adapted from tauri/crates/tauri/src/tray/mod.rs,
#                      and TrayIconId from tray-icon 0.21.0 src/tray_icon_id.rs

module Tokra
  # Tray icons: an app's icon in the system tray.
  #
  # Some apps live in the tray rather than in a window: a clock, a sync
  # client, a music player. This module puts an icon there, from Ruby,
  # with a tooltip, a title, and a menu, and tells the app when the
  # pointer clicks, enters, moves over, or leaves it. Build one with
  # TrayIconBuilder once the app runs, such as in the setup hook, and find
  # it again with AppHandle#tray_by_id. Every tray answers on the main
  # thread; from another thread a call travels there and waits.
  #
  # Mirrors Tauri's <tt>tauri::tray</tt> module (tray/mod.rs), which wraps
  # the tray-icon crate.
  #
  # === Example
  #
  #   Tokra::Builder.default.setup(&Ractor.shareable_proc { |app|
  #     Tokra::Tray::TrayIconBuilder.with_id("main").tooltip("Tokra").build(app)
  #   })
  module Tray
    # The id of a tray icon.
    #
    # Each event names the tray it came from by this id. An id equals
    # another with the same text, and equals that text as a String.
    #
    # Mirrors tray-icon's <tt>TrayIconId(String)</tt>, which Tauri
    # re-exports (tray_icon_id.rs). Rust's tuple struct needs a member name
    # in Ruby's Data, so the text is +value+.
    #
    # === Example
    #
    #   Tokra::Tray::TrayIconId.new(value: "main") == "main"  #=> true
    class TrayIconId < Data.define(:value)
      # The id for +id+: itself if it is a TrayIconId, else one of its
      # text, as tray-icon's <tt>From<T: ToString></tt> makes one.
      #
      # === Example
      #
      #   Tokra::Tray::TrayIconId.from(:main).value  #=> "main"
      def self.from(id)
        id.is_a?(TrayIconId) ? id : new(value: id.to_s)
      end

      # Whether +other+ is this id, or its text (tray-icon's
      # <tt>PartialEq<&str></tt> and <tt>PartialEq<String></tt>).
      def ==(other)
        other.is_a?(String) ? value == other : super
      end

      # The id's text, as tray-icon's <tt>AsRef<str></tt> gives it.
      def to_s
        value
      end

      # The id as JSON: its text alone, as serde writes the newtype struct.
      def to_json(*)
        value.to_json(*)
      end
    end

    # Which mouse button an event came from.
    #
    # Mirrors Tauri's MouseButton (tray/mod.rs:40-50), serialized by name.
    class MouseButton < Data.define(:name)
      extend ClosedEnum

      # The left button.
      Left = new(name: "Left")
      # The right button.
      Right = new(name: "Right")
      # The middle button.
      Middle = new(name: "Middle")

      close

      # The button's name as JSON.
      def to_json(*)
        name.to_json(*)
      end
    end

    # Whether a click pressed or released its button.
    #
    # Mirrors Tauri's MouseButtonState (tray/mod.rs:21-29), serialized by
    # name.
    class MouseButtonState < Data.define(:name)
      extend ClosedEnum

      # The button went up.
      Up = new(name: "Up")
      # The button went down.
      Down = new(name: "Down")

      close

      # The state's name as JSON.
      def to_json(*)
        name.to_json(*)
      end
    end

    # What the pointer did on a tray icon. Each event names its tray by
    # +id+, holds the pointer's +position+ as a PhysicalPosition, and the
    # icon's place on the screen as a Rect.
    #
    # Linux sends none of these: the desktop shows the icon and its menu
    # itself.
    #
    # Mirrors Tauri's TrayIconEvent (tray/mod.rs:62-137). Its variants are
    # the classes here; their JSON is Tauri's, tagged by +type+.
    module TrayIconEvent
      # The JSON fields every event shares.
      module Base # :nodoc:
        # The event as JSON (tray/mod.rs:68-124): its fields, camelCase,
        # tagged by +type+.
        def to_json(*)
          as_json.to_json(*)
        end

        # The event as Tauri serializes it, with +fields+ after the shared
        # ones.
        private def json_with(fields)
          {
"type" => self.class.name.to_s.split("::").last,
"id" => id.value,
"position" => { "x" => position.x, "y" => position.y },
"rect" => rect.as_json,
}.merge(fields)
        end
      end

      # A button went down or up over the icon.
      class Click < Data.define(:id, :position, :rect, :button, :button_state)
        include Base

        # The event as a JSON value (tray/mod.rs:73-85).
        def as_json # :nodoc:
          json_with("button" => button.name, "buttonState" => button_state.name)
        end
      end

      # A button was double-clicked over the icon. Windows only.
      class DoubleClick < Data.define(:id, :position, :rect, :button)
        include Base

        # The event as a JSON value (tray/mod.rs:86-96).
        def as_json # :nodoc:
          json_with("button" => button.name)
        end
      end

      # The pointer entered the icon.
      class Enter < Data.define(:id, :position, :rect)
        include Base

        # The event as a JSON value (tray/mod.rs:97-105).
        def as_json # :nodoc:
          json_with({})
        end
      end

      # The pointer moved over the icon.
      class Move < Data.define(:id, :position, :rect)
        include Base

        # The event as a JSON value (tray/mod.rs:106-114).
        def as_json # :nodoc:
          json_with({})
        end
      end

      # The pointer left the icon.
      class Leave < Data.define(:id, :position, :rect)
        include Base

        # The event as a JSON value (tray/mod.rs:115-123).
        def as_json # :nodoc:
          json_with({})
        end
      end

      # The event for +native+, a Native::TrayIconEvent, as Tauri's
      # <tt>From<tray_icon::TrayIconEvent></tt> makes it
      # (tray/mod.rs:139-199).
      def self.from_native(native) # :nodoc:
        id = TrayIconId.new(value: native.id)
        x, y = native.position
        rect_x, rect_y, width, height = native.rect
        position = PhysicalPosition.new(x:, y:)
        rect = Rect.new(position: PhysicalPosition.new(x: rect_x, y: rect_y),
          size: PhysicalSize.new(width:, height:))
        case native.kind
        when "Click"
          Click.new(id:, position:, rect:, button: MouseButton.const_get(native.button.to_s, false),
            button_state: MouseButtonState.const_get(native.button_state.to_s, false))
        when "DoubleClick"
          DoubleClick.new(id:, position:, rect:, button: MouseButton.const_get(native.button.to_s, false))
        when "Enter" then Enter.new(id:, position:, rect:)
        when "Move" then Move.new(id:, position:, rect:)
        else Leave.new(id:, position:, rect:)
        end
      end
    end

    # The native tray class one app's trays are built with: Native's, or a
    # test's stand-in.
    class Natives < Data.define(:tray_icon) # :nodoc:
      # The tray class of +native+.
      def self.from(native)
        new(tray_icon: native.const_get(:TrayIcon))
      end
    end

    class << self
      # Runs +call+ on the main thread of +manager+'s app and answers its
      # result, as Tauri's run_item_main_thread! does, raising Error::Tray
      # with tray-icon's text for a RuntimeError the native layer raises.
      def run_main_thread(manager, &call) # :nodoc:
        manager.app_handle.runtime_context.run_main_thread do
          call.call
        rescue RuntimeError => e
          # The native layer raises tray-icon's errors as plain
          # RuntimeErrors; a subclass, such as FrozenError, is a bug.
          raise unless e.instance_of?(RuntimeError)

          raise Error::Tray, e.message
        end
      end

      # The native tray classes of +manager+'s app.
      def natives(manager) # :nodoc:
        manager.app_handle.runtime_context.tray_natives
      end

      # tray-icon's icon for +image+, a Tokra::Image: Tauri's
      # <tt>TryFrom<Image> for tray_icon::Icon</tt> (image/mod.rs:149-156),
      # on the calling thread. The icon is plain data (or, on Windows, an
      # +HICON+ tray-icon makes on any thread), so every app's trays share
      # Native's class. Raises Error::BadTrayIcon with tray-icon's text for
      # an image it refuses (plan 043, decision 8).
      def tray_icon(image) # :nodoc:
        Native::TrayIcon::Icon.from_rgba(image.rgba, image.width, image.height)
      rescue RuntimeError => e
        raise unless e.instance_of?(RuntimeError)

        raise Error::BadTrayIcon, e.message
      end

      # The native menu of +menu+, a Menu or Submenu, raising TypeError for
      # anything else, as Tauri's ContextMenu bound would not compile.
      def native_menu(menu) # :nodoc:
        if menu.is_a?(Menu::ContextMenu)
          native = menu.native #: Native::Menu | Native::Submenu
          return native
        end

        raise TypeError, "wrong argument type #{menu.class} (expected Tokra::Menu::Menu or Tokra::Menu::Submenu)"
      end

      # Raises Error::Menu, on the main thread, for a menu muda's GTK
      # context menu would panic on, which tray-icon builds on Linux
      # (plan 043, decision 8). Elsewhere it does nothing.
      def refuse_unbuildable_menu(manager, native_menu) # :nodoc:
        app = Menu.natives(manager).app
        return unless native_menu && app.respond_to?(:refuse_unbuildable_menu)

        Menu.run_main_thread(manager) { app.refuse_unbuildable_menu(native_menu) }
        nil
      end
    end
  end
end

# SPDX-SnippetEnd

require_relative "tray/tray_icon"
require_relative "tray/tray_icon_builder"
require_relative "tray/plugin"
