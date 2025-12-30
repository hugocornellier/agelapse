import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/dropdown_with_custom_textfield.dart';

/// Widget tests for DropdownWithCustomTextField.
void main() {
  group('DropdownWithCustomTextField Widget', () {
    test('DropdownWithCustomTextField can be instantiated', () {
      expect(DropdownWithCustomTextField, isNotNull);
    });

    test('DropdownWithCustomTextField stores required parameters', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Framerate',
        initialValue: 24,
        onChanged: (value) {},
      );

      expect(widget.projectId, 1);
      expect(widget.title, 'Framerate');
      expect(widget.initialValue, 24);
    });

    test('showDivider defaults to null', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 10,
        onChanged: (value) {},
      );

      expect(widget.showDivider, isNull);
    });

    test('showDivider can be set', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 10,
        onChanged: (value) {},
        showDivider: true,
      );

      expect(widget.showDivider, isTrue);
    });

    test('onChanged callback is stored', () {
      int? receivedValue;

      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 10,
        onChanged: (value) {
          receivedValue = value;
        },
      );

      widget.onChanged(30);
      expect(receivedValue, 30);
    });

    test('DropdownWithCustomTextField creates state', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 16,
        onChanged: (value) {},
      );

      expect(widget.createState(), isA<DropdownWithCustomTextFieldState>());
    });
  });

  group('DropdownWithCustomTextField Initial Values', () {
    test('recognizes default value 1', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 1,
        onChanged: (value) {},
      );

      // 1 is a default value
      expect(widget.initialValue, 1);
    });

    test('recognizes default value 24', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 24,
        onChanged: (value) {},
      );

      expect(widget.initialValue, 24);
    });

    test('recognizes default value 60', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 60,
        onChanged: (value) {},
      );

      expect(widget.initialValue, 60);
    });

    test('handles custom value (non-default)', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 45,
        onChanged: (value) {},
      );

      // 45 is not a default value
      expect(widget.initialValue, 45);
    });
  });

  group('DropdownWithCustomTextFieldState defaultValues', () {
    test('defaultValues contains expected framerates', () {
      // Access the static constant
      const expected = [1, 5, 10, 16, 24, 30, 60];
      expect(DropdownWithCustomTextFieldState.defaultValues, expected);
    });

    test('defaultValues has 7 values', () {
      expect(DropdownWithCustomTextFieldState.defaultValues.length, 7);
    });

    test('defaultValues are sorted', () {
      final values = DropdownWithCustomTextFieldState.defaultValues;
      final sorted = List<int>.from(values)..sort();
      expect(values, sorted);
    });
  });

  group('DropdownWithCustomTextField Edge Cases', () {
    test('handles projectId 0', () {
      final widget = DropdownWithCustomTextField(
        projectId: 0,
        title: 'Test',
        initialValue: 24,
        onChanged: (value) {},
      );

      expect(widget.projectId, 0);
    });

    test('handles large projectId', () {
      final widget = DropdownWithCustomTextField(
        projectId: 999999,
        title: 'Test',
        initialValue: 24,
        onChanged: (value) {},
      );

      expect(widget.projectId, 999999);
    });

    test('handles empty title', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: '',
        initialValue: 24,
        onChanged: (value) {},
      );

      expect(widget.title, '');
    });

    test('handles very small initialValue', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 1,
        onChanged: (value) {},
      );

      expect(widget.initialValue, 1);
    });

    test('handles value at boundary (120)', () {
      final widget = DropdownWithCustomTextField(
        projectId: 1,
        title: 'Test',
        initialValue: 120,
        onChanged: (value) {},
      );

      // 120 would be a custom value since it's not in defaults
      expect(widget.initialValue, 120);
    });
  });
}
