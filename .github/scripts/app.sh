#!/usr/bin/env bash
# Generates the Xcode project, lints, builds with warnings as errors, and runs the tests on an iPhone simulator.
set -euo pipefail

[ -f project.yml ] || { echo "No app project yet."; exit 0; }

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

xcrun swift-format lint --strict --recursive --parallel Magpie $(ls -d MagpieTests MagpieUITests Packages 2>/dev/null)

# The newest iPhone simulator this Xcode ships, so the job doesn't break when device names change.
udid=$(xcrun simctl list devices available -j |
  jq -r '[.devices | to_entries[] | select(.key | contains("iOS")) | .value[] | select(.name | startswith("iPhone"))] | last | .udid')
test -n "$udid" && test "$udid" != null

set +e
xcodebuild test \
  -project Magpie.xcodeproj -scheme Magpie \
  -destination "id=$udid" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  > xcodebuild.log 2>&1
rc=$?
set -e
grep -E 'error:|warning:|Test Suite|Executed|\*\* (BUILD|TEST)' xcodebuild.log | sort -u | tail -80 || true
[ "$rc" -eq 0 ] || { tail -60 xcodebuild.log; exit "$rc"; }
