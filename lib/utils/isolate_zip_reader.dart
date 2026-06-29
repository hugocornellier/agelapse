import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

/// Metadata describing a single entry inside a Zip archive.
typedef ZipEntryInfo = ({String name, int size, bool isDir});

/// Thrown when an [IsolateZipReader] operation fails on the worker isolate.
class ZipReaderException implements Exception {
  ZipReaderException(this.message);

  final String message;

  @override
  String toString() => 'ZipReaderException: $message';
}

/// Reads entries from a Zip archive on a background isolate.
///
/// This mirrors the off-main-thread behavior of the former `async_zip`
/// dependency, but is implemented purely in Dart on top of `package:archive`.
/// The archive's central directory is decoded once and kept open on the worker
/// isolate; entries are extracted lazily, one at a time, via [readToFile], so
/// peak memory and temporary disk usage stay bounded to a single entry
/// regardless of archive size. All decompression happens on the worker
/// isolate, keeping the UI thread responsive during imports.
///
/// Usage mirrors `async_zip`'s `ZipFileReader`:
/// ```dart
/// final reader = IsolateZipReader();
/// await reader.open(file);
/// final entries = await reader.entries();
/// await reader.readToFile(entries.first.name, tempFile);
/// await reader.close();
/// ```
class IsolateZipReader {
  final ReceivePort _responses = ReceivePort();
  final Completer<SendPort> _commandPort = Completer<SendPort>();
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;
  Isolate? _isolate;
  bool _closed = false;

  /// Opens [file] and decodes its central directory on a worker isolate.
  ///
  /// Throws a [ZipReaderException] if the archive cannot be opened or decoded.
  Future<void> open(File file) async {
    if (_isolate != null) {
      throw StateError('IsolateZipReader already open; call close() first');
    }
    _listen();
    _isolate = await Isolate.spawn(
      _worker,
      (_responses.sendPort, file.path),
      onError: _responses.sendPort,
      onExit: _responses.sendPort,
      debugName: 'IsolateZipReader',
    );
    // Round-trip to the worker so any open/decode error surfaces eagerly.
    await _send('ready');
  }

  /// Returns metadata for every entry in the archive.
  Future<List<ZipEntryInfo>> entries() async {
    final result = await _send('entries');
    return (result as List).cast<ZipEntryInfo>();
  }

  /// Extracts the entry named [name], writing its decompressed bytes to [file].
  ///
  /// Throws a [ZipReaderException] if the entry is missing or extraction fails.
  Future<void> readToFile(String name, File file) async {
    await _send('read', [name, file.path]);
  }

  /// Closes the archive and shuts down the worker isolate. Safe to call more
  /// than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_isolate != null) {
      try {
        await _send('close');
      } catch (_) {
        // Best-effort: the worker may already be gone.
      }
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
    }
    _failPending(ZipReaderException('reader closed'));
    _responses.close();
  }

  void _listen() {
    _responses.listen((Object? message) {
      if (message is SendPort) {
        if (!_commandPort.isCompleted) _commandPort.complete(message);
        return;
      }
      // An uncaught error from the worker arrives as a [error, stack] list;
      // a clean exit arrives as null. Either way, fail in-flight requests so
      // callers never hang on a dead isolate.
      if (message == null || message is List) {
        if (!_closed) {
          final detail = message is List && message.isNotEmpty
              ? '${message.first}'
              : 'worker isolate terminated unexpectedly';
          _failPending(ZipReaderException(detail));
        }
        return;
      }
      final (int id, Object? result, String? error) =
          message as (int, Object?, String?);
      final completer = _pending.remove(id);
      if (completer == null || completer.isCompleted) return;
      if (error != null) {
        completer.completeError(ZipReaderException(error));
      } else {
        completer.complete(result);
      }
    });
  }

  Future<Object?> _send(String command, [Object? param]) async {
    if (_closed && command != 'close') {
      throw ZipReaderException('reader closed');
    }
    final port = await _commandPort.future;
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send((id, command, param));
    return completer.future;
  }

  void _failPending(Object error) {
    if (_pending.isEmpty) return;
    final pending = List.of(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  // --- Worker isolate ------------------------------------------------------

  static void _worker((SendPort, String) init) {
    final (SendPort responses, String path) = init;
    final commands = ReceivePort();

    InputFileStream? input;
    final filesByName = <String, ArchiveFile>{};
    final entryInfos = <ZipEntryInfo>[];
    String? openError;

    try {
      final stream = InputFileStream(path);
      input = stream;
      final archive = ZipDecoder().decodeStream(stream);
      for (final file in archive.files) {
        filesByName[file.name] = file;
        entryInfos.add((name: file.name, size: file.size, isDir: !file.isFile));
      }
    } catch (e) {
      openError = '$e';
      input?.closeSync();
      input = null;
    }

    responses.send(commands.sendPort);

    commands.listen((Object? message) {
      final (int id, String command, Object? param) =
          message as (int, String, Object?);
      try {
        switch (command) {
          case 'ready':
            if (openError != null) throw Exception(openError);
            responses.send((id, null, null));
          case 'entries':
            responses.send((id, entryInfos, null));
          case 'read':
            final params = (param as List).cast<String>();
            final file = filesByName[params[0]];
            if (file == null) {
              throw Exception('entry not found: ${params[0]}');
            }
            final out = OutputFileStream(params[1]);
            file.writeContent(out);
            out.closeSync();
            responses.send((id, null, null));
          case 'close':
            input?.closeSync();
            input = null;
            responses.send((id, null, null));
            commands.close();
          default:
            responses.send((id, null, 'unknown command: $command'));
        }
      } catch (e) {
        responses.send((id, null, '$e'));
      }
    });
  }
}
