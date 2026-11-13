# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Tokra's development tools on Windows, from the pins in mise.toml, and its
# git hooks: bin/setup, run in the bash of the MSYS2 that Ruby builds gems
# with. Run it from PowerShell, as often as you like; it asks nothing and
# needs no administrator rights.
#
# It needs mise (https://mise.jdx.dev). mise installs RubyInstaller's Ruby,
# which builds gems with an MSYS2 it finds on its own, C:\msys64 among
# other places, and Tokra's gems need that MSYS2's UCRT64 compiler. If
# either is missing, install it with RubyInstaller's ridk install, as
# RubyInstaller's own installer does, and run this again.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
  [Console]::Error.WriteLine("mise isn't installed. Please install it to continue.")
  exit 1
}

# Ruby first, since Ruby knows where its MSYS2 is. bin/setup runs mise
# install again, which then changes nothing.
mise install
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$msys = mise x -- ruby -e "print RubyInstaller::Runtime.msys2_installation.msys_path"
if ($LASTEXITCODE -ne 0 -or -not $msys) {
  [Console]::Error.WriteLine("RubyInstaller's Ruby found no MSYS2. Install one with: mise x -- ridk install 1 3")
  exit 1
}
$ucrt64 = Join-Path $msys "ucrt64\bin"
if (-not (Test-Path (Join-Path $ucrt64 "gcc.exe"))) {
  [Console]::Error.WriteLine("$msys has no UCRT64 compiler. Install it with: mise x -- ridk install 3")
  exit 1
}

# bin/setup and the gate run in that MSYS2's UCRT64 environment, as
# RubyInstaller's ridk enable sets it up, with mise's tools still on PATH.
$env:MSYSTEM = "UCRT64"
$env:CHERE_INVOKING = "1"
$env:Path = "$ucrt64;$(Join-Path $msys 'usr\bin');$env:Path"
& (Join-Path $msys "usr\bin\bash.exe") bin/setup
exit $LASTEXITCODE
