# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Commands adapted from tauri-plugin-global-shortcut
#                      src/lib.rs:268-334

module Tokra
  module Plugins
    module GlobalShortcut
      # The plugin's IPC commands: register, unregister, unregister_all,
      # and is_registered.
      #
      # Each answers the frontend the way Tauri's plugin does. Arguments are
      # read as Tauri deserializes them, so a bad one rejects with Tauri's
      # message, and a shortcut that does not parse rejects with
      # global-hotkey's. +register+ takes the page's Channel and sends each
      # press and release of the shortcuts through it, as
      # <tt>{ shortcut, id, state }</tt>.
      #
      # These are Tauri's command functions (lib.rs:275-334). Plugin#extend_api
      # calls them.
      module Commands
        # The handler the register command gives its shortcuts: it sends
        # each event through the page's Channel as a ShortcutJsEvent, and is
        # dropped, ending the channel, when no shortcut holds it any longer
        # (lib.rs:268-273, 293-302).
        class ChannelHandler # :nodoc:
          # A handler sending through +channel+, a Tokra::Ipc::Channel.
          def initialize(channel)
            @channel = channel
          end

          # Sends <tt>{ shortcut, id, state }</tt> for +event+ on +shortcut+,
          # ignoring a channel that can no longer send, as Tauri's
          # <tt>let _ =</tt> does.
          def call(_app, shortcut, event)
            state = (event.state == ShortcutState::Pressed) ? "Pressed" : "Released"
            # Channel#send is Tauri's name (channel.rs:291-297), not Object#send.
            @channel.send({ "shortcut" => shortcut.into_string, "id" => event.id, "state" => state }) # rubocop:disable Style/Send
          rescue Tokra::Error
            nil
          end

          # Ends the channel, as Rust drops the closure that owns it.
          def drop
            @channel.drop
          end
        end

        # Registers the +shortcuts+ the page names, sending their events
        # through its +handler+ Channel, and settles +invoke+ with +nil+
        # (lib.rs:275-304).
        #
        # === Example
        #
        #   Commands.register(invoke, handle.global_shortcut)
        def self.register(invoke, global_shortcut)
          shortcuts = Tokra::Ipc::CommandItem.new(name: "register", key: "shortcuts", payload: invoke.payload).strings
          handler = ChannelHandler.new(Tokra::Ipc::Channel.from_command(invoke, "handler"))
          hotkeys = begin
            shortcuts.map { |shortcut| Plugins::GlobalShortcut.parse_shortcut(shortcut) }
          rescue Error
            handler.drop
            raise
          end
          global_shortcut.register_multiple_internal(hotkeys, handler)
          invoke.resolve(nil)
        end

        # Unregisters the +shortcuts+ the page names and settles +invoke+
        # with +nil+ (lib.rs:306-317).
        #
        # === Example
        #
        #   Commands.unregister(invoke, handle.global_shortcut)
        def self.unregister(invoke, global_shortcut)
          shortcuts = Tokra::Ipc::CommandItem.new(name: "unregister", key: "shortcuts", payload: invoke.payload).strings
          hotkeys = shortcuts.map { |shortcut| Plugins::GlobalShortcut.parse_shortcut(shortcut) }
          global_shortcut.unregister_multiple(hotkeys)
          invoke.resolve(nil)
        end

        # Unregisters every shortcut and settles +invoke+ with +nil+
        # (lib.rs:319-325).
        #
        # === Example
        #
        #   Commands.unregister_all(invoke, handle.global_shortcut)
        def self.unregister_all(invoke, global_shortcut)
          global_shortcut.unregister_all
          invoke.resolve(nil)
        end

        # Settles +invoke+ with whether the +shortcut+ the page names is
        # registered by this app. Unlike GlobalShortcut#is_registered, a
        # shortcut that does not parse rejects (lib.rs:327-334).
        #
        # === Example
        #
        #   Commands.is_registered(invoke, handle.global_shortcut)
        def self.is_registered(invoke, global_shortcut)
          shortcut = Tokra::Ipc::CommandItem.new(name: "is_registered", key: "shortcut", payload: invoke.payload).string
          invoke.resolve(global_shortcut.is_registered(Plugins::GlobalShortcut.parse_shortcut(shortcut)))
        end
      end
    end
  end
end

# SPDX-SnippetEnd
