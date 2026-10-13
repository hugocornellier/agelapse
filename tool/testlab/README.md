# Bulk import on real Android phones (Firebase Test Lab)

`integration_test/android_bulk_import_test.dart` reproduces issue #15 on a real
phone: one zip of hundreds of phone-sized photos, imported through the
gallery's zip import, then stabilized and compiled by the app itself with its
UI open. Every 15 seconds it logs an `AGELAPSE_BULK {...}` line to logcat
(photos stabilized and failed, stabilization state, memory, elapsed time). If
the app crashes, the run ends and the device's logcat holds the native crash
or low-memory kill.

Alongside, `MainActivityTest` logs the app's memory breakdown from `dumpsys
meminfo` every 20 seconds under the tag `AGELAPSE_MEM` (native heap, Dalvik
heap, graphics, code, and the rest), and each `AGELAPSE_BULK` line carries the
split of the RSS into anonymous, file-backed and shared pages plus Flutter's
image cache size. Together they say which kind of memory grew.

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
tool/testlab/bulk_import.sh build headless  # like bulk, without the app's UI

B=gs://test-lab-7yqvc8ruj90y2-k9u7wfunxj2sa/agelapse-fixtures
tool/testlab/bulk_import.sh run bulk akita 35 $B/agelapse-bulk-700.zip
tool/testlab/bulk_import.sh run compile a55xzh 36 $B/agelapse-bulk-54.zip
```

`run` downloads the device's logcat to `build/testlab/results/` and prints the
progress lines. List devices with
`gcloud firebase test android models list --project flutter-litert`.
`MediumPhone.arm` is an ARM virtual phone: use it to check the harness without
spending a physical run.

`headless` runs the same import, then drives `StabilizationService` directly
instead of starting the app. A normal run and a headless run side by side tell
UI memory (thumbnails, the image cache) from pipeline memory (decoding, face
detection, warping).

`probe` builds `integration_test/android_memory_probe_test.dart` instead. It
runs the pipeline layer by layer on distinct photos (the detector alone, the
worker pool's source cache alone, the warp pipeline without `FaceStabilizer`,
`FaceStabilizer.stabilize()` on distinct photos, the same call on one photo
over and over, then `StabilizationService` the way the app runs it) and logs
an `AGELAPSE_PROBE {...}` line before and after each layer, with a raw reading
every five photos in between. Before the before-and-after lines it garbage
collects every Dart isolate through the app's own VM service, so the figures
are what is really held, and every line carries the Dart heap and the
Dart-tracked external memory (`dartHeapMb`, `dartExternalMb`), the number of
collections the VM has run on its own (`gcEvents`) and the VM performance
mode the framework asked for (`perfMode`), next to the RSS and bionic's malloc
totals (`mallocUsedMb`, `mallocFreeMb`). A layer whose RSS and malloc figures
climb while `dartExternalMb` stays put holds native memory the Dart GC knows
nothing about; a climb with no collections in between is garbage the collector
is not getting to. The service stage adds a reading after a forced collection
every `PROBE_SERVICE_GC_EVERY` photos. The stage lengths are Dart defines
(`PROBE_ROUNDS`, `PROBE_RAW_ROUNDS`, `PROBE_SERVICE_ROUNDS`,
`PROBE_SERVICE_GC_EVERY`; the test's comment has the defaults), passed with
`EXTRA_DEFINES`. Any zip of 30 or more photos will do:

```sh
EXTRA_DEFINES="PROBE_ROUNDS=5 PROBE_RAW_ROUNDS=10 PROBE_SERVICE_ROUNDS=60" \
  tool/testlab/bulk_import.sh build probe
tool/testlab/bulk_import.sh run probe MediumPhone.arm 35 $B/agelapse-bulk-120.zip
```

## Running it on a desktop

The same test runs on macOS, Linux or Windows, where a run takes about a
minute and costs nothing. Point it at a zip with `BULK_ZIP_PATH`:

```sh
flutter test integration_test/android_bulk_import_test.dart -d macos \
  --dart-define=BULK_ZIP_PATH=/tmp/agelapse-bulk-120.zip \
  --dart-define=BULK_BUDGET_MINUTES=10
```

Test mode keeps the data in a temporary folder and a separate database, so a
desktop run doesn't touch the real app's projects.

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
