#!/bin/zsh
set -euo pipefail

# https://stackoverflow.com/a/78572430
mkdir -p ~/Library/org.swift.swiftpm/security/

# Path to the Package.resolved file for the FlowKitController workspace
PACKAGE_RESOLVED="../FlowKit Controller.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

# List of "packageIdentity targetName" pairs for Swift macro packages
PACKAGES="
swift-dependencies DependenciesMacrosPlugin
swift-composable-architecture ComposableArchitectureMacros
swift-case-paths CasePathsMacros
swift-perception PerceptionMacros
swift-openapi-generator OpenAPIGenerator
"

entries=""

# Loop through packages
echo "$PACKAGES" | while read -r pkg target; do
  [ -z "$pkg" ] && continue

  # Extract fingerprint (revision) using jq
  fingerprint=$(jq -r --arg pkg "$pkg" \
    '.pins[] | select(.identity == $pkg) | .state.revision' \
    "$PACKAGE_RESOLVED")

  if [ -z "$fingerprint" ] || [ "$fingerprint" = "null" ]; then
    echo "Error: Could not find fingerprint for package '$pkg'" >&2
    exit 1
  fi

  # Create JSON entry
  jq -n \
    --arg fp "$fingerprint" \
    --arg pkg "$pkg" \
    --arg target "$target" \
    '{fingerprint: $fp, packageIdentity: $pkg, targetName: $target}'
done | jq -s '.' > macros.json

# copy the new file
cp macros.json ~/Library/org.swift.swiftpm/security/

defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
