# Face stabilization engine benchmark

`integration_test/stabilization_benchmark_test.dart` runs the production face
stabilization path with one of three detector configurations:

| `PERF_BACKEND` | Detector initialization |
| --- | --- |
| `interpreter` (default) | Unmodified production initialization; macOS selects XNNPACK with four CPU threads on this host |
| `compiled_cpu` | `useCompiledModel: true`, `{Accelerator.cpu}`, fp32 |
| `compiled_gpu_cpu` | `useCompiledModel: true`, `{Accelerator.gpu, Accelerator.cpu}`, fp32 |

The CompiledModel configurations are injected by the integration test. Normal
app initialization remains Interpreter. Dependencies, model bytes, back-camera
detector selection, full face detection mode, mesh pool size, image transforms,
PNG encoding, project settings, and fixture order remain the same between runs.
CompiledModel CPU thread count is controlled by its runtime; the face package
does not expose a matching thread-count option for that engine. This compares
the supported engine configurations, not API overhead in isolation.

Each process runs six rounds of the same three photos, discarding the first
round and reporting the median of 15 measured stabilizations. Every round uses
a fresh project, so project-scoped detection and transform caches start empty.
The detector persists between rounds. Model initialization is outside the
steady-state results; they do not measure time to the first stabilized photo.
PNG hashing and embedding hashing run after the per-photo stopwatch stops.
The test requires every measured photo to succeed, every output and embedding
to exist, and hashes to be deterministic across rounds.

## Results: 2026-09-22

Host: Apple M4 Max, Mac16,5, 16 CPU cores, macOS 27.0 (26A428). Flutter 3.47.5,
profile build, `face_detection_tflite 6.9.0`, `flutter_litert 3.9.0`. Repository
base: `a3f894db84e035e827c30ff1b0bf6cae8df03bdd`, plus the benchmark injection
and reporting changes. Output canvas: 1080×1920. The 12 MP inputs are upscaled
versions of the same three 640×480 JPEGs, not separate camera originals.

Times below are milliseconds per photo. Each cell comes from 15 measured
stabilizations after one three-photo warm-up round.

| Backend | 640×480 median | 640×480 mean | 12 MP median | 12 MP mean |
| --- | ---: | ---: | ---: | ---: |
| Interpreter, production XNNPACK | 109 | 99.73 | 104 | 108.93 |
| CompiledModel CPU | 101 | 91.40 | 105 | 111.60 |
| CompiledModel GPU+CPU, fp32 | 91 | 83.53 | 105 | 104.87 |

GPU+CPU reduced the small-fixture median by 16.5%. At 12 MP, medians were
effectively tied; GPU+CPU reduced average batch time by 3.7%, while CM CPU's
average was 2.4% slower than Interpreter. This does not establish a universal
CompiledModel speed advantage.

All six runs passed: 15/15 measured photos succeeded per run, and pixel and
embedding hashes were identical across all six rounds of each run. However,
**both CompiledModel configurations changed the pixel and embedding hashes for
all three fixtures at both resolutions** compared with Interpreter. Numerical
changes also affected how many refinement passes the unchanged algorithm took:

| Input | Interpreter warps, photos 1/2/3 | CM CPU warps | CM GPU+CPU warps |
| --- | --- | --- | --- |
| 640×480 | 7 / 2 / 6 | 5 / 2 / 5 | 5 / 2 / 6 |
| 12 MP | 1 / 3 / 5 | 1 / 3 / 6 | 1 / 4 / 5 |

Thus these are actual end-to-end engine-switch results, including changes in
refinement work; they cannot be attributed entirely to inference throughput.
The small-fixture GPU run changed one final rotation by 0.226 degrees relative
to Interpreter. No claim of identical image quality or bit-identical behavior
is made from the timing results.

Native logs confirmed Metal initialization in both GPU+CPU runs and showed
MobileFaceNet partitioned as 230 GPU operations plus one CPU operation
(`L2_NORMALIZATION`). There was no package-level GPU-to-CPU compilation fallback
message. Iris was CPU by the package's explicit implementation.

Run order was Interpreter → CM CPU → CM GPU+CPU for small inputs, followed by
CM GPU+CPU → CM CPU → Interpreter for 12 MP inputs. A final repeat of the small
Interpreter baseline also passed with a 109 ms median, 98.73 ms mean, and a
byte-identical manifest (`engine_interpreter_small_2`), checking for drift after
the initial native build. The raw JSON reports and manifests from these runs
were kept locally and are not checked in; rerun the commands below to
regenerate them.
Startup and shader compilation are excluded from the measured rounds; this
does not benchmark cold-start latency.

## Run

Use `flutter drive` for profile mode (`flutter test` only supports the debug
integration-test build):

```sh
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/stabilization_benchmark_test.dart \
  -d macos --profile --no-pub \
  --dart-define=PERF_BACKEND=interpreter \
  --dart-define=PERF_LABEL=interpreter
```

Repeat with `compiled_cpu` and `compiled_gpu_cpu`, changing both defines.
Add `--dart-define=PERF_LARGE=true` to **all** runs in a separate comparison
to use the existing 4000×3000 upscaled fixtures. Keep build mode, fixture size,
dependencies, and machine conditions consistent. Repeat in reverse order when
the timing difference is small.

Reports are written to `/tmp/agelapse_perf/<PERF_LABEL>.json` and `.manifest`.
The JSON includes every round, build mode, requested backend, transforms,
operation counts, pixel hashes, and embedding hashes. A cross-engine manifest
diff reports exact output changes; a successful run by itself checks only
within-engine determinism, not cross-engine equivalence.

## Existing flutter_litert matrix

The [flutter_litert benchmark directory][litert-bench] contains macOS, iOS, Galaxy S23,
Pixel 9 Pro, and Galaxy A56 results, plus a GPU vendor analysis. The local
macOS CSV is dated 2026-08-05; it is newer than the prose report. Its four
relevant model hashes match the installed `face_detection_tflite 6.9.0` assets.

These are macOS per-model p50 times, in milliseconds. Interpreter measures
invoke-only; CompiledModel includes managed I/O. Use these rows to select
candidates, not as a direct end-to-end speedup claim.

| Model | Interpreter XNNPACK | CM CPU | CM GPU+CPU fp32 | CM NPU+CPU |
| --- | ---: | ---: | ---: | ---: |
| Back-camera face detector | 2.451 | 3.881 | 1.849 | 1.229 |
| Face mesh | 0.748 | 0.803 | 1.058 | 4.122 |
| Iris | 0.933 | 0.490 | 0.829 | 4.776 |
| MobileFaceNet embedding | 2.962 | 2.172 | 0.738 | 25.066 |

All of these rows passed the matrix's CPU-reference tolerance. That tolerance
is `1e-4 + 1%`, not bit identity. The matrix uses synthetic tensor fixtures;
the stabilization benchmark adds real-image, full-pipeline checks.

- **GPU+CPU:** permits partitioning. MobileFaceNet has an operation that fails
  strict GPU compilation but can run in a mixed graph. The face package retries
  the complete model on CPU if its default GPU+CPU construction fails. The
  benchmark records a requested configuration, not proof of placement of every
  model; native diagnostics must be checked for fallback.
- **Iris:** `face_detection_tflite 6.9.0` explicitly pins CompiledModel iris to
  CPU, including when the other models request GPU+CPU.
- **fp32:** the vendor matrix found fp32 parity passed for every GPU model that
  executed on Metal, Adreno, Mali, and Xclipse. fp16 frequently failed that
  tolerance and is excluded from this comparison.
- **NPU:** strict NPU failed for these four models in the macOS matrix. Mixed
  NPU+CPU ran, but mesh and embedding latency make it an unpromising whole-pipeline
  selection here. Accelerator selection needs model- and device-specific data.
- **Other devices:** the Android rows do not show a universal CM advantage over
  XNNPACK. Pixel's long matrix also hit compilation-resource exhaustion;
  `GPU_VENDOR_MATRIX.md` records follow-up runs distinguishing that problem
  from model incompatibility. A Mac result should not set an Android default.

Source files in flutter_litert:
[`MACOS_MODEL_MATRIX_RESULTS.csv`](https://github.com/hugocornellier/flutter_litert/blob/ae56ca4/test/benchmark/MACOS_MODEL_MATRIX_RESULTS.csv),
[`GPU_VENDOR_MATRIX.md`](https://github.com/hugocornellier/flutter_litert/blob/ae56ca4/test/benchmark/GPU_VENDOR_MATRIX.md),
[`APPLE_MODEL_MATRIX.md`](https://github.com/hugocornellier/flutter_litert/blob/ae56ca4/test/benchmark/APPLE_MODEL_MATRIX.md).

[litert-bench]: https://github.com/hugocornellier/flutter_litert/tree/ae56ca4/test/benchmark
