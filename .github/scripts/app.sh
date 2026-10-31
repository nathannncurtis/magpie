#!/usr/bin/env bash
# Generates the Xcode project, lints, builds with warnings as errors, and runs the tests on an iPhone simulator.
set -euo pipefail

[ -f project.yml ] || { echo "No app project yet."; exit 0; }

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

xcrun swift-format lint --strict --recursive --parallel Magpie $(ls -d MagpieTests MagpieUITests Packages 2>/dev/null)

# SIM_UDID picks a device (parallel local runs each use their own); otherwise the newest standard iPhone Pro
# this Xcode ships (by name pattern, so the job doesn't break when device names change; the foldable gets its
# own run once it has a layout).
udid=${SIM_UDID:-$(xcrun simctl list devices available -j |
  jq -r '[.devices | to_entries | map(select(.key | contains("iOS"))) | sort_by(.key | [scan("[0-9]+") | tonumber]) | .[] | .value[] | select(.name | test("^iPhone [0-9]+ Pro$"))] | last | .udid')}
test -n "$udid" && test "$udid" != null

# UI tests write a PNG per flow step here (the simulator shares the host filesystem); CI uploads them with the
# full xcodebuild log.
shots=${MAGPIE_SHOTS_DIR:-$PWD/shots}
mkdir -p "$shots"
export TEST_RUNNER_MAGPIE_SHOTS_DIR="$shots"

# The first UI test can start before the simulator finishes booting, and the launch then
# times out; boot the device and wait for it first.
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b

# A fresh simulator covers its first keyboard with the slide-to-type tip, which eats the keys a UI test types
# under it ("magpie test" lands as "magpietest"); mark the tip as already shown.
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences DidShowGestureKeyboardIntroduction -bool true
# UI tests type by tapping keys; a tap that lands as the suggestion bar over the keys
# changes is dropped or picks a suggestion ("magpie test" as "magpie tes", an address as
# "The http://…"). No suggestion bar and no autocorrection, so each tap is just a key.
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.predictive KeyboardPrediction -bool false
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences KeyboardAutocorrection -bool false

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
grep -E 'error:|warning:|Test Suite|Executed|✘|recorded an issue|\*\* (BUILD|TEST)' xcodebuild.log | sort -u | tail -80 || true
cp xcodebuild.log "$shots/" 2>/dev/null || true
# An app crash under test leaves its report with the host; keep it beside the shots.
cp ~/Library/Logs/DiagnosticReports/Magpie*.ips "$shots/" 2>/dev/null || true
[ "$rc" -eq 0 ] || { tail -60 xcodebuild.log; exit "$rc"; }
