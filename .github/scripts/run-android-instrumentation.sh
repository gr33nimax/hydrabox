#!/usr/bin/env bash
set -euo pipefail

api_level="${1:?API level is required}"
arch="${2:?architecture is required}"
app_apk="$(find instrumentation-apks -name app-debug.apk -print -quit)"
test_apk="$(find instrumentation-apks -name app-debug-androidTest.apk -print -quit)"

test -f "$app_apk"
test -f "$test_apk"
adb wait-for-device

package_service_ready=false
for _ in 1 2 3 4 5 6; do
  if adb shell service check package | grep -q 'found'; then
    package_service_ready=true
    break
  fi
  sleep 5
done
test "$package_service_ready" = true

install_apk() {
  local apk="$1"
  local attempt
  for attempt in 1 2 3; do
    if adb install -r "$apk"; then
      return 0
    fi
    if [[ "$attempt" -eq 3 ]]; then
      return 1
    fi
    adb wait-for-device
    sleep $((attempt * 5))
  done
}

install_apk "$app_apk"
install_apk "$test_apk"

report_dir="build/instrumentation"
result_file="$report_dir/api-$api_level-$arch.txt"
logcat_file="$report_dir/api-$api_level-$arch-logcat.txt"
mkdir -p "$report_dir"
adb logcat -c || true

set +e
adb shell am instrument -w \
  io.hydrabox.client.test/androidx.test.runner.AndroidJUnitRunner \
  >"$result_file" 2>&1
status=$?
adb logcat -d -v threadtime >"$logcat_file" 2>&1
set -e

cat "$result_file"
if [[ "$status" -ne 0 ]]; then
  grep -E \
    'HydraCore|HydraBox|AndroidRuntime|FATAL EXCEPTION|UnsatisfiedLinkError|linker' \
    "$logcat_file" || true
  exit "$status"
fi
grep -E '^OK \([0-9]+ tests?\)$' "$result_file"
