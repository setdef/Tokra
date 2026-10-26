# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "stub_native"

# The app's own origin, for tests that send an invoke from the app's page.
#
# The page's origin depends on the platform: tokra://localhost on macOS and
# Linux, http://tokra.localhost on Windows, where WebView2 serves custom
# protocols over http, as Tauri's tauri_protocol_url says
# (manager/mod.rs:331-338). App decides what is local with that rule
# (App#tokra_protocol_url), so tests ask App rather than repeat it. Request
# URIs are another matter: wry hands every platform's tokra:// request to
# the handler as tokra://localhost/..., so those stay literal.
module LocalOrigin
  # The URL of +path+ on the app's own origin, as +app+ (or a fresh app)
  # computes it on this platform.
  def self.url(path = "/", app: Tokra::Builder.default.build(native: StubNative))
    "#{app.__send__(:tokra_protocol_url)}#{path}"
  end
end
