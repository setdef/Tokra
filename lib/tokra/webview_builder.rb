# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WebviewBuilder adapted from tauri/crates/tauri/src/webview/mod.rs,
#                      tauri-runtime/src/webview.rs, and tauri-runtime-wry/src/lib.rs

module Tokra
  # The webview rows of a WebviewWindowBuilder, as Tauri's WebviewBuilder
  # holds them (webview/mod.rs:270-282, 816-1203). Each row records what
  # tauri-runtime-wry's create_webview hands wry (lib.rs:4556-4961), with
  # the defaults of WebviewAttributes::new (tauri-runtime webview.rs:482-526),
  # and #native_attributes gives Native::WebView#open all of them at once
  # (plan 052, decision e1-2).
  #
  # Window#add_child, which builds one of these into a window, arrives
  # with child webviews (plan 052, phase 4); until then a
  # WebviewWindowBuilder holds one, and this class is internal.
  class WebviewBuilder # :nodoc:
    # Tauri's WebviewBuilder::new (webview/mod.rs:349-359): the label, the
    # WebviewUrl to load, and WebviewAttributes::new's defaults. Keys for
    # another platform's rows are sent everywhere and read only there.
    def initialize(label, url)
      raise TypeError, "wrong argument type #{label.class} (expected String)" unless label.is_a?(String)

      @label = label
      @url = url
      @initialization_scripts = [] #: Array[[String, bool]]
      @attributes = {
        focused: true,
        transparent: false,
        background_color: nil,
        traffic_light_position: nil,
        accept_first_mouse: false,
        user_agent: nil,
        additional_browser_args: nil,
        drag_drop_handler_enabled: true,
        clipboard: false,
        incognito: false,
        proxy_url: nil,
        browser_extensions_enabled: false,
        extensions_path: nil,
        data_store_identifier: nil,
        background_throttling: nil,
        javascript_disabled: false,
        scroll_bar_style: ScrollBarStyle::Default.name,
        allow_link_preview: true,
      } #: Hash[Symbol, Native::WebView::attribute]
    end

    # The label the webview will have.
    attr_reader :label

    # The WebviewUrl the webview will load.
    attr_reader :url

    # The attributes Native::WebView#open builds the webview with, without
    # its URL and scripts: a fresh Hash.
    def native_attributes
      @attributes.dup
    end

    # The scripts the rows added, in call order, each
    # <tt>[script, for_main_frame_only]</tt> as Tauri's InitializationScript
    # (tauri-runtime webview.rs:807-815): a fresh Array.
    def initialization_scripts
      @initialization_scripts.map(&:dup)
    end

    # Tauri's WebviewBuilder::accept_first_mouse (webview/mod.rs:819-822;
    # lib.rs:4628).
    def accept_first_mouse(accept)
      flag(:accept_first_mouse, accept)
    end

    # Tauri's WebviewBuilder::initialization_script, for the main frame
    # (webview/mod.rs:873-882; lib.rs:4958-4961).
    def initialization_script(script)
      script(script, true)
    end

    # Tauri's WebviewBuilder::initialization_script_for_all_frames
    # (webview/mod.rs:932-941).
    def initialization_script_for_all_frames(script)
      script(script, false)
    end

    # Tauri's WebviewBuilder::user_agent (webview/mod.rs:945-948;
    # lib.rs:4857-4859).
    def user_agent(user_agent)
      expect(user_agent, String)
      set(:user_agent, user_agent.dup)
    end

    # Tauri's WebviewBuilder::additional_browser_args, read on Windows
    # (webview/mod.rs:961-964; lib.rs:4868-4871).
    def additional_browser_args(additional_args)
      expect(additional_args, String)
      set(:additional_browser_args, additional_args.dup)
    end

    # Tauri's WebviewBuilder::disable_drag_drop_handler
    # (webview/mod.rs:978-981; lib.rs:4669).
    def disable_drag_drop_handler
      set(:drag_drop_handler_enabled, false)
    end

    # Tauri's WebviewBuilder::enable_clipboard_access
    # (webview/mod.rs:988-991; lib.rs:4630).
    def enable_clipboard_access
      set(:clipboard, true)
    end

    # Tauri's WebviewBuilder::incognito (webview/mod.rs:1002-1005;
    # lib.rs:4629).
    def incognito(incognito)
      flag(:incognito, incognito)
    end

    # Tauri's WebviewBuilder::proxy_url, sent as parse_proxy_url reads it
    # (webview/mod.rs:1015-1018; lib.rs:4301-4316, 4861-4865).
    def proxy_url(url)
      expect(url, Ferro::Url::Url)
      set(:proxy_url, WebviewBuilder.proxy_endpoint(url))
    end

    # The <tt>[scheme, host, port]</tt> tauri-runtime-wry's parse_proxy_url
    # reads from +url+, a Ferro::Url::Url (lib.rs:4301-4316): the scheme,
    # the host as the url crate prints it, empty when there is none, and
    # the port as a String, empty when Url::port answers none, as it does
    # for the scheme's default.
    def self.proxy_endpoint(url)
      [url.scheme, url.host.to_s, url.port.to_s]
    end

    # Tauri's WebviewBuilder::focused (webview/mod.rs:1034-1037).
    def focused(focus)
      flag(:focused, focus)
    end

    # Tauri's WebviewBuilder::browser_extensions_enabled, read on Windows
    # (webview/mod.rs:1068-1071; lib.rs:4892-4895).
    def browser_extensions_enabled(enabled)
      flag(:browser_extensions_enabled, enabled)
    end

    # Tauri's WebviewBuilder::extensions_path, read on Windows and Linux
    # (webview/mod.rs:1080-1083; lib.rs:4897-4909).
    def extensions_path(path)
      set(:extensions_path, File.path(path))
    end

    # Tauri's WebviewBuilder::data_store_identifier, read on macOS
    # (webview/mod.rs:1093-1096; lib.rs:4925-4928): Rust's
    # <tt>[u8; 16]</tt>, as 16 Integers.
    def data_store_identifier(data_store_identifier)
      identifier = data_store_identifier
      unless identifier.is_a?(Array) && identifier.all?(Integer)
        raise TypeError, "wrong argument type #{identifier.class} (expected an Array of 16 Integers)"
      end
      raise ArgumentError, "a data store identifier is 16 bytes, not #{identifier.size}" unless identifier.size == 16
      raise ArgumentError, "a data store identifier's bytes are 0 to 255" unless identifier.all? { |byte| byte.between?(0, 255) }

      set(:data_store_identifier, identifier.dup)
    end

    # Tauri's WebviewBuilder::background_color (webview/mod.rs:1136-1139;
    # lib.rs:4665-4667).
    def background_color(color)
      expect(color, Color)
      set(:background_color, [color.red, color.green, color.blue, color.alpha])
    end

    # Tauri's WebviewBuilder::background_throttling (webview/mod.rs:1156-1159;
    # lib.rs:4647-4659).
    def background_throttling(policy)
      expect(policy, BackgroundThrottlingPolicy)
      set(:background_throttling, policy.name)
    end

    # Tauri's WebviewBuilder::disable_javascript (webview/mod.rs:1163-1166;
    # lib.rs:4661-4663).
    def disable_javascript
      set(:javascript_disabled, true)
    end

    # Tauri's WebviewBuilder::scroll_bar_style, read on Windows
    # (webview/mod.rs:1182-1185; lib.rs:4883-4889).
    def scroll_bar_style(style)
      expect(style, ScrollBarStyle)
      set(:scroll_bar_style, style.name)
    end

    # The traffic-light inset, a webview attribute for which only
    # WebviewWindowBuilder has a row (webview_window.rs:838-847), as
    # <tt>[physical, x, y]</tt>.
    def set_traffic_light_position(dimensions)
      set(:traffic_light_position, dimensions)
    end

    # Adds +script+ for the main frame only, or for every frame.
    private def script(script, for_main_frame_only)
      expect(script, String)
      @initialization_scripts << [script.dup, for_main_frame_only]
      self
    end

    # Records +value+ under +key+ and answers the builder.
    private def set(key, value)
      @attributes[key] = value
      self
    end

    # Records +value+ as a boolean, by Ruby's truthiness, as the native
    # setters read theirs (plan 052, decision c5).
    private def flag(key, value)
      set(key, value ? true : false)
    end

    # Raises TypeError, in Ruby's words, unless +value+ is a +type+.
    private def expect(value, type)
      raise TypeError, "wrong argument type #{value.class} (expected #{type})" unless value.is_a?(type)

      nil
    end
  end
end

# SPDX-SnippetEnd
