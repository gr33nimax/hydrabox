#!/usr/bin/env bash
set -euo pipefail

api_level="${1:?API level is required}"
arch="${2:?architecture is required}"
app_apk="$(find instrumentation-apks -name "app-$arch-debug.apk" -print -quit)"
test_apk="$(find instrumentation-apks -name app-debug-androidTest.apk -print -quit)"

test -f "$app_apk"
test -f "$test_apk"
adb wait-for-device

android_ready=false
for _ in $(seq 1 36); do
  boot_completed="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
  if [[ "$boot_completed" == "1" ]] \
    && adb shell service check package 2>/dev/null | grep -q 'found' \
    && adb shell cmd package list packages android 2>/dev/null | grep -q '^package:android$' \
    && adb shell test -d /data/user/0; then
    android_ready=true
    break
  fi
  sleep 5
done
if [[ "$android_ready" != true ]]; then
  adb shell getprop || true
  adb shell service check package || true
  adb shell cmd package list packages android || true
  adb logcat -d -v threadtime || true
  exit 1
fi

install_apk() {
  local apk="$1"
  local attempt
  for attempt in 1 2 3; do
    if adb install --no-streaming -r "$apk"; then
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

# Launch the actual Flutter activity after native instrumentation. This catches
# the production seam that service-only tests missed: Dart must reach both the
# Pigeon host bridge and the embedded HydraCore process.
bridge_file="$report_dir/api-$api_level-$arch-platform-bridge.txt"
ui_file="$report_dir/api-$api_level-$arch-window.xml"
adb shell am force-stop io.hydrabox.client
adb logcat -c || true
adb shell am start -W -n io.hydrabox.client/.MainActivity >>"$bridge_file" 2>&1

bridge_ready=false
for _ in $(seq 1 45); do
  adb logcat -d -v brief >"$logcat_file" 2>&1
  if grep -q 'platform_bridge_ready name=core_manager' "$logcat_file" \
    && grep -q 'platform_bridge_ready name=singbox' "$logcat_file" \
    && grep -q 'startup_healthy source=' "$logcat_file" \
    && grep -q 'platform_bridge_result name=getCoreCapabilities success=true' "$logcat_file"; then
    bridge_ready=true
    break
  fi
  if grep -Eq 'FATAL EXCEPTION|UnsatisfiedLinkError|startup_failed source=' "$logcat_file"; then
    break
  fi
  sleep 2
done

if [[ "$bridge_ready" != true ]]; then
  adb shell uiautomator dump /sdcard/hydrabox-window.xml >/dev/null 2>&1 || true
  adb pull /sdcard/hydrabox-window.xml "$ui_file" >/dev/null 2>&1 || true
  grep -E \
    'HydraCore|HydraBox|platform_bridge|AndroidRuntime|FATAL EXCEPTION|UnsatisfiedLinkError|startup_' \
    "$logcat_file" | tee -a "$bridge_file" || true
  exit 1
fi

grep -E 'platform_bridge_|startup_healthy' "$logcat_file" | tee -a "$bridge_file"
