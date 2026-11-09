#!/usr/bin/env bash
set +e
mkdir -p test-output
adb wait-for-device
adb shell input keyevent 82
adb shell wm size 1280x720
adb shell wm density 240
echo "=== DEVICE ===" > test-output/summary.txt
adb shell getprop ro.build.version.release >> test-output/summary.txt
adb shell getprop ro.product.cpu.abi >> test-output/summary.txt
echo "=== APK INSTALL ===" >> test-output/summary.txt
# Wait until Android's Package Manager is responsive before installing.
PACKAGE_MANAGER_READY=0
for attempt in $(seq 1 30); do
  if adb shell pm list packages >/dev/null 2>&1; then
    PACKAGE_MANAGER_READY=1
    break
  fi
  sleep 2
done
echo "package_manager_ready=$PACKAGE_MANAGER_READY" >> test-output/summary.txt

# Avoid adb's streamed-install path, which previously failed with Broken pipe.
INSTALL_RC=1
for attempt in 1 2 3; do
  echo "Install attempt $attempt" | tee -a test-output/install.txt
  adb install --no-streaming -r test-output/build-7.apk >> test-output/install.txt 2>&1
  INSTALL_RC=$?
  if [ "$INSTALL_RC" -eq 0 ]; then
    break
  fi
  sleep 5
done
cat test-output/install.txt
echo "install_exit_code=$INSTALL_RC" >> test-output/summary.txt
if [ "$INSTALL_RC" -eq 0 ]; then
  adb shell am force-stop com.webapp.neoracing3000
  adb logcat -c
  echo "=== LAUNCH ===" >> test-output/summary.txt
  adb shell monkey -p com.webapp.neoracing3000 -c android.intent.category.LAUNCHER 1 > test-output/launch.txt 2>&1
  LAUNCH_RC=$?
  cat test-output/launch.txt
  echo "launch_command_exit_code=$LAUNCH_RC" >> test-output/summary.txt
  sleep 30
  adb shell pidof com.webapp.neoracing3000 > test-output/process-id.txt 2>&1
  adb shell dumpsys activity activities > test-output/activities.txt 2>&1
  adb shell dumpsys package com.webapp.neoracing3000 > test-output/package-dump.txt 2>&1
  adb shell screencap -p /sdcard/build7-screen.png
  adb pull /sdcard/build7-screen.png test-output/build7-screen.png
  adb shell uiautomator dump /sdcard/build7-window.xml > test-output/uiautomator-command.txt 2>&1
  adb pull /sdcard/build7-window.xml test-output/build7-window.xml
  adb logcat -d -v threadtime > test-output/build7-logcat.txt
  adb logcat -b crash -d -v threadtime > test-output/build7-crash-buffer.txt
  if [ -s test-output/process-id.txt ]; then
    echo "RESULT=PROCESS_RUNNING_AFTER_30_SECONDS" >> test-output/summary.txt
  else
    echo "RESULT=PROCESS_NOT_RUNNING_AFTER_30_SECONDS" >> test-output/summary.txt
  fi
  if grep -E "FATAL EXCEPTION|Fatal signal|ANR in com.webapp.neoracing3000|Process: com.webapp.neoracing3000" test-output/build7-logcat.txt test-output/build7-crash-buffer.txt > test-output/crash-signatures.txt; then
    echo "CRASH_SIGNATURE_FOUND=true" >> test-output/summary.txt
  else
    echo "CRASH_SIGNATURE_FOUND=false" >> test-output/summary.txt
  fi
else
  adb logcat -d -v threadtime > test-output/build7-install-failure-logcat.txt
  adb logcat -b crash -d -v threadtime > test-output/build7-install-failure-crash-buffer.txt
  echo "RESULT=INSTALL_FAILED" >> test-output/summary.txt
fi
echo "=== FINAL SUMMARY ==="
cat test-output/summary.txt
