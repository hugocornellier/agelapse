import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/database_import.dart';

/// Unit tests for database_import.dart conditional export.
/// This file re-exports database_import_mobile.dart or database_import_ffi.dart
/// depending on platform support for dart.library.ffi.
void main() {
  group('Database Import', () {
    test('initDatabase function is available', () {
      expect(initDatabase, isA<Function>());
    });

    test('initDatabase can be called without throwing', () {
      // On desktop (macOS), this initializes sqflite_ffi.
      // Calling it multiple times should be safe due to _databaseInitialized guard.
      expect(() => initDatabase(), returnsNormally);
    });

    test('initDatabase is idempotent', () {
      // Calling multiple times should not throw (guarded by _databaseInitialized flag)
      initDatabase();
      expect(() => initDatabase(), returnsNormally);
    });
  });
}
