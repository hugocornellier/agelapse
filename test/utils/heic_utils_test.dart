import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/heic_utils.dart';

/// Unit tests for HeicUtils.
/// Tests constants, method signatures, and platform checks.
void main() {
  group('HeicUtils Class', () {
    test('HeicUtils class is accessible', () {
      expect(HeicUtils, isNotNull);
    });
  });

  group('HeicUtils Method Signatures', () {
    test('convertHeicToJpg method exists', () {
      expect(HeicUtils.convertHeicToJpg, isA<Function>());
    });

    test('convertHeicToJpgAt method exists', () {
      expect(HeicUtils.convertHeicToJpgAt, isA<Function>());
    });
  });

  group('HeicUtils Static Nature', () {
    test('all methods are static', () {
      // These should compile without needing an instance
      // ignore: unnecessary_type_check
      expect(HeicUtils.convertHeicToJpg is Function, isTrue);
      // ignore: unnecessary_type_check
      expect(HeicUtils.convertHeicToJpgAt is Function, isTrue);
    });
  });

  group('HeicUtils Platform Behavior', () {
    test('convertHeicToJpg returns null on non-Windows platforms', () async {
      if (!Platform.isWindows) {
        final result =
            await HeicUtils.convertHeicToJpg('/nonexistent/file.heic');
        expect(result, isNull);
      }
    });

    test('convertHeicToJpgAt returns false on non-Windows platforms', () async {
      if (!Platform.isWindows) {
        final result = await HeicUtils.convertHeicToJpgAt(
          '/nonexistent/file.heic',
          '/nonexistent/output.jpg',
        );
        expect(result, isFalse);
      }
    });
  });

  group('HeicUtils Quality Parameter', () {
    test('convertHeicToJpg accepts quality parameter', () async {
      // This tests that the method signature accepts quality
      // We pass a file that doesn't exist, so it will return null on non-Windows
      if (!Platform.isWindows) {
        final result = await HeicUtils.convertHeicToJpg(
          '/nonexistent/file.heic',
          quality: 90,
        );
        expect(result, isNull);
      }
    });

    test('convertHeicToJpgAt accepts quality parameter', () async {
      if (!Platform.isWindows) {
        final result = await HeicUtils.convertHeicToJpgAt(
          '/nonexistent/file.heic',
          '/nonexistent/output.jpg',
          quality: 85,
        );
        expect(result, isFalse);
      }
    });
  });
}
