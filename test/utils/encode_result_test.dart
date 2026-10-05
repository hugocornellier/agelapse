import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/video_utils.dart';

/// Unit tests for [EncodeResult.problemWith], which decides whether a
/// finished encode may replace the project's video.
void main() {
  late Directory dir;
  late File output;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('encode_result_test');
    output = File('${dir.path}/out.mp4');
    await output.writeAsBytes(List.filled(1024, 1));
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  EncodeResult result({
    int exitCode = 0,
    int expectedFrames = 690,
    int lastFrame = 690,
    String? suspectLine,
  }) => EncodeResult(
    exitCode: exitCode,
    cancelled: false,
    expectedFrames: expectedFrames,
    lastFrame: lastFrame,
    suspectLine: suspectLine,
  );

  test('a clean encode can be published', () async {
    expect(await result().problemWith(output), isNull);
  });

  test('a non-zero exit code is rejected', () async {
    expect(await result(exitCode: 1).problemWith(output), contains('exited'));
  });

  test('a suspicious FFmpeg message is rejected despite exit code 0', () async {
    final problem = await result(
      suspectLine:
          '[h264_videotoolbox] VT session restarted because of a '
          'kVTInvalidSessionErr error.',
    ).problemWith(output);
    expect(problem, contains('VT session restarted'));
  });

  test('a missing or empty output is rejected', () async {
    expect(
      await result().problemWith(File('${dir.path}/missing.mp4')),
      'no output file',
    );
    await output.writeAsBytes([]);
    expect(await result().problemWith(output), 'no output file');
  });

  test('a clearly short encode is rejected', () async {
    final problem = await result(lastFrame: 400).problemWith(output);
    expect(problem, 'encoded 400 of 690 frames');
  });

  test('a final progress line trailing the end slightly is accepted', () async {
    expect(await result(lastFrame: 660).problemWith(output), isNull);
  });

  test('the frame check is skipped when it cannot be measured', () async {
    // No progress reported.
    expect(await result(lastFrame: 0).problemWith(output), isNull);
    // Very short videos may not report a final count.
    expect(
      await result(expectedFrames: 3, lastFrame: 1).problemWith(output),
      isNull,
    );
  });
}
