import 'dart:io' show Platform;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

export 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _databaseInitialized = false;

void initDatabase() {
  if (_databaseInitialized) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    // Reset factory to null first to suppress "changing factory" warning
    databaseFactoryOrNull = null;
    databaseFactory = databaseFactoryFfi;
    _databaseInitialized = true;
  }
}
