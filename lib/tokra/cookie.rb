# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

# SPDX-SnippetBegin
# SPDX-License-Identifier: Apache-2.0 OR MIT
# SPDX-SnippetCopyrightText: 2019-2024 Tauri Programme within The Commons Conservancy
# SPDX-SnippetComment: Cookie adapted from tauri/crates/tauri-runtime/src/lib.rs and
#                      tauri/crates/tauri/src/webview/mod.rs, which re-export the cookie crate's

module Tokra
  # One HTTP cookie in a webview's cookie store.
  #
  # A page you load from the web often signs in by setting a cookie, and
  # your app may need to read it, hand one to the page before it loads, or
  # sign out by deleting it. Webview#cookies and Webview#cookies_for_url
  # answer these, and Webview#set_cookie and Webview#delete_cookie take
  # one.
  #
  # A cookie has a +name+ and a +value+, both Strings. Everything else is
  # +nil+ until you give it, and +nil+ means the cookie does not say:
  #
  # [expires] an Expiration::DateTime, when the cookie expires, or
  #           Expiration::Session, when it lasts until the browsing session
  #           ends.
  # [max_age] an Integer, how many seconds the cookie lives, which a
  #           64-bit signed integer holds, or Cookie.new raises
  #           RangeError. On Linux wry hands WebKitGTK the seconds cut to
  #           32 bits (webkitgtk/mod.rs:975-978), so a max_age past
  #           2147483647 wraps there, as in a Tauri app.
  # [domain] a String, the host the cookie is sent to.
  # [path] a String, the path the cookie is sent under.
  # [secure] +true+ to send the cookie only over HTTPS.
  # [http_only] +true+ to hide the cookie from the page's JavaScript.
  # [same_site] a SameSite, whether the cookie goes with requests from
  #             other sites.
  # [partitioned] +true+ to keep the cookie apart for each top-level site.
  #
  # Each must be its type, or Cookie.new raises TypeError. An expiration
  # outside the years -9999 to 9999 raises RangeError, from
  # Expiration::DateTime.new.
  #
  # A cookie the webview answers has its +domain+, +path+, +secure+,
  # +http_only+, +same_site+, and +expires+ set by the platform, as wry
  # reads them, and never a +max_age+ or a +partitioned+. Its +domain+ has
  # no leading dot, as the cookie crate answers it. Its expiration is in
  # whole seconds, and so is the one you give: wry passes a cookie's
  # expiration on as whole Unix seconds, so the fraction of a second is
  # dropped.
  #
  # On macOS give +secure+ and +http_only+ only to set them. wry writes a
  # flag of +false+ as the string FALSE (wkwebview/mod.rs:1053-1068), which
  # WebKit counts as set, as it does in a Tauri app; leave a flag +nil+ to
  # leave it unset. WebKit may also cap the expiration, at 400 days.
  #
  # Mirrors Tauri's <tt>Cookie</tt>, which is the cookie crate's
  # (tauri-runtime lib.rs:46; tauri webview/mod.rs:17-23), at 0.18.1, the
  # version wry 0.54.1 locks: its fields (cookie src/lib.rs:215-239), and
  # its <tt>Expiration</tt> and <tt>SameSite</tt>
  # (src/expiration.rs:26-34, src/same_site.rs:29-36). Ruby has no
  # module beside a class of the same name, so the two live in this class
  # where Tauri's live in its <tt>cookie</tt> module.
  #
  # === Example
  #
  #   Tokra::Cookie.new(name: "session", value: "abc", domain: "localhost", path: "/",
  #     http_only: true, same_site: Tokra::Cookie::SameSite::Lax)
  class Cookie < Data.define(:name, :value, :expires, :max_age, :domain, :path, :secure, :http_only, :same_site,
    :partitioned)
    # Whether a cookie goes with a request that another site starts.
    #
    # These three are the only policies, as in the cookie crate's enum, so
    # SameSite.new is private.
    #
    # Mirrors the cookie crate's <tt>SameSite</tt> (src/same_site.rs:29-36).
    #
    # === Example
    #
    #   Tokra::Cookie::SameSite::Strict.name  #=> "Strict"
    class SameSite < Data.define(:name)
      extend ClosedEnum

      ##
      # Only with requests this cookie's own site starts.
      Strict = new(name: "Strict")
      # Also when another site links here, but not with its other requests.
      Lax = new(name: "Lax")
      # With every request, which browsers allow only for a secure cookie.
      None = new(name: "None")

      close
    end

    # When a cookie expires.
    #
    # Mirrors the cookie crate's <tt>Expiration</tt>, an enum of a moment
    # and the session (src/expiration.rs:26-34), as two classes.
    #
    # === Example
    #
    #   Tokra::Cookie::Expiration::DateTime.new(datetime: Time.now + 3600)
    #   Tokra::Cookie::Expiration::Session.new
    module Expiration
      # The cookie expires at +datetime+, a Time from the year -9999 to
      # 9999, the years the time crate holds without its large-dates
      # feature, as the cookie crate builds it. Anything but a Time raises
      # TypeError, and a Time outside those years RangeError.
      #
      # === Example
      #
      #   Tokra::Cookie::Expiration::DateTime.new(datetime: Time.utc(2030, 1, 1))
      class DateTime < Data.define(:datetime)
        # The Unix seconds of -9999-01-01T00:00:00Z to
        # 9999-12-31T23:59:59Z (time 0.3.46 src/date.rs:30-41, MIN_YEAR and
        # MAX_YEAR without large-dates).
        SECONDS = (-377_705_116_800..253_402_300_799)
        # Takes +datetime+ as a Time. A Data class validating in
        # initialize: its RBS declares self.new, as AGENTS.md asks, and
        # Steep cannot see that self.new reaches this.
        def initialize(datetime:) # steep:ignore MethodParameterMismatch
          raise TypeError, "wrong argument type #{datetime.class} (expected Time)" unless datetime.is_a?(Time)
          unless SECONDS.cover?(datetime.to_i)
            raise RangeError, "#{datetime} is outside the years -9999 to 9999 a cookie's expiration holds"
          end

          super # steep:ignore UnexpectedKeywordArgument
        end
      end

      # The cookie lasts until the browsing session ends.
      #
      # === Example
      #
      #   Tokra::Cookie::Expiration::Session.new
      class Session < Data.define
      end
    end

    # The type each optional field takes, with +nil+ for unset.
    TYPES = {
      expires: [Expiration::DateTime, Expiration::Session],
      max_age: [Integer],
      domain: [String],
      path: [String],
      secure: [TrueClass, FalseClass],
      http_only: [TrueClass, FalseClass],
      same_site: [SameSite],
      partitioned: [TrueClass, FalseClass],
    }.freeze
    private_constant :TYPES

    # The seconds a max_age holds: the cookie crate's Duration from an
    # i64 (cookie src/builder.rs:105).
    MAX_AGE = (-(2 ** 63)..((2 ** 63) - 1))
    private_constant :MAX_AGE

    # Makes a cookie of +name+ and +value+, Strings, with each optional
    # field +nil+ unless given. A field of the wrong type raises
    # TypeError, and a max_age a 64-bit signed integer cannot hold
    # RangeError. A Data class validating in initialize: its RBS declares
    # self.new, as AGENTS.md asks, and Steep cannot see that self.new
    # reaches this.
    def initialize(name:, value:, expires: nil, max_age: nil, domain: nil, path: nil, secure: nil, http_only: nil, # steep:ignore MethodParameterMismatch
      same_site: nil, partitioned: nil
    )
      { name:, value: }.each do |field, given|
        raise TypeError, "wrong argument type #{given.class} for #{field} (expected String)" unless given.is_a?(String)
      end
      optional = { expires:, max_age:, domain:, path:, secure:, http_only:, same_site:, partitioned: }
      optional.each do |field, given|
        next if given.nil? || TYPES.fetch(field).any? { |type| given.is_a?(type) }

        raise TypeError, "wrong argument type #{given.class} for #{field} (expected #{TYPES.fetch(field).join(' or ')})"
      end
      raise RangeError, "max_age #{max_age} is outside a 64-bit signed integer" if max_age && !MAX_AGE.cover?(max_age)

      super(name:, value:, **optional) # steep:ignore UnexpectedKeywordArgument
    end

    # The cookie as Native::WebView takes it: each field by name, the
    # expiration as <tt>"Session"</tt> or whole Unix seconds, and the
    # same-site policy by name.
    def native_fields # :nodoc:
      deadline = expires
      {
        name:,
        value:,
        expires: deadline.is_a?(Expiration::DateTime) ? deadline.datetime.to_i : deadline && "Session",
        max_age:,
        domain:,
        path:,
        secure:,
        http_only:,
        same_site: same_site&.name,
        partitioned:,
      }
    end

    # The cookie Native::WebView answers as +fields+, in #native_fields's
    # shape.
    def self.from_native(fields) # :nodoc:
      deadline = fields[:expires]
      expires = case deadline
      when Integer then Expiration::DateTime.new(datetime: Time.at(deadline).utc)
      when "Session" then Expiration::Session.new
      end
      policy = fields[:same_site]
      new(name: fields[:name], value: fields[:value], expires:, max_age: fields[:max_age], domain: fields[:domain],
        path: fields[:path], secure: fields[:secure], http_only: fields[:http_only],
        same_site: policy && SameSite.const_get(policy, false), partitioned: fields[:partitioned])
    end
  end
end

# SPDX-SnippetEnd
