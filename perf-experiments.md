# Stabilization perf experiments — branch `perf/stabilize-tier-a`

**Methodology:** one change at a time, BEFORE/AFTER on **speed** (median ms/photo
over measured rounds, warm-up discarded) **and** output **parity** (SHA-256 of
every stabilized PNG via the benchmark's manifest, diffed against baseline).
Keep only changes that show a speed win with byte-identical parity; scrap the
rest. Machine: macOS / Apple Silicon. Fixtures: 3 × 1080p face JPEGs.
Oracle commit: `0dd4da2`.

**Baseline (current main):** median **143 ms/photo**, determinism OK, 15/15 success.

| Item | Change | Parity | Speed (median) | Verdict |
|------|--------|--------|----------------|---------|
| A.2  | Route final PNG save through the persistent pool instead of a per-photo `Isolate.spawn` | identical ✅ | 147 vs 143 ms — no win (within noise) | **SCRAPPED** |
| A.1  | Fold the dims-only decode into a sticky `prepareSourceMat` (decode once, cache, return dims) + `useCachedSrc` on the initial warp (2 decodes → 1) | identical ✅ | 640×480: 147 vs 143 (noise). **12 MP: 147 vs 156 (−6%)** | **COMMITTED** (large-photo) |
| A.4  | `encodeRawToPng`: reconstruct Mat via `create` + `data.setAll` instead of `Mat.fromList` (which takes `List<num>` and copies twice) | identical ✅ | **114 vs 143 ms — −20%** (rounds 313–325 vs 387–436, no overlap) | **COMMITTED** |

### Micro-timing (op cost on a 640×480 / 0.9 MB frame)
| Op | Before | After | Per-photo | Decision |
|----|--------|-------|-----------|----------|
| A.1 source decode | 0.63 ms | — | once | **skip** — negligible on 640×480 fixtures; would help large (12 MP) inputs |
| A.4 Mat reconstruct | 2.55 ms | **0.02 ms** | once (on full ~6 MB canvas → ~15–29 ms) | **commit** — ~125× faster, byte-identical |
| A.3 `clearMatCache` | 0.20 ms | — | once | **skip** — negligible |

**Correction to the earlier "detection-bound" finding:** A.4 proves not all plumbing
is sub-noise. `Mat.fromList` scales with frame bytes (it copies twice + boxes to
`List<num>`); on the full output canvas it was a ~29 ms/photo hot spot the A.1/A.2
macro runs never exercised. Micro-timing is what surfaced it. Worth scanning for
other `Mat.fromList` uses on large frames as a follow-up.

### Large-photo (12 MP) regime — `PERF_LARGE=true`
The 640×480 fixtures masked decode-bound costs. A decode is 0.68 ms at 0.3 MP
but ~16 ms at 12 MP and ~28 ms at 23 MP (decode-size microbench). Re-running at
~12 MP (fixtures upscaled to 4000×3000):

| Item | 640×480 | 12 MP | Parity | Verdict |
|------|---------|-------|--------|---------|
| baseline (A.4 in) | median 114 ms | median **156 ms** | — | reference |
| **A.1** (reinstated) | 147 vs 143 (noise) | **147 vs 156 (−6%, ~9 ms)** | identical ✅ | **COMMITTED** |

**Lesson:** "sub-noise" was a fixture-size artifact. A.1 removes one full source
decode that's ~16 ms on a real photo and fires on every photo — neutral on tiny
fixtures, a real win at realistic sizes / old hardware. Always benchmark
decode-bound changes at representative resolution.

### #3 — plugin-side source-decode reuse (`face_detection_tflite`)
A single-face photo decoded the source twice in the detector isolate (once for
detection, once for embedding). Added a one-entry decode cache in the plugin so
the embedding reuses the Mat the preceding detect decoded. Tested via
`dependency_overrides` → local plugin, with the stored embedding added to the
parity manifest. Plugin change committed on its own branch
`perf/source-decode-reuse` (`4765f7a`).

| Item | 12 MP (override-baseline → after) | Parity (PNG + embedding) | Verdict |
|------|-----------------------------------|--------------------------|---------|
| **#3** | median **149 → 134 ms (−10%)**; rounds 431–443 → 374–397 | **IDENTICAL ✅** | **COMMITTED (plugin branch)** |

The `emb=` manifest hashes matched exactly — reusing the cached Mat yields a
bit-identical embedding (no wrong-image/mutation bug). ~15 ms/photo at 12 MP,
matching the predicted decode cost.

**Shipping:** AgeLapse's `dependency_overrides → ../face_detection_tflite` is
TEMP (local-path, breaks elsewhere). To ship: publish the plugin with this
change, bump AgeLapse's `face_detection_tflite` constraint, and remove the
override. Run the plugin's own CI/test suite before release.

## Banked wins (branch `perf/stabilize-tier-a` + plugin `perf/source-decode-reuse`)
- **A.4** `encodeRawToPng` create+setAll — −20% (640×480), byte-identical.
- **A.1** decode source once for initial pass — −6% (12 MP), byte-identical.
- **#3** plugin detect+embed share one decode — −10% (12 MP), byte-identical incl. embedding.
- Scrapped/skipped: A.2 (spawn→pool, no win), A.3 (clearMatCache, negligible).

### Finding: the benchmarked pipeline is detection-bound
A.1 removed a full source decode; A.2 removed an isolate spawn. Both were
byte-perfect and both were below the measurement noise floor (run-to-run
round-total drift ≈ ±15–20 ms on ~400 ms). Per-photo time is dominated by
TFLite **full-mode** inference (detect + mesh + iris) run across multiple
passes — not by decode/encode/isolate overhead. Implication: the Tier-A
plumbing items (incl. A.3 `clearMatCache`, A.4 `Mat.fromList`) are real but
unmeasurable here; meaningful speed lives in the detection levers (full→fast
mode for trials, fewer passes) and cross-photo concurrency — all output-changing
or structural, i.e. higher risk. Options: (a) stop Tier A; (b) add per-stage
micro-timing to bank sub-noise plumbing wins anyway; (c) pivot to detection.

### A.2 notes
Implementation was correct (parity held byte-for-byte). No speed gain because on
macOS/Apple Silicon `Isolate.spawn` is cheap, and routing the save through the
shared pool adds queue/dispatch overhead + contention with warp work without
removing the cross-isolate byte copy (the PNG bytes are sent either way).
Codex's "10–50 ms spawn → 1–5% win" estimate was too high for this platform.
**Lesson:** prioritize changes that cut real CPU work (A.1 full decode, A.4
element-wise Mat copy) over pure isolate round-trip removals (A.3).
