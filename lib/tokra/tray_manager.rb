# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: TrayManager adapted from tauri/crates/tauri/src/manager/tray.rs

module Tokra
  # The app's tray icons and their listeners, which Tauri's AppManager
  # holds (manager/tray.rs).
  #
  # Each list is guarded by one mutex, and every listener is copied out
  # before it is called, so a listener may register another (plan 043,
  # decision 4).
  class TrayManager # :nodoc:
    # An entry of the icons: a tray's id and its rid in the app's
    # resources table.
    Entry = Data.define(:id, :rid)

    def initialize(global_event_listeners = [])
      @mutex = Thread::Mutex.new
      @icons = [] #: Array[Entry]
      @global_event_listeners = global_event_listeners.dup
      @event_listeners = {} #: Hash[Tray::TrayIconId, ^(Tray::TrayIcon, Tray::TrayIconEvent::event) -> void]
    end

    # Adds +handler+ to the listeners of every tray's events
    # (manager/tray.rs:37-46).
    def on_tray_icon_event(handler)
      @mutex.synchronize { @global_event_listeners << handler }
      nil
    end

    # Makes +handler+ the listener of the tray +id+, replacing any
    # (tray/mod.rs:437-445, 479-491).
    def set_tray_listener(id, handler)
      @mutex.synchronize { @event_listeners[id] = handler }
      nil
    end

    # Records the tray +id+ at +rid+ (tray/mod.rs:447-454).
    def insert(id, rid)
      @mutex.synchronize { @icons << Entry.new(id:, rid:) }
      nil
    end

    # Forgets the first tray with +id+, as TrayIcon's Resource::close does
    # (tray/mod.rs:610-620).
    def delete(id)
      @mutex.synchronize do
        index = @icons.index { |entry| entry.id == id }
        @icons.delete_at(index) if index
      end
      nil
    end

    # The rid of the first tray with +id+, or +nil+
    # (manager/tray.rs:64-77).
    def tray_resource_by_id(id)
      id = Tray::TrayIconId.from(id)
      @mutex.synchronize { @icons.find { |entry| entry.id == id }&.rid }
    end

    # The tray with +id+ in +app+'s resources table, or +nil+: the first
    # icon with the id whose resource is still a tray (manager/tray.rs:48-62).
    def tray_by_id(app, id)
      id = Tray::TrayIconId.from(id)
      entries = @mutex.synchronize { @icons.select { |entry| entry.id == id } }
      entries.each do |entry|
        next unless app.resources_table.has?(entry.rid)

        resource = app.resources_table.get(entry.rid)
        return resource if resource.is_a?(Tray::TrayIcon)
      end
      nil
    end

    # Takes the tray with +id+ out of +app+'s resources table, closes it,
    # and returns it, or +nil+ (manager/tray.rs:79-89).
    def remove_tray_by_id(app, id)
      rid = tray_resource_by_id(id)
      return nil unless rid && app.resources_table.has?(rid)

      resource = app.resources_table.get(rid)
      return nil unless resource.is_a?(Tray::TrayIcon)

      app.resources_table.take(rid)
      resource.close
      resource
    end

    # Closes every tray, as Tauri's cleanup_before_exit drops them by
    # clearing the app's resources table (app.rs:1026-1028; plan 043,
    # decision 7).
    def close_all(app)
      entries = @mutex.synchronize { @icons.dup }
      entries.each do |entry|
        table = app.resources_table
        next unless table.has?(entry.rid) && table.get(entry.rid).is_a?(Tray::TrayIcon)

        tray = table.take(entry.rid) #: Tray::TrayIcon
        begin
          tray.close
        rescue Tokra::Error
          next
        end
      end
      @mutex.synchronize { @icons.clear }
      nil
    end

    # A copy of the app-wide listeners.
    def global_event_listeners
      @mutex.synchronize { @global_event_listeners.dup }
    end

    # A copy of the per-tray listeners.
    def event_listeners
      @mutex.synchronize { @event_listeners.dup }
    end
  end
end

# SPDX-SnippetEnd
