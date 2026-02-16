import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/utils/flatpak_utils.dart';

/// Unit tests for FlatpakUtils.
/// Tests Flatpak detection, app ID, user home resolution, and permission checks.
void main() {
  group('FlatpakUtils', () {
    group('isFlatpak', () {
      test('returns a boolean value', () {
        expect(FlatpakUtils.isFlatpak, isA<bool>());
      });

      test('returns false on non-Linux platforms', () {
        // On macOS (test runner), this should always be false
        if (!Platform.isLinux) {
          expect(FlatpakUtils.isFlatpak, isFalse);
        }
      });

      test('result is cached (same value on subsequent calls)', () {
        final first = FlatpakUtils.isFlatpak;
        final second = FlatpakUtils.isFlatpak;
        expect(first, equals(second));
      });
    });

    group('flatpakAppId', () {
      test('returns null on non-Flatpak environments', () {
        if (!FlatpakUtils.isFlatpak) {
          expect(FlatpakUtils.flatpakAppId, isNull);
        }
      });
    });

    group('realUserHome', () {
      test('returns a string on non-Flatpak environments', () {
        if (!FlatpakUtils.isFlatpak) {
          // On non-Flatpak, it returns HOME environment variable
          final home = FlatpakUtils.realUserHome;
          if (Platform.environment['HOME'] != null) {
            expect(home, isNotNull);
            expect(home, equals(Platform.environment['HOME']));
          }
        }
      });

      test('result is cached (same value on subsequent calls)', () {
        final first = FlatpakUtils.realUserHome;
        final second = FlatpakUtils.realUserHome;
        expect(first, equals(second));
      });
    });

    group('hasLikelyPermission', () {
      test('returns true for all permissions on non-Flatpak', () {
        if (!FlatpakUtils.isFlatpak) {
          expect(FlatpakUtils.hasLikelyPermission('filesystem'), isTrue);
          expect(FlatpakUtils.hasLikelyPermission('network'), isTrue);
          expect(FlatpakUtils.hasLikelyPermission('device'), isTrue);
        }
      });

      test('returns true for unknown permissions on non-Flatpak', () {
        if (!FlatpakUtils.isFlatpak) {
          expect(FlatpakUtils.hasLikelyPermission('unknown'), isTrue);
        }
      });
    });

    group('getDownloadsPath', () {
      test('returns a non-null string when HOME is set', () {
        if (Platform.environment['HOME'] != null) {
          final path = FlatpakUtils.getDownloadsPath();
          expect(path, isNotNull);
          expect(path, contains('Downloads'));
        }
      });

      test('path ends with Downloads', () {
        final path = FlatpakUtils.getDownloadsPath();
        if (path != null) {
          expect(path, endsWith('/Downloads'));
        }
      });
    });
  });
}
