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
  #   Tokra::WebviewUrl::External.new(URI("https://tauri.app"))
  #   Tokra::WebviewUrl::CustomProtocol.new(URI("doom://index.html"))
  module WebviewUrl
    # The path portion of an app URL. To load
    # <tt>tokra://localhost/users/john</tt>, give <tt>"users/john"</tt>.
    # <tt>"index.html"</tt> loads the app URL itself.
    #
    # +path+ is a String or a Pathname, and reads back as a Pathname, as
    # Tauri's holds a PathBuf. Anything else raises TypeError.
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

    # A page on the web, at +url+, a URI. It must use the +http+ or
    # +https+ scheme. Anything but a URI raises TypeError.
    #
    # === Example
    #
    #   Tokra::WebviewUrl::External.new(URI("https://tauri.app"))
    class External < Data.define(:url)
      # Takes +url+ as a URI::Generic. A Data class validating in
      # initialize, as App is.
      def initialize(url:) # steep:ignore MethodParameterMismatch
        WebviewUrl.expect_uri(url)
        super
      end
    end

    # A page a custom protocol serves, at +url+, a URI such as
    # <tt>doom://index.html</tt>, or a <tt>data:</tt> URL, which loads as
    # given. Anything but a URI raises TypeError.
    #
    # Ruby's URI refuses characters the url crate percent-encodes as it
    # parses, such as the <tt><</tt> of a <tt>data:</tt> URL's HTML, so
    # encode them first.
    #
    # === Example
    #
    #   Tokra::WebviewUrl::CustomProtocol.new(URI("doom://index.html"))
    class CustomProtocol < Data.define(:url)
      # Takes +url+ as a URI::Generic. A Data class validating in
      # initialize, as App is.
      def initialize(url:) # steep:ignore MethodParameterMismatch
        WebviewUrl.expect_uri(url)
        super
      end
    end

    # Raises TypeError, in Ruby's words, unless +url+ is a URI.
    def self.expect_uri(url) # :nodoc:
      raise TypeError, "wrong argument type #{url.class} (expected URI::Generic)" unless url.is_a?(URI::Generic)

      nil
    end
  end
end

# SPDX-SnippetEnd
