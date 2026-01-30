# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "uri"
require "stringio"

module Rack # :nodoc:
  module Handler # :nodoc:
    # Tokra Rack Handler - Bridge between tokra:// custom protocol and Rack apps.
    #
    # This allows any Rack application (Rails, Roda, Sinatra, etc.) to run inside
    # a Tokra desktop window without a TCP server. The WebView makes requests to
    # +tokra://localhost/path+ and this handler translates them to Rack calls.
    #
    # == Usage
    #
    # The simplest way to run a Rack app in a desktop window:
    #
    #   Rack::Handler::Tokra.run(MyRodaApp)
    #
    # With options:
    #
    #   Rack::Handler::Tokra.run(MyRodaApp, title: "My App", width: 800, height: 600)
    #
    # This follows the standard Rack handler interface, so it works with +rackup+:
    #
    #   rackup -s tokra config.ru
    #
    class Tokra
      MAX_REDIRECTS = 10 # :nodoc:

      # Default window configuration
      DEFAULT_OPTIONS = {
        title: "Tokra",
        width: 800.0,
        height: 600.0,
      }.freeze

      class << self
        # Run a Rack application in a Tokra desktop window.
        #
        # This is the primary entry point, handling all wiring automatically:
        # - Creates the event loop, proxy, window, and webview
        # - Registers the tokra:// protocol handler
        # - Dispatches HTTP requests to the Rack app
        # - Runs the event loop until the window closes
        #
        # +app+ is any Rack application (responds to #call).
        # +options+ may include:
        # - +:title+ - Window title (default: "Tokra")
        # - +:width+ - Window width in pixels (default: 800)
        # - +:height+ - Window height in pixels (default: 600)
        #
        # == Example
        #
        #   class MyApp < Roda
        #     route { |r| r.root { "Hello" } }
        #   end
        #
        #   Rack::Handler::Tokra.run(MyApp.freeze.app)
        #
        def run(app, title: "Tokra", width: 800.0, height: 600.0, invoke_handler: nil)
          # Create Tokra components
          event_loop = ::Tokra::Native::EventLoop.new
          proxy = event_loop.create_proxy

          window = ::Tokra::Native::Window.new(event_loop)
          window.set_title(title)
          window.set_size(width.to_f, height.to_f)

          # Create the handler
          handler = new(app, proxy)

          # Create WebView with tokra:// protocol
          ::Tokra::Native::WebView.new_with_protocol(window, proxy)

          # Run the event loop, dispatching HTTP requests to the Rack app
          event_loop.run(
            lambda { |event|
              case event
              when ::Tokra::Native::HttpRequestEvent
                handler.call(event)
              when ::Tokra::Native::IpcEvent
                # If an invoke_handler is provided, call it with the message
                invoke_handler&.call(event.message)
              end
            }
          )
        end
      end

      # Create a new Rack handler.
      #
      # +app+ is any Rack application (responds to #call).
      # +proxy+ is the Tokra::Native::Proxy for responding to requests.
      #
      # Note: For most use cases, prefer +Rack::Handler::Tokra.run(app)+
      # which handles all setup automatically.
      def initialize(app, proxy)
        @app = app
        @proxy = proxy
      end

      # Handle an HTTP request event from the custom protocol.
      #
      # This method:
      # 1. Translates the HttpRequestEvent into a Rack environment
      # 2. Calls the Rack app
      # 3. Follows redirects internally (WKWebView doesn't follow redirects for custom protocols)
      # 4. Sends the final response back through the protocol
      def call(event)
        uri = URI.parse(event.uri)
        env = build_env(uri, event.method, event.body)

        # Follow redirects internally (WKWebView doesn't follow for custom protocols)
        redirect_count = 0
        cookies = nil

        loop do
          status, headers, body = @app.call(env)

          # Check for redirect (3xx with Location header)
          if (300..399).cover?(status) && headers["location"]
            body.close if body.respond_to?(:close)

            redirect_count += 1
            if redirect_count > MAX_REDIRECTS
              break respond_with_error(event.request_id, 508, "Too many redirects")
            end

            # Capture Set-Cookie for the next request (flash/sessions need this)
            cookies = headers["set-cookie"] if headers["set-cookie"]

            # Follow the redirect with GET (PRG pattern)
            new_uri = URI.parse(headers["location"])
            env = build_env(new_uri, "GET", "", cookies)
            next
          end

          # Send the response
          header_pairs = headers.map { |k, v| [k.to_s, v.to_s] } #: Array[[String, String]]

          body_str = String.new
          body.each { |chunk| body_str << chunk }
          body.close if body.respond_to?(:close)

          @proxy.respond(event.request_id, status, header_pairs, body_str)
          break
        end
      end

      private def build_env(uri, method, body, cookies = nil)
        env = {
          "REQUEST_METHOD" => method,
          "SCRIPT_NAME" => "",
          "PATH_INFO" => (uri.path.nil? || uri.path.empty?) ? "/" : uri.path,
          "QUERY_STRING" => uri.query || "",
          "SERVER_NAME" => uri.host || "localhost",
          "SERVER_PORT" => (uri.port || 80).to_s,
          "rack.version" => [2, 0],
          "rack.url_scheme" => "tokra",
          "rack.input" => StringIO.new(body),
          "rack.errors" => $stderr,
          "rack.multithread" => false,
          "rack.multiprocess" => false,
          "rack.run_once" => false,
        }
        env["HTTP_COOKIE"] = cookies if cookies
        env
      end

      private def respond_with_error(request_id, status, message)
        @proxy.respond(request_id, status, [["content-type", "text/plain"]], message)
      end
    end
  end
end
