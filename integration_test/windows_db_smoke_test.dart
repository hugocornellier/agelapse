// Fast Windows CI smoke test for the desktop SQLite path.
//
// Context: `sqlite3_flutter_libs` was removed from the app. On `package:sqlite3`
// 3.x the native SQLite library is bundled via Dart build hooks (a native code
// asset), and `sqlite3.dart` resolves its symbols exclusively through that
// asset (no filename / system fallback). Windows is the only shipped platform
// with no system SQLite to fall back on, so this test proves the hook-bundled
// library actually loads and works there.
//
// If the native asset is missing or fails to load, `openDatabase` throws and
// the job fails. Kept intentionally tiny (in-memory round-trip) so the only
// slow part is building the Windows app.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Re-exports package:sqflite_common_ffi/sqflite_ffi.dart (the exact factory the
// app uses on desktop), so this pins the same SQLite stack the app ships.
import 'package:agelapse/services/database_import_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('desktop sqlite3 loads without sqlite3_flutter_libs and round-trips',
      () async {
    // Same FFI factory setup the app performs in initDatabase() on desktop.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    try {
      await db
          .execute('CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT NOT NULL)');
      await db.insert('t', {'v': 'agelapse'});
      final rows = await db.query('t');
      expect(rows.single['v'], 'agelapse');

      // Reading the real SQLite version proves the bundled native lib is live.
      final version = (await db.rawQuery('SELECT sqlite_version() AS v'))
          .single['v'] as String;
      expect(version, isNotEmpty);
      // ignore: avoid_print
      print('[windows-db-smoke] sqlite_version = $version');
    } finally {
      await db.close();
    }
  });
}
