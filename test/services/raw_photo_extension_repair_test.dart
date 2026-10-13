import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/services/raw_photo_extension_repair.dart';
import 'package:path/path.dart' as p;

/// The file-system half of the #41 repair, on a temporary directory.
///
/// A case-insensitive file system (macOS, Windows) already resolves
/// `1.heic` to a file named `1.HEIC`, so there the repair must rename
/// nothing; the assertions branch on what the directory actually does.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('raw_ext_repair_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File fileIn(String name) => File(p.join(dir.path, name));

  bool caseSensitive() {
    final probe = fileIn('Probe.TMP')..writeAsStringSync('x');
    final sensitive = !fileIn('probe.tmp').existsSync();
    probe.deleteSync();
    return sensitive;
  }

  test(
    'renames upper-case extensions and leaves everything else alone',
    () async {
      fileIn('1700000000001.HEIC').writeAsStringSync('heic');
      fileIn('1700000000002.jpg').writeAsStringSync('jpg');
      fileIn('1700000000003.Jpg').writeAsStringSync('mixed');
      fileIn('README').writeAsStringSync('no extension');
      Directory(p.join(dir.path, 'Nested.DIR')).createSync();

      final sensitive = caseSensitive();
      final renamed = await RawPhotoExtensionRepair.renameUpperCaseExtensions(
        dir,
      );

      expect(renamed.length, sensitive ? 2 : 0);
      expect(fileIn('1700000000001.heic').readAsStringSync(), 'heic');
      expect(fileIn('1700000000002.jpg').readAsStringSync(), 'jpg');
      expect(fileIn('1700000000003.jpg').readAsStringSync(), 'mixed');
      expect(fileIn('README').existsSync(), isTrue);
      expect(Directory(p.join(dir.path, 'Nested.DIR')).existsSync(), isTrue);
      if (sensitive) {
        expect(renamed.map(p.basename).toSet(), {
          '1700000000001.heic',
          '1700000000003.jpg',
        });
        expect(fileIn('1700000000001.HEIC').existsSync(), isFalse);
        expect(fileIn('1700000000003.Jpg').existsSync(), isFalse);
      }
    },
  );

  test('never overwrites a lower-case twin', () async {
    if (!caseSensitive()) {
      markTestSkipped('needs a case-sensitive file system');
      return;
    }
    fileIn('1700000000004.JPG').writeAsStringSync('upper');
    fileIn('1700000000004.jpg').writeAsStringSync('lower');

    final renamed = await RawPhotoExtensionRepair.renameUpperCaseExtensions(
      dir,
    );

    expect(renamed, isEmpty);
    expect(fileIn('1700000000004.jpg').readAsStringSync(), 'lower');
    expect(fileIn('1700000000004.JPG').readAsStringSync(), 'upper');
  });

  test('a missing directory is a no-op', () async {
    final renamed = await RawPhotoExtensionRepair.renameUpperCaseExtensions(
      Directory(p.join(dir.path, 'missing')),
    );
    expect(renamed, isEmpty);
  });
}
