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

---

# Session 2 (Tier B) — branch `perf/stabilize-micro-2`

Same methodology and oracle as Tier A. **Baseline for this session** (main at
`e853c17`, 12 MP fixtures): median **144 ms/photo**, p25/p75 128/149,
determinism OK, 15/15 success. Manifest: `b2_baseline`.

| Item | Change | Op-level | Verdict |
|------|--------|----------|---------|
| B.M2 | Feed the detector raw Mat bytes from the pool's cached decode (kill the plugin-side source decode) | scrapped on arithmetic, not wired | **SCRAPPED** |
| B.1  | TransferableTypedData for big pool payloads (`encodeRawToPng` data, `prepareSourceMat` bytes) | 4.4 MB: 0.56 → 0.29 ms; 36 MB: 2.13 → 2.11 ms (wash). Total ≈ 0.5 ms/photo | **SKIPPED** (sub-1 ms; a plain TypedData send is already one memcpy) |
| B.2  | Coalesce `setPhotoStabilized` + `setPhotoFaceData` into one UPDATE (photo save does 2 UPDATEs on the same row) | 0.56 → 0.38 ms/photo | **SKIPPED** (0.18 ms; SQLite small-row UPDATEs are cheap here) |
| B.3  | **Harness fix**: benchmark called `stabilize()` without `knownFingerprint`, so the cache path streamed the source file through pure-Dart SHA-256 per photo (plus a backfill UPDATE) — a path the real batch flow never takes (import precomputes, `StabilizationService` passes `photo['fingerprint']`) | sha256: 75 KB fixture 0.82 ms; 12 MP 1.2 MB JPEG **8.52 ms/photo** (real 3–6 MB camera JPEGs: ~20–40 ms) | **COMMITTED** (test-only: setup stores fingerprints like import, rounds pass `knownFingerprint` like the service; re-baselines the oracle) |

### B.3 result — re-baselined oracle
With fingerprints stored at setup and passed as `knownFingerprint` (mirroring
import + `StabilizationService`): median **129 ms/photo** (was 144), p25/p75
119/138, 15/15 success, determinism OK, and the parity manifest is
**byte-identical** to `b2_baseline` (fingerprint only affects the timing path,
never the output). All future BEFORE/AFTER comparisons should use this
harness; the pre-fix numbers overstate per-photo cost by the sha256 of the
source file (~6% here, more with real multi-MB camera JPEGs).

### B.1/B.2 lesson
Both scraps died at the op level, cheaply. A plain `SendPort.send` of TypedData
is already a single memcpy (TransferableTypedData only wins when it avoids an
extra materialization, as the warp's native-view export does), and SQLite
small-row UPDATEs on this schema are ~0.3 ms, so coalescing two saves ~0.2 ms.
The remaining per-photo time is detection inference + the PNG encode of the
final save (byte-locked by the compression level) + the single source decode —
i.e. the byte-identical app-side plumbing is now genuinely mined out; what's
left is structural (cross-photo pipelining behind the reveal gate, detector
instance pool) or output-changing (GPU engine, detection input downscale).

### B.M2 notes — why raw handoff to the detector loses
The plugin's 6.4.1 decode cache only covers the encoded-bytes path
(`detectFacesFromBytes` + `getFaceEmbedding`); the raw-pixel APIs are stateless.
Feeding the detector raw pixels means shipping the 12 MP BGR frame (36 MB)
main→detector for detect AND again for embed, and exporting it worker→main
first. `TransferableTypedData.fromList` is a memcpy, so that is ~4 × 36 MB of
copies (~16–24 ms) to save one ~16 ms decode. Net regression at every size
(at small sizes both the decode and the copies are proportionally small).
The only winning shape is plugin-side: one API that decodes once and returns
faces + embedding in one call, keeping the frame inside the detector isolate.
That is a plugin feature, not an app-side micro.

## Session 2b — full per-photo budget reconciliation (op counters + op prices)

Op counters (`StabUtils.opDetectFull/opDetectRaw/opEmbeds/opWarps/opPngEncodes/
opSourceDecodes`, counting only) + per-fixture medians in the benchmark, plus
B.4/B.5 op prices, so the measured ms/photo can be explained line by line.

**Op mix at 12 MP (deterministic across all 6 rounds, parity identical):**

| fixture | median | detectFull | detectRaw | embeds | warps | pngEncodes | srcDecodes |
|---------|--------|------------|-----------|--------|-------|------------|------------|
| photo1  | 145 ms | 1 | 1 | 1 | 1 | 1 (L3: initial pass won) | 1 |
| photo2  | 127 ms | 1 | 3 | 1 | 3 | 1 (L1: refinement won)   | 1 |
| photo3  | 150 ms | 1 | 5 | 1 | 5 | 1 (L1)                   | 1 |

**Op prices (B.4/B.5, steady-state, 12 MP source / 1080x1920 canvas):**
srcDecode 16.3 ms; warp (cached src) 3.4 ms; detectFull (decode-cached)
9.5 ms; detectRaw (canvas) 8.4 ms; embed 5.1 ms; PNG encode of the real
photo1 frame: **L3 73.8 ms (1027 KB) vs L1 41.5 ms (1077 KB)**, decoded
pixels proven identical. (Synthetic full-content frame for reference:
L3 147.4 ms / L1 64.5 ms.)

**Ledger (op count × op price + ~20–30 ms misc vs measured):**

| fixture | explained | measured |
|---------|-----------|----------|
| photo1 (1 pass, L3)   | 16.3+9.5+5.1+11.8+73.8+misc ≈ 137–147 | 145 ms ✓ |
| photo2 (3 passes, L1) | 16.3+9.5+5.1+35.4+~35+misc ≈ 121–131  | 127 ms ✓ |
| photo3 (5 passes, L1) | 16.3+9.5+5.1+59.0+~35+misc ≈ 145–155  | 150 ms ✓ |

misc ≈ source file read, save-write isolate spawn + disk write, DB writes,
detection-cache write, cross-isolate transfers/materializes, round-trips.
The budget is fully accounted; nothing unexplained is hiding.

**Cross-checks:** photo3 − photo2 = 23 ms measured vs 2 × (3.4 + 8.4) =
23.6 ms predicted. photo1 (1 pass) is 18 ms *slower* than photo2 (3 passes):
solving the pair gives an L3-vs-L1 encode premium of ~42 ms on a real frame.
The best-aligned photo pays the most, because winning on the initial pass buys
the compression-3 encode.

**Headline correction:** the Tier-A conclusion "the pipeline is
detection-bound" was wrong — it was inferred from plumbing wins being
sub-noise, never from pricing the ops. Detection is 9.5 + 8.4 × passes + 5.1
≈ 23–57 ms/photo. **The single largest op is the final PNG encode**
(~40–80 ms depending on level), which nobody had measured because it is a
constant in every A/B diff.

### B.6 — unify the saved-PNG encode at compression 1 (APPROVED: pixel oracle)
`_finalizeStabilization` encoded the saved PNG at compression 3 when the
initial pass won (kept for byte-compat with the legacy non-raw flow) and 1
when a refinement pass won — the artifact byte format ALREADY varied by which
pass won, and the best-aligned photos paid a ~32 ms encode premium for it.
Decision (user-approved): define parity at the pixel level. The benchmark
oracle now hashes DECODED PIXELS (dims + type + data) instead of file bytes,
and the initial-pass encode moves to L1. B.5 proves L3/L1 decode-equality at
the op level; the end-to-end pixel manifest must be identical across the
change.

**Result (b2_pixelbaseline → b2_l1unified, same day, back-to-back):**

| fixture | before | after | pixels | file bytes |
|---------|--------|-------|--------|------------|
| photo1 (initial-pass winner) | 132 ms | **108 ms (−18%)** | identical ✅ | 1051887 → 1103123 (+4.9%) |
| photo2 | 113 ms | 117 ms (noise) | identical ✅ | unchanged (already L1) |
| photo3 | 135 ms | 135 ms | identical ✅ | unchanged (already L1) |

Overall median 132 → **117 ms/photo (−11%)**; determinism OK; embeddings and
transforms byte-identical. The win lands exactly where predicted: only on
initial-pass winners, the most common class in real libraries (well-aligned
photos), where it is −18% (−24 ms; op-level predicted −32, run noise absorbs
some).

Follow-ups in the same vein (pixel-identical, not yet done): the non-raw
save flow (`generateStabilizedImageBytesCVAsync`, non-eye projects + cat/dog)
still defaults to compression 3; and a faster PNG encoder (fpng/spng-class)
would cut the remaining ~40 ms encode by 5–10x at the cost of byte-format
differences — both now measurable against the pixel oracle.

### Not benchmarked, flagged for a future output-tolerant session
`face_detection_tflite` ships an optional LiteRT-Next GPU engine
(`useCompiledModel: true`, added in 6.4.0) that the app never enables. The
pipeline is detection-bound, so this is the biggest untouched lever, but GPU
float accumulation will not be bit-identical to the CPU interpreter: landmarks
shift in float noise, transforms shift, PNGs differ. Needs a tolerance oracle
(landmark/transform deltas + visual diff), not SHA-256.
