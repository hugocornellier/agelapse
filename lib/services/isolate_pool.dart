import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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

    LogService.instance
        .log('IsolatePool: Initializing with $_workerCount workers');

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
    final isolate =
        await Isolate.spawn(_workerEntryPoint, receivePort.sendPort);

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
        final filePath = params['filePath'] as String;
        final bytes = params['bytes'] as Uint8List;
        await File(filePath).writeAsBytes(bytes);
        return 'File written successfully';

      case 'writeJpg':
        final filePath = params['filePath'] as String;
        final bytes = params['bytes'] as Uint8List;
        final mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
        if (mat.isEmpty) {
          mat.dispose();
          return 'Decoded mat is empty';
        }
        final (success, jpgBytes) = cv.imencode('.jpg', mat,
            params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));
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
              cv.VecMat.fromList([channels[0], channels[1], channels[2]]));
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
              cv.VecMat.fromList([channels[0], channels[1], channels[2]]));
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
        final height = (500 * aspectRatio).round();
        final thumb = cv.resize(composited, (500, height));
        composited.dispose();

        final (success, jpgBytes) = cv.imencode('.jpg', thumb,
            params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, 90]));
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

        final dst = cv.warpAffine(
          srcMat,
          rotMat,
          (canvasWidth, canvasHeight),
          borderMode: cv.BORDER_CONSTANT,
          borderValue: cv.Scalar.black,
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

      default:
        throw UnsupportedError('Unknown operation: $operation');
    }
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
      _Worker worker, String operation, Map<String, dynamic> params) async {
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
