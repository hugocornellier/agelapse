import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/bool_setting_switch.dart';

/// Widget tests for BoolSettingSwitch.
void main() {
  group('BoolSettingSwitch Widget', () {
    test('BoolSettingSwitch can be instantiated', () {
      expect(BoolSettingSwitch, isNotNull);
    });

    test('BoolSettingSwitch stores required parameters', () {
      final widget = BoolSettingSwitch(
        title: 'Enable Feature',
        initialValue: true,
        onChanged: (value) {},
      );

      expect(widget.title, 'Enable Feature');
      expect(widget.initialValue, isTrue);
    });

    test('BoolSettingSwitch accepts optional showInfo', () {
      final widget = BoolSettingSwitch(
        title: 'Test',
        initialValue: false,
        onChanged: (value) {},
        showInfo: true,
      );

      expect(widget.showInfo, isTrue);
    });

    test('BoolSettingSwitch accepts optional infoContent', () {
      final widget = BoolSettingSwitch(
        title: 'Test',
        initialValue: false,
        onChanged: (value) {},
        infoContent: 'This is info content',
      );

      expect(widget.infoContent, 'This is info content');
    });

    test('BoolSettingSwitch accepts optional showDivider', () {
      final widget = BoolSettingSwitch(
        title: 'Test',
        initialValue: false,
        onChanged: (value) {},
        showDivider: false,
      );

      expect(widget.showDivider, isFalse);
    });

    test('BoolSettingSwitch creates state', () {
      final widget = BoolSettingSwitch(
        title: 'Test',
        initialValue: true,
        onChanged: (value) {},
      );

      expect(widget.createState(), isA<BoolSettingSwitchState>());
    });

    test('onChanged callback is stored correctly', () {
      bool callbackFired = false;
      bool? receivedValue;

      final widget = BoolSettingSwitch(
        title: 'Test',
        initialValue: false,
        onChanged: (value) {
          callbackFired = true;
          receivedValue = value;
        },
      );

      widget.onChanged(true);

      expect(callbackFired, isTrue);
      expect(receivedValue, isTrue);
    });
  });

  group('BoolSettingSwitch Edge Cases', () {
    test('handles empty title', () {
      final widget = BoolSettingSwitch(
        title: '',
        initialValue: false,
        onChanged: (value) {},
      );

      expect(widget.title, '');
    });

    test('handles long title', () {
      final longTitle = 'A' * 100;
      final widget = BoolSettingSwitch(
        title: longTitle,
        initialValue: false,
        onChanged: (value) {},
      );

      expect(widget.title.length, 100);
    });

    test('handles empty infoContent', () {
      final widget = BoolSettingSwitch(
        title: 'Test',
        initialValue: false,
        onChanged: (value) {},
        infoContent: '',
      );

      expect(widget.infoContent, '');
    });
  });
}
