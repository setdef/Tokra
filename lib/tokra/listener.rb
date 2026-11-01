# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Listener adapted from tauri/crates/tauri/src/lib.rs

module Tokra
  # Hears events that Ruby or the page emits.
  #
  # Each listener is registered for a target. App and AppHandle listen as
  # the app, a Window as itself, a Webview as itself, so an event sent to
  # one window with Emitter#emit_to reaches that window's listeners and
  # not the others'. #listen_any and #once_any hear an event whatever its
  # target.
  #
  # Each including class defines #listen, #once, and #unlisten for its
  # own target, as each of Tauri's impls does; this module provides
  # #listen_any and #once_any. The handler receives an Event and runs on
  # the thread that emitted it. Each method raises
  # Error::IllegalEventName for a bad name.
  #
  # Mirrors Tauri's <tt>Listener</tt> trait (lib.rs:829-936).
  #
  # === Example
  #
  #   id = window.listen("refresh") { |event| reload(JSON.parse(event.payload)) }
  #   window.unlisten(id)
  module Listener
    # Calls the block with each +event+ sent to any target, and returns
    # the handler's id (lib.rs:893-922).
    def listen_any(event, &handler)
      app_handle.manager.listen(Event::Name.check(event), EventTarget.any, &handler)
    end

    # Calls the block with the next +event+ sent to any target, and
    # returns the handler's id (lib.rs:924-935).
    def once_any(event, &handler)
      app_handle.manager.once(Event::Name.check(event), EventTarget.any, &handler)
    end
  end
end

# SPDX-SnippetEnd
