# Bulk import on real Android phones (Firebase Test Lab)

`integration_test/android_bulk_import_test.dart` reproduces issue #15 on a real
phone: one zip of hundreds of phone-sized photos, imported through the
gallery's zip import, then stabilized and compiled by the app itself with its
UI open. Every 15 seconds it logs an `AGELAPSE_BULK {...}` line to logcat
(photos stabilized and failed, stabilization state, memory, elapsed time). If
the app crashes, the run ends and the device's logcat holds the native crash
or low-memory kill.

Test Lab runs it on the `flutter-litert` Firebase project. With the free plan
that is 5 physical device runs a day (each up to 45 minutes) and 10 virtual.

## 1. Make the photos

```sh
python3 -I tool/testlab/make_bulk_zip.py 700 /tmp/agelapse-bulk-700.zip
python3 -I tool/testlab/make_bulk_zip.py 54 /tmp/agelapse-bulk-54.zip
gcloud storage cp /tmp/agelapse-bulk-*.zip \
  gs://test-lab-7yqvc8ruj90y2-k9u7wfunxj2sa/agelapse-fixtures/ --project flutter-litert
```

Each photo is one of the 20 seeds in `samples_for_testing/hugocornellier-first20pics`,
upscaled to 4032x3024 (12 MP) with its own framing, brightness and noise, so
every file is unique and about the size of a phone camera JPEG (2.3 MB). The
700 photo zip is 1.6 GB.

## 2. Build and run

```sh
tool/testlab/bulk_import.sh build bulk      # stabilize as far as 40 minutes allow
tool/testlab/bulk_import.sh build compile   # date stamps on, must end with a video

B=gs://test-lab-7yqvc8ruj90y2-k9u7wfunxj2sa/agelapse-fixtures
tool/testlab/bulk_import.sh run bulk akita 35 $B/agelapse-bulk-700.zip
tool/testlab/bulk_import.sh run compile a55xzh 36 $B/agelapse-bulk-54.zip
```

`run` downloads the device's logcat to `build/testlab/results/` and prints the
progress lines. List devices with
`gcloud firebase test android models list --project flutter-litert`.
`MediumPhone.arm` is an ARM virtual phone: use it to check the harness without
spending a physical run.

## How the zip gets to the app

Test Lab's `--other-files` pushes the zip to `/sdcard/agelapse_bulk_import.zip`.
Recent Android doesn't let the app read that file, so
`android/app/src/androidTest/.../MainActivityTest.java` copies it into the
app's files folder through a shell command before the app starts. Without a
pushed zip the Dart test skips, so it is not part of any CI suite.

The same works on a local device with `adb push` plus `adb shell am instrument
-w com.hugocornellier.agelapse.test/androidx.test.runner.AndroidJUnitRunner`,
but not on an arm64 emulator on an M4 Mac: the emulator advertises SVE2 and
SME, which the Mac's hypervisor doesn't let guests run, so TensorFlow Lite
dies with SIGILL as soon as face detection starts.
