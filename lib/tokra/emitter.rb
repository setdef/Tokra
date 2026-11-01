# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Emitter adapted from tauri/crates/tauri/src/lib.rs

module Tokra
  # Sends events to listeners in Ruby and in the page.
  #
  # Ruby code tells the page, and other Ruby code, that something
  # happened, without knowing who listens. App, AppHandle, Window, and
  # Webview all emit the same way, since an event belongs to the app, not
  # to the object that sent it: #emit reaches every listener, #emit_to the
  # ones a target matches, and #emit_filter the ones a block accepts.
  # Listeners for the Any target hear all three. The page hears the event
  # first, then each Ruby handler runs on the calling thread.
  #
  # The payload is serialized as an IPC response is, a non-finite float
  # becoming +null+; the +_str+ forms take JSON text as it is. Each
  # method raises Error::IllegalEventName for a bad name.
  #
  # Mirrors Tauri's <tt>Emitter</tt> trait (lib.rs:938-1048).
  #
  # === Example
  #
  #   handle.emit("download-progress", { percent: 40 })
  #   handle.emit_to("updater", "download-progress", 40)
  #   handle.emit_filter("download-progress", 40) { |target| target == Tokra::EventTarget.window("main") }
  module Emitter
    # Emits +event+ with +payload+ to every target, and returns +nil+
    # (lib.rs:942-956).
    def emit(event, payload)
      event = Event::Name.check(event)
      app_handle.manager.emit(Event::EmitArgs.serialize(event, payload))
    end

    # Emits +event+ with +payload+, already JSON text, to every target
    # (lib.rs:958-963).
    def emit_str(event, payload)
      event = Event::Name.check(event)
      app_handle.manager.emit(Event::EmitArgs.new(event:, payload:))
    end

    # Emits +event+ with +payload+ to the listeners +target+ matches, an
    # EventTarget or a label String (lib.rs:965-996).
    def emit_to(target, event, payload)
      event = Event::Name.check(event)
      app_handle.manager.emit_to(EventTarget.from(target), Event::EmitArgs.serialize(event, payload))
    end

    # Emits +event+ with +payload+, already JSON text, as #emit_to does
    # (lib.rs:998-1006).
    def emit_str_to(target, event, payload)
      event = Event::Name.check(event)
      app_handle.manager.emit_to(EventTarget.from(target), Event::EmitArgs.new(event:, payload:))
    end

    # Emits +event+ with +payload+ to the listeners whose EventTarget the
    # block accepts (lib.rs:1008-1034). The block is required, as Tauri's
    # filter is; without one this raises ArgumentError.
    def emit_filter(event, payload, &filter)
      raise ArgumentError, "emit_filter needs a filter block" unless filter

      event = Event::Name.check(event)
      app_handle.manager.emit_filter(Event::EmitArgs.serialize(event, payload), filter)
    end

    # Emits +event+ with +payload+, already JSON text, as #emit_filter
    # does (lib.rs:1036-1044), and needs its block as #emit_filter does.
    def emit_str_filter(event, payload, &filter)
      raise ArgumentError, "emit_str_filter needs a filter block" unless filter

      event = Event::Name.check(event)
      app_handle.manager.emit_filter(Event::EmitArgs.new(event:, payload:), filter)
    end
  end
end

# SPDX-SnippetEnd
