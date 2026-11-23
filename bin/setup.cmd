@echo off
rem SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
rem SPDX-License-Identifier: AGPL-3.0-or-later
rem
rem Tokra's development tools and git hooks, from the pins in mise.toml,
rem for cmd.exe and Windows PowerShell: bin/setup's two lines. Everything
rem it does is in tasks/setup.rb. The first run on a clean machine installs
rem Ruby, Rust, and Python, and takes minutes.
cd /d "%~dp0.."
mise trust -q mise.toml
mise x -- ruby tasks/setup.rb %*
