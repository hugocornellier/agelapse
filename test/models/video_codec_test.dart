import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/video_codec.dart';

void main() {
  group('VideoCodec', () {
    group('fromString', () {
      test('parses h264', () {
        expect(VideoCodec.fromString('h264'), VideoCodec.h264);
      });

      test('parses hevc', () {
        expect(VideoCodec.fromString('hevc'), VideoCodec.hevc);
      });

      test('parses prores422', () {
        expect(VideoCodec.fromString('prores422'), VideoCodec.prores422);
      });

      test('parses prores422hq', () {
        expect(VideoCodec.fromString('prores422hq'), VideoCodec.prores422hq);
      });

      test('parses prores4444', () {
        expect(VideoCodec.fromString('prores4444'), VideoCodec.prores4444);
      });

      test('parses vp9', () {
        expect(VideoCodec.fromString('vp9'), VideoCodec.vp9);
      });

      test('defaults to h264 for invalid string', () {
        expect(VideoCodec.fromString('invalid'), VideoCodec.h264);
      });

      test('defaults to h264 for empty string', () {
        expect(VideoCodec.fromString(''), VideoCodec.h264);
      });

      test('is case-insensitive', () {
        expect(VideoCodec.fromString('H264'), VideoCodec.h264);
        expect(VideoCodec.fromString('HEVC'), VideoCodec.hevc);
        expect(VideoCodec.fromString('ProRes422'), VideoCodec.prores422);
        expect(VideoCodec.fromString('VP9'), VideoCodec.vp9);
      });

      test('round-trips through name property', () {
        for (final codec in VideoCodec.values) {
          expect(VideoCodec.fromString(codec.name), codec);
        }
      });
    });

    group('displayName', () {
      test('h264 displays as H.264', () {
        expect(VideoCodec.h264.displayName, 'H.264');
      });

      test('hevc displays as HEVC (H.265)', () {
        expect(VideoCodec.hevc.displayName, 'HEVC (H.265)');
      });

      test('prores422 displays as ProRes 422', () {
        expect(VideoCodec.prores422.displayName, 'ProRes 422');
      });

      test('prores422hq displays as ProRes 422 HQ', () {
        expect(VideoCodec.prores422hq.displayName, 'ProRes 422 HQ');
      });

      test('prores4444 displays as ProRes 4444', () {
        expect(VideoCodec.prores4444.displayName, 'ProRes 4444');
      });

      test('vp9 displays as VP9', () {
        expect(VideoCodec.vp9.displayName, 'VP9');
      });

      test('all codecs have non-empty display names', () {
        for (final codec in VideoCodec.values) {
          expect(codec.displayName, isNotEmpty);
        }
      });
    });

    group('description', () {
      test('all codecs have non-empty descriptions', () {
        for (final codec in VideoCodec.values) {
          expect(codec.description, isNotEmpty);
        }
      });
    });

    group('containerExtension', () {
      test('h264 uses .mp4', () {
        expect(VideoCodec.h264.containerExtension, '.mp4');
      });

      test('hevc uses .mp4', () {
        expect(VideoCodec.hevc.containerExtension, '.mp4');
      });

      test('prores422 uses .mov', () {
        expect(VideoCodec.prores422.containerExtension, '.mov');
      });

      test('prores422hq uses .mov', () {
        expect(VideoCodec.prores422hq.containerExtension, '.mov');
      });

      test('prores4444 uses .mov', () {
        expect(VideoCodec.prores4444.containerExtension, '.mov');
      });

      test('vp9 uses .webm', () {
        expect(VideoCodec.vp9.containerExtension, '.webm');
      });

      test('all extensions start with a dot', () {
        for (final codec in VideoCodec.values) {
          expect(codec.containerExtension, startsWith('.'));
        }
      });
    });

    group('pixelFormat', () {
      test('h264 uses yuv420p', () {
        expect(VideoCodec.h264.pixelFormat, 'yuv420p');
      });

      test('hevc uses yuv420p', () {
        expect(VideoCodec.hevc.pixelFormat, 'yuv420p');
      });

      test('prores422 uses yuv422p10le', () {
        expect(VideoCodec.prores422.pixelFormat, 'yuv422p10le');
      });

      test('prores422hq uses yuv422p10le', () {
        expect(VideoCodec.prores422hq.pixelFormat, 'yuv422p10le');
      });

      test('prores4444 uses yuva444p10le', () {
        expect(VideoCodec.prores4444.pixelFormat, 'yuva444p10le');
      });

      test('vp9 uses yuva420p', () {
        expect(VideoCodec.vp9.pixelFormat, 'yuva420p');
      });

      test('all pixel formats are non-empty', () {
        for (final codec in VideoCodec.values) {
          expect(codec.pixelFormat, isNotEmpty);
        }
      });
    });

    group('pixelFormatForSource', () {
      test('returns default pixelFormat when highBitDepth is false', () {
        for (final codec in VideoCodec.values) {
          expect(
            codec.pixelFormatForSource(highBitDepth: false),
            codec.pixelFormat,
          );
        }
      });

      test('h264 stays 8-bit even with high bit depth source', () {
        expect(
          VideoCodec.h264.pixelFormatForSource(highBitDepth: true),
          'yuv420p',
        );
      });

      test('hevc upgrades to 10-bit with high bit depth source', () {
        expect(
          VideoCodec.hevc.pixelFormatForSource(highBitDepth: true),
          'yuv420p10le',
        );
      });

      test('prores keeps native 10-bit regardless of source', () {
        expect(
          VideoCodec.prores422.pixelFormatForSource(highBitDepth: true),
          'yuv422p10le',
        );
        expect(
          VideoCodec.prores422hq.pixelFormatForSource(highBitDepth: true),
          'yuv422p10le',
        );
        expect(
          VideoCodec.prores4444.pixelFormatForSource(highBitDepth: true),
          'yuva444p10le',
        );
      });

      test('vp9 stays 8-bit alpha with high bit depth when supportsAlpha', () {
        // VP9 alpha can't do 10-bit, stays at yuva420p
        expect(
          VideoCodec.vp9.pixelFormatForSource(highBitDepth: true),
          'yuva420p',
        );
      });
    });

    group('supportsAlpha', () {
      test('only prores4444 and vp9 support alpha', () {
        expect(VideoCodec.h264.supportsAlpha, false);
        expect(VideoCodec.hevc.supportsAlpha, false);
        expect(VideoCodec.prores422.supportsAlpha, false);
        expect(VideoCodec.prores422hq.supportsAlpha, false);
        expect(VideoCodec.prores4444.supportsAlpha, true);
        expect(VideoCodec.vp9.supportsAlpha, true);
      });
    });

    group('usesBitrateControl', () {
      test('h264 uses bitrate control', () {
        expect(VideoCodec.h264.usesBitrateControl, true);
      });

      test('hevc uses bitrate control', () {
        expect(VideoCodec.hevc.usesBitrateControl, true);
      });

      test('vp9 uses bitrate control', () {
        expect(VideoCodec.vp9.usesBitrateControl, true);
      });

      test('prores variants do not use bitrate control', () {
        expect(VideoCodec.prores422.usesBitrateControl, false);
        expect(VideoCodec.prores422hq.usesBitrateControl, false);
        expect(VideoCodec.prores4444.usesBitrateControl, false);
      });
    });

    group('usesMovFlags', () {
      test('only h264 and hevc use movflags', () {
        expect(VideoCodec.h264.usesMovFlags, true);
        expect(VideoCodec.hevc.usesMovFlags, true);
        expect(VideoCodec.prores422.usesMovFlags, false);
        expect(VideoCodec.prores422hq.usesMovFlags, false);
        expect(VideoCodec.prores4444.usesMovFlags, false);
        expect(VideoCodec.vp9.usesMovFlags, false);
      });
    });

    group('encoder (platform-specific)', () {
      // These tests verify the encoder strings contain expected substrings
      // without depending on the specific platform the test runs on.

      test('encoderApple returns videotoolbox for h264 with sw fallback', () {
        expect(VideoCodec.h264.encoderApple, contains('h264_videotoolbox'));
        expect(VideoCodec.h264.encoderApple, contains('-allow_sw 1'));
      });

      test('encoderApple returns videotoolbox for hevc with sw fallback', () {
        expect(VideoCodec.hevc.encoderApple, contains('hevc_videotoolbox'));
        expect(VideoCodec.hevc.encoderApple, contains('-allow_sw 1'));
      });

      test('encoderApple returns prores_ks for prores variants', () {
        expect(VideoCodec.prores422.encoderApple, contains('prores_ks'));
        expect(VideoCodec.prores422.encoderApple, contains('standard'));
        expect(VideoCodec.prores422hq.encoderApple, contains('prores_ks'));
        expect(VideoCodec.prores422hq.encoderApple, contains('hq'));
      });

      test('encoderApple returns prores_ks 4444 with alpha for prores4444', () {
        expect(VideoCodec.prores4444.encoderApple, contains('prores_ks'));
        expect(VideoCodec.prores4444.encoderApple, contains('4444'));
        expect(VideoCodec.prores4444.encoderApple, contains('-alpha_bits 16'));
        expect(VideoCodec.prores4444.encoderApple, contains('-vendor apl0'));
      });

      test('encoderDesktop returns libx264 for h264', () {
        expect(VideoCodec.h264.encoderDesktop, 'libx264');
      });

      test('encoderDesktop returns libx265 for hevc', () {
        expect(VideoCodec.hevc.encoderDesktop, 'libx265');
      });

      test('encoderDesktop throws for prores codecs', () {
        expect(() => VideoCodec.prores422.encoderDesktop, throwsStateError);
        expect(() => VideoCodec.prores422hq.encoderDesktop, throwsStateError);
        expect(() => VideoCodec.prores4444.encoderDesktop, throwsStateError);
      });

      test('encoderAndroid throws for prores codecs', () {
        expect(() => VideoCodec.prores422.encoderAndroid, throwsStateError);
        expect(() => VideoCodec.prores422hq.encoderAndroid, throwsStateError);
        expect(() => VideoCodec.prores4444.encoderAndroid, throwsStateError);
      });

      test('encoderApple throws for vp9', () {
        expect(() => VideoCodec.vp9.encoderApple, throwsStateError);
      });

      test('encoderAndroid matches encoderDesktop for shared codecs', () {
        for (final codec in [VideoCodec.h264, VideoCodec.vp9]) {
          expect(codec.encoderAndroid, codec.encoderDesktop);
        }
      });

      test('encoderAndroid throws for hevc', () {
        expect(() => VideoCodec.hevc.encoderAndroid, throwsStateError);
      });

      test('valid encoder combinations are non-empty', () {
        // Apple encoders (all except VP9)
        for (final codec in VideoCodec.values.where(
          (c) => c != VideoCodec.vp9,
        )) {
          expect(codec.encoderApple, isNotEmpty);
        }
        // Desktop encoders (h264, hevc, vp9 only)
        for (final codec in [
          VideoCodec.h264,
          VideoCodec.hevc,
          VideoCodec.vp9,
        ]) {
          expect(codec.encoderDesktop, isNotEmpty);
        }
        // Android encoders (h264, vp9 only)
        for (final codec in [VideoCodec.h264, VideoCodec.vp9]) {
          expect(codec.encoderAndroid, isNotEmpty);
        }
      });
    });

    group('codecTag', () {
      // codecTag is platform-dependent, so test the known values
      test('non-h264/hevc codecs have empty tag', () {
        expect(VideoCodec.prores422.codecTag, '');
        expect(VideoCodec.prores422hq.codecTag, '');
        expect(VideoCodec.prores4444.codecTag, '');
        expect(VideoCodec.vp9.codecTag, '');
      });
    });

    group('availableCodecs', () {
      test('opaque codecs are platform-appropriate', () {
        final codecs = VideoCodec.availableCodecs(isTransparentVideo: false);
        expect(codecs, contains(VideoCodec.h264));

        if (Platform.isMacOS) {
          expect(codecs, contains(VideoCodec.hevc));
          expect(codecs, contains(VideoCodec.prores422));
          expect(codecs, contains(VideoCodec.prores422hq));
          expect(codecs.length, 4);
        } else if (Platform.isAndroid) {
          expect(codecs, isNot(contains(VideoCodec.hevc)));
          expect(codecs.length, 1);
        } else {
          // iOS, Windows, Linux: H.264 + HEVC
          expect(codecs, contains(VideoCodec.hevc));
          expect(codecs, isNot(contains(VideoCodec.prores422)));
          expect(codecs, isNot(contains(VideoCodec.prores422hq)));
          expect(codecs.length, 2);
        }

        // ProRes 4444 never in opaque list (alpha-only codec)
        expect(codecs, isNot(contains(VideoCodec.prores4444)));
        // VP9 never in opaque list (alpha-only fallback)
        expect(codecs, isNot(contains(VideoCodec.vp9)));
      });

      test('transparent returns only alpha-capable codecs', () {
        final codecs = VideoCodec.availableCodecs(isTransparentVideo: true);
        expect(codecs.length, 1);
        for (final c in codecs) {
          expect(c.supportsAlpha, true);
        }
      });

      test('transparent codecs are platform-specific', () {
        final codecs = VideoCodec.availableCodecs(isTransparentVideo: true);
        if (Platform.isMacOS || Platform.isIOS) {
          expect(codecs, [VideoCodec.prores4444]);
        } else {
          expect(codecs, [VideoCodec.vp9]);
        }
      });
    });

    group('defaultCodec', () {
      test('opaque default is h264', () {
        expect(
          VideoCodec.defaultCodec(isTransparentVideo: false),
          VideoCodec.h264,
        );
      });

      test('transparent default is alpha-capable', () {
        final codec = VideoCodec.defaultCodec(isTransparentVideo: true);
        expect(codec.supportsAlpha, true);
      });
    });
  });
}
