import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'log_service.dart';

/// A task to be executed by a worker isolate.
class IsolateTask {
  final String operation;
  final Map<String, dynamic> params;
  final Completer<dynamic> completer;

  IsolateTask(this.operation, this.params, this.completer);
}

/// A persistent worker isolate that can process multiple tasks.
class _Worker {
  final Isolate isolate;
  final SendPort sendPort;
  final ReceivePort receivePort;
  bool isBusy = false;

  _Worker(this.isolate, this.sendPort, this.receivePort);

  Future<void> dispose() async {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

/// A pool of persistent worker isolates for image processing operations.
///
/// This eliminates the 10-50ms overhead of spawning/killing isolates per operation.
/// Workers are spawned once and reused for multiple tasks.
///
/// Usage:
/// ```dart
/// // Initialize once at app start
/// await IsolatePool.instance.initialize();
///
/// // Execute operations
/// final result = await IsolatePool.instance.execute('readToPng', {'filePath': path});
///
/// // Cleanup on app exit
/// await IsolatePool.instance.dispose();
/// ```
class IsolatePool {
  IsolatePool._internal();

  static final IsolatePool _instance = IsolatePool._internal();
  static IsolatePool get instance => _instance;

  /// Number of worker isolates to maintain.
  /// Desktop: 4 workers, Mobile: 2 workers.
  static int get _workerCount {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return 4;
    }
    return 2;
  }

  final List<_Worker> _workers = [];
  final List<IsolateTask> _taskQueue = [];
  bool _initialized = false;
  bool _isShuttingDown = false;

  /// Whether the pool is initialized and ready.
  bool get isInitialized => _initialized;

  /// Number of pending tasks in the queue.
  int get queueLength => _taskQueue.length;

  /// Number of busy workers.
  int get busyWorkers => _workers.where((w) => w.isBusy).length;

  /// Initialize the pool by spawning worker isolates.
  /// Call this once at app startup.
  Future<void> initialize() async {
    if (_initialized) return;

    LogService.instance.log(
      'IsolatePool: Initializing with $_workerCount workers',
    );

    for (int i = 0; i < _workerCount; i++) {
      final worker = await _spawnWorker();
      _workers.add(worker);
    }

    _initialized = true;
    LogService.instance.log('IsolatePool: Initialized');
  }

  /// Spawn a new worker isolate.
  Future<_Worker> _spawnWorker() async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerEntryPoint,
      receivePort.sendPort,
    );

    // First message from worker is its SendPort
    final sendPort = await receivePort.first as SendPort;

    // Create new ReceivePort for subsequent messages
    final workerReceivePort = ReceivePort();
    sendPort.send(workerReceivePort.sendPort);

    return _Worker(isolate, sendPort, workerReceivePort);
  }

  /// Worker isolate entry point.
  static void _workerEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    cv.Mat? cachedSrcMat;
    String? cachedSrcId;

    receivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        final operation = message['operation'] as String;
        final params = message['params'] as Map<String, dynamic>;
        final replyPort = message['replyPort'] as SendPort;

        try {
          final result = await _executeOperation(
            operation,
            params,
            cachedSrcMat: cachedSrcMat,
            cachedSrcId: cachedSrcId,
            onCacheUpdate: (mat, id) {
              // Dispose old cache before updating
              if (cachedSrcMat != null && cachedSrcId != id) {
                cachedSrcMat!.dispose();
              }
              cachedSrcMat = mat;
              cachedSrcId = id;
            },
            onCacheClear: () {
              cachedSrcMat?.dispose();
              cachedSrcMat = null;
              cachedSrcId = null;
            },
          );
          replyPort.send({'success': true, 'result': result});
        } catch (e) {
          replyPort.send({'success': false, 'error': e.toString()});
        }
      }
    });
  }

  /// Execute an operation in the worker isolate.
  static Future<dynamic> _executeOperation(
    String operation,
    Map<String, dynamic> params, {
    cv.Mat? cachedSrcMat,
    String? cachedSrcId,
    void Function(cv.Mat, String)? onCacheUpdate,
    void Function()? onCacheClear,
  }) async {
    switch (operation) {
      case 'readToPng':
        final filePath = params['filePath'] as String;
        final fileBytes = await File(filePath).readAsBytes();
        final mat = cv.imdecode(fileBytes, cv.IMREAD_COLOR);
        if (mat.isEmpty) {
          mat.dispose();
          return null;
        }
        final (success, pngBytes) = cv.imencode('.png', mat);
        mat.dispose();
        return success ? pngBytes : null;

      case 'writePngFromBytes':
        // Atomic write: temp file + rename to prevent partial writes
        final filePath = params['filePath'] as String;
        final bytes = params['bytes'] as Uint8List;
        final tempPath = '$filePath.tmp';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(bytes, flush: true);
        // Delete target first for Windows compatibility
        final targetFile = File(filePath);
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(filePath);
        return 'File written successfully';

      case 'writeJpg':
        final filePath = params['filePath'] as String;
        final bytes = params['bytes'] as Uint8List;
        final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
        if (mat.isEmpty) {
          mat.dispose();
          return 'Decoded mat is empty';
        }
        final (success, jpgBytes) = cv.imencode(
          '.jpg',
          mat,
          params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]),
        );
        mat.dispose();
        if (success) {
          await File(filePath).writeAsBytes(jpgBytes);
          return 'File written successfully';
        }
        return 'Failed to encode JPG';

      case 'compositeBlackPng':
        final input = params['bytes'] as Uint8List;
        final mat = cv.imdecode(input, cv.IMREAD_UNCHANGED);
        if (mat.isEmpty) {
          mat.dispose();
          return null;
        }

        cv.Mat result;
        if (mat.channels == 4) {
          final bg = cv.Mat.zeros(mat.rows, mat.cols, cv.MatType.CV_8UC3);
          final channels = cv.split(mat);
          final bgr = cv.merge(
            cv.VecMat.fromList([channels[0], channels[1], channels[2]]),
          );
          final alpha = channels[3];
          bgr.copyTo(bg, mask: alpha);
          for (final ch in channels) {
            ch.dispose();
          }
          bgr.dispose();
          result = bg;
        } else {
          result = mat.clone();
        }
        mat.dispose();

        final (success, pngBytes) = cv.imencode('.png', result);
        result.dispose();
        return success ? pngBytes : null;

      case 'thumbnailFromPng':
        final input = params['bytes'] as Uint8List;
        final mat = cv.imdecode(input, cv.IMREAD_UNCHANGED);
        if (mat.isEmpty) {
          mat.dispose();
          return null;
        }

        cv.Mat composited;
        if (mat.channels == 4) {
          final bg = cv.Mat.zeros(mat.rows, mat.cols, cv.MatType.CV_8UC3);
          final channels = cv.split(mat);
          final bgr = cv.merge(
            cv.VecMat.fromList([channels[0], channels[1], channels[2]]),
          );
          final alpha = channels[3];
          bgr.copyTo(bg, mask: alpha);
          for (final ch in channels) {
            ch.dispose();
          }
          bgr.dispose();
          composited = bg;
        } else {
          composited = mat.clone();
        }
        mat.dispose();

        final aspectRatio = composited.rows / composited.cols;
        final height = (800 * aspectRatio).round();
        final thumb = cv.resize(
          composited,
          (800, height),
          interpolation: cv.INTER_CUBIC,
        );
        composited.dispose();

        final (success, jpgBytes) = cv.imencode(
          '.jpg',
          thumb,
          params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]),
        );
        thumb.dispose();
        return success ? jpgBytes : null;

      case 'getImageDimensions':
        final bytes = params['bytes'] as Uint8List;
        final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
        if (mat.isEmpty) {
          mat.dispose();
          return null;
        }
        final dims = (mat.cols, mat.rows);
        mat.dispose();
        return dims;

      case 'stabilizeCV':
        final srcBytes = params['srcBytes'] as Uint8List;
        final rotationDegrees = params['rotationDegrees'] as double;
        final scaleFactor = params['scaleFactor'] as double;
        final translateX = params['translateX'] as double;
        final translateY = params['translateY'] as double;
        final canvasWidth = params['canvasWidth'] as int;
        final canvasHeight = params['canvasHeight'] as int;
        final srcId = params['srcId'] as String?;
        final backgroundColorBGR = params['backgroundColorBGR'] as List<int>?;

        // Use cached source Mat if available and matching, otherwise decode
        cv.Mat srcMat;
        bool shouldCache = srcId != null && onCacheUpdate != null;
        bool usedCache = false;

        if (srcId != null &&
            cachedSrcId == srcId &&
            cachedSrcMat != null &&
            !cachedSrcMat.isEmpty) {
          // Cache hit - reuse decoded Mat
          srcMat = cachedSrcMat;
          usedCache = true;
        } else {
          // Cache miss - decode and optionally cache
          srcMat = cv.imdecode(srcBytes, cv.IMREAD_COLOR);
          if (srcMat.isEmpty) {
            srcMat.dispose();
            return null;
          }
          // shouldCache implies srcId != null, safe to use directly
          if (srcId != null && onCacheUpdate != null) {
            onCacheUpdate(srcMat, srcId);
          }
        }

        final iw = srcMat.cols;
        final ih = srcMat.rows;

        final rotMat = cv.getRotationMatrix2D(
          cv.Point2f(iw / 2.0, ih / 2.0),
          -rotationDegrees,
          scaleFactor,
        );

        final offsetX = (canvasWidth - iw) / 2.0 + translateX;
        final offsetY = (canvasHeight - ih) / 2.0 + translateY;
        rotMat.set<double>(0, 2, rotMat.at<double>(0, 2) + offsetX);
        rotMat.set<double>(1, 2, rotMat.at<double>(1, 2) + offsetY);

        // Create border color scalar (default to black)
        final borderValue = backgroundColorBGR != null
            ? cv.Scalar(
                backgroundColorBGR[0].toDouble(),
                backgroundColorBGR[1].toDouble(),
                backgroundColorBGR[2].toDouble(),
                255.0,
              )
            : cv.Scalar.black;

        final dst = cv.warpAffine(
          srcMat,
          rotMat,
          (canvasWidth, canvasHeight),
          flags: cv.INTER_CUBIC,
          borderMode: cv.BORDER_CONSTANT,
          borderValue: borderValue,
        );

        final (success, bytes) = cv.imencode('.png', dst);

        rotMat.dispose();
        dst.dispose();
        // Only dispose srcMat if we didn't cache it and didn't use cache
        if (!shouldCache && !usedCache) {
          srcMat.dispose();
        }

        return success ? bytes : null;

      case 'clearMatCache':
        // Clear the cached source Mat to free memory
        onCacheClear?.call();
        return 'Cache cleared';

      case 'filterAndCenterEyes':
        return _filterAndCenterEyesIsolate(params);

      case 'getEyesFromFaces':
        return _getEyesFromFacesIsolate(params);

      case 'getCentermostEyes':
        return _getCentermostEyesIsolate(params);

      case 'pickFaceIndexByBox':
        return _pickFaceIndexByBoxIsolate(params);

      default:
        throw UnsupportedError('Unknown operation: $operation');
    }
  }

  // ============================================================
  // COORDINATE PROCESSING ISOLATE FUNCTIONS
  // ============================================================

  /// Isolate implementation: Extract eye coordinates from serialized faces.
  static List<List<double>?> _getEyesFromFacesIsolate(
      Map<String, dynamic> params) {
    final facesData = params['faces'] as List;
    final List<List<double>?> eyes = [];

    for (final faceMap in facesData) {
      final Map<String, dynamic> f = faceMap as Map<String, dynamic>;
      final leftEyeData = f['leftEye'] as List?;
      final rightEyeData = f['rightEye'] as List?;

      List<double>? a = leftEyeData != null
          ? [
              (leftEyeData[0] as num).toDouble(),
              (leftEyeData[1] as num).toDouble()
            ]
          : null;
      List<double>? b = rightEyeData != null
          ? [
              (rightEyeData[0] as num).toDouble(),
              (rightEyeData[1] as num).toDouble()
            ]
          : null;

      // Fallback to bounding box estimation if eyes missing
      if (a == null || b == null) {
        final bbox = f['bbox'] as List;
        final left = (bbox[0] as num).toDouble();
        final top = (bbox[1] as num).toDouble();
        final right = (bbox[2] as num).toDouble();
        final bottom = (bbox[3] as num).toDouble();
        final width = right - left;
        final height = bottom - top;
        final ey = top + height * 0.42;
        a = [left + width * 0.33, ey];
        b = [left + width * 0.67, ey];
      }

      // Ensure left eye is actually on the left
      if (a[0] > b[0]) {
        final tmp = a;
        a = b;
        b = tmp;
      }

      eyes.add(a);
      eyes.add(b);
    }

    return eyes;
  }

  /// Isolate implementation: Get centermost eyes from multiple faces.
  static List<List<double>> _getCentermostEyesIsolate(
      Map<String, dynamic> params) {
    final eyesData = params['eyes'] as List;
    final facesData = params['faces'] as List;
    final imgWidth = params['imgWidth'] as int;
    final imgHeight = params['imgHeight'] as int;

    // Convert serialized data to working format
    final List<List<double>?> eyes = eyesData
        .map((e) => e != null
            ? [(e[0] as num).toDouble(), (e[1] as num).toDouble()]
            : null)
        .toList();

    // Filter to faces with detected eyes
    final validFaces = <Map<String, dynamic>>[];
    for (final faceMap in facesData) {
      final f = faceMap as Map<String, dynamic>;
      if (f['leftEye'] != null && f['rightEye'] != null) {
        validFaces.add(f);
      }
    }

    final double marginPx = max(4.0, imgWidth * 0.01);

    bool touchesEdge(List bbox) {
      final left = (bbox[0] as num).toDouble();
      final top = (bbox[1] as num).toDouble();
      final right = (bbox[2] as num).toDouble();
      final bottom = (bbox[3] as num).toDouble();
      return left <= marginPx ||
          top <= marginPx ||
          right >= imgWidth - marginPx ||
          bottom >= imgHeight - marginPx;
    }

    double calcHorizontalProximity(List<double> point) {
      final centerX = imgWidth ~/ 2;
      return (point[0] - centerX).abs();
    }

    double smallestDistance = double.infinity;
    List<List<double>> centeredEyes = [];

    final int pairCount = eyes.length ~/ 2;
    final int limit =
        validFaces.length < pairCount ? validFaces.length : pairCount;

    for (var i = 0; i < limit; i++) {
      final bbox = validFaces[i]['bbox'] as List;
      if (touchesEdge(bbox)) continue;

      final int li = 2 * i, ri = li + 1;
      final leftEye = eyes[li];
      final rightEye = eyes[ri];
      if (leftEye == null || rightEye == null) continue;

      final double distance =
          calcHorizontalProximity(leftEye) + calcHorizontalProximity(rightEye);

      if (distance < smallestDistance) {
        smallestDistance = distance;
        centeredEyes = [leftEye, rightEye];
      }
    }

    // Fallback to first valid pair
    if (centeredEyes.isEmpty &&
        eyes.length >= 2 &&
        eyes[0] != null &&
        eyes[1] != null) {
      centeredEyes = [eyes[0]!, eyes[1]!];
    }

    return centeredEyes;
  }

  /// Isolate implementation: Filter eyes and get centermost if multiple faces.
  static List<List<double>?> _filterAndCenterEyesIsolate(
      Map<String, dynamic> params) {
    final facesData = params['faces'] as List;
    final imgWidth = params['imgWidth'] as int;
    final imgHeight = params['imgHeight'] as int;
    final eyeDistanceGoal = (params['eyeDistanceGoal'] as num).toDouble();

    // Get all eyes from faces
    final allEyes = _getEyesFromFacesIsolate({'faces': facesData});

    final List<List<double>> validPairs = [];
    final List<Map<String, dynamic>> validFaces = [];

    for (int faceIdx = 0; faceIdx < facesData.length; faceIdx++) {
      final int li = 2 * faceIdx;
      final int ri = li + 1;
      if (ri >= allEyes.length) break;

      final leftEye = allEyes[li];
      final rightEye = allEyes[ri];
      if (leftEye == null || rightEye == null) continue;

      // Check eye distance validity
      if ((rightEye[0] - leftEye[0]).abs() > 0.75 * eyeDistanceGoal) {
        validPairs.add(leftEye);
        validPairs.add(rightEye);
        validFaces.add(facesData[faceIdx] as Map<String, dynamic>);
      }
    }

    // If multiple valid faces, get centermost
    if (validFaces.length > 1 && validPairs.length > 2) {
      return _getCentermostEyesIsolate({
        'eyes': validPairs,
        'faces': validFaces,
        'imgWidth': imgWidth,
        'imgHeight': imgHeight,
      });
    }

    return validPairs.isEmpty ? [] : validPairs;
  }

  /// Isolate implementation: Pick face index by bounding box IoU.
  static int _pickFaceIndexByBoxIsolate(Map<String, dynamic> params) {
    final facesData = params['faces'] as List;
    final targetBbox = params['targetBox'] as List;
    final targetLeft = (targetBbox[0] as num).toDouble();
    final targetTop = (targetBbox[1] as num).toDouble();
    final targetRight = (targetBbox[2] as num).toDouble();
    final targetBottom = (targetBbox[3] as num).toDouble();
    final targetCenterX = (targetLeft + targetRight) / 2;
    final targetCenterY = (targetTop + targetBottom) / 2;

    double rectIoU(List bbox) {
      final aLeft = (bbox[0] as num).toDouble();
      final aTop = (bbox[1] as num).toDouble();
      final aRight = (bbox[2] as num).toDouble();
      final aBottom = (bbox[3] as num).toDouble();

      final x1 = aLeft > targetLeft ? aLeft : targetLeft;
      final y1 = aTop > targetTop ? aTop : targetTop;
      final x2 = aRight < targetRight ? aRight : targetRight;
      final y2 = aBottom < targetBottom ? aBottom : targetBottom;

      final w = x2 - x1;
      final h = y2 - y1;
      if (w <= 0 || h <= 0) return 0.0;

      final inter = w * h;
      final areaA = (aRight - aLeft) * (aBottom - aTop);
      final areaB = (targetRight - targetLeft) * (targetBottom - targetTop);
      final union = areaA + areaB - inter;
      return union <= 0 ? 0.0 : inter / union;
    }

    double bestIoU = 0.0;
    int bestIdx = -1;

    for (int i = 0; i < facesData.length; i++) {
      final face = facesData[i] as Map<String, dynamic>;
      final bbox = face['bbox'] as List;
      final iou = rectIoU(bbox);
      if (iou > bestIoU) {
        bestIoU = iou;
        bestIdx = i;
      }
    }

    if (bestIdx != -1) return bestIdx;

    // Fallback to distance-based selection
    double bestDist = double.infinity;
    for (int i = 0; i < facesData.length; i++) {
      final face = facesData[i] as Map<String, dynamic>;
      final bbox = face['bbox'] as List;
      final left = (bbox[0] as num).toDouble();
      final top = (bbox[1] as num).toDouble();
      final right = (bbox[2] as num).toDouble();
      final bottom = (bbox[3] as num).toDouble();
      final centerX = (left + right) / 2;
      final centerY = (top + bottom) / 2;
      final dx = centerX - targetCenterX;
      final dy = centerY - targetCenterY;
      final d2 = dx * dx + dy * dy;
      if (d2 < bestDist) {
        bestDist = d2;
        bestIdx = i;
      }
    }

    return bestIdx;
  }

  /// Execute an operation on a pooled worker.
  /// Returns the result of the operation.
  Future<T?> execute<T>(String operation, Map<String, dynamic> params) async {
    if (!_initialized) {
      await initialize();
    }

    if (_isShuttingDown) {
      throw StateError('IsolatePool is shutting down');
    }

    // Find an available worker
    final worker = _workers.firstWhereOrNull((w) => !w.isBusy);

    if (worker != null) {
      return await _executeOnWorker<T>(worker, operation, params);
    } else {
      // All workers busy - queue the task
      final completer = Completer<dynamic>();
      _taskQueue.add(IsolateTask(operation, params, completer));
      return await completer.future as T?;
    }
  }

  Future<T?> _executeOnWorker<T>(
    _Worker worker,
    String operation,
    Map<String, dynamic> params,
  ) async {
    worker.isBusy = true;

    try {
      final responsePort = ReceivePort();
      worker.sendPort.send({
        'operation': operation,
        'params': params,
        'replyPort': responsePort.sendPort,
      });

      final response = await responsePort.first as Map<String, dynamic>;
      responsePort.close();

      if (response['success'] == true) {
        return response['result'] as T?;
      } else {
        LogService.instance.log('IsolatePool error: ${response['error']}');
        return null;
      }
    } finally {
      worker.isBusy = false;
      _processQueue();
    }
  }

  void _processQueue() {
    if (_taskQueue.isEmpty) return;

    final worker = _workers.firstWhereOrNull((w) => !w.isBusy);
    if (worker == null) return;

    final task = _taskQueue.removeAt(0);
    _executeOnWorker(worker, task.operation, task.params).then((result) {
      task.completer.complete(result);
    }).catchError((e) {
      task.completer.completeError(e);
    });
  }

  /// Clear cached Mat in all workers (call after finishing a photo).
  /// This frees memory held by decoded source images.
  Future<void> clearMatCache() async {
    if (!_initialized) return;

    // Send clear command to all workers
    final futures = <Future>[];
    for (final worker in _workers) {
      if (!worker.isBusy) {
        futures.add(_executeOnWorker(worker, 'clearMatCache', {}));
      }
    }
    await Future.wait(futures);
  }

  /// Kill all workers instantly (for cancellation).
  void killAll() {
    LogService.instance.log('IsolatePool: Killing all workers');
    for (final worker in _workers) {
      worker.isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
    _initialized = false;

    // Fail all queued tasks
    for (final task in _taskQueue) {
      task.completer.completeError(StateError('Pool was killed'));
    }
    _taskQueue.clear();
  }

  /// Gracefully dispose of the pool.
  Future<void> dispose() async {
    if (!_initialized) return;

    _isShuttingDown = true;
    LogService.instance.log('IsolatePool: Disposing');

    // Wait for busy workers to finish
    while (_workers.any((w) => w.isBusy)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    for (final worker in _workers) {
      await worker.dispose();
    }
    _workers.clear();
    _initialized = false;
    _isShuttingDown = false;

    LogService.instance.log('IsolatePool: Disposed');
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
