<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Tokra

TODO: Delete this and the text below, and describe your gem

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/tokra`. To experiment with that code, run `bin/console` for an interactive prompt.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

### Building the native extension

Installing `tokra` compiles a Rust extension, so you need Rust and Cargo on
the machine that installs the gem. `tokra-clipboard`, `tokra-dialog`,
`tokra-notification`, and `tokra-global-shortcut` are pure Ruby, but their
`ferro-arboard`, `ferro-rfd`, `ferro-notify-rust`, and `ferro-global-hotkey`
dependencies compile one too (their READMEs name their versions; on Linux,
`ferro-rfd` also needs `pkg-config` and libwayland's development files).

- Rust 1.88 or newer, the highest `rust-version` among the locked
  dependencies (the gem ships a version 4 `Cargo.lock`, which Cargo reads
  from 1.78 on). On macOS 27, use Rust 1.99 or newer: earlier toolchains
  strip the extension in a way the new loader rejects.
- The build runs `cargo --locked`, so it compiles exactly the dependency
  versions this repository tested and fails rather than resolving newer
  ones. To build against newer versions anyway, set
  `RB_SYS_EXTRA_CARGO_ARGS` (for example to an empty string); it replaces
  `--locked`.

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/tokra. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/tokra/blob/main/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the Tokra project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/tokra/blob/main/CODE_OF_CONDUCT.md).
