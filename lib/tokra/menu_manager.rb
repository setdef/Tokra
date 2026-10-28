# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: MenuManager adapted from tauri/crates/tauri/src/manager/menu.rs

module Tokra
  # The app's menus: the menus in use, the app's own menu, and the menu
  # event listeners.
  #
  # The stash keeps every menu the app or a window uses, so a menu stays
  # alive while it shows; on Windows it is also the list whose keyboard
  # shortcuts the event loop translates (plan 042, decision 10).
  #
  # Mirrors Tauri's MenuManager (manager/menu.rs). Tauri calls the
  # listeners while holding their lock; this copies the list and calls
  # them outside it, so a listener may add another (plan 042, decision 5).
  class MenuManager # :nodoc:
    # A manager with the app's +global_event_listeners+, which the Builder
    # gathered, running native work through +runtime_context+.
    def initialize(runtime_context, global_event_listeners = [])
      @runtime_context = runtime_context
      @mutex = Thread::Mutex.new
      @menus = {} #: Hash[Menu::MenuId, Menu::Menu]
      @menu = nil #: Menu::Menu?
      @global_event_listeners = global_event_listeners.dup
      @event_listeners = {} #: Hash[String, ^(Window, Menu::MenuEvent) -> void]
    end

    # The app's menu, or +nil+.
    def menu
      @mutex.synchronize { @menu }
    end

    # Makes +menu+ the app's menu and returns the one before it.
    def replace_menu(menu)
      @mutex.synchronize do
        previous = @menu
        @menu = menu
        previous
      end
    end

    # Takes the app's menu away and returns it.
    def take_menu
      replace_menu(nil)
    end

    # Whether the app's menu has the id +id+.
    def menu_in_use?(id)
      current = menu
      !current.nil? && current.id == id
    end

    # Keeps +menu+ in the stash.
    def insert_menu_into_stash(menu)
      @mutex.synchronize { @menus[menu.id] = menu }
      stash_changed
    end

    # Drops the menu with the id +id+ from the stash.
    def remove_menu_from_stash(id)
      @mutex.synchronize { @menus.delete(id) }
      stash_changed
    end

    # The stashed menus.
    def menus
      @mutex.synchronize { @menus.values }
    end

    # Adds an app-wide listener, called with the app handle and each
    # MenuEvent.
    def on_menu_event(handler)
      @mutex.synchronize { @global_event_listeners << handler }
      nil
    end

    # Makes +handler+ the listener of the window labeled +label+,
    # replacing any before it, as Tauri's HashMap insert does.
    def set_window_listener(label, handler)
      @mutex.synchronize { @event_listeners[label] = handler }
      nil
    end

    # The app-wide listeners, in the order they came.
    def global_event_listeners
      @mutex.synchronize { @global_event_listeners.dup }
    end

    # The window listeners, by window label.
    def event_listeners
      @mutex.synchronize { @event_listeners.dup }
    end

    # Gives the event loop on Windows the stash's menus, whose keyboard
    # shortcuts it translates. Elsewhere there is nothing to tell it.
    private def stash_changed
      app = @runtime_context.menu_natives.app
      return unless app.respond_to?(:set_accelerator_menus)

      list = menus.map(&:native) #: Array[Native::Menu]
      @runtime_context.run_on_main_thread { app.set_accelerator_menus(list) }
    rescue Error::Runtime
      # The loop has ended: no key will come to translate.
      nil
    end
  end
end

# SPDX-SnippetEnd
