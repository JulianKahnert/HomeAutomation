#!/usr/bin/env bash
set -euo pipefail

# https://developer.apple.com/forums/thread/732893
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
