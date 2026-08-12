#!/usr/bin/env bash
# Bootstrap the locked CocoaPods bundle and run pod install.
#
# The example pins cocoapods/activesupport/concurrent-ruby in Gemfile/Gemfile.lock
# so iOS builds are reproducible against system Ruby (2.6.10) without globally
# installing CocoaPods. Every iOS install path (yarn pod-install, yarn clean,
# postinstall, scripts/verify.sh, README/CLAUDE setup steps) MUST flow through
# this script so the gems are guaranteed to be installed before
# `bundle exec pod install` is invoked.
#
# This script is a no-op on non-Darwin hosts so it is safe to wire into
# postinstall hooks that run on Linux/CI agents that do not build iOS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "[pod-install] Skipping: not running on macOS"
    exit 0
fi

if [ ! -f "${APP_ROOT}/ios/Podfile" ]; then
    echo "[pod-install] Skipping: ios/Podfile not found"
    exit 0
fi

if ! command -v bundle >/dev/null 2>&1; then
    echo "error: 'bundle' command not found. Install Bundler with 'gem install bundler'." >&2
    exit 1
fi

cd "${APP_ROOT}"

# `bundle check` exits 0 only when the locked gemset is fully installed; on
# a fresh checkout (or any time Gemfile.lock changes) it returns non-zero
# and we must run `bundle install` before `bundle exec pod install` can
# resolve cocoapods, activesupport, etc.
if ! bundle check >/dev/null 2>&1; then
    echo "[pod-install] Installing locked gems via bundler"
    bundle install
fi

cd "${APP_ROOT}/ios"
echo "[pod-install] Running 'bundle exec pod install'"
bundle exec pod install
