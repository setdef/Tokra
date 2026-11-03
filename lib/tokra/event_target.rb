# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetCopyrightText: Erick Tryzelaar and David Tolnay (serde, serde_json)
# SPDX-SnippetComment: EventTarget adapted from tauri/crates/tauri/src/event/mod.rs;
#                      its reader follows serde 1.0.228's internally tagged enums

module Tokra
  # Who an event is for.
  #
  # Every listener is registered for a target: App#listen for the app,
  # Window#listen for that window, Webview#listen for that webview, and
  # Listener#listen_any for any. Emitter#emit_to sends an event to the
  # listeners whose target matches, and the page names one the same way
  # in <tt>emitTo</tt> and in <tt>listen</tt>'s options.
  #
  # Each variant is a value class; the module functions make them as
  # Tauri's constructors do. Mirrors Tauri's <tt>EventTarget</tt>
  # (event/mod.rs:22-110).
  #
  # === Example
  #
  #   app.emit_to(Tokra::EventTarget.window("main"), "refresh", nil)
  #   app.emit_to("main", "refresh", nil) # any window or webview labeled "main"
  module EventTarget
    # Any and all event targets.
    class Any < Data.define
      # The target as JSON, tagged with its kind as serde writes it:
      # <tt>{"kind": "Any"}</tt>.
      def to_json(state = nil)
        json = EventTarget.as_json(self)
        state ? json.to_json(state) : json.to_json
      end
    end

    # Any Window, Webview, or webview window with this label.
    class AnyLabel < Data.define(:label)
      # The target as JSON, tagged with its kind as serde writes it:
      # <tt>{"kind": "AnyLabel", "label": "..."}</tt>.
      def to_json(state = nil)
        json = EventTarget.as_json(self)
        state ? json.to_json(state) : json.to_json
      end
    end

    # The App and AppHandle.
    class App < Data.define
      # The target as JSON, tagged with its kind as serde writes it:
      # <tt>{"kind": "App"}</tt>.
      def to_json(state = nil)
        json = EventTarget.as_json(self)
        state ? json.to_json(state) : json.to_json
      end
    end

    # The Window with this label.
    class Window < Data.define(:label)
      # The target as JSON, tagged with its kind as serde writes it:
      # <tt>{"kind": "Window", "label": "..."}</tt>.
      def to_json(state = nil)
        json = EventTarget.as_json(self)
        state ? json.to_json(state) : json.to_json
      end
    end

    # The Webview with this label.
    class Webview < Data.define(:label)
      # The target as JSON, tagged with its kind as serde writes it:
      # <tt>{"kind": "Webview", "label": "..."}</tt>.
      def to_json(state = nil)
        json = EventTarget.as_json(self)
        state ? json.to_json(state) : json.to_json
      end
    end

    # The webview window with this label. Tokra's own windows listen as a
    # Window and a Webview; the page may listen as a webview window.
    class WebviewWindow < Data.define(:label)
      # The target as JSON, tagged with its kind as serde writes it:
      # <tt>{"kind": "WebviewWindow", "label": "..."}</tt>.
      def to_json(state = nil)
        json = EventTarget.as_json(self)
        state ? json.to_json(state) : json.to_json
      end
    end

    # The variants, in declaration order.
    VARIANTS = [Any, AnyLabel, App, Window, Webview, WebviewWindow].freeze

    # The variants' names, as serde names them.
    NAMES = %w[Any AnyLabel App Window Webview WebviewWindow].freeze

    # The variants that carry a label.
    LABELED = %w[AnyLabel Window Webview WebviewWindow].freeze

    # The Any target.
    def self.any
      Any.new
    end

    # The App target.
    def self.app
      App.new
    end

    # The AnyLabel target for +label+.
    def self.labeled(label)
      AnyLabel.new(label:)
    end

    # The Window target for +label+.
    def self.window(label)
      Window.new(label:)
    end

    # The Webview target for +label+.
    def self.webview(label)
      Webview.new(label:)
    end

    # The WebviewWindow target for +label+.
    def self.webview_window(label)
      WebviewWindow.new(label:)
    end

    # +value+ as a target: a String is the AnyLabel for it, as Rust's
    # <tt>From<T: AsRef<str>></tt> makes it, and a target is itself.
    # Anything else raises TypeError.
    def self.from(value)
      case value
      when String then labeled(value)
      when *VARIANTS then value
      else raise TypeError, "no implicit conversion of #{value.class} into Tokra::EventTarget"
      end
    end

    # +target+ as serde's internally tagged form writes it.
    def self.as_json(target) # :nodoc:
      case target
      when Any then { "kind" => "Any" }
      when App then { "kind" => "App" }
      when AnyLabel then { "kind" => "AnyLabel", "label" => target.label }
      when Window then { "kind" => "Window", "label" => target.label }
      when Webview then { "kind" => "Webview", "label" => target.label }
      when WebviewWindow then { "kind" => "WebviewWindow", "label" => target.label }
      end
    end

    # The target a command argument holds, read as serde reads an
    # internally tagged enum from serde_json's Value: an object whose
    # +kind+ names the variant, or a sequence whose first element does
    # (Ipc::Serde.internally_tagged), then the variant's +label+ from the
    # rest (serde_derive de/enum_internally.rs:46, de/struct_.rs:50).
    def self.read(item) # :nodoc:
      item.deserialize do |value|
        kind, rest = Ipc::Serde.internally_tagged(value, "kind", "EventTarget", NAMES)
        rest.is_a?(Hash) ? from_map(kind, rest) : from_seq(kind, rest)
      end
    end

    def self.from_map(kind, map)
      return build(kind, nil) unless LABELED.include?(kind)
      raise Ipc::CommandItem::Mismatch, "missing field `label`" unless map.key?("label")

      build(kind, label(map["label"]))
    end
    private_class_method :from_map

    def self.from_seq(kind, rest)
      unless LABELED.include?(kind)
        # A unit variant reads the rest as an empty sequence (serde
        # private/de.rs:1092-1101; serde_core de/value.rs:1030-1042).
        raise Ipc::CommandItem::Mismatch, "invalid length #{rest.length}, expected 0 elements in sequence" unless rest.empty?

        return build(kind, nil)
      end

      if rest.empty?
        raise Ipc::CommandItem::Mismatch, "invalid length 0, expected struct variant EventTarget::#{kind} with 1 element"
      end
      label = label(rest.first)
      raise Ipc::CommandItem::Mismatch, "invalid length #{rest.length}, expected 1 element in sequence" if rest.length > 1

      build(kind, label)
    end
    private_class_method :from_seq

    def self.build(kind, label)
      case kind
      when "Any" then any
      when "App" then app
      when "AnyLabel" then labeled(label.to_s)
      when "Window" then window(label.to_s)
      when "Webview" then webview(label.to_s)
      else webview_window(label.to_s)
      end
    end
    private_class_method :build

    def self.label(value)
      raise Ipc::CommandItem::Mismatch.invalid_type(value, "a string") unless value.is_a?(String)

      value
    end
    private_class_method :label
  end
end

# SPDX-SnippetEnd
