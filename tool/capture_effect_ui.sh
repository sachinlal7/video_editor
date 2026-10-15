#!/usr/bin/env bash
# Capture at the test's marker, before the native view is unmounted.
set -euo pipefail
platform=${1:?android or ios}
device=${2:?device id}
label=${3:?verification filename prefix}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/example"
flutter test integration_test/effects_ui_test.dart -d "$device" --no-uninstall --dart-define=CAPTURE_UI=true --reporter expanded 2>&1 |
while IFS= read -r line; do
  printf '%s\n' "$line"
  for theme in dark light; do
    if [[ "$line" == *"PHASE4_CAPTURE_$theme"* ]]; then
      output="$root/docs/verification/$label-$theme.png"
      if [[ "$platform" == android ]]; then
        adb -s "$device" exec-out screencap -p > "$output"
      elif [[ "$platform" == ios ]]; then
        xcrun simctl io "$device" screenshot "$output"
      else
        exit 2
      fi
    fi
  done
done
