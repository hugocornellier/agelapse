import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/thumbnail_service.dart';

import '../helpers/mock_services.dart';

void main() {
  group('ThumbnailStatus', () {
    test('has all expected values', () {
      expect(ThumbnailStatus.values, hasLength(3));
      expect(ThumbnailStatus.values, contains(ThumbnailStatus.success));
      expect(ThumbnailStatus.values, contains(ThumbnailStatus.noFacesFound));
      expect(ThumbnailStatus.values, contains(ThumbnailStatus.stabFailed));
    });
  });

  group('ThumbnailEvent', () {
    test('stores all properties correctly', () {
      final event = ThumbnailEvent(
        thumbnailPath: '/path/to/thumb.jpg',
        status: ThumbnailStatus.success,
        projectId: 42,
        timestamp: '2024-01-01T12:00:00',
      );

      expect(event.thumbnailPath, '/path/to/thumb.jpg');
      expect(event.status, ThumbnailStatus.success);
      expect(event.projectId, 42);
      expect(event.timestamp, '2024-01-01T12:00:00');
    });

    test('handles noFacesFound status', () {
      final event = ThumbnailEvent(
        thumbnailPath: '/path/to/thumb.jpg',
        status: ThumbnailStatus.noFacesFound,
        projectId: 1,
        timestamp: '2024-01-01',
      );

      expect(event.status, ThumbnailStatus.noFacesFound);
    });

    test('handles stabFailed status', () {
      final event = ThumbnailEvent(
        thumbnailPath: '/path/to/thumb.jpg',
        status: ThumbnailStatus.stabFailed,
        projectId: 1,
        timestamp: '2024-01-01',
      );

      expect(event.status, ThumbnailStatus.stabFailed);
    });
  });

  group('TestableThumbnailService', () {
    late TestableThumbnailService service;

    setUp(() {
      service = TestableThumbnailService();
    });

    tearDown(() {
      service.dispose();
    });

    group('getStatus()', () {
      test('returns null for unknown path', () {
        expect(service.getStatus('/unknown/path.jpg'), isNull);
      });

      test('returns cached status after emit', () {
        final event = ThumbnailEvent(
          thumbnailPath: '/path/to/thumb.jpg',
          status: ThumbnailStatus.success,
          projectId: 1,
          timestamp: '2024-01-01',
        );

        service.emit(event);

        expect(
          service.getStatus('/path/to/thumb.jpg'),
          ThumbnailStatus.success,
        );
      });
    });

    group('emit()', () {
      test('adds event to stream', () async {
        final events = <ThumbnailEvent>[];
        final subscription = service.stream.listen(events.add);

        final event = ThumbnailEvent(
          thumbnailPath: '/path/to/thumb.jpg',
          status: ThumbnailStatus.success,
          projectId: 1,
          timestamp: '2024-01-01',
        );

        service.emit(event);

        await Future.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.first.thumbnailPath, '/path/to/thumb.jpg');

        await subscription.cancel();
      });

      test('caches status for later retrieval', () {
        final event = ThumbnailEvent(
          thumbnailPath: '/test/path.jpg',
          status: ThumbnailStatus.noFacesFound,
          projectId: 2,
          timestamp: '2024-01-02',
        );

        service.emit(event);

        expect(
          service.getStatus('/test/path.jpg'),
          ThumbnailStatus.noFacesFound,
        );
      });

      test('updates cache on re-emit for same path', () {
        final event1 = ThumbnailEvent(
          thumbnailPath: '/path.jpg',
          status: ThumbnailStatus.stabFailed,
          projectId: 1,
          timestamp: '2024-01-01',
        );

        final event2 = ThumbnailEvent(
          thumbnailPath: '/path.jpg',
          status: ThumbnailStatus.success,
          projectId: 1,
          timestamp: '2024-01-02',
        );

        service.emit(event1);
        expect(service.getStatus('/path.jpg'), ThumbnailStatus.stabFailed);

        service.emit(event2);
        expect(service.getStatus('/path.jpg'), ThumbnailStatus.success);
      });

      test('multiple subscribers receive same event', () async {
        final events1 = <ThumbnailEvent>[];
        final events2 = <ThumbnailEvent>[];

        final sub1 = service.stream.listen(events1.add);
        final sub2 = service.stream.listen(events2.add);

        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path.jpg',
            status: ThumbnailStatus.success,
            projectId: 1,
            timestamp: '2024-01-01',
          ),
        );

        await Future.delayed(Duration.zero);

        expect(events1, hasLength(1));
        expect(events2, hasLength(1));

        await sub1.cancel();
        await sub2.cancel();
      });
    });

    group('clearCache()', () {
      test('removes specific entry from cache', () {
        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path1.jpg',
            status: ThumbnailStatus.success,
            projectId: 1,
            timestamp: '2024-01-01',
          ),
        );
        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path2.jpg',
            status: ThumbnailStatus.success,
            projectId: 1,
            timestamp: '2024-01-01',
          ),
        );

        service.clearCache('/path1.jpg');

        expect(service.getStatus('/path1.jpg'), isNull);
        expect(service.getStatus('/path2.jpg'), ThumbnailStatus.success);
      });

      test('does nothing for non-existent path', () {
        // Should not throw
        expect(() => service.clearCache('/nonexistent.jpg'), returnsNormally);
      });
    });

    group('clearAllCache()', () {
      test('removes all entries from cache', () {
        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path1.jpg',
            status: ThumbnailStatus.success,
            projectId: 1,
            timestamp: '2024-01-01',
          ),
        );
        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path2.jpg',
            status: ThumbnailStatus.noFacesFound,
            projectId: 2,
            timestamp: '2024-01-02',
          ),
        );
        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path3.jpg',
            status: ThumbnailStatus.stabFailed,
            projectId: 3,
            timestamp: '2024-01-03',
          ),
        );

        service.clearAllCache();

        expect(service.getStatus('/path1.jpg'), isNull);
        expect(service.getStatus('/path2.jpg'), isNull);
        expect(service.getStatus('/path3.jpg'), isNull);
      });

      test('can emit and cache after clear', () {
        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path.jpg',
            status: ThumbnailStatus.success,
            projectId: 1,
            timestamp: '2024-01-01',
          ),
        );

        service.clearAllCache();

        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path.jpg',
            status: ThumbnailStatus.noFacesFound,
            projectId: 1,
            timestamp: '2024-01-02',
          ),
        );

        expect(service.getStatus('/path.jpg'), ThumbnailStatus.noFacesFound);
      });
    });

    group('stream', () {
      test('is broadcast stream (multiple listeners allowed)', () async {
        final completer1 = Completer<ThumbnailEvent>();
        final completer2 = Completer<ThumbnailEvent>();

        service.stream.first.then(completer1.complete);
        service.stream.first.then(completer2.complete);

        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/path.jpg',
            status: ThumbnailStatus.success,
            projectId: 1,
            timestamp: '2024-01-01',
          ),
        );

        final result1 = await completer1.future;
        final result2 = await completer2.future;

        expect(result1.thumbnailPath, '/path.jpg');
        expect(result2.thumbnailPath, '/path.jpg');
      });

      test('can filter events by projectId', () async {
        final project1Events = <ThumbnailEvent>[];
        final subscription = service.stream
            .where((e) => e.projectId == 1)
            .listen(project1Events.add);

        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/p1.jpg',
            status: ThumbnailStatus.success,
            projectId: 1,
            timestamp: '2024-01-01',
          ),
        );
        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/p2.jpg',
            status: ThumbnailStatus.success,
            projectId: 2,
            timestamp: '2024-01-01',
          ),
        );
        service.emit(
          ThumbnailEvent(
            thumbnailPath: '/p3.jpg',
            status: ThumbnailStatus.success,
            projectId: 1,
            timestamp: '2024-01-01',
          ),
        );

        await Future.delayed(Duration.zero);

        expect(project1Events, hasLength(2));
        expect(project1Events.every((e) => e.projectId == 1), isTrue);

        await subscription.cancel();
      });
    });

    group('dispose()', () {
      test('closes the stream', () async {
        bool streamDone = false;
        service.stream.listen((_) {}, onDone: () => streamDone = true);

        service.dispose();

        await Future.delayed(Duration.zero);
        expect(streamDone, isTrue);
      });
    });
  });
}
