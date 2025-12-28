import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:mocktail/mocktail.dart';
import 'package:sqflite/sqflite.dart';

import 'package:agelapse/services/database_helper.dart';
import 'package:agelapse/services/stabilization_service.dart';
import 'package:agelapse/services/thumbnail_service.dart';
import 'package:agelapse/services/log_service.dart';
import 'package:agelapse/services/isolate_manager.dart';
import 'package:agelapse/services/ffmpeg_process_manager.dart';
import 'package:agelapse/services/theme_provider.dart';
import 'package:agelapse/services/stabilization_progress.dart';

// Database mocks
class MockDatabase extends Mock implements Database {}

class MockDatabaseHelper extends Mock implements DB {}

// Service mocks
class MockStabilizationService extends Mock implements StabilizationService {
  final _progressController =
      StreamController<StabilizationProgress>.broadcast();

  @override
  Stream<StabilizationProgress> get progressStream =>
      _progressController.stream;

  void emitProgress(StabilizationProgress progress) {
    _progressController.add(progress);
  }

  @override
  void dispose() {
    _progressController.close();
  }
}

class MockThumbnailService extends Mock implements ThumbnailService {
  final _controller = StreamController<ThumbnailEvent>.broadcast();
  final Map<String, ThumbnailStatus> _statusCache = {};

  @override
  Stream<ThumbnailEvent> get stream => _controller.stream;

  @override
  ThumbnailStatus? getStatus(String thumbnailPath) =>
      _statusCache[thumbnailPath];

  @override
  void emit(ThumbnailEvent event) {
    _statusCache[event.thumbnailPath] = event.status;
    _controller.add(event);
  }

  @override
  void clearCache(String thumbnailPath) {
    _statusCache.remove(thumbnailPath);
  }

  @override
  void clearAllCache() {
    _statusCache.clear();
  }

  @override
  void dispose() {
    _controller.close();
  }
}

class MockLogService extends Mock implements LogService {}

class MockIsolateManager extends Mock implements IsolateManager {}

class MockFFmpegProcessManager extends Mock implements FFmpegProcessManager {}

class MockThemeProvider extends Mock implements ThemeProvider {}

// File system mocks
class MockDirectory extends Mock implements Directory {}

class MockFile extends Mock implements File {}

class MockIOSink extends Mock implements IOSink {}

// Note: Isolate is a final class and cannot be mocked
// For isolate manager testing, use TestableIsolateManager with real isolates
// or test with integration tests

// A testable version of ThumbnailService that doesn't use singleton
class TestableThumbnailService {
  final StreamController<ThumbnailEvent> _controller =
      StreamController<ThumbnailEvent>.broadcast();

  Stream<ThumbnailEvent> get stream => _controller.stream;

  final Map<String, ThumbnailStatus> _statusCache = {};

  ThumbnailStatus? getStatus(String thumbnailPath) =>
      _statusCache[thumbnailPath];

  void emit(ThumbnailEvent event) {
    _statusCache[event.thumbnailPath] = event.status;
    _controller.add(event);
  }

  void clearCache(String thumbnailPath) {
    _statusCache.remove(thumbnailPath);
  }

  void clearAllCache() {
    _statusCache.clear();
  }

  void dispose() {
    _controller.close();
  }
}

// A testable version of IsolateManager that doesn't use singleton
class TestableIsolateManager {
  final Set<Isolate> _activeIsolates = {};

  int get activeCount => _activeIsolates.length;

  bool get hasActiveIsolates => _activeIsolates.isNotEmpty;

  void register(Isolate isolate) {
    _activeIsolates.add(isolate);
  }

  void unregister(Isolate isolate) {
    _activeIsolates.remove(isolate);
  }

  void killAll() {
    if (_activeIsolates.isEmpty) return;

    for (final isolate in _activeIsolates) {
      try {
        isolate.kill(priority: Isolate.immediate);
      } catch (_) {}
    }

    _activeIsolates.clear();
  }

  void clear() {
    _activeIsolates.clear();
  }
}
