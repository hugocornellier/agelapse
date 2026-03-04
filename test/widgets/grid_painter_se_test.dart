import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/grid_painter_se.dart';

/// Unit tests for GridPainterSE custom painter.
void main() {
  group('GridPainterSE', () {
    test('can be instantiated with required parameters', () {
      final painter = GridPainterSE(
        0.12,
        0.35,
        null,
        null,
        null,
        '9:16',
        'portrait',
      );
      expect(painter, isA<GridPainterSE>());
      expect(painter, isA<CustomPainter>());
    });

    test('stores offsetX and offsetY', () {
      final painter = GridPainterSE(
        0.15,
        0.40,
        null,
        null,
        null,
        '16:9',
        'landscape',
      );
      expect(painter.offsetX, 0.15);
      expect(painter.offsetY, 0.40);
    });

    test('stores aspect ratio and orientation', () {
      final painter = GridPainterSE(
        0.1,
        0.3,
        null,
        null,
        null,
        '1:1',
        'square',
      );
      expect(painter.aspectRatio, '1:1');
      expect(painter.projectOrientation, 'square');
    });

    test('ghost image offsets default to null', () {
      final painter = GridPainterSE(
        0.1,
        0.3,
        null,
        null,
        null,
        '9:16',
        'portrait',
      );
      expect(painter.ghostImageOffsetX, isNull);
      expect(painter.ghostImageOffsetY, isNull);
    });

    test('guideImage defaults to null', () {
      final painter = GridPainterSE(
        0.1,
        0.3,
        null,
        null,
        null,
        '9:16',
        'portrait',
      );
      expect(painter.guideImage, isNull);
    });

    test('hideToolTip defaults to false', () {
      final painter = GridPainterSE(
        0.1,
        0.3,
        null,
        null,
        null,
        '9:16',
        'portrait',
      );
      expect(painter.hideToolTip, isFalse);
    });

    test('hideCorners defaults to false', () {
      final painter = GridPainterSE(
        0.1,
        0.3,
        null,
        null,
        null,
        '9:16',
        'portrait',
      );
      expect(painter.hideCorners, isFalse);
    });

    test('dateStampEnabled defaults to false', () {
      final painter = GridPainterSE(
        0.1,
        0.3,
        null,
        null,
        null,
        '9:16',
        'portrait',
      );
      expect(painter.dateStampEnabled, isFalse);
    });

    test('dateStampPosition defaults to lower right', () {
      final painter = GridPainterSE(
        0.1,
        0.3,
        null,
        null,
        null,
        '9:16',
        'portrait',
      );
      expect(painter.dateStampPosition, 'lower right');
    });

    test('accepts optional parameters', () {
      final painter = GridPainterSE(
        0.1,
        0.3,
        0.5,
        0.5,
        null,
        '9:16',
        'portrait',
        hideToolTip: true,
        hideCorners: true,
        backgroundColor: Colors.black,
        dateStampEnabled: true,
        dateStampText: 'Jan 2024',
        dateStampPosition: 'upper left',
        dateStampSizePercent: 5,
        dateStampOpacity: 0.8,
        dateStampFontFamily: 'Roboto',
        watermarkEnabled: true,
        watermarkPosition: 'lower right',
      );
      expect(painter.hideToolTip, isTrue);
      expect(painter.hideCorners, isTrue);
      expect(painter.backgroundColor, Colors.black);
      expect(painter.dateStampEnabled, isTrue);
      expect(painter.dateStampText, 'Jan 2024');
      expect(painter.dateStampPosition, 'upper left');
      expect(painter.dateStampSizePercent, 5);
      expect(painter.dateStampOpacity, 0.8);
      expect(painter.dateStampFontFamily, 'Roboto');
      expect(painter.watermarkEnabled, isTrue);
      expect(painter.watermarkPosition, 'lower right');
    });

    group('shouldRepaint', () {
      test('returns true when offsetX changes', () {
        final p1 = GridPainterSE(
          0.1,
          0.3,
          null,
          null,
          null,
          '9:16',
          'portrait',
        );
        final p2 = GridPainterSE(
          0.2,
          0.3,
          null,
          null,
          null,
          '9:16',
          'portrait',
        );
        expect(p1.shouldRepaint(p2), isTrue);
      });

      test('returns true when offsetY changes', () {
        final p1 = GridPainterSE(
          0.1,
          0.3,
          null,
          null,
          null,
          '9:16',
          'portrait',
        );
        final p2 = GridPainterSE(
          0.1,
          0.4,
          null,
          null,
          null,
          '9:16',
          'portrait',
        );
        expect(p1.shouldRepaint(p2), isTrue);
      });

      test('returns false when nothing changes', () {
        final p1 = GridPainterSE(
          0.1,
          0.3,
          null,
          null,
          null,
          '9:16',
          'portrait',
        );
        final p2 = GridPainterSE(
          0.1,
          0.3,
          null,
          null,
          null,
          '9:16',
          'portrait',
        );
        expect(p1.shouldRepaint(p2), isFalse);
      });

      test('returns true when dateStampEnabled changes', () {
        final p1 = GridPainterSE(
          0.1,
          0.3,
          null,
          null,
          null,
          '9:16',
          'portrait',
        );
        final p2 = GridPainterSE(
          0.1,
          0.3,
          null,
          null,
          null,
          '9:16',
          'portrait',
          dateStampEnabled: true,
        );
        expect(p1.shouldRepaint(p2), isTrue);
      });
    });
  });
}
