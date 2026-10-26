# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: GlobalShortcut, GlobalShortcutExt, and the shortcut
#                      conversions adapted from tauri-plugin-global-shortcut
#                      src/lib.rs:38-266

module Tokra
  module Plugins
    module GlobalShortcut
      # +shortcut+ as a Shortcut: a Shortcut as it is, or a String parsed
      # as global-hotkey parses one, raising Error::GlobalHotkey with the
      # parse error's message. Mirrors +try_into_shortcut+ and
      # +ShortcutWrapper+ (lib.rs:41-54, 258-266).
      def self.try_into_shortcut(shortcut) # :nodoc:
        case shortcut
        when Shortcut then shortcut
        when String then parse_shortcut(shortcut)
        else raise TypeError, "no implicit conversion of #{shortcut.class} into #{Shortcut}"
        end
      end

      # +string+ parsed as a Shortcut, raising Error::GlobalHotkey with the
      # parse error's message (lib.rs:254-256, error.rs:33-37).
      def self.parse_shortcut(string) # :nodoc:
        Shortcut.from_str(string)
      rescue Ferro::GlobalHotkey::Hotkey::HotKeyParseError => e
        raise Error::GlobalHotkey, e.message
      end

      # The global shortcuts an app registers, shared through managed state.
      #
      # A launcher's summon key, a recorder's push-to-talk, a screenshot
      # tool's capture key all have to work while another app is in front.
      # The system grants that one combination at a time, takes it away from
      # every other program while you hold it, and reports each press on a
      # thread of its own choosing.
      #
      # The plugin registers shortcuts with the system for you and manages
      # one GlobalShortcut, which every manager reaches as +global_shortcut+.
      # Register a Shortcut, or a string such as <tt>"CmdOrCtrl+Shift+K"</tt>,
      # with or without a handler, ask whether one is registered, and
      # unregister it when you are done. A handler is a block that takes the
      # app handle, the Shortcut, and the ShortcutEvent, which says whether
      # the keys went down (ShortcutState::Pressed) or came up
      # (ShortcutState::Released).
      #
      # Every call reaches the system on the main thread, as the system
      # asks: from the main thread it runs at once, and from another thread
      # it waits for the event loop to run it. A handler runs on a thread of
      # its own, never the main thread, so a slow one does not freeze the
      # window. If the shortcut is already taken by another application, its
      # handler is not triggered, so choose a combination that is unlikely
      # to clash.
      #
      # Mirrors Tauri's <tt>GlobalShortcut</tt> (lib.rs:68-242).
      #
      # === Examples
      #
      #   shortcuts = handle.global_shortcut
      #   shortcuts.on_shortcut("CmdOrCtrl+Shift+K") do |app, shortcut, event|
      #     app.emit("summon", nil) if event.state == Tokra::Plugins::GlobalShortcut::ShortcutState::Pressed
      #   end
      #   shortcuts.is_registered("CmdOrCtrl+Shift+K")  #=> true
      #   shortcuts.unregister("CmdOrCtrl+Shift+K")
      #
      #   modifiers = Tokra::Plugins::GlobalShortcut::Modifiers
      #   code = Tokra::Plugins::GlobalShortcut::Code
      #   push_to_talk = Tokra::Plugins::GlobalShortcut::Shortcut.new(modifiers::ALT, code::Space)
      #   shortcuts.register_multiple([push_to_talk, "CmdOrCtrl+Shift+R"])
      #   shortcuts.unregister_all
      class GlobalShortcut
        # A registered shortcut and its own handler, if any (lib.rs:56-59).
        class RegisteredShortcut < Data.define(:shortcut, :handler); end

        # Creates the shortcuts for +app+, the app handle, with +manager+,
        # a Ferro::GlobalHotkey::GlobalHotKeyManager made on the main
        # thread, and +shortcuts+, the Hash of RegisteredShortcut by id that
        # setup already registered. The plugin does this once and manages
        # the result (lib.rs:427-431).
        def initialize(app, manager, shortcuts) # :nodoc:
          @app = app
          @manager = manager
          @shortcuts = shortcuts
          @lock = Thread::Mutex.new
        end

        # Registers +shortcut+, a Shortcut or a String, with no handler of
        # its own; the Builder's handler still hears it (lib.rs:130-140).
        # Raises Error::GlobalHotkey when it does not parse or the system
        # refuses it. Returns +nil+.
        #
        # === Example
        #
        #   handle.global_shortcut.register("Alt+Space")
        def register(shortcut)
          register_internal(Plugins::GlobalShortcut.try_into_shortcut(shortcut), nil)
        end

        # Registers +shortcut+ with a handler, the block, which receives the
        # app handle, the Shortcut, and the ShortcutEvent (lib.rs:142-150).
        # Raises as #register does. Returns +nil+.
        #
        # === Example
        #
        #   handle.global_shortcut.on_shortcut("CmdOrCtrl+Shift+K") do |app, shortcut, event|
        #     puts "#{shortcut} #{event.state.inspect}"
        #   end
        def on_shortcut(shortcut, &handler)
          raise ArgumentError, "on_shortcut needs a block for the handler" unless handler

          register_internal(Plugins::GlobalShortcut.try_into_shortcut(shortcut), handler)
        end

        # Registers each of +shortcuts+, an Array of Shortcuts or Strings,
        # with no handler of its own (lib.rs:152-164). Every one is parsed
        # before any is registered; a failure to register stops there, and
        # the ones before it stay registered. Returns +nil+.
        #
        # === Example
        #
        #   handle.global_shortcut.register_multiple(["Alt+Space", "CmdOrCtrl+Shift+R"])
        def register_multiple(shortcuts)
          register_multiple_internal(shortcuts.map { |shortcut| Plugins::GlobalShortcut.try_into_shortcut(shortcut) }, nil)
        end

        # Registers each of +shortcuts+ with one handler, the block, as
        # #register_multiple does (lib.rs:166-179). Returns +nil+.
        #
        # === Example
        #
        #   handle.global_shortcut.on_shortcuts(["F17", "F18"]) { |_app, shortcut, _event| puts shortcut }
        def on_shortcuts(shortcuts, &handler)
          raise ArgumentError, "on_shortcuts needs a block for the handler" unless handler

          register_multiple_internal(shortcuts.map { |shortcut| Plugins::GlobalShortcut.try_into_shortcut(shortcut) }, handler)
        end

        # Unregisters +shortcut+, a Shortcut or a String (lib.rs:181-190).
        # Raises Error::GlobalHotkey when it does not parse or the system
        # refuses. Returns +nil+.
        #
        # === Example
        #
        #   handle.global_shortcut.unregister("Alt+Space")
        def unregister(shortcut)
          shortcut = Plugins::GlobalShortcut.try_into_shortcut(shortcut)
          run_main_thread { |manager| manager.unregister(shortcut) }
          removed = @lock.synchronize { @shortcuts.delete(shortcut.id) }
          release([removed&.handler])
        end

        # Unregisters each of +shortcuts+ (lib.rs:192-217). Every one is
        # parsed first. Returns +nil+.
        #
        # === Example
        #
        #   handle.global_shortcut.unregister_multiple(["Alt+Space", "F17"])
        def unregister_multiple(shortcuts)
          mapped = shortcuts.map { |shortcut| Plugins::GlobalShortcut.try_into_shortcut(shortcut) }
          run_main_thread { |manager| manager.unregister_all(mapped) }
          removed = @lock.synchronize { mapped.filter_map { |shortcut| @shortcuts.delete(shortcut.id) } }
          release(removed.map(&:handler))
        end

        # Unregisters every shortcut this app registered (lib.rs:219-227).
        # The shortcuts are forgotten even when the system refuses to let one
        # go. Returns +nil+.
        #
        # === Example
        #
        #   handle.global_shortcut.unregister_all
        def unregister_all
          taken = @lock.synchronize do
            registered = @shortcuts.values
            @shortcuts.clear
            registered
          end
          run_main_thread { |manager| manager.unregister_all(taken.map(&:shortcut)) }
        ensure
          release(taken.to_a.map(&:handler))
        end

        # Determines whether the given shortcut is registered by this
        # application or not.
        #
        # If the shortcut is registered by another application, it will
        # still return +false+. A string that does not parse is +false+ too
        # (lib.rs:229-241).
        #
        # === Example
        #
        #   handle.global_shortcut.is_registered("Alt+Space")  #=> false
        def is_registered(shortcut)
          id = Plugins::GlobalShortcut.try_into_shortcut(shortcut).id
          @lock.synchronize { @shortcuts.key?(id) }
        rescue Error::GlobalHotkey
          false
        end

        # Calls the handlers for +event+, a ShortcutEvent: the shortcut's
        # own, then +global+, the Builder's, each with the app handle and
        # the Shortcut. An event for a shortcut this app did not register
        # calls nothing. This is the body of the event handler the plugin
        # installs (lib.rs:416-425). The handlers run after the lock is
        # released (Plan 025, decision 6), and one that raises is reported
        # with +warn+ without stopping the next.
        def handle_event(event, global) # :nodoc:
          entry = @lock.synchronize { @shortcuts[event.id] }
          return unless entry

          [entry.handler, global].compact.each do |handler|
            handler.call(@app, entry.shortcut, event)
          rescue => e
            warn("global shortcut handler failed: #{e.full_message(highlight: false)}")
          end
          nil
        end

        # Registers +shortcut+ on the main thread, then stores it with
        # +handler+ (lib.rs:89-102).
        private def register_internal(shortcut, handler)
          register_multiple_internal([shortcut], handler)
        end

        # Registers and stores each of +shortcuts+ in turn, with +handler+,
        # stopping at the first failure (lib.rs:104-126). The lock is taken
        # for each store, not across the main-thread calls (Plan 025,
        # decision 6). The register command calls it with its Channel
        # handler.
        def register_multiple_internal(shortcuts, handler) # :nodoc:
          replaced = []
          shortcuts.each do |shortcut|
            run_main_thread { |manager| manager.register(shortcut) }
            entry = RegisteredShortcut.new(shortcut:, handler:)
            previous = @lock.synchronize do
              old = @shortcuts[shortcut.id]
              @shortcuts[shortcut.id] = entry
              old
            end
            replaced << previous.handler if previous
          end
          nil
        ensure
          release([handler, *replaced])
        end

        # Runs the block with the manager on the main thread and returns its
        # result, as <tt>run_main_thread!</tt> does (lib.rs:75-86), with
        # global-hotkey's errors and the main thread's as Tauri's +?+
        # converts them.
        private def run_main_thread
          manager = @manager
          @app.runtime_context.getter { yield manager }
        rescue Ferro::GlobalHotkey::Error => e
          raise Error::GlobalHotkey, e.message
        rescue Tokra::Error::Runtime => e
          raise Error::RecvError if e.message.end_with?(Tokra::Error::Runtime::FAILED_TO_RECEIVE_MESSAGE)

          raise Error::Tauri, e.message
        end

        # Drops each channel handler in +handlers+ that no registered
        # shortcut holds any longer, as Rust drops the register command's
        # closure with its last shortcut (Plan 025, decision 5).
        private def release(handlers)
          handlers.compact.uniq.each do |handler|
            next unless handler.is_a?(Commands::ChannelHandler)
            next if @lock.synchronize { @shortcuts.each_value.any? { |entry| entry.handler.equal?(handler) } }

            handler.drop
          end
          nil
        end
      end

      # Gives every manager a +global_shortcut+ method.
      #
      # When included into Tokra::Manager, an app handle, window, or webview
      # reaches the managed GlobalShortcut directly:
      #
      #   handle.global_shortcut.register("Alt+Space")
      #
      # Mirrors Tauri's <tt>GlobalShortcutExt</tt> blanket implementation
      # (lib.rs:244-252).
      module GlobalShortcutExt
        # The GlobalShortcut the plugin manages. Raises +KeyError+ before
        # the plugin is registered.
        #
        # === Example
        #
        #   window.global_shortcut.is_registered("Alt+Space")
        def global_shortcut
          state(GlobalShortcut)
        end
      end
    end
  end
end

# SPDX-SnippetEnd
