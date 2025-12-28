import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_services.dart';

void main() {
  group('TestableIsolateManager', () {
    late TestableIsolateManager manager;

    setUp(() {
      manager = TestableIsolateManager();
    });

    tearDown(() {
      manager.clear();
    });

    group('initial state', () {
      test('activeCount is 0', () {
        expect(manager.activeCount, 0);
      });

      test('hasActiveIsolates is false', () {
        expect(manager.hasActiveIsolates, isFalse);
      });
    });

    group('register() and unregister() with real isolates', () {
      test('register increments activeCount', () async {
        final receivePort = ReceivePort();
        final isolate = await Isolate.spawn(
          _simpleIsolateEntry,
          receivePort.sendPort,
        );

        try {
          manager.register(isolate);
          expect(manager.activeCount, 1);
          expect(manager.hasActiveIsolates, isTrue);
        } finally {
          manager.unregister(isolate);
          isolate.kill(priority: Isolate.immediate);
          receivePort.close();
        }
      });

      test('unregister decrements activeCount', () async {
        final receivePort = ReceivePort();
        final isolate = await Isolate.spawn(
          _simpleIsolateEntry,
          receivePort.sendPort,
        );

        try {
          manager.register(isolate);
          expect(manager.activeCount, 1);

          manager.unregister(isolate);
          expect(manager.activeCount, 0);
          expect(manager.hasActiveIsolates, isFalse);
        } finally {
          isolate.kill(priority: Isolate.immediate);
          receivePort.close();
        }
      });

      test('can register multiple isolates', () async {
        final ports = <ReceivePort>[];
        final isolates = <Isolate>[];

        try {
          for (var i = 0; i < 3; i++) {
            final receivePort = ReceivePort();
            ports.add(receivePort);
            final isolate = await Isolate.spawn(
              _simpleIsolateEntry,
              receivePort.sendPort,
            );
            isolates.add(isolate);
            manager.register(isolate);
          }

          expect(manager.activeCount, 3);
        } finally {
          for (var i = 0; i < isolates.length; i++) {
            manager.unregister(isolates[i]);
            isolates[i].kill(priority: Isolate.immediate);
            ports[i].close();
          }
        }
      });

      test('registering same isolate twice only counts once', () async {
        final receivePort = ReceivePort();
        final isolate = await Isolate.spawn(
          _simpleIsolateEntry,
          receivePort.sendPort,
        );

        try {
          manager.register(isolate);
          manager.register(isolate);

          expect(manager.activeCount, 1);
        } finally {
          manager.unregister(isolate);
          isolate.kill(priority: Isolate.immediate);
          receivePort.close();
        }
      });
    });

    group('killAll()', () {
      test('clears all isolates and kills them', () async {
        final ports = <ReceivePort>[];
        final isolates = <Isolate>[];

        for (var i = 0; i < 3; i++) {
          final receivePort = ReceivePort();
          ports.add(receivePort);
          final isolate = await Isolate.spawn(
            _simpleIsolateEntry,
            receivePort.sendPort,
          );
          isolates.add(isolate);
          manager.register(isolate);
        }

        expect(manager.activeCount, 3);

        manager.killAll();

        expect(manager.activeCount, 0);
        expect(manager.hasActiveIsolates, isFalse);

        // Clean up ports
        for (final port in ports) {
          port.close();
        }
      });

      test('does nothing when no isolates registered', () {
        expect(() => manager.killAll(), returnsNormally);
        expect(manager.activeCount, 0);
      });
    });

    group('clear()', () {
      test('removes all isolates without killing', () async {
        final receivePort = ReceivePort();
        final isolate = await Isolate.spawn(
          _simpleIsolateEntry,
          receivePort.sendPort,
        );

        try {
          manager.register(isolate);
          expect(manager.activeCount, 1);

          manager.clear();

          expect(manager.activeCount, 0);
          expect(manager.hasActiveIsolates, isFalse);
        } finally {
          isolate.kill(priority: Isolate.immediate);
          receivePort.close();
        }
      });
    });

    group('edge cases', () {
      test('unregister non-existent isolate does nothing', () async {
        final receivePort1 = ReceivePort();
        final receivePort2 = ReceivePort();
        final isolate1 = await Isolate.spawn(
          _simpleIsolateEntry,
          receivePort1.sendPort,
        );
        final isolate2 = await Isolate.spawn(
          _simpleIsolateEntry,
          receivePort2.sendPort,
        );

        try {
          manager.register(isolate1);

          // Unregistering an isolate that was never registered
          expect(() => manager.unregister(isolate2), returnsNormally);
          expect(manager.activeCount, 1);
        } finally {
          manager.clear();
          isolate1.kill(priority: Isolate.immediate);
          isolate2.kill(priority: Isolate.immediate);
          receivePort1.close();
          receivePort2.close();
        }
      });
    });
  });
}

/// Simple isolate entry point for testing
void _simpleIsolateEntry(SendPort sendPort) {
  // Just send a message back to confirm we're running
  sendPort.send('ready');
}
