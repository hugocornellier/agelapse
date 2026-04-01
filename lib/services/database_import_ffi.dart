import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/platform_utils.dart';

export 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _databaseInitialized = false;

void initDatabase() {
  if (_databaseInitialized) return;
  if (isDesktop) {
    sqfliteFfiInit();
    // Reset factory to null first to suppress "changing factory" warning
    databaseFactoryOrNull = null;
    databaseFactory = databaseFactoryFfi;
    _databaseInitialized = true;
  }
}
