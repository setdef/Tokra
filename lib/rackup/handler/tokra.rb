# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "tokra"

# rackup 2.x finds a handler only through Rackup::Handler: its registry,
# then its constants, then a require of <tt>rackup/handler/<name></tt>
# (rackup 2.3.1 lib/rackup/handler.rb, +get+). This file is that require
# for <tt>rackup -s tokra</tt>. It registers Rack::Handler::Tokra and names
# it Rackup::Handler::Tokra, so both <tt>tokra</tt> and <tt>Tokra</tt>
# resolve. Rackup is not a dependency of tokra: the file does nothing
# unless rackup has loaded Rackup::Handler, as it has when it requires this
# file, so loading every file of the gem without rackup stays harmless.
return unless defined?(::Rackup::Handler.register)

module Rackup # :nodoc:
  module Handler # :nodoc:
    Tokra = ::Rack::Handler::Tokra
    register(:tokra, Tokra)
  end
end
