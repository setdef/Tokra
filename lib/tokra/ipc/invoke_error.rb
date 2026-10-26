# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  module Ipc
    # Raised when a command's argument cannot be read, with the message
    # the invoke rejects with.
    #
    # Most argument failures are serde's and raise Tokra::Error::InvalidArgs.
    # A few arguments check more than their type: a page's Channel must be
    # a <tt>__CHANNEL__:ID</tt> string, and its message names neither the
    # command nor the key. A plugin's extend_api rescues this beside
    # InvalidArgs and rejects the invoke with its message.
    #
    # Mirrors Tauri's <tt>ipc::InvokeError</tt> (ipc/mod.rs:222-224) as an
    # argument's <tt>CommandArg::from_command</tt> returns it
    # (ipc/channel.rs:308-313). Tauri's holds any JSON value; this one holds
    # the String message those arguments give.
    #
    # === Example
    #
    #   raise Tokra::Ipc::InvokeError, "invalid channel value `x`, expected a string in the `__CHANNEL__:ID` format"
    class InvokeError < StandardError
    end
  end
end
