import 'dart:io';
import 'dart:typed_data';

import 'package:agelapse/utils/isolate_zip_reader.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lists entries and extracts content via a worker isolate', () async {
    final tmp = await Directory.systemTemp.createTemp('izr_test');
    addTearDown(() => tmp.delete(recursive: true));

    final fileA = File('${tmp.path}/a.txt')..writeAsStringSync('hello world');
    final fileB = File('${tmp.path}/b.bin')
      ..writeAsBytesSync(Uint8List(20000)); // compressible -> exercises inflate

    final zipPath = '${tmp.path}/test.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath); // default deflate
    await encoder.addFile(fileA, 'a.txt');
    await encoder.addFile(fileB, 'nested/b.bin');
    await encoder.close();

    final reader = IsolateZipReader();
    await reader.open(File(zipPath));
    try {
      final entries = await reader.entries();
      expect(
        entries.map((e) => e.name),
        containsAll(<String>['a.txt', 'nested/b.bin']),
      );

      final a = entries.firstWhere((e) => e.name == 'a.txt');
      expect(a.isDir, isFalse);
      expect(a.size, 'hello world'.length);

      final outA = File('${tmp.path}/out_a.txt');
      await reader.readToFile('a.txt', outA);
      expect(outA.readAsStringSync(), 'hello world');

      final outB = File('${tmp.path}/out_b.bin');
      await reader.readToFile('nested/b.bin', outB);
      expect(outB.lengthSync(), 20000);
      expect(outB.readAsBytesSync().every((b) => b == 0), isTrue);
    } finally {
      await reader.close();
    }
  });

  test('open() on a non-zip file yields no entries without crashing', () async {
    // archive's decoder tolerates garbage input and reports an empty archive
    // rather than throwing; the import flow handles an empty entry list. This
    // guards against the reader hanging or crashing on degenerate input.
    final tmp = await Directory.systemTemp.createTemp('izr_bad');
    addTearDown(() => tmp.delete(recursive: true));
    final bad = File('${tmp.path}/not_a_zip.txt')
      ..writeAsStringSync('definitely not a zip archive');

    final reader = IsolateZipReader();
    await reader.open(bad);
    try {
      expect(await reader.entries(), isEmpty);
    } finally {
      await reader.close();
    }
  });

  test('readToFile throws ZipReaderException for a missing entry', () async {
    final tmp = await Directory.systemTemp.createTemp('izr_missing');
    addTearDown(() => tmp.delete(recursive: true));
    final fileA = File('${tmp.path}/a.txt')..writeAsStringSync('x');

    final zipPath = '${tmp.path}/t.zip';
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addFile(fileA, 'a.txt');
    await encoder.close();

    final reader = IsolateZipReader();
    await reader.open(File(zipPath));
    try {
      await expectLater(
        reader.readToFile('does_not_exist.txt', File('${tmp.path}/out')),
        throwsA(isA<ZipReaderException>()),
      );
    } finally {
      await reader.close();
    }
  });
}
