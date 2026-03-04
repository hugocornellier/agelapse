import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/confirm_action_dialog.dart';

/// Unit tests for ConfirmActionDialog widget.
void main() {
  group('ConfirmActionDialog', () {
    test('can be instantiated with required parameters', () {
      const dialog = ConfirmActionDialog(
        title: 'Test Title',
        description: 'Test Description',
      );
      expect(dialog, isA<ConfirmActionDialog>());
    });

    test('stores title correctly', () {
      const dialog = ConfirmActionDialog(
        title: 'Are you sure?',
        description: 'Description',
      );
      expect(dialog.title, 'Are you sure?');
    });

    test('stores description correctly', () {
      const dialog = ConfirmActionDialog(
        title: 'Title',
        description: 'This will delete everything.',
      );
      expect(dialog.description, 'This will delete everything.');
    });

    test('has default cancelText of Cancel', () {
      const dialog = ConfirmActionDialog(title: 'Title', description: 'Desc');
      expect(dialog.cancelText, 'Cancel');
    });

    test('has default confirmText of Proceed Anyway', () {
      const dialog = ConfirmActionDialog(title: 'Title', description: 'Desc');
      expect(dialog.confirmText, 'Proceed Anyway');
    });

    test('has default titleIcon of warning_amber_rounded', () {
      const dialog = ConfirmActionDialog(title: 'Title', description: 'Desc');
      expect(dialog.titleIcon, Icons.warning_amber_rounded);
    });

    test('accepts custom warningIcon', () {
      const dialog = ConfirmActionDialog(
        title: 'Title',
        description: 'Desc',
        warningIcon: Icons.refresh_rounded,
      );
      expect(dialog.warningIcon, Icons.refresh_rounded);
    });

    test('accepts custom warningText', () {
      const dialog = ConfirmActionDialog(
        title: 'Title',
        description: 'Desc',
        warningText: 'This will re-stabilize all photos.',
      );
      expect(dialog.warningText, 'This will re-stabilize all photos.');
    });

    test('warningIcon defaults to null', () {
      const dialog = ConfirmActionDialog(title: 'Title', description: 'Desc');
      expect(dialog.warningIcon, isNull);
    });

    test('warningText defaults to null', () {
      const dialog = ConfirmActionDialog(title: 'Title', description: 'Desc');
      expect(dialog.warningText, isNull);
    });

    test('accepts custom cancelText and confirmText', () {
      const dialog = ConfirmActionDialog(
        title: 'Title',
        description: 'Desc',
        cancelText: 'No',
        confirmText: 'Delete',
      );
      expect(dialog.cancelText, 'No');
      expect(dialog.confirmText, 'Delete');
    });
  });

  group('ConfirmActionDialog static methods', () {
    test('showReStabilization is a static method', () {
      expect(ConfirmActionDialog.showReStabilization, isA<Function>());
    });

    test('showRecompileVideo is a static method', () {
      expect(ConfirmActionDialog.showRecompileVideo, isA<Function>());
    });

    test('showRecompileVideoSetting is a static method', () {
      expect(ConfirmActionDialog.showRecompileVideoSetting, isA<Function>());
    });

    test('showDateChangeRecompile is a static method', () {
      expect(ConfirmActionDialog.showDateChangeRecompile, isA<Function>());
    });

    test('showDeleteRecompile is a static method', () {
      expect(ConfirmActionDialog.showDeleteRecompile, isA<Function>());
    });

    test('showDeleteSimple is a static method', () {
      expect(ConfirmActionDialog.showDeleteSimple, isA<Function>());
    });
  });
}
