import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/camera_page/capture_flash_overlay.dart';

/// Unit tests for CaptureFlashOverlay widget.
void main() {
  group('CaptureFlashOverlay', () {
    test('can be referenced', () {
      expect(CaptureFlashOverlay, isNotNull);
    });

    test('creates state of correct type', () {
      const widget = CaptureFlashOverlay(child: SizedBox());
      expect(widget.createState(), isA<CaptureFlashOverlayState>());
    });

    test('stores child widget', () {
      const child = SizedBox(width: 100);
      const widget = CaptureFlashOverlay(child: child);
      expect(widget.child, isA<SizedBox>());
    });
  });
}
