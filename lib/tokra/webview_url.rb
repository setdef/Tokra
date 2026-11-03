# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: WebviewUrl adapted from tauri/crates/tauri-utils/src/config.rs

module Tokra
  # The page a new webview opens.
  #
  # A webview opens one of three kinds of page: one of your own app's,
  # served over the <tt>tokra://</tt> protocol your app answers; a page on
  # the web; or a page another custom protocol serves. Each needs a
  # different address, and an app page's address differs by platform.
  #
  # So you name the page by its kind, and Tokra works out the address. Pass
  # one of these to WebviewWindowBuilder.new.
  #
  # Mirrors Tauri's <tt>WebviewUrl</tt> enum (tauri-utils config.rs:72-125),
  # as three classes.
  #
  # === Examples
  #
  #   Tokra::WebviewUrl::App.new("index.html")
  #   Tokra::WebviewUrl::External.new(Ferro::Url::Url.parse("https://tauri.app"))
  #   Tokra::WebviewUrl::CustomProtocol.new(Ferro::Url::Url.parse("doom://index.html"))
  module WebviewUrl
    # The path portion of an app URL. To load
    # <tt>tokra://localhost/users/john</tt>, give <tt>"users/john"</tt>.
    # <tt>"index.html"</tt> loads the app URL itself.
    #
    # +path+ is a String or a Pathname, and reads back as a Pathname, as
    # Tauri's holds a PathBuf. Anything else raises TypeError.
    #
    # The path joins the app URL as the url crate joins it, when
    # WebviewWindowBuilder#build runs. A path naming another host, such as
    # <tt>//exa mple</tt>, that the crate cannot join raises
    # Error::InvalidUrl there, where Tauri's app panics.
    #
    # === Example
    #
    #   Tokra::WebviewUrl::App.new("settings.html").path  #=> #<Pathname:settings.html>
    class App < Data.define(:path)
      # Takes +path+ as a String or a Pathname. A Data class validating
      # in initialize: its RBS declares self.new, as AGENTS.md asks, and
      # Steep cannot see that self.new reaches this.
      def initialize(path:) # steep:ignore MethodParameterMismatch
        unless path.is_a?(String) || path.is_a?(Pathname)
          raise TypeError, "wrong argument type #{path.class} (expected String or Pathname)"
        end

        super(path: Pathname.new(path)) # steep:ignore UnexpectedKeywordArgument
      end
    end

    # A page on the web, at +url+, a Ferro::Url::Url, the url crate's
    # URL, as a config's URL reads. It must use the +http+ or +https+
    # scheme. Parse the address first, as a Rust caller does; anything
    # else, a Ruby URI included, raises TypeError.
    #
    # The URL reads back frozen: a frozen URL is kept, any other is
    # copied, so a change you make to yours later does not reach the page.
    #
    # === Example
    #
    #   Tokra::WebviewUrl::External.new(Ferro::Url::Url.parse("https://tauri.app"))
    class External < Data.define(:url)
      # Takes +url+ as a Ferro::Url::Url. A Data class validating in
      # initialize, as App is.
      def initialize(url:) # steep:ignore MethodParameterMismatch
        super(url: WebviewUrl.held(url)) # steep:ignore UnexpectedKeywordArgument
      end
    end

    # A page a custom protocol serves, at +url+, a Ferro::Url::Url such as
    # <tt>doom://index.html</tt>, or a <tt>data:</tt> URL, which loads as
    # given. Anything else raises TypeError, and the URL reads back frozen,
    # as External's does.
    #
    # === Example
    #
    #   Tokra::WebviewUrl::CustomProtocol.new(Ferro::Url::Url.parse("doom://index.html"))
    class CustomProtocol < Data.define(:url)
      # Takes +url+ as a Ferro::Url::Url. A Data class validating in
      # initialize, as App is.
      def initialize(url:) # steep:ignore MethodParameterMismatch
        super(url: WebviewUrl.held(url)) # steep:ignore UnexpectedKeywordArgument
      end
    end

    # Reads +value+, a JSON value, as Tauri's own deserializer does
    # (config.rs:88-109): through an untagged enum of a URL, then a path.
    # A URL with the +http+ or +https+ scheme is External, any other URL
    # CustomProtocol, and any other string App. Anything but a string
    # raises Ipc::CommandItem::Mismatch with serde's words.
    #
    # A URL is the url crate's own, a Ferro::Url::Url, so a config's URL
    # reads, normalizes, and splits as Tauri's does (Utils::Config.url).
    def self.deserialize(value) # :nodoc:
      Ipc::Serde.untagged(value, "WebviewUrlDeserializer", [
        lambda do |raw|
          url = Utils::Config.url(raw)
          %w[http https].include?(url.scheme.to_s) ? External.new(url:) : CustomProtocol.new(url:)
        end,
        -> (raw) { App.new(path: Utils::Config.path(raw)) },
      ])
    end

    # +url+ as a variant holds it: frozen, copied first unless it already
    # is, since Rust moves the Url into the enum and no one else can change
    # it there. Raises TypeError, in Ruby's words, unless +url+ is a
    # Ferro::Url::Url, the url crate's <tt>url::Url</tt> (plan 055).
    def self.held(url) # :nodoc:
      raise TypeError, "wrong argument type #{url.class} (expected Ferro::Url::Url)" unless url.is_a?(Ferro::Url::Url)

      url.frozen? ? url : url.dup.freeze
    end
  end
end

# SPDX-SnippetEnd
