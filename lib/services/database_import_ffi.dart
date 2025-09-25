import 'dart:io' show Platform;

import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

export 'package:sqflite_common/sqflite.dart';
export 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initDatabase() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else {
    // just use default sqflite on mobile
  }
}
