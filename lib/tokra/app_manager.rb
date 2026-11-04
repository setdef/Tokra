# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: AppManager structure adapted from tauri/crates/tauri/src/manager/mod.rs

module Tokra
  # Internal manager for application state (minimal MVP subset of Tauri's AppManager).
  #
  # See tauri/src/manager/mod.rs AppManager
  class AppManager < Data.define(:config, :package_info, :pattern, :dev, :webviews, :windows, :plugins, :invoke_key,
    :listeners)
    # Creates a new AppManager.
    #
    # +config+, +package_info+, +pattern+, and +dev+ are the Context's, as
    # Tauri's AppManager takes them from its context
    # (manager/mod.rs:249-322). +plugins+ defaults to an empty PluginStore,
    # mirroring Tauri's AppManager which always owns its plugin store. +invoke_key+
    # defaults to a fresh per-app key (Tokra.generate_invoke_key),
    # mirroring the invoke_key member Tauri's AppManager holds
    # (manager/mod.rs). +listeners+ is the app's event registry, an
    # Event::Listeners.
    def self.new(config:, package_info:, pattern:, dev:, webviews:, windows:, plugins: PluginStore.new,
      invoke_key: Tokra.generate_invoke_key, listeners: Event::Listeners.new
    )
      super
    end

    # Adds +handler+ for +event+ and +target+ (manager/mod.rs:502-511).
    def listen(event, target, &handler)
      listeners.listen(event, target, &handler)
    end

    # Adds a handler that hears one event (manager/mod.rs:513-522).
    def once(event, target, &handler)
      listeners.once(event, target, &handler)
    end

    # Removes the handler with +id+ (manager/mod.rs:524-526).
    def unlisten(id)
      listeners.unlisten(id)
    end

    # Hands +emit_args+, an Event::EmitArgs, to every page listener, then
    # to every Ruby handler (manager/mod.rs:528-551).
    def emit(emit_args)
      listeners.emit_js(webviews.values, emit_args)
      listeners.emit(emit_args)
      nil
    end

    # Hands +emit_args+ to the page listeners and Ruby handlers whose
    # target is Any or passes +filter+ (manager/mod.rs:553-586).
    def emit_filter(emit_args, filter)
      listeners.emit_js_filter(webviews.values, emit_args, filter)
      listeners.emit_filter(emit_args, filter)
      nil
    end

    # Hands +emit_args+ to the listeners +target+ matches: every one for
    # Any, otherwise each whose target names the same label in a way
    # +target+ accepts (manager/mod.rs:588-635).
    def emit_to(target, emit_args)
      return emit(emit_args) if target == EventTarget.any

      emit_filter(emit_args, -> (candidate) { AppManager.filter_target(target, candidate) })
    end

    # Whether +candidate+, a listener's target, hears an event sent to
    # +target+ (manager/mod.rs:597-628).
    def self.filter_target(target, candidate)
      case target
      when EventTarget::AnyLabel
        case candidate
        when EventTarget::Window, EventTarget::Webview, EventTarget::WebviewWindow, EventTarget::AnyLabel
          candidate.label == target.label
        else false
        end
      when EventTarget::Window then same_label?(candidate, EventTarget::Window, target.label)
      when EventTarget::Webview then same_label?(candidate, EventTarget::Webview, target.label)
      when EventTarget::WebviewWindow then same_label?(candidate, EventTarget::WebviewWindow, target.label)
      else target == candidate
      end
    end

    # Whether +candidate+ is an AnyLabel or a +kind+ with +label+.
    def self.same_label?(candidate, kind, label)
      case candidate
      when EventTarget::AnyLabel, EventTarget::Window, EventTarget::Webview, EventTarget::WebviewWindow
        (candidate.is_a?(EventTarget::AnyLabel) || candidate.instance_of?(kind)) && candidate.label == label
      else false
      end
    end
    private_class_method :same_label?
  end
end

# SPDX-SnippetEnd
