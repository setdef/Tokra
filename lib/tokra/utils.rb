# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

module Tokra
  # The pieces Tauri keeps in its tauri-utils crate: the config schema and
  # its reader, the platform targets, and the package information.
  #
  # Tauri splits the work of reading its config across three crates: the
  # macro, tauri-codegen, and tauri-utils. Tokra keeps the split, so each
  # file answers to one crate (ADR 014 §2): Tokra.generate_context is the
  # macro, Tokra::Codegen is tauri-codegen, and this module is tauri-utils.
  #
  # Use Tokra::Utils::Config to read a config's types, and
  # Tokra::Utils::Config::Parse to read config files yourself.
  #
  # === Examples
  #
  #   Tokra::Utils::Platform::Target.current  #=> Tokra::Utils::Platform::Target::MacOS
  #   Tokra::Utils::Config::Parse.read_from(Tokra::Utils::Platform::Target.current, __dir__)
  module Utils
  end
end

require_relative "utils/platform"
require_relative "utils/package_info"
require_relative "utils/config"
