# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

#--
# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: HeaderSource and HeaderConfig adapted from tauri-utils
#   src/config.rs:2288-2573 at vendor/tauri 9f0306fbc
#++

module Tokra
  module Utils
    module Config
      # The value of one HTTP header the config sets.
      #
      # A header's value is a string, but some headers list values, and
      # some pair names with values. The config writes whichever is
      # natural: a string, an array, or an object.
      #
      # Mirrors Tauri's untagged <tt>HeaderSource</tt> (config.rs:2288-2300).
      #
      # === Example
      #
      #   # "Access-Control-Max-Age": "3600"
      #   headers.access_control_max_age  #=> #<data Tokra::Utils::Config::HeaderSource::Inline value="3600">
      module HeaderSource
        # The value as a string.
        class Inline < Data.define(:value)
        end

        # The value as a list, which the header joins with commas.
        class List < Data.define(:values)
        end

        # The value as a Hash of name to value, which the header joins as
        # <tt>name value; name value</tt>.
        class Map < Data.define(:values)
        end

        # Reads +value+, a JSON value, as serde reads the untagged enum.
        def self.deserialize(value) # :nodoc:
          Ipc::Serde.untagged(value, "HeaderSource", [
            -> (raw) { Inline.new(value: Ipc::Serde.string(raw)) },
            -> (raw) { List.new(values: Utils::Config.sequence(raw) { |item| Ipc::Serde.string(item) }) },
            -> (raw) { Map.new(values: Utils::Config.map(raw) { |item| Ipc::Serde.string(item) }) },
          ])
        end
      end

      # The HTTP headers your app's own responses carry.
      #
      # Some browser features turn on only with a header, such as
      # <tt>SharedArrayBuffer</tt> behind cross-origin isolation. A page
      # served from your app cannot set its own headers, so the config
      # names them, and each <tt>tokra://</tt> response would carry them.
      #
      # The keys are the headers' own names. Tokra reads them now, and
      # acts on them with the plan that serves your frontend's assets
      # (plan 054's inventory).
      #
      # Mirrors Tauri's <tt>HeaderConfig</tt> (config.rs:2420-2573).
      #
      # === Example
      #
      #   # "headers": { "Cross-Origin-Opener-Policy": "same-origin" }
      #   security.headers.cross_origin_opener_policy.value  #=> "same-origin"
      class HeaderConfig < Data.define(
        :access_control_allow_credentials, :access_control_allow_headers, :access_control_allow_methods,
        :access_control_expose_headers, :access_control_max_age, :cross_origin_embedder_policy,
        :cross_origin_opener_policy, :cross_origin_resource_policy, :permissions_policy, :service_worker_allowed,
        :timing_allow_origin, :x_content_type_options, :tauri_custom_header
      )
        SOURCE = -> (raw) { HeaderSource.deserialize(raw) } # :nodoc:
        private_constant :SOURCE

        FIELDS = [
          Field.option(:access_control_allow_credentials, "Access-Control-Allow-Credentials", SOURCE),
          Field.option(:access_control_allow_headers, "Access-Control-Allow-Headers", SOURCE),
          Field.option(:access_control_allow_methods, "Access-Control-Allow-Methods", SOURCE),
          Field.option(:access_control_expose_headers, "Access-Control-Expose-Headers", SOURCE),
          Field.option(:access_control_max_age, "Access-Control-Max-Age", SOURCE),
          Field.option(:cross_origin_embedder_policy, "Cross-Origin-Embedder-Policy", SOURCE),
          Field.option(:cross_origin_opener_policy, "Cross-Origin-Opener-Policy", SOURCE),
          Field.option(:cross_origin_resource_policy, "Cross-Origin-Resource-Policy", SOURCE),
          Field.option(:permissions_policy, "Permissions-Policy", SOURCE),
          Field.option(:service_worker_allowed, "Service-Worker-Allowed", SOURCE),
          Field.option(:timing_allow_origin, "Timing-Allow-Origin", SOURCE),
          Field.option(:x_content_type_options, "X-Content-Type-Options", SOURCE),
          Field.option(:tauri_custom_header, "Tauri-Custom-Header", SOURCE),
        ].freeze # :nodoc:

        DEFAULTS = Utils::Config.defaults_of(FIELDS).freeze # :nodoc:

        # Reads +value+, a JSON value, as serde reads the struct.
        def self.deserialize(value) # :nodoc:
          new(**Utils::Config.read_struct(value, "HeaderConfig", FIELDS))
        end

        # Takes any of the members as keywords; each one left out is +nil+.
        def initialize(**fields)
          super(**DEFAULTS, **fields)
        end
      end
    end
  end
end

#--
# SPDX-SnippetEnd
#++
