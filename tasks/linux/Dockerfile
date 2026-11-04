# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later

# CI's Linux job, on this machine (Plan 058). rake test:linux builds this
# with tasks/linux/ as its whole context, and passes the pins CI reads from
# the files CI reads them from (LinuxGate#build_args). Ruby's version and
# checksum live here, and the tests check them against mise.toml and
# ci.yml's matrix. Each layer comes after the ones that change less.

# The release ubuntu-latest runs today. It is fixed here, while
# ubuntu-latest moves when GitHub moves it.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# What the runner image has and the job relies on without installing it:
# git, curl, a C toolchain, and Python 3.12 (mise.toml's pin) with venv for
# the REUSE tool; and the libraries Ruby's own extensions build against.
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      ca-certificates curl git build-essential python3 python3-venv \
      libssl-dev libyaml-dev zlib1g-dev libffi-dev libgmp-dev \
 && rm -rf /var/lib/apt/lists/*

# Ruby, built as setup-ruby's are, with a shared libruby. Its checksum is
# the one ruby-lang.org publishes for the version, so the two change
# together. test_linux_gate.rb checks the version is mise.toml's, and in
# the series of each Ruby in ci.yml's matrix, which names a series, not a
# patch.
ARG RUBY_VERSION=4.0.9
ARG RUBY_SHA256=c35350682ff050b79702d57ade4516e7336063f510155d19fb2fb5b3f3909511
RUN curl --fail --silent --show-error --location --output /tmp/ruby.tar.gz \
      "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz" \
 && echo "${RUBY_SHA256}  /tmp/ruby.tar.gz" | sha256sum --check - \
 && mkdir /tmp/ruby && tar -xzf /tmp/ruby.tar.gz -C /tmp/ruby --strip-components=1 \
 && cd /tmp/ruby \
 && ./configure --prefix=/usr/local --enable-shared --disable-install-doc \
 && make -j"$(nproc)" && make install && ldconfig \
 && cd / && rm -rf /tmp/ruby /tmp/ruby.tar.gz

# Rust at mise.toml's pin, with the components ci.yml's toolchain step
# names. The toolchain lives in the image; the container's CARGO_HOME, a
# volume, holds only the registry and git checkouts. rustup-init comes
# unpinned from sh.rustup.rs over TLS, as rustup's own instructions give it.
ARG RUST_VERSION
ARG RUST_COMPONENTS
ENV RUSTUP_HOME=/usr/local/rustup
RUN curl --proto '=https' --tlsv1.2 --fail --silent --show-error https://sh.rustup.rs \
    | CARGO_HOME=/usr/local/cargo sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_VERSION}" --component "${RUST_COMPONENTS}" \
 && chmod -R a+rX /usr/local/rustup /usr/local/cargo

# ci.yml's apt packages, read from its install step.
ARG APT_PACKAGES
RUN apt-get update \
 && apt-get install --yes --no-install-recommends ${APT_PACKAGES} \
 && rm -rf /var/lib/apt/lists/*

# The REUSE tool, at ci.yml's requirement.
ARG REUSE_REQUIREMENT
RUN python3 -m venv /opt/reuse && /opt/reuse/bin/pip install --no-cache-dir "${REUSE_REQUIREMENT}"

# Bundler at the version Gemfile.lock names, in Ruby's own gem directory.
ARG BUNDLER_VERSION
RUN gem install bundler --version "${BUNDLER_VERSION}" --no-document

# The user the tests run as, and the places the task mounts volumes on,
# made here so each new volume starts out the user's.
RUN useradd --create-home --shell /bin/bash tokra \
 && mkdir -p /work/target /work/tmp /work/vendor/bundle /home/tokra/.cargo /home/tokra/gems \
 && chown -R tokra:tokra /work /home/tokra

USER tokra
# The runner's locale: without it Ruby reads gemspecs as US-ASCII.
ENV LANG=C.UTF-8 \
    CARGO_HOME=/home/tokra/.cargo \
    GEM_HOME=/home/tokra/gems \
    PATH=/home/tokra/gems/bin:/usr/local/cargo/bin:/opt/reuse/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /work
