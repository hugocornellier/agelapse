package com.hugocornellier.agelapse;

import android.app.UiAutomation;
import android.content.Context;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import dev.flutter.plugins.integration_test.FlutterTestRunner;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import org.junit.Rule;
import org.junit.runner.RunWith;

/**
 * Runs the Dart integration-test target as an Android instrumentation test,
 * which is how Firebase Test Lab runs tests on its phones.
 *
 * <p>Before the app starts, a fixture pushed to the device (Test Lab's
 * --other-files, or adb push) at {@link #PUSHED_FIXTURE} is copied into the
 * app's private files folder, where the Dart test reads it. Recent Android
 * versions don't let an app read arbitrary files on shared storage, but the
 * shell can, so the copy streams the file through a shell command.
 */
@RunWith(FlutterTestRunner.class)
public final class MainActivityTest {
  private static final String TAG = "AgeLapseTest";
  private static final String MEM_TAG = "AGELAPSE_MEM";
  private static final String PUSHED_FIXTURE = "/sdcard/agelapse_bulk_import.zip";
  private static final String STAGED_FIXTURE = "agelapse_bulk_import.zip";

  @Rule
  public ActivityTestRule<MainActivity> rule =
      new ActivityTestRule<MainActivity>(MainActivity.class, true, false) {
        @Override
        protected void beforeActivityLaunched() {
          stagePushedFixture();
          startMemorySampler();
        }
      };

  /**
   * Logs the app's memory breakdown every 20 seconds, as {@code dumpsys
   * meminfo} reports it, under the tag {@link #MEM_TAG}. The Dart test logs
   * the process RSS; this splits it into native heap, Dalvik heap, graphics
   * and the rest, so a run that grows shows which kind of memory grew.
   */
  private static void startMemorySampler() {
    Thread sampler =
        new Thread(
            () -> {
              UiAutomation shell =
                  InstrumentationRegistry.getInstrumentation().getUiAutomation();
              String target = InstrumentationRegistry.getInstrumentation().getTargetContext()
                  .getPackageName();
              while (true) {
                try {
                  Thread.sleep(20_000);
                } catch (InterruptedException e) {
                  return;
                }
                try (InputStream in =
                    new ParcelFileDescriptor.AutoCloseInputStream(
                        shell.executeShellCommand("dumpsys meminfo -s " + target))) {
                  String report = new String(readAll(in), "UTF-8");
                  StringBuilder summary = new StringBuilder();
                  for (String line : report.split("\n")) {
                    String t = line.trim();
                    if (t.startsWith("Native Heap:")
                        || t.startsWith("Dalvik Heap:")
                        || t.startsWith("Graphics:")
                        || t.startsWith("Code:")
                        || t.startsWith("Stack:")
                        || t.startsWith("Private Other:")
                        || t.startsWith("System:")
                        || t.startsWith("TOTAL PSS:")
                        || t.startsWith("TOTAL RSS:")) {
                      summary.append(t.replaceAll("\\s+", " ")).append(" | ");
                    }
                  }
                  Log.i(MEM_TAG, summary.toString());
                } catch (IOException e) {
                  Log.w(TAG, "meminfo failed: " + e);
                }
              }
            },
            "agelapse-mem-sampler");
    sampler.setDaemon(true);
    sampler.start();
  }

  private static byte[] readAll(InputStream in) throws IOException {
    java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
    byte[] buffer = new byte[1 << 14];
    int read;
    while ((read = in.read(buffer)) != -1) {
      out.write(buffer, 0, read);
    }
    return out.toByteArray();
  }

  private static void stagePushedFixture() {
    Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
    File target = new File(context.getFilesDir(), STAGED_FIXTURE);
    UiAutomation shell = InstrumentationRegistry.getInstrumentation().getUiAutomation();
    long total = 0;
    try (InputStream in =
            new ParcelFileDescriptor.AutoCloseInputStream(
                shell.executeShellCommand("cat " + PUSHED_FIXTURE));
        OutputStream out = new FileOutputStream(target)) {
      byte[] buffer = new byte[1 << 20];
      int read;
      while ((read = in.read(buffer)) != -1) {
        out.write(buffer, 0, read);
        total += read;
      }
    } catch (IOException e) {
      Log.w(TAG, "Could not stage " + PUSHED_FIXTURE + ": " + e);
      total = 0;
    }
    if (total == 0) {
      // Nothing was pushed: the Dart test skips itself.
      target.delete();
      Log.i(TAG, "No fixture at " + PUSHED_FIXTURE);
    } else {
      Log.i(TAG, "Staged " + PUSHED_FIXTURE + " (" + total + " bytes) at " + target);
    }
  }
}
