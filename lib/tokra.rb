# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
#
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "tokra/version"
require_relative "tokra/native"
require_relative "tokra/tokra"
require_relative "tokra/rack/handler"

# Tokra is a port of Tauri to Ruby.
module Tokra
  # TODO: Document me.
  class Error < StandardError; end
  # Your code goes here...
end
