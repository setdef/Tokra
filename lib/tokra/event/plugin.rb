# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Event plugin adapted from tauri/crates/tauri/src/event/plugin.rs

module Tokra
  class Event
    # Core plugin answering the event commands of
    # <tt>@tauri-apps/api/event</tt>.
    #
    # The page's +listen+, +once+, +emit+, and +emitTo+ call
    # <tt>plugin:event|listen</tt>, +unlisten+, +emit+, and +emit_to+.
    # This plugin answers them against the app's registry, so the page and
    # Ruby hear each other's events, and its init script gives the page
    # the function that drops a listener's callback. Tokra registers it
    # first among its core plugins, as Tauri's register_core_plugins does.
    #
    # Each command reads its arguments in Tauri's order and rejects with
    # Tauri's <tt>invalid args</tt> message for the first that does not
    # read.
    #
    # Mirrors Tauri's event/plugin.rs.
    class Plugin < Tokra::Plugin
      # Returns the plugin identifier.
      def name
        "event"
      end

      # Defines <tt>window.__TAURI_EVENT_PLUGIN_INTERNALS__</tt> with
      # +unregisterListener+, which drops a listener's callback in the
      # page (event/plugin.rs:60-76, event/init.js).
      def initialization_script
        listeners = app.manager.listeners
        ERB.new(Native.load_js_template("event_plugin_init.js.erb")).result_with_hash(
          unregister_listener_function: "(event, eventId) => #{
            Event.unlisten_js_script(listeners.listeners_object_name, 'event', 'eventId')
          }"
        )
      end

      # Answers +listen+, +unlisten+, +emit+, and +emit_to+
      # (event/plugin.rs:14-58). Returns +false+ for any other command.
      def extend_api(invoke)
        case invoke.command
        when "listen" then listen(invoke)
        when "unlisten" then unlisten(invoke)
        when "emit" then emit(invoke)
        when "emit_to" then emit_to(invoke)
        else return false
        end
        true
      rescue Error::InvalidArgs => e
        invoke.reject(e.message)
        true
      end

      private def listen(invoke)
        event = Name.read(item(invoke, "event"))
        target = EventTarget.read(item(invoke, "target"))
        handler = item(invoke, "handler").u32
        invoke.resolve(invoke.webview.listen_js(event, target, handler))
      end

      private def unlisten(invoke)
        event = Name.read(item(invoke, "event"))
        event_id = item(invoke, "eventId").u32
        invoke.webview.unlisten_js(event, event_id)
        invoke.resolve(nil)
      end

      private def emit(invoke)
        event = Name.read(item(invoke, "event"))
        payload = item(invoke, "payload").deserialize_option { |value| value }
        app.emit(event, payload)
        invoke.resolve(nil)
      end

      private def emit_to(invoke)
        target = EventTarget.read(item(invoke, "target"))
        event = Name.read(item(invoke, "event"))
        payload = item(invoke, "payload").deserialize_option { |value| value }
        app.emit_to(target, event, payload)
        invoke.resolve(nil)
      end

      private def item(invoke, key)
        Ipc::CommandItem.new(name: invoke.command, key:, payload: invoke.body)
      end
    end
  end
end

# SPDX-SnippetEnd
