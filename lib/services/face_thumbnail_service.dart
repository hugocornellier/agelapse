import 'dart:typed_data';

import '../models/detected_faces_snapshot.dart';
import '../models/face_detection_cache_result.dart';
import '../utils/format_decode_utils.dart';
import 'isolate_pool.dart';
import 'log_service.dart';

/// One cropped face thumbnail (or a per-face error). [faceIndex] matches the
/// detection-cache order (UI "Face N" == index N-1).
class FaceThumbnailResult {
  final int faceIndex;
  final Uint8List? bytes;
  final String? error;

  const FaceThumbnailResult({
    required this.faceIndex,
    this.bytes,
    this.error,
  });

  bool get ok => bytes != null;
}

/// Generates per-face cropped thumbnails from a [DetectedFacesSnapshot].
///
/// The source raw image is decoded once per request (in a worker isolate) and
/// every face is cropped from that single decode. Results are deduplicated
/// in-flight (so the info dialog and standalone dialog share one job) and held
/// in a small bounded in-memory LRU keyed by the exact detection signature.
/// Disk caching is intentionally deferred.
class FaceThumbnailService {
  FaceThumbnailService._();
  static final FaceThumbnailService instance = FaceThumbnailService._();

  static const int _maxCacheEntries = 24;

  final Map<String, List<FaceThumbnailResult>> _cache = {};
  final List<String> _lru = [];
  final Map<String, Future<List<FaceThumbnailResult>>> _inFlight = {};

  /// Loads (or generates) crops for [snapshot]. Returns an empty list when the
  /// snapshot has no available faces. The returned list is aligned to the
  /// detection-cache face order; individual entries may carry an error.
  Future<List<FaceThumbnailResult>> loadOrCreate(
    DetectedFacesSnapshot snapshot, {
    int maxDimension = 256,
    double paddingFraction = 0.15,
  }) async {
    if (!snapshot.isAvailable || snapshot.rawPath.isEmpty) {
      return const <FaceThumbnailResult>[];
    }
    final faces = snapshot.cache!.faces;
    if (faces.isEmpty) return const <FaceThumbnailResult>[];

    final key = _key(snapshot, maxDimension, paddingFraction);

    final cached = _cache[key];
    if (cached != null) {
      _touch(key);
      return cached;
    }

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _runGenerate(
      key,
      snapshot,
      faces,
      maxDimension,
      paddingFraction,
    );
    _inFlight[key] = future;
    return future;
  }

  Future<List<FaceThumbnailResult>> _runGenerate(
    String key,
    DetectedFacesSnapshot snapshot,
    List<CachedFace> faces,
    int maxDimension,
    double paddingFraction,
  ) async {
    try {
      final results =
          await _generate(snapshot, faces, maxDimension, paddingFraction);
      _put(key, results);
      return results;
    } catch (e, st) {
      LogService.instance.log('[face-thumb] generate threw: $e\n$st');
      return _allErrors(faces.length, 'Could not generate face thumbnails.');
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<List<FaceThumbnailResult>> _generate(
    DetectedFacesSnapshot snapshot,
    List<CachedFace> faces,
    int maxDimension,
    double paddingFraction,
  ) async {
    Uint8List? cvBytes;
    try {
      cvBytes = await FormatDecodeUtils.loadCvCompatibleBytes(snapshot.rawPath);
    } catch (e) {
      LogService.instance.log('[face-thumb] decode failed: $e');
    }
    if (cvBytes == null) {
      return _allErrors(faces.length, 'Could not read source image.');
    }

    final boxes = faces
        .map((f) => [
              f.boundingBox.left,
              f.boundingBox.top,
              f.boundingBox.right,
              f.boundingBox.bottom,
            ])
        .toList();

    List<dynamic>? raw;
    try {
      raw = await IsolatePool.instance.execute<List<dynamic>>(
        'cropFaceThumbnails',
        {
          'bytes': cvBytes,
          'orientation': snapshot.orientation ?? 'original',
          'boxes': boxes,
          'maxDimension': maxDimension,
          'paddingFraction': paddingFraction,
          'quality': 85,
        },
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          LogService.instance.log('[face-thumb] crop op timed out');
          return null;
        },
      );
    } catch (e) {
      LogService.instance.log('[face-thumb] crop failed: $e');
    }

    if (raw == null) {
      return _allErrors(faces.length, 'Could not generate face thumbnails.');
    }

    // Build results with a type-test (not a cast) so a non-Uint8List element
    // degrades to a per-face error instead of throwing and stalling the future.
    final results = <FaceThumbnailResult>[];
    for (int i = 0; i < faces.length; i++) {
      final dynamic el = i < raw.length ? raw[i] : null;
      Uint8List? bytes;
      if (el is Uint8List) {
        bytes = el;
      } else if (el is List<int>) {
        // Defensive: some transports surface bytes as a plain List<int>.
        bytes = Uint8List.fromList(el);
      } else if (el != null) {
        LogService.instance.log(
          '[face-thumb] result[$i] unexpected type=${el.runtimeType}',
        );
      }
      results.add(
        FaceThumbnailResult(
          faceIndex: i,
          bytes: bytes,
          error: bytes == null ? 'Face could not be cropped.' : null,
        ),
      );
    }
    return results;
  }

  List<FaceThumbnailResult> _allErrors(int n, String message) {
    return List<FaceThumbnailResult>.generate(
      n,
      (i) => FaceThumbnailResult(faceIndex: i, error: message),
    );
  }

  /// Cache key = the inputs that change the produced pixels. Excludes
  /// `selectedFaceIndex` (the checkmark doesn't change crops). Starts with the
  /// fingerprint so [evictForFingerprint] can prefix-match.
  String _key(
    DetectedFacesSnapshot s,
    int maxDimension,
    double paddingFraction,
  ) {
    final faces = s.cache?.faces ?? const <CachedFace>[];
    final sig = StringBuffer()
      ..write(s.fingerprint ?? s.rawPath)
      ..write('|${s.modelVersion}')
      ..write('|${s.orientation}')
      ..write('|d$maxDimension|p$paddingFraction');
    for (final f in faces) {
      final b = f.boundingBox;
      sig.write('|${b.left.toStringAsFixed(1)},${b.top.toStringAsFixed(1)},'
          '${b.right.toStringAsFixed(1)},${b.bottom.toStringAsFixed(1)}');
    }
    return sig.toString();
  }

  void _put(String key, List<FaceThumbnailResult> results) {
    _cache[key] = results;
    _touch(key);
    while (_lru.length > _maxCacheEntries) {
      final evict = _lru.removeAt(0);
      _cache.remove(evict);
    }
  }

  void _touch(String key) {
    _lru.remove(key);
    _lru.add(key);
  }

  /// Drops cached crops whose source fingerprint matches (call after a photo's
  /// source changes or it is re-stabilized onto a different face).
  void evictForFingerprint(String fingerprint) {
    if (fingerprint.isEmpty) return;
    _cache.removeWhere((k, _) => k.startsWith(fingerprint));
    _lru.removeWhere((k) => k.startsWith(fingerprint));
  }

  void clear() {
    _cache.clear();
    _lru.clear();
  }
}
