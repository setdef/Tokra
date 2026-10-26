# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2023 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Builder adapted from tauri-plugin-global-shortcut src/lib.rs:336-387

module Tokra
  module Plugins
    module GlobalShortcut
      # Configures the plugin before it starts: the shortcuts it registers
      # at once, and one handler that hears all of them.
      #
      # An app with a fixed summon key, or a few keys of its own, wants them
      # registered as the app starts, and wants one place to react to every
      # press, rather than a handler per key.
      #
      # This builder collects those shortcuts and that handler. Its #build
      # makes the plugin for an app handle, which registers the shortcuts
      # during setup. The handler also hears every shortcut registered later,
      # through GlobalShortcut or the page, after that shortcut's own handler.
      #
      # Mirrors Tauri's global-shortcut <tt>Builder</tt> (lib.rs:336-387).
      #
      # === Examples
      #
      #   Tokra::Builder.default
      #     .setup(&Ractor.shareable_proc { |app|
      #       state = Tokra::Plugins::GlobalShortcut::ShortcutState
      #       plugin = Tokra::Plugins::GlobalShortcut::Builder.new
      #         .with_shortcuts(["CmdOrCtrl+Shift+D", "Alt+Space"])
      #         .with_handler { |handle, shortcut, event| handle.emit("shortcut", shortcut.to_s) if event.state == state::Pressed }
      #         .build(app.handle)
      #       app.handle.plugin(plugin)
      #     })
      #     .run
      #
      #   Tokra::Plugins::GlobalShortcut::Builder.new.with_shortcut("Ctrl+D").build(handle)
      class Builder
        # The Shortcuts setup registers. The plugin reads them.
        attr_reader :shortcuts # :nodoc:

        # The handler for every shortcut, or +nil+. The plugin reads it.
        attr_reader :handler # :nodoc:

        # A builder with no shortcuts and no handler (lib.rs:341-353).
        #
        # === Example
        #
        #   Tokra::Plugins::GlobalShortcut::Builder.new
        def initialize
          @shortcuts = [] #: Array[Shortcut]
          @handler = nil
        end

        # Add a shortcut to be registered: a Shortcut or a String. Raises
        # Error::GlobalHotkey when the string does not parse. Returns the
        # builder (lib.rs:355-363).
        #
        # === Example
        #
        #   builder.with_shortcut("CmdOrCtrl+Shift+D")
        def with_shortcut(shortcut)
          @shortcuts << Plugins::GlobalShortcut.try_into_shortcut(shortcut)
          self
        end

        # Add multiple shortcuts to be registered, as #with_shortcut does
        # for each. A string that does not parse raises before any is added.
        # Returns the builder (lib.rs:365-377).
        #
        # === Example
        #
        #   builder.with_shortcuts(["Ctrl+D", "Alt+Space"])
        def with_shortcuts(shortcuts)
          @shortcuts.concat(shortcuts.map { |shortcut| Plugins::GlobalShortcut.try_into_shortcut(shortcut) })
          self
        end

        # Specify a global shortcut handler that will be triggered for any
        # and all shortcuts: the block, which receives the app handle, the
        # Shortcut, and the ShortcutEvent. A later call replaces it. Returns
        # the builder (lib.rs:379-386).
        #
        # === Example
        #
        #   builder.with_handler { |_app, shortcut, event| puts "#{shortcut} #{event.state.inspect}" }
        def with_handler(&handler)
          raise ArgumentError, "with_handler needs a block" unless handler

          @handler = handler
          self
        end

        # The plugin for +app+, the app handle, which runs setup at once:
        # it registers the shortcuts and installs the handler. Tauri's
        # +build+ takes no app, since its setup runs when the app adds the
        # plugin; a Tokra plugin's setup is its constructor (Plan 025,
        # decision 2). Raises Tokra::Error::PluginInitialization when setup
        # fails (lib.rs:388-435).
        #
        # === Example
        #
        #   handle.plugin(builder.build(handle))
        def build(app)
          Plugin.new(app, self)
        end
      end
    end
  end
end

# SPDX-SnippetEnd
