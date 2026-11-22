# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "digest"
require_relative "package_check"
require_relative "platform_gem"

# tokra's precompiled gem for this platform and Ruby (Plan 072). Neither
# task is in the gate: the build compiles the extension in release mode,
# and the check compiles ferro-url as it installs it. Nothing here tags,
# releases, or pushes a gem anywhere.
namespace :package do
  desc "Build tokra's precompiled gem for this platform and Ruby (#{PlatformGem.new(root: Dir.pwd).platform}) into pkg/"
  task native: "compile:strict" do
    package = PlatformGem.new(root: Dir.pwd).build("pkg")
    puts "✅ Built #{File.join('pkg', File.basename(package))}, sha256 #{Digest::SHA256.file(package).hexdigest}"
  rescue PlatformGem::Failure => e
    abort "❌ #{e.message}"
  end

  # Builds nothing, so it checks a gem built on another machine as well as
  # one package:native built here.
  desc "Install tokra's precompiled gems given (default pkg/*.gem for this platform) with no Rust on PATH, and load each"
  task :deliver do |_task, args|
    platform = PlatformGem.new(root: Dir.pwd).platform
    files = args.extras.empty? ? Dir.glob("pkg/tokra-[0-9]*-#{platform}.gem") : args.extras
    abort "❌ no precompiled gem of tokra for #{platform} in pkg/; run rake package:native first" if files.empty?

    tokra = PACKAGES.find { |target| target.name == "tokra" }
    files.each do |file|
      puts "#{File.basename(file)}: sha256 #{Digest::SHA256.file(file).hexdigest}"
      PackageCheck.new(root: Dir.pwd, gems: [tokra]).precompiled(tokra, file)
    end
  rescue PackageCheck::Failure => e
    abort "❌ #{e.message}"
  end
end
