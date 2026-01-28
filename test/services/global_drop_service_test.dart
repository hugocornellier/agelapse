import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/global_drop_service.dart';

void main() {
  group('QueuedDropItem', () {
    test('creates instance with path and projectId', () {
      final item = QueuedDropItem(path: '/path/to/file.jpg', projectId: 1);

      expect(item.path, equals('/path/to/file.jpg'));
      expect(item.projectId, equals(1));
      expect(item.queuedAt, isA<DateTime>());
    });

    test('queuedAt is set to current time', () {
      final before = DateTime.now();
      final item = QueuedDropItem(path: '/test.jpg', projectId: 1);
      final after = DateTime.now();

      expect(item.queuedAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(item.queuedAt.isBefore(after.add(const Duration(seconds: 1))),
          isTrue);
    });
  });

  group('GlobalDropService', () {
    late GlobalDropService service;

    setUp(() {
      service = GlobalDropService.instance;
      // Reset state before each test
      service.clearQueue();
      if (service.isDragging) {
        service.onDragExit();
      }
      service.setImportSheetOpen(false);
    });

    group('singleton', () {
      test('returns same instance', () {
        final instance1 = GlobalDropService.instance;
        final instance2 = GlobalDropService.instance;
        expect(identical(instance1, instance2), isTrue);
      });
    });

    group('isDragging', () {
      test('is initially false', () {
        service.onDragExit(); // Ensure clean state
        expect(service.isDragging, isFalse);
      });

      test('becomes true after onDragEnter', () {
        service.onDragEnter();
        expect(service.isDragging, isTrue);
      });

      test('becomes false after onDragExit', () {
        service.onDragEnter();
        service.onDragExit();
        expect(service.isDragging, isFalse);
      });

      test('onDragEnter is idempotent', () {
        service.onDragEnter();
        service.onDragEnter();
        expect(service.isDragging, isTrue);
      });

      test('onDragExit is idempotent', () {
        service.onDragExit();
        service.onDragExit();
        expect(service.isDragging, isFalse);
      });
    });

    group('dragStateStream', () {
      test('emits true on drag enter', () async {
        final completer = Completer<bool>();
        final sub = service.dragStateStream.listen((state) {
          if (!completer.isCompleted) completer.complete(state);
        });

        service.onDragEnter();

        expect(await completer.future, isTrue);
        await sub.cancel();
      });

      test('emits false on drag exit', () async {
        service.onDragEnter();

        final completer = Completer<bool>();
        final sub = service.dragStateStream.listen((state) {
          if (!completer.isCompleted) completer.complete(state);
        });

        service.onDragExit();

        expect(await completer.future, isFalse);
        await sub.cancel();
      });
    });

    group('importSheetOpen', () {
      test('is initially false', () {
        expect(service.importSheetOpen, isFalse);
      });

      test('can be set to true', () {
        service.setImportSheetOpen(true);
        expect(service.importSheetOpen, isTrue);
      });

      test('can be set back to false', () {
        service.setImportSheetOpen(true);
        service.setImportSheetOpen(false);
        expect(service.importSheetOpen, isFalse);
      });
    });

    group('queueFiles', () {
      test('queues files successfully', () {
        final result =
            service.queueFiles(['/path/to/file1.jpg', '/path/to/file2.jpg'], 1);
        expect(result, isTrue);
        expect(service.queuedCount, equals(2));
      });

      test('deduplicates files by path', () {
        service.queueFiles(['/path/to/file1.jpg', '/path/to/file2.jpg'], 1);
        service.queueFiles(['/path/to/file1.jpg', '/path/to/file3.jpg'], 1);

        expect(service.queuedCount, equals(3)); // file1 not duplicated
      });

      test('returns true when queue is not full', () {
        final result = service.queueFiles(['/test.jpg'], 1);
        expect(result, isTrue);
      });

      test('tracks different project IDs separately', () {
        service.queueFiles(['/file1.jpg'], 1);
        service.queueFiles(['/file2.jpg'], 2);

        expect(service.queuedCount, equals(2));
      });

      test('hasQueuedFiles returns true when files are queued', () {
        expect(service.hasQueuedFiles, isFalse);
        service.queueFiles(['/test.jpg'], 1);
        expect(service.hasQueuedFiles, isTrue);
      });
    });

    group('queueUpdateStream', () {
      test('emits count on queue', () async {
        final completer = Completer<int>();
        final sub = service.queueUpdateStream.listen((count) {
          if (!completer.isCompleted) completer.complete(count);
        });

        service.queueFiles(['/test.jpg'], 1);

        expect(await completer.future, equals(1));
        await sub.cancel();
      });
    });

    group('consumeQueuedFiles', () {
      test('returns files for specific project', () {
        service.queueFiles(['/file1.jpg', '/file2.jpg'], 1);
        service.queueFiles(['/file3.jpg'], 2);

        final project1Files = service.consumeQueuedFiles(1);

        expect(project1Files, containsAll(['/file1.jpg', '/file2.jpg']));
        expect(project1Files.length, equals(2));
      });

      test('removes consumed files from queue', () {
        service.queueFiles(['/file1.jpg'], 1);
        service.queueFiles(['/file2.jpg'], 2);

        service.consumeQueuedFiles(1);

        expect(service.queuedCount, equals(1));
      });

      test('does not affect other project files', () {
        service.queueFiles(['/file1.jpg'], 1);
        service.queueFiles(['/file2.jpg'], 2);

        service.consumeQueuedFiles(1);
        final project2Files = service.consumeQueuedFiles(2);

        expect(project2Files, contains('/file2.jpg'));
      });

      test('returns empty list when no files for project', () {
        service.queueFiles(['/file1.jpg'], 1);

        final project2Files = service.consumeQueuedFiles(2);

        expect(project2Files, isEmpty);
      });

      test('returns empty list when queue is empty', () {
        final files = service.consumeQueuedFiles(1);
        expect(files, isEmpty);
      });
    });

    group('clearQueue', () {
      test('removes all queued files', () {
        service.queueFiles(['/file1.jpg', '/file2.jpg'], 1);
        service.queueFiles(['/file3.jpg'], 2);

        service.clearQueue();

        expect(service.queuedCount, equals(0));
        expect(service.hasQueuedFiles, isFalse);
      });

      test('emits 0 on queueUpdateStream', () async {
        service.queueFiles(['/test.jpg'], 1);

        final completer = Completer<int>();
        final sub = service.queueUpdateStream.listen((count) {
          if (!completer.isCompleted) completer.complete(count);
        });

        service.clearQueue();

        expect(await completer.future, equals(0));
        await sub.cancel();
      });
    });

    group('queuedCount', () {
      test('returns 0 when empty', () {
        expect(service.queuedCount, equals(0));
      });

      test('returns correct count after queuing', () {
        service.queueFiles(['/file1.jpg', '/file2.jpg', '/file3.jpg'], 1);
        expect(service.queuedCount, equals(3));
      });

      test('updates after consuming', () {
        service.queueFiles(['/file1.jpg', '/file2.jpg'], 1);
        service.consumeQueuedFiles(1);
        expect(service.queuedCount, equals(0));
      });
    });
  });
}
