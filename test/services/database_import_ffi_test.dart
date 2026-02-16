import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/database_import_ffi.dart';

/// Unit tests for database_import_ffi.dart.
/// Tests the FFI-specific database initialization for desktop platforms.
void main() {
  group('Database Import FFI', () {
    test('initDatabase function is available', () {
      expect(initDatabase, isA<Function>());
    });

    test('initDatabase can be called on desktop platforms', () {
      // On macOS/Windows/Linux, this initializes sqflite_ffi.
      // The _databaseInitialized guard prevents double-init.
      expect(() => initDatabase(), returnsNormally);
    });

    test('initDatabase is idempotent - multiple calls are safe', () {
      initDatabase();
      initDatabase();
      expect(() => initDatabase(), returnsNormally);
    });
  });
}
